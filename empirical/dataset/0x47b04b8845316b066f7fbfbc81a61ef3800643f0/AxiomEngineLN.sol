// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// AxiomEngineLN — pre-norm transformer engine with on-chain layer-norm.
// quill-axiom Stage 6: the integration of AxiomLayerNorm into a full engine.
//
// The original AxiomEngine ran a transformer in integer EVM arithmetic but
// had no layer-norm — which AxiomScope and the QAT writeup identified as the
// structural cause of the residual-stream drift the int8 model exhibited.
// This engine fixes that. Every value — embeddings, weights, residual
// stream, gamma, beta — is in the SAME ONE = 2^16 fixed-point unit. After
// each matmul, the accumulator is divided by ONE (truncated toward zero) to
// stay in scale. Layer-norm is applied in pre-norm position at three places:
// before attention, before the FFN, and at the head. The attention block is
// the same causal self-attention as AxiomEngine.
//
// Spec: V=96 C=16 D=32 FF=64, single block, single head, no on-chain
// tokenizer (char-level). Weights are passed as one int256[] array (15,232
// entries) at fixed offsets — the deployment-packed blob is a follow-up,
// this engine is the verified correctness reference for it.
contract AxiomEngineLN {
    uint256 internal constant V  = 96;
    uint256 internal constant C  = 16;
    uint256 internal constant D  = 32;
    uint256 internal constant FF = 64;
    uint256 internal constant CD = 512;            // C * D
    int256  internal constant ONE      = 65536;
    uint256 internal constant ONE_U    = 65536;
    int256  internal constant ONE2     = 4294967296;       // 2^32
    uint256 internal constant ONE3_U   = 281474976710656;  // 2^48
    uint256 internal constant WLEN     = 15232;

    // weight offsets (units: int256 entries in W)
    uint256 internal constant OFF_TOK     = 0;
    uint256 internal constant OFF_POS     = 3072;
    uint256 internal constant OFF_LN1_G   = 3584;
    uint256 internal constant OFF_LN1_B   = 3616;
    uint256 internal constant OFF_WQ      = 3648;
    uint256 internal constant OFF_WK      = 4672;
    uint256 internal constant OFF_WV      = 5696;
    uint256 internal constant OFF_WO      = 6720;
    uint256 internal constant OFF_LN2_G   = 7744;
    uint256 internal constant OFF_LN2_B   = 7776;
    uint256 internal constant OFF_FFN_W1  = 7808;
    uint256 internal constant OFF_FFN_B1  = 9856;
    uint256 internal constant OFF_FFN_W2  = 9920;
    uint256 internal constant OFF_FFN_B2  = 11968;
    uint256 internal constant OFF_LN3_G   = 12000;
    uint256 internal constant OFF_LN3_B   = 12032;
    uint256 internal constant OFF_WOUT    = 12064;
    uint256 internal constant OFF_BOUT    = 15136;

    // softmax fixed-point constants (same as AxiomSoftmax)
    int256 internal constant LOG2E = 94548;
    int256 internal constant K1 = 45426;
    int256 internal constant K2 = 15743;
    int256 internal constant K3 = 3637;

    error BadWeights();

    // ---- character mapping (same as AxiomEngine) ----
    function _charIdx(uint8 b) internal pure returns (uint256) {
        if (b == 0x0a) return 0;
        if (b >= 0x20 && b <= 0x7e) return uint256(b) - 31;
        return 1;
    }
    function _seed(string calldata prompt) private pure returns (uint256[C] memory ctx) {
        for (uint256 i = 0; i < C; i++) ctx[i] = 1;
        bytes calldata p = bytes(prompt);
        uint256 plen = p.length;
        uint256 take = plen < C ? plen : C;
        for (uint256 k = 0; k < take; k++) {
            ctx[C - take + k] = _charIdx(uint8(p[plen - take + k]));
        }
    }

    // ---- integer math helpers ----
    function _isqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
        return y;
    }
    function _exp2frac(int256 f) private pure returns (int256 r) {
        r = K2 + (K3 * f) / ONE;
        r = K1 + (r * f) / ONE;
        r = ONE + (r * f) / ONE;
    }
    function _expNeg(int256 d) private pure returns (int256) {
        if (d >= 0) return ONE;
        int256 t = d * LOG2E;
        int256 k = t >> 16;
        int256 f = t - (k << 16);
        uint256 sh = uint256(-k);
        if (sh >= 32) return 0;
        return _exp2frac(f) >> sh;
    }
    function _softmaxInto(int256[] memory s, uint256 n) private pure returns (uint256[] memory w) {
        int256 mx = s[0];
        for (uint256 i = 1; i < n; i++) if (s[i] > mx) mx = s[i];
        int256[] memory e = new int256[](n);
        int256 sum;
        for (uint256 i = 0; i < n; i++) { int256 ei = _expNeg(s[i] - mx); e[i] = ei; sum += ei; }
        w = new uint256[](n);
        for (uint256 i = 0; i < n; i++) w[i] = uint256(e[i] * ONE / sum);
    }

    // ---- layer-norm of one D-dim row ----
    function _layerNormRow(
        int256[] memory src, uint256 srcOff,
        int256[] calldata W, uint256 gOff, uint256 bOff, uint256 eps,
        int256[] memory dst, uint256 dstOff
    ) private pure {
        int256 s;
        for (uint256 i = 0; i < D; i++) s += src[srcOff + i];
        int256 mean = s / int256(D);
        int256 varSum;
        for (uint256 i = 0; i < D; i++) {
            int256 c = src[srcOff + i] - mean;
            varSum += c * c;
        }
        uint256 v = uint256(varSum) / D / ONE_U + eps;
        if (v == 0) v = 1;
        int256 inv = int256(_isqrt(ONE3_U / v));
        for (uint256 i = 0; i < D; i++) {
            int256 c = src[srcOff + i] - mean;
            dst[dstOff + i] = (c * inv * W[gOff + i]) / ONE2 + W[bOff + i];
        }
    }

    // ---- forward stages, each in its own scope to keep the stack shallow ----

    // X[t*D+d] = W[OFF_TOK + ctx[t]*D + d] + W[OFF_POS + t*D + d]
    function _embed(int256[] calldata W, uint256[C] memory ctx) private pure returns (int256[] memory X) {
        X = new int256[](CD);
        for (uint256 t = 0; t < C; t++) {
            uint256 tok = ctx[t];
            for (uint256 d = 0; d < D; d++) X[t * D + d] = W[OFF_TOK + tok * D + d] + W[OFF_POS + t * D + d];
        }
    }

    // apply layer-norm to each row of `src` -> `dst` using (gOff, bOff)
    function _normAllRows(
        int256[] memory src, int256[] calldata W,
        uint256 gOff, uint256 bOff, uint256 eps
    ) private pure returns (int256[] memory dst) {
        dst = new int256[](CD);
        for (uint256 t = 0; t < C; t++) {
            _layerNormRow(src, t * D, W, gOff, bOff, eps, dst, t * D);
        }
    }

    // out[t][col] = (sum_a x[t][a] * W[wOff + a*D + col]) / ONE   for D x D weight
    function _projDD(int256[] memory x, int256[] calldata W, uint256 wOff)
        private pure returns (int256[] memory out)
    {
        out = new int256[](CD);
        for (uint256 t = 0; t < C; t++) {
            uint256 xb = t * D;
            uint256 ob = t * D;
            for (uint256 c = 0; c < D; c++) {
                int256 acc;
                for (uint256 a = 0; a < D; a++) acc += x[xb + a] * W[wOff + a * D + c];
                out[ob + c] = acc / ONE;
            }
        }
    }

    function _causalAttention(
        int256[] memory n1, int256[] calldata W, uint256 scoreShift
    ) private pure returns (int256[] memory O) {
        int256[] memory Q = _projDD(n1, W, OFF_WQ);
        int256[] memory K = _projDD(n1, W, OFF_WK);
        int256[] memory Vv = _projDD(n1, W, OFF_WV);
        O = new int256[](CD);
        for (uint256 i = 0; i < C; i++) {
            uint256 len = i + 1;
            int256[] memory scores = new int256[](len);
            for (uint256 j = 0; j < len; j++) {
                int256 dot;
                for (uint256 a = 0; a < D; a++) dot += Q[i * D + a] * K[j * D + a];
                scores[j] = dot >> scoreShift;
            }
            uint256[] memory aw = _softmaxInto(scores, len);
            for (uint256 d = 0; d < D; d++) {
                int256 acc;
                for (uint256 j = 0; j < len; j++) acc += int256(aw[j]) * Vv[j * D + d];
                O[i * D + d] = acc / ONE;
            }
        }
    }

    // FFN: F = relu((n2 @ W1) / ONE + b1)  then  out = (F @ W2) / ONE + b2
    function _ffn(int256[] memory n2, int256[] calldata W) private pure returns (int256[] memory F2) {
        int256[] memory F1 = new int256[](C * FF);
        for (uint256 t = 0; t < C; t++) {
            for (uint256 j = 0; j < FF; j++) {
                int256 acc;
                for (uint256 a = 0; a < D; a++) acc += n2[t * D + a] * W[OFF_FFN_W1 + a * FF + j];
                int256 v = acc / ONE + W[OFF_FFN_B1 + j];
                F1[t * FF + j] = v > 0 ? v : int256(0);
            }
        }
        F2 = new int256[](CD);
        for (uint256 t = 0; t < C; t++) {
            for (uint256 d = 0; d < D; d++) {
                int256 acc;
                for (uint256 j = 0; j < FF; j++) acc += F1[t * FF + j] * W[OFF_FFN_W2 + j * D + d];
                F2[t * D + d] = acc / ONE + W[OFF_FFN_B2 + d];
            }
        }
    }

    function _projHead(int256[] memory n3, int256[] calldata W)
        private pure returns (int256[] memory logits)
    {
        logits = new int256[](V);
        for (uint256 v = 0; v < V; v++) {
            int256 acc;
            for (uint256 a = 0; a < D; a++) acc += n3[a] * W[OFF_WOUT + a * V + v];
            logits[v] = acc / ONE + W[OFF_BOUT + v];
        }
    }
}

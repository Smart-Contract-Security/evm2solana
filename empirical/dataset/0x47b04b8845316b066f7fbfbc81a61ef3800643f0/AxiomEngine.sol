// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// AxiomEngine — a complete one-layer transformer, on-chain, in pure integer
// arithmetic. quill-axiom (roadmap Update 06), Stage 3.
//
// Composes the verified pieces — the Stage 1 fixed-point softmax and the
// Stage 2 causal attention head — into a full next-token forward pass:
//
//   embed    : x[t] = tokenEmb[ctx[t]] + posEmb[t]
//   attention: O    = causalAttention(x)              (Stage 2)
//   project  : H1   = x + (O · Wo  >> attnShift)       residual
//   ffn      : F    = relu(H1 · W1 + b1) · W2 + b2
//              H2   = H1 + (F        >> ffnShift)       residual
//   logits   : logit[v] = bout[v] + H2[last] · Wout
//   next     : argmax(logit)
//
// Everything is deterministic integer math — no floats, byte-identical on
// every node. The right-shifts (scoreShift / attnShift / ffnShift) are the
// integer temperatures that keep the residual stream in range; they are
// model constants set at quantization time. No layer-norm: a one-block model
// at this size is kept in range by the shifts and the int8 quantization
// scales instead — on-chain layer-norm (integer rsqrt) is a separate item.
//
// Spec axiom-S: vocab V=96, context C=16, model width D=32 (single head,
// d_head = D), feed-forward width FF=64. Weights are passed as one int256
// array W, sliced at fixed offsets — the deployment-packed blob + assembly
// optimisation is the follow-up; this engine is the verified correctness
// reference for it.
contract AxiomEngine {
    uint256 internal constant V  = 96;
    uint256 internal constant C  = 16;
    uint256 internal constant D  = 32;
    uint256 internal constant FF = 64;
    uint256 public  constant MAX_COUNT = 256;

    // weight-array offsets (units: int256 entries)
    uint256 internal constant OFF_TOK  = 0;       // tokenEmb V*D
    uint256 internal constant OFF_POS  = 3072;    // posEmb   C*D
    uint256 internal constant OFF_WQ   = 3584;    // Wq       D*D
    uint256 internal constant OFF_WK   = 4608;    // Wk       D*D
    uint256 internal constant OFF_WV   = 5632;    // Wv       D*D
    uint256 internal constant OFF_WO   = 6656;    // Wo       D*D
    uint256 internal constant OFF_W1   = 7680;    // W1ff     D*FF
    uint256 internal constant OFF_B1   = 9728;    // b1ff     FF
    uint256 internal constant OFF_W2   = 9792;    // W2ff     FF*D
    uint256 internal constant OFF_B2   = 11840;   // b2ff     D
    uint256 internal constant OFF_WOUT = 11872;   // Wout     D*V
    uint256 internal constant OFF_BOUT = 14944;   // bout     V
    uint256 internal constant WLEN     = 15040;

    // fixed-point softmax constants (verified in AxiomSoftmax)
    int256 internal constant ONE   = 65536;
    int256 internal constant LOG2E = 94548;
    int256 internal constant K1 = 45426;
    int256 internal constant K2 = 15743;
    int256 internal constant K3 = 3637;

    error BadWeights();
    error BadCount();

    function _vocab(uint256 i) internal pure returns (bytes1) {
        if (i == 0) return 0x0a;
        return bytes1(uint8(31 + i));
    }
    function _charIdx(uint8 b) internal pure returns (uint256) {
        if (b == 0x0a) return 0;
        if (b >= 0x20 && b <= 0x7e) return uint256(b) - 31;
        return 1; // space
    }

    // ---- fixed-point softmax (Stage 1) ----
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
    function _softmaxRow(int256[] memory s) private pure returns (uint256[] memory w) {
        uint256 n = s.length;
        int256 mx = s[0];
        for (uint256 i = 1; i < n; i++) if (s[i] > mx) mx = s[i];
        int256[] memory e = new int256[](n);
        int256 sum;
        for (uint256 i = 0; i < n; i++) { int256 ei = _expNeg(s[i] - mx); e[i] = ei; sum += ei; }
        w = new uint256[](n);
        for (uint256 i = 0; i < n; i++) w[i] = uint256(e[i] * ONE / sum);
    }

    // ---- transformer forward, in shallow stages (keeps the stack flat) ----

    // embed: X[t][d] = tokenEmb[ctx[t]][d] + posEmb[t][d]
    function _embed(int256[] calldata W, uint256[] memory ctx)
        private pure returns (int256[] memory X)
    {
        X = new int256[](C * D);
        for (uint256 t = 0; t < C; t++) {
            uint256 tok = ctx[t];
            for (uint256 d = 0; d < D; d++)
                X[t * D + d] = W[OFF_TOK + tok * D + d] + W[OFF_POS + t * D + d];
        }
    }

    // X (C*D) projected by a D*D weight block at offset `off` -> (C*D)
    function _proj(int256[] calldata W, int256[] memory X, uint256 off)
        private pure returns (int256[] memory out)
    {
        out = new int256[](C * D);
        for (uint256 t = 0; t < C; t++)
            for (uint256 b = 0; b < D; b++) {
                int256 acc;
                for (uint256 a = 0; a < D; a++) acc += X[t * D + a] * W[off + a * D + b];
                out[t * D + b] = acc;
            }
    }

    // causal score row for query i: scores over keys 0..i
    function _scoreRow(int256[] memory Q, int256[] memory Kk, uint256 i, uint256 scoreShift)
        private pure returns (int256[] memory sc)
    {
        sc = new int256[](i + 1);
        for (uint256 j = 0; j <= i; j++) {
            int256 dot;
            for (uint256 h = 0; h < D; h++) dot += Q[i * D + h] * Kk[j * D + h];
            sc[j] = dot >> scoreShift;
        }
    }

    // single causal self-attention head -> O (C*D)
    function _attention(int256[] calldata W, int256[] memory X, uint256 scoreShift)
        private pure returns (int256[] memory O)
    {
        int256[] memory Q  = _proj(W, X, OFF_WQ);
        int256[] memory Kk = _proj(W, X, OFF_WK);
        int256[] memory Vv = _proj(W, X, OFF_WV);
        O = new int256[](C * D);
        for (uint256 i = 0; i < C; i++) {
            uint256[] memory a = _softmaxRow(_scoreRow(Q, Kk, i, scoreShift));
            for (uint256 h = 0; h < D; h++) {
                int256 acc;
                for (uint256 j = 0; j <= i; j++) acc += int256(a[j]) * Vv[j * D + h];
                O[i * D + h] = acc / ONE;
            }
        }
    }

    // output projection (>> attnShift) and residual:  H1 = X + O·Wo
    function _outResidual(int256[] calldata W, int256[] memory X, int256[] memory O, uint256 attnShift)
        private pure returns (int256[] memory H1)
    {
        H1 = new int256[](C * D);
        for (uint256 t = 0; t < C; t++)
            for (uint256 d = 0; d < D; d++) {
                int256 acc;
                for (uint256 e = 0; e < D; e++) acc += O[t * D + e] * W[OFF_WO + e * D + d];
                H1[t * D + d] = X[t * D + d] + (acc >> attnShift);
            }
    }

    // feed-forward (ReLU) and residual:  H2 = H1 + FFN(H1)
    function _ffnResidual(int256[] calldata W, int256[] memory H1, uint256 ffnShift)
        private pure returns (int256[] memory H2)
    {
        H2 = new int256[](C * D);
        for (uint256 t = 0; t < C; t++) {
            int256[] memory g = new int256[](FF);
            for (uint256 j = 0; j < FF; j++) {
                int256 acc = W[OFF_B1 + j];
                for (uint256 d = 0; d < D; d++) acc += H1[t * D + d] * W[OFF_W1 + d * FF + j];
                g[j] = acc > 0 ? acc : int256(0);
            }
            for (uint256 d = 0; d < D; d++) {
                int256 acc2 = W[OFF_B2 + d];
                for (uint256 j = 0; j < FF; j++) acc2 += g[j] * W[OFF_W2 + j * D + d];
                H2[t * D + d] = H1[t * D + d] + (acc2 >> ffnShift);
            }
        }
    }

    // logits from the last context position
    function _logits(int256[] calldata W, int256[] memory H2)
        private pure returns (int256[] memory logits)
    {
        logits = new int256[](V);
        for (uint256 v = 0; v < V; v++) {
            int256 acc = W[OFF_BOUT + v];
            for (uint256 d = 0; d < D; d++) acc += H2[(C - 1) * D + d] * W[OFF_WOUT + d * V + v];
            logits[v] = acc;
        }
    }

    // one full transformer forward pass -> V logits
    function _forward(
        int256[] calldata W, uint256[] memory ctx,
        uint256 scoreShift, uint256 attnShift, uint256 ffnShift
    ) private pure returns (int256[] memory) {
        int256[] memory X  = _embed(W, ctx);
        int256[] memory O  = _attention(W, X, scoreShift);
        int256[] memory H1 = _outResidual(W, X, O, attnShift);
        return _logits(W, _ffnResidual(W, H1, ffnShift));
    }

    function _argmax(int256[] memory a) private pure returns (uint256 bi) {
        int256 best = a[0];
        for (uint256 i = 1; i < a.length; i++) if (a[i] > best) { best = a[i]; bi = i; }
    }

    function _seed(string calldata prompt) private pure returns (uint256[] memory ctx) {
        ctx = new uint256[](C);
        for (uint256 i = 0; i < C; i++) ctx[i] = 1;          // space
        bytes calldata p = bytes(prompt);
        uint256 plen = p.length;
        uint256 take = plen < C ? plen : C;
        for (uint256 k = 0; k < take; k++)
            ctx[C - take + k] = _charIdx(uint8(p[plen - take + k]));
    }

    // The V logits the model produces for the next character after `prompt`.
    function forwardLogits(
        int256[] calldata W, string calldata prompt,
        uint256 scoreShift, uint256 attnShift, uint256 ffnShift
    ) external pure returns (int256[] memory) {
        if (W.length != WLEN) revert BadWeights();
        return _forward(W, _seed(prompt), scoreShift, attnShift, ffnShift);
    }

    // Greedy generation: `count` characters from the transformer.
    function generate(
        int256[] calldata W, string calldata prompt, uint256 count,
        uint256 scoreShift, uint256 attnShift, uint256 ffnShift
    ) external pure returns (string memory) {
        if (W.length != WLEN) revert BadWeights();
        if (count == 0 || count > MAX_COUNT) revert BadCount();
        uint256[] memory ctx = _seed(prompt);
        bytes memory out = new bytes(count);
        for (uint256 pos = 0; pos < count; pos++) {
            int256[] memory logits = _forward(W, ctx, scoreShift, attnShift, ffnShift);
            uint256 nxt = _argmax(logits);
            out[pos] = _vocab(nxt);
            for (uint256 i = 0; i < C - 1; i++) ctx[i] = ctx[i + 1];
            ctx[C - 1] = nxt;
        }
        return string(out);
    }
}

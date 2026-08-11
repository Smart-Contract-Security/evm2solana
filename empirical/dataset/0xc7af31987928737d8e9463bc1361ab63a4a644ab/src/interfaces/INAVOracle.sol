// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedPriceBundle} from "./Types.sol";

interface INAVOracle {
    function ingest(SignedPriceBundle calldata bundle) external returns (uint64 round);
    function latestRound() external view returns (uint64);
    function priceOf(address asset) external view returns (uint256);
    function domainSeparator() external view returns (bytes32);
    function hashBundle(SignedPriceBundle calldata bundle) external view returns (bytes32);
    function recoverBundleSigner(SignedPriceBundle calldata bundle)
        external
        view
        returns (bytes32 digest, address recovered, bool signerMatches, bool recoveredTrusted);
    function recomputeTotalAssetsFromBundle(
        address vault,
        address usdc,
        SignedPriceBundle calldata bundle
    ) external view returns (uint256 totalAssetsValue);
}

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
library PoolIdLibrary {
    /// @notice Returns value equal to keccak256(abi.encode(poolKey))
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        bytes memory encoded = abi.encode(poolKey);
        bytes32 hash = keccak256(encoded);
        poolId = PoolId.wrap(hash);
    }
}
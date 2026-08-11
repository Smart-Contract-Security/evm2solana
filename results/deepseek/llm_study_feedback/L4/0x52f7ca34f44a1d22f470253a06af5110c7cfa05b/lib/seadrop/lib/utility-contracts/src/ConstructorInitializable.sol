// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * @author emo.eth
 * @notice Abstract smart contract that provides an onlyUninitialized modifier which only allows calling when
 *         from within a constructor of some sort, whether directly instantiating an inherting contract,
 *         or when delegatecalling from a proxy
 */
abstract contract ConstructorInitializable {
    modifier onlyConstructor() {
        // On Solana, we cannot check code length via address.code.
        // Instead, we use a storage flag to track initialization state.
        // This flag is set to true at the end of the constructor.
        // The modifier reverts if the contract is already initialized.
        if (_initialized()) {
            revert("AlreadyInitialized");
        }
        _;
    }

    bool private _initializedFlag;

    function _initialized() internal view returns (bool) {
        return _initializedFlag;
    }

    function _setInitialized() internal {
        _initializedFlag = true;
    }
}
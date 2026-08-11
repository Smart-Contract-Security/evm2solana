// SPDX-License-Identifier: MIT

/**
 * @author emo.eth
 * @notice Abstract smart contract that provides an onlyUninitialized modifier which only allows calling when
 *         from within a constructor of some sort, whether directly instantiating an inherting contract,
 *         or when delegatecalling from a proxy
 */
abstract contract ConstructorInitializable {
    modifier onlyConstructor() {
        // On Solana, we check if the data account has been initialized by checking its data length
        // The program account always has code, so we check the data account instead
        if (tx.accounts.dataAccount.data.length != 0) {
            revert("AlreadyInitialized");
        }
        _;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEternalStorage {
    function storedUser() external view returns (address);
    function storedBalance() external view returns (uint256);
}

/// @title EternalStorageProxy
/// @custom:storage-user 0x9030dcB01830EAA3D8BA285a824a05d8FB489aD0
/// @custom:eternal-storage 0xecfe30993612e636df37938f2d2428042f739468
contract EternalStorageProxy {
    address public constant storedUser =
        0x9030dcB01830EAA3D8BA285a824a05d8FB489aD0;

    address public constant eternalStorage =
        0xECFe30993612E636df37938f2d2428042f739468;

    /// @notice Human-readable summary (Etherscan Read → STORAGE_SUMMARY).
    string public constant STORAGE_SUMMARY =
        "storedUser=0x9030dcB01830EAA3D8BA285a824a05d8FB489aD0; eternalStorage=0xECFe30993612E636df37938f2d2428042f739468";

    uint256 public storedBalance;

    event StoragePublished(
        address indexed storedUser,
        address indexed eternalStorage,
        uint256 storedBalance
    );

    event ProxyLinked(
        address indexed eternalStorage,
        address indexed storedUser,
        uint256 storedBalance
    );

    constructor() {
        IEternalStorage store = IEternalStorage(eternalStorage);
        require(
            store.storedUser() == storedUser,
            "EternalStorage storedUser mismatch"
        );
        storedBalance = store.storedBalance();
        emit ProxyLinked(eternalStorage, storedUser, storedBalance);
        emit StoragePublished(storedUser, eternalStorage, storedBalance);
    }

    /// @notice Etherscan "Write" tab — publishes storage to Events (no state change except log).
    function publishStorage() external {
        emit StoragePublished(storedUser, eternalStorage, storedBalance);
    }

    /// @notice Etherscan "Write" tab — returns storage (shown after call; not a view in ABI).
    function queryStorage()
        external
        returns (address user, address storageContract, uint256 balance)
    {
        return (storedUser, eternalStorage, storedBalance);
    }

    function getStoredAccount() external pure returns (address) {
        return storedUser;
    }

    function getStoredBalance() external view returns (uint256) {
        return storedBalance;
    }

    function readFromEternalStorage()
        external
        view
        returns (address account, uint256 balance)
    {
        IEternalStorage store = IEternalStorage(eternalStorage);
        return (store.storedUser(), store.storedBalance());
    }
}

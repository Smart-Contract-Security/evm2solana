// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    BondContract
} from "../core/BondContract.sol";

import {
    BondEvents
} from "../libraries/BondEvents.sol";

import {
    BondStatus
} from "../libraries/BondEnums.sol";

import {
    OnlyOwner,
    ZeroAddress,
    InvalidClassId,
    ClassIdTaken
} from "../libraries/BondErrors.sol";

/// @title BondFactory
/// @notice Deploys BondContract instances and maintains a
///         directory keyed by address, issuer and classId.
contract BondFactory is BondEvents {
    /// @notice ФТ п.4.1: BondInfo — directory entry per issue.
    ///         `status` is filled at read time via cross-call
    ///         to keep it up-to-date.
    struct BondInfo {
        address bondAddress;
        uint256 classId;
        address issuer;
        uint256 creationTime;
        BondStatus status;
        string docHash;
    }

    address public immutable owner;

    address public immutable usdt;

    address[] public allBonds;

    mapping(address => bool) public isBond;

    /// All bonds grouped by issuer for cheap directory lookup.
    /// Append-only; entries are never removed.
    mapping(address => address[]) private _bondsByIssuer;

    /// classId -> bond address. 0x0 means unknown classId.
    mapping(uint256 => address) public bondByClassId;

    /// Static metadata recorded at creation time. `status` is
    /// stored as DRAFT on creation and is intentionally NOT
    /// updated here when the bond transitions; live reads of
    /// `status` go through cross-call (see `getBondInfo`).
    mapping(address => BondInfo) private _bondInfo;

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    constructor(address _usdt) {
        if (_usdt == address(0)) revert ZeroAddress();

        owner = msg.sender;
        usdt = _usdt;
    }

    /// @notice Deploy a new BondContract with its own EscrowVault.
    /// @dev    The `owner` of the new bond is set to this factory's
    ///         owner, keeping a single platform-wide operator.
    ///         `classId` must be non-zero and unique within the
    ///         factory.
    function createBond(
        address issuer,
        uint256 classId,
        uint256 issueStartDate,
        uint256 issueEndDate,
        uint256 maturityDate,
        uint256 issueVolume,
        uint256 minTokensForIssue,
        uint256 priceInUSDT,
        uint256 faceValue,
        string calldata docHash
    ) external onlyOwner returns (address) {
        if (classId == 0) revert InvalidClassId();
        if (bondByClassId[classId] != address(0)) {
            revert ClassIdTaken();
        }

        BondContract bond = new BondContract(
            owner,
            issuer,
            usdt,
            classId,
            issueStartDate,
            issueEndDate,
            maturityDate,
            issueVolume,
            minTokensForIssue,
            priceInUSDT,
            faceValue,
            docHash
        );

        address bondAddr = address(bond);

        allBonds.push(bondAddr);
        isBond[bondAddr] = true;
        _bondsByIssuer[issuer].push(bondAddr);
        bondByClassId[classId] = bondAddr;

        _bondInfo[bondAddr] = BondInfo({
            bondAddress: bondAddr,
            classId: classId,
            issuer: issuer,
            creationTime: block.timestamp,
            status: BondStatus.DRAFT,
            docHash: docHash
        });

        emit BondCreated(bondAddr, issuer, classId);

        return bondAddr;
    }

    // =====================================================
    // VIEWS  (ФТ п.4.1 / п.5.1)
    // =====================================================

    function totalBonds() external view returns (uint256) {
        return allBonds.length;
    }

    function getAllBonds()
        external
        view
        returns (address[] memory)
    {
        return allBonds;
    }

    function getBondsByIssuer(address issuer_)
        external
        view
        returns (address[] memory)
    {
        return _bondsByIssuer[issuer_];
    }

    function bondsByIssuerCount(address issuer_)
        external
        view
        returns (uint256)
    {
        return _bondsByIssuer[issuer_].length;
    }

    function bondByIssuerAt(address issuer_, uint256 index)
        external
        view
        returns (address)
    {
        return _bondsByIssuer[issuer_][index];
    }

    function getBondByClassId(uint256 classId)
        external
        view
        returns (address)
    {
        return bondByClassId[classId];
    }

    /// @return Live snapshot for a known bond, with `status`
    ///         read from the bond itself. Reverts (zero
    ///         struct) if the address was not produced by
    ///         this factory.
    function getBondInfo(address bondAddr)
        external
        view
        returns (BondInfo memory)
    {
        BondInfo memory info = _bondInfo[bondAddr];
        if (info.bondAddress == address(0)) {
            return info;
        }
        info.status = BondContract(bondAddr).status();
        return info;
    }

    function getAllBondInfos()
        external
        view
        returns (BondInfo[] memory list)
    {
        uint256 n = allBonds.length;
        list = new BondInfo[](n);
        for (uint256 i = 0; i < n; i++) {
            address addr = allBonds[i];
            BondInfo memory info = _bondInfo[addr];
            info.status = BondContract(addr).status();
            list[i] = info;
        }
    }
}

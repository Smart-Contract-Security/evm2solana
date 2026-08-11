// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20;

interface IAzimuth {
    event Activated(uint32 indexed point);
    event BrokeContinuity(uint32 indexed point, uint32 number);
    event ChangedDns(string primary, string secondary, string tertiary);
    event ChangedKeys(
        uint32 indexed point,
        bytes32 encryptionKey,
        bytes32 authenticationKey,
        uint32 cryptoSuiteVersion,
        uint32 keyRevisionNumber
    );
    event ChangedManagementProxy(
        uint32 indexed point,
        address indexed managementProxy
    );
    event ChangedSpawnProxy(uint32 indexed point, address indexed spawnProxy);
    event ChangedTransferProxy(
        uint32 indexed point,
        address indexed transferProxy
    );
    event ChangedVotingProxy(uint32 indexed point, address indexed votingProxy);
    event EscapeAccepted(uint32 indexed point, uint32 indexed sponsor);
    event EscapeCanceled(uint32 indexed point, uint32 indexed sponsor);
    event EscapeRequested(uint32 indexed point, uint32 indexed sponsor);
    event LostSponsor(uint32 indexed point, uint32 indexed sponsor);
    event OwnerChanged(uint32 indexed point, address indexed owner);
    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Spawned(uint32 indexed prefix, uint32 indexed child);

    function activatePoint(uint32 _point) external;

    function canManage(
        uint32 _point,
        address _who
    ) external view returns (bool result);

    function canSpawnAs(
        uint32 _point,
        address _who
    ) external view returns (bool result);

    function canTransfer(
        uint32 _point,
        address _who
    ) external view returns (bool result);

    function canVoteAs(
        uint32 _point,
        address _who
    ) external view returns (bool result);

    function cancelEscape(uint32 _point) external;

    function dnsDomains(uint256) external view returns (string memory);

    function doEscape(uint32 _point) external;

    function escapeRequests(uint32, uint256) external view returns (uint32);

    function escapeRequestsIndexes(
        uint32,
        uint32
    ) external view returns (uint256);

    function getContinuityNumber(
        uint32 _point
    ) external view returns (uint32 continuityNumber);

    function getEscapeRequest(
        uint32 _point
    ) external view returns (uint32 escape);

    function getEscapeRequests(
        uint32 _sponsor
    ) external view returns (uint32[] memory requests);

    function getEscapeRequestsCount(
        uint32 _sponsor
    ) external view returns (uint256 count);

    function getKeyRevisionNumber(
        uint32 _point
    ) external view returns (uint32 revision);

    function getKeys(
        uint32 _point
    )
        external
        view
        returns (bytes32 crypt, bytes32 auth, uint32 suite, uint32 revision);

    function getManagementProxy(
        uint32 _point
    ) external view returns (address manager);

    function getManagerFor(
        address _proxy
    ) external view returns (uint32[] memory mfor);

    function getManagerForCount(
        address _proxy
    ) external view returns (uint256 count);

    function getOwnedPointAtIndex(
        address _whose,
        uint256 _index
    ) external view returns (uint32 point);

    function getOwnedPointCount(
        address _whose
    ) external view returns (uint256 count);

    function getOwnedPoints(
        address _whose
    ) external view returns (uint32[] memory ownedPoints);

    function getOwner(uint32 _point) external view returns (address owner);

    function getPointSize(uint32 _point) external pure returns (uint8 _size);

    function getPrefix(uint32 _point) external pure returns (uint16 prefix);

    function getSpawnCount(
        uint32 _point
    ) external view returns (uint32 spawnCount);

    function getSpawnProxy(
        uint32 _point
    ) external view returns (address spawnProxy);

    function getSpawned(
        uint32 _point
    ) external view returns (uint32[] memory spawned);

    function getSpawningFor(
        address _proxy
    ) external view returns (uint32[] memory sfor);

    function getSpawningForCount(
        address _proxy
    ) external view returns (uint256 count);

    function getSponsor(uint32 _point) external view returns (uint32 sponsor);

    function getSponsoring(
        uint32 _sponsor
    ) external view returns (uint32[] memory sponsees);

    function getSponsoringCount(
        uint32 _sponsor
    ) external view returns (uint256 count);

    function getTransferProxy(
        uint32 _point
    ) external view returns (address transferProxy);

    function getTransferringFor(
        address _proxy
    ) external view returns (uint32[] memory tfor);

    function getTransferringForCount(
        address _proxy
    ) external view returns (uint256 count);

    function getVotingFor(
        address _proxy
    ) external view returns (uint32[] memory vfor);

    function getVotingForCount(
        address _proxy
    ) external view returns (uint256 count);

    function getVotingProxy(
        uint32 _point
    ) external view returns (address voter);

    function hasBeenLinked(uint32 _point) external view returns (bool result);

    function hasSponsor(uint32 _point) external view returns (bool has);

    function incrementContinuityNumber(uint32 _point) external;

    function isActive(uint32 _point) external view returns (bool equals);

    function isEscaping(uint32 _point) external view returns (bool escaping);

    function isLive(uint32 _point) external view returns (bool result);

    function isManagementProxy(
        uint32 _point,
        address _proxy
    ) external view returns (bool result);

    function isOperator(
        address _owner,
        address _operator
    ) external view returns (bool result);

    function isOwner(
        uint32 _point,
        address _address
    ) external view returns (bool result);

    function isRequestingEscapeTo(
        uint32 _point,
        uint32 _sponsor
    ) external view returns (bool equals);

    function isSpawnProxy(
        uint32 _point,
        address _proxy
    ) external view returns (bool result);

    function isSponsor(
        uint32 _point,
        uint32 _sponsor
    ) external view returns (bool result);

    function isTransferProxy(
        uint32 _point,
        address _proxy
    ) external view returns (bool result);

    function isVotingProxy(
        uint32 _point,
        address _proxy
    ) external view returns (bool result);

    function loseSponsor(uint32 _point) external;

    function managerFor(address, uint256) external view returns (uint32);

    function managerForIndexes(address, uint32) external view returns (uint256);

    function operators(address, address) external view returns (bool);

    function owner() external view returns (address);

    function pointOwnerIndexes(address, uint32) external view returns (uint256);

    function points(
        uint32
    )
        external
        view
        returns (
            bytes32 encryptionKey,
            bytes32 authenticationKey,
            bool hasSponsor,
            bool active,
            bool escapeRequested,
            uint32 sponsor,
            uint32 escapeRequestedTo,
            uint32 cryptoSuiteVersion,
            uint32 keyRevisionNumber,
            uint32 continuityNumber
        );

    function pointsOwnedBy(address, uint256) external view returns (uint32);

    function registerSpawned(uint32 _point) external;

    function renounceOwnership() external;

    function rights(
        uint32
    )
        external
        view
        returns (
            address owner,
            address managementProxy,
            address spawnProxy,
            address votingProxy,
            address transferProxy
        );

    function setDnsDomains(
        string memory _primary,
        string memory _secondary,
        string memory _tertiary
    ) external;

    function setEscapeRequest(uint32 _point, uint32 _sponsor) external;

    function setKeys(
        uint32 _point,
        bytes32 _encryptionKey,
        bytes32 _authenticationKey,
        uint32 _cryptoSuiteVersion
    ) external;

    function setManagementProxy(uint32 _point, address _proxy) external;

    function setOperator(
        address _owner,
        address _operator,
        bool _approved
    ) external;

    function setOwner(uint32 _point, address _owner) external;

    function setSpawnProxy(uint32 _point, address _proxy) external;

    function setTransferProxy(uint32 _point, address _proxy) external;

    function setVotingProxy(uint32 _point, address _proxy) external;

    function spawningFor(address, uint256) external view returns (uint32);

    function spawningForIndexes(
        address,
        uint32
    ) external view returns (uint256);

    function sponsoring(uint32, uint256) external view returns (uint32);

    function sponsoringIndexes(uint32, uint32) external view returns (uint256);

    function transferOwnership(address _newOwner) external;

    function transferringFor(address, uint256) external view returns (uint32);

    function transferringForIndexes(
        address,
        uint32
    ) external view returns (uint256);

    function votingFor(address, uint256) external view returns (uint32);

    function votingForIndexes(address, uint32) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

interface IBronToken {
    function lockedTokens(address) external view returns (uint64);
    function multisig() external view returns (address);
    function bronDao() external view returns (address);
    function oftContract() external view returns (address);
    function loyaltyLockedTokens(address) external view returns (uint64);
    function loyaltyProgramContract() external view returns (address);
    function votesSynced(address) external view returns (bool);
}

abstract contract BronTokenStorage is IBronToken {
    // ------------------------------
    // Constants
    // ------------------------------

    uint64 public constant TOTAL_SUPPLY = 10000000000 * 10**18;

    // ------------------------------
    // State variables
    // ------------------------------

    mapping(address => uint64) public lockedTokens;

    address public multisig;
    address public bronDao;

    address public oftContract;

    mapping(address => uint64) public loyaltyLockedTokens;
    address public loyaltyProgramContract;

    mapping(address => uint64) internal votesCheckpoints;
    uint64 internal totalCheckpoints;

    mapping(address => bool) public votesSynced;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint64[45] private __gap;
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IMATP} from "@atp/atps/milestone/IMATP.sol";

/**
 * @title RevocationPayload
 * @notice One-time use contract for revoking MATPs in a single atomic batch
 * @dev Security Design:
 *      - Immutable ATP address data (cannot be modified after deployment)
 *      - Deployer-only execution (DEPLOYER set in constructor)
 *      - Single-use execution with irreversibility checks
 *      - Post-revocation verification that reverts on any mismatch
 *      - All-or-nothing: if any revocation fails, entire tx reverts
 *
 *      This contract is designed to be deployed with hardcoded ATP addresses,
 *      then set as the revoker in the Registry by the MPC wallet. When run()
 *      is called by the DEPLOYER, the contract:
 *      1. Calls revoke() on each ATP
 *      2. Verifies all ATPs are marked as revoked (reverts if not)
 *
 *      The deployer cannot abuse this because:
 *      - run() cannot be called until MPC wallet sets this as revoker
 *      - The ATP addresses are immutable (hardcoded at deployment)
 *      - Only the DEPLOYER can call run()
 */
contract RevocationPayload {
    // ============ Immutable Configuration ============

    /// @notice The address that deployed this contract (only one who can call run())
    address public immutable DEPLOYER;

    /// @notice Total number of ATPs to revoke
    uint256 public immutable ATP_COUNT;

    /// @notice Hash of the ATP addresses for cryptographic verification
    bytes32 public immutable DATA_HASH;

    // ============ ATP Data (Set Once in Constructor) ============

    /// @notice Array of ATP addresses to revoke
    address[] internal _atps;

    // ============ Execution State ============

    /// @notice Whether run() has been executed
    bool public executed;

    // ============ Events ============

    event ATPRevoked(address indexed atp, uint256 amount);
    event PayloadExecuted(uint256 atpCount, uint256 totalRevoked);

    // ============ Errors ============

    error NotDeployer(address caller, address deployer);
    error AlreadyExecuted();
    error EmptyATPList();
    error ZeroATPAddress(uint256 index);
    error ATPNotRevoked(uint256 index, address atp);

    // ============ Constructor ============

    /**
     * @notice Creates a new RevocationPayload with hardcoded ATP addresses
     * @dev All data is validated and stored immutably. The DATA_HASH allows
     *      cryptographic verification that the deployed contract matches expected data.
     * @param atps_ Array of ATP addresses to revoke
     */
    constructor(address[] memory atps_) {
        require(atps_.length > 0, EmptyATPList());

        DEPLOYER = msg.sender;
        ATP_COUNT = atps_.length;

        // Validate all addresses are non-zero
        for (uint256 i = 0; i < atps_.length; i++) {
            require(atps_[i] != address(0), ZeroATPAddress(i));
        }

        _atps = atps_;
        DATA_HASH = keccak256(abi.encode(atps_));
    }

    // ============ Execution ============

    /**
     * @notice Execute the payload: revoke all ATPs and verify revocations
     * @dev Can only be called once by the DEPLOYER. Requires:
     *      1. This contract is set as the revoker in the Registry
     *      2. All ATPs have Pending milestone status (for MATP)
     *
     *      This function:
     *      1. Sets executed = true (prevents re-execution)
     *      2. Calls revoke() on each ATP
     *      3. Verifies all ATPs are marked as revoked (reverts if not)
     *
     *      ALL-OR-NOTHING: If any revocation fails, the entire transaction reverts.
     */
    function run() external {
        require(msg.sender == DEPLOYER, NotDeployer(msg.sender, DEPLOYER));
        require(!executed, AlreadyExecuted());
        executed = true;

        uint256 totalRevoked = 0;

        // Revoke all ATPs
        for (uint256 i = 0; i < ATP_COUNT; i++) {
            uint256 amount = IMATP(_atps[i]).revoke();
            totalRevoked += amount;
            emit ATPRevoked(_atps[i], amount);
        }

        // Post-revocation verification - reverts if any mismatch
        _verifyRevocations();

        emit PayloadExecuted(ATP_COUNT, totalRevoked);
    }

    /**
     * @notice Verify all ATPs are marked as revoked
     * @dev Reverts with descriptive error if any ATP is not revoked.
     */
    function _verifyRevocations() internal view {
        for (uint256 i = 0; i < ATP_COUNT; i++) {
            bool isRevoked = IMATP(_atps[i]).getIsRevoked();
            require(isRevoked, ATPNotRevoked(i, _atps[i]));
        }
    }

    // ============ View Functions for Reconciliation ============

    /**
     * @notice Get all ATP addresses for verification
     * @return atps_ Array of ATP addresses
     */
    function getATPAddresses() external view returns (address[] memory atps_) {
        return _atps;
    }

    /**
     * @notice Get ATP address by index
     * @param index The ATP index (0-based)
     * @return atp The ATP address
     */
    function getATP(uint256 index) external view returns (address atp) {
        return _atps[index];
    }

    /**
     * @notice Verify data hash matches expected values
     * @dev Allows cryptographic verification without reading all data on-chain
     * @param atps_ Expected ATP addresses
     * @return matches Whether the hash matches
     */
    function verifyDataHash(address[] calldata atps_) external view returns (bool matches) {
        return DATA_HASH == keccak256(abi.encode(atps_));
    }

    /**
     * @notice Check the revocation status of all ATPs
     * @return statuses Array of revocation statuses (true = revoked)
     */
    function getRevocationStatuses() external view returns (bool[] memory statuses) {
        statuses = new bool[](ATP_COUNT);
        for (uint256 i = 0; i < ATP_COUNT; i++) {
            statuses[i] = IMATP(_atps[i]).getIsRevoked();
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ─────────────────────────────────────────────────────────────────────────────
//  SupraLib · v1.1 dual-oracle · external-linked library for Supra glue
//
//  Bytecode-size optimization. BurnBombV1_1 (dual-oracle) pushes past the
//  EIP-170 24,576-byte deployed-code ceiling once both Chainlink + Supra
//  paths are inlined. SupraLib extracts the Supra-specific helpers that have
//  zero coupling to the round lifecycle / randomness logic.
//
//  Pattern mirrors ThroneLib + BulkWithdrawLib:
//    - `external` functions (deploy as separate bytecode, delegate-called).
//    - Storage primitives (bool / uint96 flags) are NOT passed as `storage`
//      refs (Solidity disallows storage refs to value types in library args).
//      Library computes + returns; caller writes state.
//    - User-facing events emit from the main contract wrapper.
//    - ETH transfers stay in main contract (nonReentrant + CEI). The library
//      calls IDepositContract.withdrawFundClient (which credits the contract
//      balance), validates, and returns the amount; caller forwards via .call.
//
//  Custom errors declared here for revert-from-library; selectors keccak-match
//  the main contract's identically-named errors.
// ─────────────────────────────────────────────────────────────────────────────

interface IDepositContract {
    function addClientToWhitelist(uint128 _maxGasPrice, uint128 _maxGasLimit) external payable;
    function addContractToWhitelist(address _contractAddress, uint128 _callbackGasPrice, uint128 _callbackGasLimit) external;
    function removeContractFromWhitelist(address _contractAddress) external;
    function depositFundClient() external payable;
    function withdrawFundClient(uint128 _amount) external;
    function checkClientFund(address _clientAddress) external view returns (uint128);
    function isContractWhitelisted(address _client, address _contract) external view returns (bool);
    function getMinBalanceLimit(uint128 _maxGasPrice, uint128 _maxGasLimit) external view returns (uint128);
}

library SupraLib {
    // Mirror the main contract's custom errors so library reverts surface
    // with identical selectors (keccak256 of the name).
    error BurnBomb_ZeroAddress();
    error NothingToWithdraw();
    error WouldDropBelowOperationalFloor();
    error CannotDisableBoth();
    error InvalidOracle();
    error BothOraclesFailed();

    // Indexer-visible event for try/catch failure surfacing (emitted from the
    // main contract address via DELEGATECALL).
    event OracleRequestFailed(uint256 indexed roundId, uint8 oracle);

    /// @dev Attempt a Supra deposit. Returns `funded`=true on success, false
    /// on revert. Caller emits event + accumulates pendingSupraReplenish on
    /// the false branch.
    function tryDeposit(address supraDepositContract, uint256 amount)
        external
        returns (bool funded)
    {
        if (amount == 0) return false;
        try IDepositContract(supraDepositContract).depositFundClient{value: amount}() {
            funded = true;
        } catch {
            funded = false;
        }
    }

    /// @dev Pre-deprecate path enforces SUPRA_OPERATIONAL_FLOOR; post-deprecate
    /// allows full recovery. Pulls funds from Deposit Contract into the main
    /// contract's balance; returns the actual amount so caller can forward.
    function pullSupraBalance(
        address supraDepositContract,
        bool deprecated_,
        uint128 operationalFloor,
        uint128 amount,
        address to
    ) external returns (uint128 actual) {
        if (to == address(0)) revert BurnBomb_ZeroAddress();
        if (amount == 0) revert NothingToWithdraw();
        if (!deprecated_) {
            uint128 current = IDepositContract(supraDepositContract).checkClientFund(address(this));
            if (current < amount) revert NothingToWithdraw();
            uint128 remaining = current - amount;
            if (remaining < operationalFloor) revert WouldDropBelowOperationalFloor();
        }
        IDepositContract(supraDepositContract).withdrawFundClient(amount);
        actual = amount;
    }

    /// @dev Validate a withdrawSupraReplenish call. Reverts on zero recipient
    /// or zero balance. Caller passes the current value; on success, caller
    /// zeroes its storage slot and transfers.
    function validateReplenishWithdraw(address to, uint96 currentPending)
        external
        pure
        returns (uint96 amount)
    {
        if (to == address(0)) revert BurnBomb_ZeroAddress();
        if (currentPending == 0) revert NothingToWithdraw();
        amount = currentPending;
    }

    /// @dev Validate a disableOracle call. Returns the new (chainlinkDisabled,
    /// supraDisabled) pair; caller writes the storage flags.
    function computeDisable(uint8 oracle, bool chainlinkDisabled, bool supraDisabled)
        external
        pure
        returns (bool newChainlinkDisabled, bool newSupraDisabled)
    {
        if (oracle == 1) {
            if (supraDisabled) revert CannotDisableBoth();
            return (true, supraDisabled);
        } else if (oracle == 2) {
            if (chainlinkDisabled) revert CannotDisableBoth();
            return (chainlinkDisabled, true);
        } else {
            revert InvalidOracle();
        }
    }

    /// @dev Validate an enableOracle call. Returns the new (chainlinkDisabled,
    /// supraDisabled) pair; caller writes the storage flags. No cross-oracle
    /// check — enable is strictly-safer direction.
    function computeEnable(uint8 oracle, bool chainlinkDisabled, bool supraDisabled)
        external
        pure
        returns (bool newChainlinkDisabled, bool newSupraDisabled)
    {
        if (oracle == 1) {
            return (false, supraDisabled);
        } else if (oracle == 2) {
            return (chainlinkDisabled, false);
        } else {
            revert InvalidOracle();
        }
    }

    /// @dev Dual-oracle request sequence. Both oracles fired (subject to
    /// disabled flags AND the optional `skipChainlinkIfPassed`/`skipSupraIfPassed`
    /// suppression used by the health-check path so an already-passed oracle
    /// is not re-requested).
    ///
    /// Implemented via low-level call to the main contract's `_requestXxxExternal()`
    /// wrappers because Solidity's `try this.fn()` doesn't compose from a
    /// library scope. Under DELEGATECALL the library runs in the main contract's
    /// context — `address(this)` IS the main contract — so the low-level call
    /// is functionally equivalent to the original `try this._requestChainlinkExternal()`
    /// pattern. The wrappers enforce `msg.sender == address(this)` so this
    /// helper is the only legitimate caller surface.
    ///
    /// Selectors are precomputed constants below for gas + bytecode efficiency.
    ///
    /// Reverts BothOraclesFailed when neither oracle yielded a request id.
    function dualOracleRequest(
        bool chainlinkDisabled,
        bool supraDisabled,
        bool skipChainlinkIfPassed,
        bool skipSupraIfPassed,
        uint256 roundIdForEvent
    ) external returns (uint256 clReqId, uint256 sNonce) {
        // bytes4(keccak256("_requestChainlinkExternal()"))
        // Derived 2026-05-25 via `keccak256(toUtf8Bytes("..."))[:10]` in
        // the contracts toolchain — not from memory. Matches the wrapper
        // declared on BurnBombV1_1.
        bytes4 clSel = 0x4d3117b2;
        // bytes4(keccak256("_requestSupraExternal()"))
        bytes4 sSel = 0x7a33542c;

        if (!chainlinkDisabled && !skipChainlinkIfPassed) {
            (bool ok, bytes memory ret) = address(this).call(abi.encodeWithSelector(clSel));
            if (ok && ret.length >= 32) {
                clReqId = abi.decode(ret, (uint256));
            } else {
                emit OracleRequestFailed(roundIdForEvent, 1);
            }
        }
        if (!supraDisabled && !skipSupraIfPassed) {
            (bool ok, bytes memory ret) = address(this).call(abi.encodeWithSelector(sSel));
            if (ok && ret.length >= 32) {
                sNonce = abi.decode(ret, (uint256));
            } else {
                emit OracleRequestFailed(roundIdForEvent, 2);
            }
        }
        if (clReqId == 0 && sNonce == 0) revert BothOraclesFailed();
    }
}

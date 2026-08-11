// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Forwarder} from "./Forwarder.sol";

/**
 * @title OrderForwarderFactory
 * @notice Deploys {Forwarder} contracts via CREATE2 with a caller-supplied
 *         salt, sweeping any ETH / USDT / USDC sitting at the predicted
 *         address to a hardcoded treasury.
 *
 * @dev    Trust model:
 *
 *           treasury, usdt, usdc are `immutable` — they are baked into
 *           the contract's bytecode at deploy time and CANNOT be changed
 *           by anyone after that. Not even the factory owner.
 *
 *           The factory owner key can ONLY trigger `sweep` / `sweepBatch`
 *           and `transferOwnership`. It CANNOT redirect funds elsewhere
 *           because the treasury is hardcoded into the Forwarder
 *           constructor args, which are passed unconditionally from the
 *           factory's immutable storage on every deploy. A compromised
 *           owner key can spam useless sweeps but cannot steal funds.
 *
 *           For a treasury change, deploy a brand-new factory pointing
 *           at the new treasury. Migration is "stop using the old
 *           factory, start using the new one" — no state to move.
 *
 *           Re-deployable forwarders: each Forwarder selfdestructs in
 *           its constructor (EIP-6780, same-tx-as-create). That lets us
 *           sweep the same CREATE2 address multiple times if the
 *           customer accidentally double-pays.
 */
contract OrderForwarderFactory {
    /// Destination for ALL funds. Immutable.
    address public immutable treasury;
    /// USDT token contract (mainnet: 0xdAC1...). Zero to skip.
    address public immutable usdt;
    /// USDC token contract (mainnet: 0xA0b8...). Zero to skip.
    address public immutable usdc;

    /// Single-step ownership. Owner can sweep + transfer ownership; nothing else.
    address public owner;

    event ForwarderDeployed(bytes32 indexed salt, address indexed forwarder);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error EmptyBatch();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /**
     * @param _treasury  Destination for all swept funds. Must be non-zero.
     * @param _usdt      USDT contract address (or zero to disable USDT sweeps).
     * @param _usdc      USDC contract address (or zero to disable USDC sweeps).
     * @param _owner     Initial owner. May be `msg.sender` if deployer = owner,
     *                   or a separate hot wallet for operational separation.
     *                   Must be non-zero.
     */
    constructor(address _treasury, address _usdt, address _usdc, address _owner) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        // _usdt and _usdc are intentionally allowed to be zero. We start
        // testnet with only USDC, for example.
        treasury = _treasury;
        usdt = _usdt;
        usdc = _usdc;
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @notice Compute the CREATE2 address for a given salt WITHOUT deploying.
     *         Used by the backend to derive a per-order receive address
     *         that we hand to the customer's wallet, then sweep later.
     *
     * @dev    Pure view function — no state changes, no gas cost from
     *         off-chain callers.
     */
    function predict(bytes32 salt) external view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(Forwarder).creationCode,
                abi.encode(treasury, usdt, usdc)
            )
        );
        return address(
            uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                initCodeHash
            ))))
        );
    }

    /**
     * @notice Deploy one Forwarder for one salt. Useful for testing or
     *         one-off sweeps. The cron normally uses {sweepBatch}.
     *
     * @return forwarder  Address of the deployed (and immediately
     *                    self-destructed) Forwarder. Will equal
     *                    {predict}(salt).
     */
    function sweep(bytes32 salt) external onlyOwner returns (address forwarder) {
        forwarder = address(new Forwarder{salt: salt}(treasury, usdt, usdc));
        emit ForwarderDeployed(salt, forwarder);
    }

    /**
     * @notice Deploy Forwarders for a batch of salts in one transaction.
     *         Each deployment is independent — if one Forwarder fails
     *         (e.g. malformed token at the time of sweep), the whole
     *         transaction reverts. Caller should de-duplicate / batch
     *         salts that are likely to succeed together.
     *
     * @dev    Gas cost roughly linear in `salts.length`. ~100 salts
     *         per tx is a comfortable upper bound on mainnet.
     */
    function sweepBatch(bytes32[] calldata salts)
        external
        onlyOwner
        returns (address[] memory forwarders)
    {
        uint256 n = salts.length;
        if (n == 0) revert EmptyBatch();
        forwarders = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            address fwd = address(new Forwarder{salt: salts[i]}(treasury, usdt, usdc));
            forwarders[i] = fwd;
            emit ForwarderDeployed(salts[i], fwd);
        }
    }

    /**
     * @notice Single-step ownership transfer. Use sparingly — there is
     *         no recovery if you transfer to the wrong address.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }
}

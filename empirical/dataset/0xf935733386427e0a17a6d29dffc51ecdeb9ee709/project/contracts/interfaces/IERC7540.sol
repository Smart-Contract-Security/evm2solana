// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

/**
 * @title IERC7540Operator - Operator Management Interface
 * @author Sivo
 * @notice Interface for managing operator permissions for ERC-7540 compatible vaults
 * @dev Allows controllers to designate operators who can act on their behalf
 */
interface IERC7540Operator {
    event OperatorSet(
        address indexed controller,
        address indexed operator,
        bool approved
    );

    /**
     * @dev Returns true if `operator` is approved to manage requests on behalf of `controller`
     *
     * - MUST NOT revert.
     *
     * @param controller The address that controls the operator permissions
     * @param operator The address to check if it has operator permissions
     * @return status Boolean indicating if operator is approved for controller
     */
    function isOperator(
        address controller,
        address operator
    ) external view returns (bool status);

    /**
     * @dev Grant or revoke operator permissions for msg.sender (the controller)
     *
     * - MUST emit the OperatorSet event.
     * - MUST return true on success.
     *
     * @param operator The address to grant or revoke permissions for
     * @param approved Boolean indicating whether to grant (true) or revoke (false) permissions
     * @return success Must be true on success
     */
    function setOperator(
        address operator,
        bool approved
    ) external returns (bool success);
}

/**
 * @title IERC7540Deposit - Asynchronous Deposit Interface
 * @author Sivo
 * @notice Interface for handling asynchronous deposits in ERC-7540 compatible vaults
 * @dev Provides methods for requesting and claiming deposits
 */
interface IERC7540Deposit {
    event DepositRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 assets
    );

    event DepositCancel(
        address indexed controller,
        address indexed receiver,
        address sender,
        uint256 assets
    );

    event DepositClaimable(
        address indexed controller,
        uint256 assets,
        uint256 shares
    );

    error ERC7540UnauthorizedSender(address sender, address subject);

    /**
     * @dev Initiate an asynchronous deposit request, locking assets and returning a requestId
     *
     * - MUST emit the DepositRequest event.
     * - MUST lock the assets until they can be claimed.
     * - MUST return a unique requestId that can be used to track and claim the deposit.
     *
     * @param assets The amount of assets to deposit
     * @param controller The address that will control this deposit
     * @param owner The address that owns the assets to be deposited
     * @return requestId An identifier for this deposit request. Always returns 0 which makes requests fungible.
     */
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of assets pending deposit for a controller under a specific requestId
     *
     * - MUST NOT revert if the requestId exists.
     * - MUST return 0 if the requestId does not exist or if the assets are no longer pending.
     *
     * @param requestId The unique identifier for the deposit request
     * @param controller The address controlling this deposit request
     * @return assets The amount of assets pending deposit
     */
    function pendingDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 assets);

    /**
     * @dev Returns the amount of assets claimable for deposit by a controller under a specific requestId
     *
     * - MUST NOT revert if the requestId exists.
     * - MUST return 0 if the requestId does not exist or if the assets are not yet claimable.
     *
     * @param requestId The unique identifier for the deposit request
     * @param controller The address controlling this deposit request
     * @return assets The amount of assets claimable for deposit
     */
    function claimableDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 assets);

    /**
     * @dev Claims deposited assets similar to ERC-4626 deposit, but with controller parameter
     *
     * - MUST emit the Deposit event.
     * - MUST convert the claimed assets to shares and transfer them to receiver.
     * - MUST revert if assets cannot be claimed.
     *
     * @param assets The amount of assets to claim
     * @param receiver The address that will receive the shares
     * @param controller The address controlling this deposit
     * @return shares The amount of shares minted to receiver
     */
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) external returns (uint256 shares);

    /**
     * @dev Claims deposited assets via ERC-4626 mint semantics, with controller parameter
     *
     * - MUST emit the Deposit event.
     * - MUST mint the specified shares to receiver.
     * - MUST revert if shares cannot be minted.
     *
     * @param shares The amount of shares to mint
     * @param receiver The address that will receive the shares
     * @param controller The address controlling this mint operation
     * @return assets The amount of assets used to mint the shares
     */
    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) external returns (uint256 assets);
}

/**
 * @title IERC7540Redeem - Asynchronous Redemption Interface
 * @author Sivo
 * @notice Interface for handling asynchronous redemptions in ERC-7540 compatible vaults
 * @dev Provides methods for requesting and tracking redemptions
 * @dev Semantics for redeem and withdraw functions: if the controller has claimable redemptions
 * it follows async (ERC-7540) semantics and consumes claimable redemptions with pricing that was
 * locked when the request transitioned to claimable.
 * Otherwise it follows sync (ERC-4626) semantics that consume shares.
 */
interface IERC7540Redeem {
    event RedeemRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares
    );

    event RedeemCancel(
        address indexed controller,
        address indexed receiver,
        address sender,
        uint256 shares
    );

    event RedeemClaimable(
        address indexed controller,
        uint256 assets,
        uint256 shares
    );

    /**
     * @dev Initiate an asynchronous redemption request, locking shares and returning a requestId
     *
     * - MUST emit the RedeemRequest event.
     * - MUST lock the shares until they can be redeemed.
     * - MUST return a unique requestId that can be used to track the redemption.
     *
     * @param shares The amount of shares to redeem
     * @param controller The address that will control this redemption
     * @param owner The address that owns the shares being redeemed
     * @return requestId A unique identifier for this redemption request. Always returns 0 which makes requests fungible.
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of shares pending redemption for a controller under a specific requestId
     *
     * - MUST NOT revert if the requestId exists.
     * - MUST return 0 if the requestId does not exist or if the shares are no longer pending.
     *
     * @param requestId The unique identifier for the redemption request
     * @param controller The address controlling this redemption request
     * @return shares The amount of shares pending redemption
     */
    function pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 shares);

    /**
     * @dev Returns the amount of shares claimable for redemption by a controller under a specific requestId
     *
     * - MUST NOT revert if the requestId exists.
     * - MUST return 0 if the requestId does not exist or if the shares are not yet claimable.
     *
     * @param requestId The unique identifier for the redemption request
     * @param controller The address controlling this redemption request
     * @return shares The amount of shares claimable for redemption
     */
    function claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 shares);
}

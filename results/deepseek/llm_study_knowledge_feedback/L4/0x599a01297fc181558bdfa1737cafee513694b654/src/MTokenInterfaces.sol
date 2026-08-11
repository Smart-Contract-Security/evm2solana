import "./ComptrollerInterface.sol";
import "./irm/InterestRateModel.sol";
import "./EIP20NonStandardInterface.sol";
import "./TokenErrorReporter.sol";

contract MTokenStorage {
    /// @dev Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice EIP-20 token name for this token
    string public name;

    /// @notice EIP-20 token symbol for this token
    string public symbol;

    /// @notice EIP-20 token decimals for this token
    uint8 public decimals;

    /// @notice Maximum borrow rate that can ever be applied (.0005% / block)
    uint64 internal constant borrowRateMaxMantissa = 0.0005e16;

    // @notice Maximum fraction of interest that can be set aside for reserves
    uint64 internal constant reserveFactorMaxMantissa = 1e18;

    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    /// @notice Contract which oversees inter-mToken operations
    address public comptroller;

    /// @notice Model which tells what the current interest rate should be
    address public interestRateModel;

    // @notice Initial exchange rate used when minting the first MTokens (used when totalSupply = 0)
    uint64 internal initialExchangeRateMantissa;

    /// @notice Fraction of interest currently set aside for reserves
    uint64 public reserveFactorMantissa;

    /// @notice Block number that interest was last accrued at
    uint64 public accrualBlockTimestamp;

    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint64 public borrowIndex;

    /// @notice Total amount of outstanding borrows of the underlying in this market
    uint64 public totalBorrows;

    /// @notice Total amount of reserves of the underlying held in this market
    uint64 public totalReserves;

    /// @notice Total number of tokens in circulation
    uint64 public totalSupply;

    /// @notice Official record of token balances for each account
    mapping(address => uint64) internal accountTokens;

    /// @notice Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint64)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @param principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @param interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint64 principal;
        uint64 interestIndex;
    }

    // @notice Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /// @notice Share of seized collateral that is added to reserves
    uint64 public protocolSeizeShareMantissa;
}

abstract contract MTokenInterface is MTokenStorage {
    /// @notice Indicator that this is a MToken contract (for inspection)
    bool public constant isMToken = true;

    /*** Market Events ***/

    /// @notice Event emitted when interest is accrued
    event AccrueInterest(
        uint64 cashPrior,
        uint64 interestAccumulated,
        uint64 borrowIndex,
        uint64 totalBorrows
    );

    /// @notice Event emitted when tokens are minted
    event Mint(address minter, uint64 mintAmount, uint64 mintTokens);

    /// @notice Event emitted when tokens are redeemed
    event Redeem(address redeemer, uint64 redeemAmount, uint64 redeemTokens);

    /// @notice Event emitted when underlying is borrowed
    event Borrow(
        address borrower,
        uint64 borrowAmount,
        uint64 accountBorrows,
        uint64 totalBorrows
    );

    /// @notice Event emitted when a borrow is repaid
    event RepayBorrow(
        address payer,
        address borrower,
        uint64 repayAmount,
        uint64 accountBorrows,
        uint64 totalBorrows
    );

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint64 repayAmount,
        address mTokenCollateral,
        uint64 seizeTokens
    );

    /*** Admin Events ***/

    /// @notice Event emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Event emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Event emitted when comptroller is changed
    event NewComptroller(
        address oldComptroller,
        address newComptroller
    );

    /// @notice Event emitted when interestRateModel is changed
    event NewMarketInterestRateModel(
        address oldInterestRateModel,
        address newInterestRateModel
    );

    /// @notice Event emitted when the reserve factor is changed
    event NewReserveFactor(
        uint64 oldReserveFactorMantissa,
        uint64 newReserveFactorMantissa
    );

    /// @notice Event emitted when the protocol seize share is changed
    event NewProtocolSeizeShare(
        uint64 oldProtocolSeizeShareMantissa,
        uint64 newProtocolSeizeShareMantissa
    );

    /// @notice Event emitted when the reserves are added
    event ReservesAdded(
        address benefactor,
        uint64 addAmount,
        uint64 newTotalReserves
    );

    /// @notice Event emitted when the reserves are reduced
    event ReservesReduced(
        address admin,
        uint64 reduceAmount,
        uint64 newTotalReserves
    );

    /// @notice EIP20 Transfer event
    event Transfer(address from, address to, uint64 amount);

    /// @notice EIP20 Approval event
    event Approval(address owner, address spender, uint64 amount);

    /*** User Interface ***/

    function transfer(address dst, uint64 amount) external virtual returns (bool);
    function transferFrom(
        address src,
        address dst,
        uint64 amount
    ) external virtual returns (bool);
    function approve(
        address spender,
        uint64 amount
    ) external virtual returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view virtual returns (uint64);
    function balanceOf(address owner) external view virtual returns (uint64);
    function balanceOfUnderlying(address owner) external virtual returns (uint64);
    function getAccountSnapshot(
        address account
    ) external view virtual returns (uint64, uint64, uint64, uint64);
    function borrowRatePerTimestamp() external view virtual returns (uint64);
    function supplyRatePerTimestamp() external view virtual returns (uint64);
    function totalBorrowsCurrent() external virtual returns (uint64);
    function borrowBalanceCurrent(
        address account
    ) external virtual returns (uint64);
    function borrowBalanceStored(
        address account
    ) external view virtual returns (uint64);
    function exchangeRateCurrent() external virtual returns (uint64);
    function exchangeRateStored() external view virtual returns (uint64);
    function getCash() external view virtual returns (uint64);
    function accrueInterest() external virtual returns (uint64);
    function seize(
        address liquidator,
        address borrower,
        uint64 seizeTokens
    ) external virtual returns (uint64);

    /*** Admin Functions ***/

    function _setPendingAdmin(
        address newPendingAdmin
    ) external virtual returns (uint64);
    function _acceptAdmin() external virtual returns (uint64);
    function _setComptroller(
        address newComptroller
    ) external virtual returns (uint64);
    function _setReserveFactor(
        uint64 newReserveFactorMantissa
    ) external virtual returns (uint64);
    function _reduceReserves(uint64 reduceAmount) external virtual returns (uint64);
    function _setInterestRateModel(
        address newInterestRateModel
    ) external virtual returns (uint64);
    function _setProtocolSeizeShare(
        uint64 newProtocolSeizeShareMantissa
    ) external virtual returns (uint64);
}

contract MErc20Storage {
    /// @notice Underlying asset for this MToken
    address public underlying;
}

abstract contract MErc20Interface is MErc20Storage {
    /*** User Interface ***/

    function mint(uint64 mintAmount) external virtual returns (uint64);
    function mintWithPermit(
        uint64 mintAmount,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual returns (uint64);
    function redeem(uint64 redeemTokens) external virtual returns (uint64);
    function redeemUnderlying(
        uint64 redeemAmount
    ) external virtual returns (uint64);
    function borrow(uint64 borrowAmount) external virtual returns (uint64);
    function repayBorrow(uint64 repayAmount) external virtual returns (uint64);
    function repayBorrowBehalf(
        address borrower,
        uint64 repayAmount
    ) external virtual returns (uint64);
    function liquidateBorrow(
        address borrower,
        uint64 repayAmount,
        address mTokenCollateral
    ) external virtual returns (uint64);
    function sweepToken(address token) external virtual;

    /*** Admin Functions ***/

    function _addReserves(uint64 addAmount) external virtual returns (uint64);
}

contract MDelegationStorage {
    /// @notice Implementation address for this contract
    address public implementation;
}

abstract contract MDelegatorInterface is MDelegationStorage {
    /// @notice Emitted when implementation is changed
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(
        address implementation_,
        bool allowResign,
        bytes memory becomeImplementationData
    ) external virtual;
}

abstract contract MDelegateInterface is MDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) external virtual;

    /// @notice Called by the delegator on a delegate to forfeit its responsibility
    function _resignImplementation() external virtual;
}
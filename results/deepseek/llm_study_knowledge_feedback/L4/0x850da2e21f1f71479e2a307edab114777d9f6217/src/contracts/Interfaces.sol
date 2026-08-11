import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
    function decimals() external view returns (uint8);

    event Transfer(address indexed from, address indexed to, uint64 value);
}

interface ILiquidityProviderARM is IERC20 {
    function previewDeposit(uint64 assets) external returns (uint64 shares);
    function deposit(uint64 assets) external returns (uint64 shares);
    function deposit(uint64 assets, address liquidityProvider) external returns (uint64 shares);

    function previewRedeem(uint64 shares) external returns (uint64 assets);
    function requestRedeem(uint64 shares) external returns (uint64 requestId, uint64 assets);
    function claimRedeem(uint64 requestId) external returns (uint64 assets);

    function totalAssets() external returns (uint64 assets);
    function convertToShares(uint64 assets) external returns (uint64 shares);
    function convertToAssets(uint64 shares) external returns (uint64 assets);
    function lastTotalAssets() external returns (uint64 assets);
}

interface ICapManager {
    function postDepositHook(address liquidityProvider, uint64 assets) external;
}

interface LegacyAMM {
    function transferToken(address tokenOut, address to, uint64 amount) external;
}

interface IOriginVault {
    function mint(address _asset, uint64 _amount, uint64 _minimumOusdAmount) external;

    function redeem(uint64 _amount, uint64 _minimumUnitAmount) external;

    function requestWithdrawal(uint64 amount) external returns (uint64 requestId, uint64 queued);

    function claimWithdrawal(uint64 requestId) external returns (uint64 amount);

    function claimWithdrawals(uint64[] memory requestIds)
        external
        returns (uint64[] memory amounts, uint64 totalAmount);

    function addWithdrawalQueueLiquidity() external;

    function setMaxSupplyDiff(uint64 _maxSupplyDiff) external;

    function governor() external view returns (address);

    function dripper() external view returns (address);

    function withdrawalQueueMetadata()
        external
        view
        returns (uint64 queued, uint64 claimable, uint64 claimed, uint64 nextWithdrawalIndex);

    function withdrawalRequests(uint64 requestId)
        external
        view
        returns (address withdrawer, bool claimed, uint40 timestamp, uint64 amount, uint64 queued);

    function withdrawalClaimDelay() external view returns (uint64);
}

interface IGovernance {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function state(uint64 proposalId) external view returns (ProposalState);

    function proposalSnapshot(uint64 proposalId) external view returns (uint64);

    function proposalDeadline(uint64 proposalId) external view returns (uint64);

    function proposalEta(uint64 proposalId) external view returns (uint64);

    function votingDelay() external view returns (uint64);

    function castVote(uint64 proposalId, uint8 support) external returns (uint64 balance);

    function queue(uint64 proposalId) external;

    function execute(uint64 proposalId) external;
}

interface IWETH is IERC20 {
    event Deposit(address indexed dst, uint64 wad);
    event Withdrawal(address indexed src, uint64 wad);

    function deposit() external;
    function withdraw(uint64 wad) external;
}

interface ISTETH is IERC20 {
    event Submitted(address indexed sender, uint64 amount, address referral);

    function submit(address _referral) external returns (uint64);
}

interface IStETHWithdrawal {
    event WithdrawalRequested(
        uint64 indexed requestId,
        address indexed requestor,
        address indexed owner,
        uint64 amountOfStETH,
        uint64 amountOfShares
    );
    event WithdrawalsFinalized(
        uint64 indexed from, uint64 indexed to, uint64 amountOfETHLocked, uint64 sharesToBurn, uint64 timestamp
    );
    event WithdrawalClaimed(
        uint64 indexed requestId, address indexed owner, address indexed receiver, uint64 amountOfETH
    );

    struct WithdrawalRequestStatus {
        uint64 amountOfStETH;
        uint64 amountOfShares;
        address owner;
        uint64 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function transferFrom(address _from, address _to, uint64 _requestId) external;
    function ownerOf(uint64 _requestId) external returns (address);
    function requestWithdrawals(uint64[] calldata _amounts, address _owner)
        external
        returns (uint64[] memory requestIds);
    function getLastCheckpointIndex() external view returns (uint64);
    function findCheckpointHints(uint64[] calldata _requestIds, uint64 _firstIndex, uint64 _lastIndex)
        external
        view
        returns (uint64[] memory hintIds);
    function claimWithdrawals(uint64[] calldata _requestIds, uint64[] calldata _hints) external;
    function getWithdrawalStatus(uint64[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function getWithdrawalRequests(address _owner) external view returns (uint64[] memory requestsIds);
    function getLastRequestId() external view returns (uint64);
}

interface IOracle {
    function price(address asset) external view returns (uint64 price);
}

interface IHarvestable {
    function collectRewards() external returns (address[] memory tokens, uint64[] memory rewards);
}

interface IMagpieRouter {
    function swapWithMagpieSignature(bytes calldata) external returns (uint64 amountOut);
}

library DistributionTypes {
    struct IncentivesProgramCreationInput {
        string name;
        address rewardToken;
        uint64 emissionPerSecond;
        uint40 distributionEnd;
    }
}

library IDistributionManager {
    struct AccruedRewards {
        uint64 amount;
        bytes32 programId;
        address rewardToken;
    }
}

interface SiloIncentivesControllerGaugeLike {
    function claimRewards(address _to) external returns (IDistributionManager.AccruedRewards[] memory accruedRewards);
    function createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput)
        external;
    function getAllProgramsNames() external view returns (string[] memory programsNames);
    function getRewardsBalance(address _user, string memory _programName)
        external
        view
        returns (uint64 unclaimedRewards);
    function incentivesPrograms(bytes32)
        external
        view
        returns (
            uint64 index,
            address rewardToken,
            uint64 emissionPerSecond,
            uint40 lastUpdateTimestamp,
            uint40 distributionEnd
        );
    function owner() external view returns (address);
}

interface IEETHWithdrawal {
    function requestWithdraw(address receipient, uint64 amount) external returns (uint64 requestId);
}

interface IEETHWithdrawalNFT {
    function finalizeRequests(uint64 requestId) external;
    function claimWithdraw(uint64 requestId) external;
    function batchClaimWithdraw(uint64[] calldata requestIds) external;
}

interface IEETHRedemptionManager {
    function redeemEEth(uint64 amount, address receiver) external;
    function redeemWeEth(uint64 amount, address receiver) external;
    function canRedeem(uint64 amount) external view returns (bool);
}

interface IDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint64[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}

struct UserCooldown {
    uint64 cooldownEnd;
    uint64 underlyingAmount;
}

interface IStakedUSDe is IERC4626 {
    function cooldownAssets(uint64 assets) external returns (uint64 shares);

    function cooldownShares(uint64 shares) external returns (uint64 assets);

    function unstake(address receiver) external;

    function cooldowns(address receiver) external view returns (UserCooldown memory);

    function getUnvestedAmount() external view returns (uint64);

    function lastDistributionTimestamp() external view returns (uint64);

    function transferInRewards(uint64 amount) external;
}
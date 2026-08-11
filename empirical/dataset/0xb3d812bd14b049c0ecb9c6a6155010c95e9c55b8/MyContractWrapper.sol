// File: @openzeppelin\contracts\token\ERC20\IERC20.sol

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}


/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

pragma solidity ^0.8.20;
interface IUtilityContractManager {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    // Add other needed functions from the manager
}
 
contract MyContractWrapper is ReentrancyGuard, Ownable {
    IUtilityContractManager public immutable myContract;
    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;
    uint256 public immutable maxStakeAmount;
    address public feeRecipient;
    uint256 public transactionFeeRate;
   
    // User deposits tracked in the wrapper
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userStakes;
    mapping(address => uint256) public lastClaimBlock;
   
    // Total amount currently staked in the manager contract
    uint256 public totalStakedInManager;
   
    // Emergency fund - buffer tokens held by the wrapper
    uint256 public emergencyFundBalance;
   
    event Deposited(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event Stake(address indexed user, uint256 amount);
    event EmergencyFundIncreased(uint256 amount);
    event EmergencyFundDecreased(uint256 amount);
   
    constructor(
    address _myContract,
    address _lpToken,
    address _rewardToken,
    uint256 _maxStakeAmount,
    address _feeRecipient,
    uint256 _transactionFeeRate
) {
    require(_myContract != address(0), "Invalid: myContract is zero");
    require(_lpToken != address(0), "Invalid: lpToken is zero");
    require(_rewardToken != address(0), "Invalid: rewardToken is zero");
    require(_feeRecipient != address(0), "Invalid: feeRecipient is zero");

    myContract = IUtilityContractManager(_myContract);
    lpToken = IERC20(_lpToken);
    rewardToken = IERC20(_rewardToken);
    maxStakeAmount = _maxStakeAmount;
    feeRecipient = _feeRecipient;
    transactionFeeRate = _transactionFeeRate;
}

    /**
     * @dev Deposit function that handles user LP token deposits
     * This now uses the batch staking pattern
     */
    // Example for deposit function
function deposit(uint256 amount) external {
    // Checks
    require(amount > 0, "Amount must be greater than 0");
    
    // Effects (update state first)
    userDeposits[msg.sender] += amount;
    
    // Emit event before external calls
    emit Deposited(msg.sender, amount);
    
    // Interactions (external calls last)
    require(lpToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
}
   
    /**
     * @dev Internal function to stake tokens to the manager contract
     * This is called by deposit or can be called separately by admin
     */
    function _stakeToManager(uint256 amount) internal {
        // Ensure we have enough unstaked balance
        uint256 unstaked = _getUnstakedBalance();
        require(unstaked >= amount, "Not enough unstaked balance");
       
        // Effects first - update state variables before external calls
    totalStakedInManager += amount;
    
    // Interactions last - make external calls after state updates
    lpToken.approve(address(myContract), amount);

    myContract.stake(amount);
}
   
    /**
     * @dev Admin function to batch stake collected deposits to the manager
     */
    function batchStakeToManager(uint256 amount) external onlyOwner {
        _stakeToManager(amount);
    }
   
    /**
     * @dev Get unstaked LP token balance - tokens held by this contract but not yet staked in manager
     */
    function _getUnstakedBalance() internal view returns (uint256) {
        return lpToken.balanceOf(address(this)) - emergencyFundBalance;
    }
   
    /**
     * @dev Emergency withdrawal function
     * This uses a dedicated emergency fund to ensure users can always instantly withdraw
     */
    function emergencyWithdraw() external nonReentrant {
        uint256 amount = userDeposits[msg.sender];
        require(amount > 0, "No deposits");
       
        // Update state before external calls
        userDeposits[msg.sender] = 0;
       
        // Emit event
        emit EmergencyWithdrawn(msg.sender, amount);
       
        // Check if we have enough in the emergency fund
        require(emergencyFundBalance >= amount, "Emergency fund depleted");
       
        // Reduce emergency fund balance
        emergencyFundBalance -= amount;
       
        // Transfer to user
        require(lpToken.transfer(msg.sender, amount), "LP token transfer failed");
       
        // Add a recovery task for admin to replenish from manager
        // This could be logged in an event or tracked in a mapping
    }
   
    /**
     * @dev Admin function to increase emergency fund
     */
    function increaseEmergencyFund(uint256 amount) external onlyOwner {
        uint256 unstaked = _getUnstakedBalance();
        require(unstaked >= amount, "Not enough unstaked tokens");
       
        emergencyFundBalance += amount;
        emit EmergencyFundIncreased(amount);
    }
   
    /**
     * @dev Admin function to withdraw from manager and replenish emergency fund
     */
     function replenishFromManager(uint256 amount) external onlyOwner nonReentrant {
    // Checks
    require(totalStakedInManager >= amount, "Not enough staked in manager");
    
    // Effects - update all state variables first
    totalStakedInManager -= amount;
    emergencyFundBalance += amount;
    
    // Event emission (part of effects)
    emit EmergencyFundIncreased(amount);
    
    // Interactions - external calls last
    myContract.withdraw(amount);
}
   
    /**
     * @dev Admin function to decrease emergency fund (if needed)
     */
    function decreaseEmergencyFund(uint256 amount) external onlyOwner {
        require(emergencyFundBalance >= amount, "Emergency fund too small");
       
        emergencyFundBalance -= amount;
        emit EmergencyFundDecreased(amount);
    }
   
    // View function to get user's staked balance
    function getStakedBalance(address user) external view returns (uint256) {
        return userDeposits[user];
    }
   
    function stake(uint256 amount) external nonReentrant {
        // Checks
        require(amount > 0, "Amount must be greater than 0");
       
        // Effects
        userStakes[msg.sender] += amount;
       
        // Interactions
        require(lpToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
       
        emit Stake(msg.sender, amount);
    }
   
    uint256 constant MIN_CLAIM_BLOCKS = 6500; // about 24 hours at 13s/block
   
    function claimRewards() external nonReentrant {
        uint256 lastBlock = lastClaimBlock[msg.sender];
        uint256 currentBlock = block.number;
        require(currentBlock - lastBlock >= MIN_CLAIM_BLOCKS, "Too early to claim");
       
        // ... rest of your claiming logic ...
       
        lastClaimBlock[msg.sender] = currentBlock;
    }
   
    /**
     * @dev Function to get total balance including both staked and unstaked
     */
    function getTotalWrapperBalance() external view returns (uint256) {
        return lpToken.balanceOf(address(this)) + totalStakedInManager;
    }
   
    /**
     * @dev Check if emergency fund is sufficient to cover all deposits
     */
    function isEmergencyFundSufficient() external view returns (bool) {
        uint256 totalDeposits = 0;
        // In a real implementation, you'd need to optimize this
        // Perhaps by keeping a running total of deposits
        return emergencyFundBalance >= totalDeposits;
    }
}
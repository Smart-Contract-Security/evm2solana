// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20RescueTarget {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title OperatorToken
/// @notice Plain fixed-supply ERC20 for operator-controlled ETH launches.
/// @dev No tax logic lives in token. Optional delayed trading gate only.
contract SHDW {
    string private _name;
    string private _symbol;
    string public projectInfo;

    uint8 public constant decimals = 18;
    string public constant contractVersion = "Transparent Hook Operator Token v1";

    address public immutable controller;
    address public immutable rescueReceiver;
    uint16 public immutable maxTxBps;
    uint256 public immutable maxTxAmount;
    bool public tradingOpen;
    uint256 public totalSupply;

    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    mapping(address account => bool) public isTradingExempt;
    mapping(address account => bool) public isMaxTxExempt;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ETHReceived(address indexed sender, uint256 amount);
    event ETHRescued(address indexed receiver, uint256 amount);
    event ERC20Rescued(address indexed token, address indexed receiver, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TradingOpened(address indexed token, address indexed controller);
    event TradingExemptSet(address indexed account, bool exempt);
    event MaxTxExemptSet(address indexed account, bool exempt);

    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidAddress();
    error NotController();
    error NotRescueReceiver();
    error RescueTransferFailed();
    error TradingAlreadyOpen();
    error TradingClosed();
    error InvalidBps();
    error MaxTxExceeded();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply_,
        address initialHolder_,
        address rescueReceiver_,
        string memory projectInfo_,
        uint16 maxTxBps_,
        bool tradingOpenOnDeploy_,
        address[] memory tradingExemptions_,
        address[] memory maxTxExemptions_
    ) {
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidAddress();
        if (initialHolder_ == address(0) || rescueReceiver_ == address(0)) revert InvalidAddress();
        if (supply_ == 0) revert InvalidAddress();
        if (maxTxBps_ > 10_000) revert InvalidBps();

        _name = name_;
        _symbol = symbol_;
        controller = initialHolder_;
        rescueReceiver = rescueReceiver_;
        projectInfo = projectInfo_;
        maxTxBps = maxTxBps_;
        tradingOpen = tradingOpenOnDeploy_;
        totalSupply = supply_;
        maxTxAmount = maxTxBps_ == 0 ? 0 : (supply_ * maxTxBps_) / 10_000;

        _setTradingExempt(initialHolder_, true);
        _setTradingExempt(rescueReceiver_, true);
        _setTradingExempt(address(this), true);
        _setMaxTxExempt(initialHolder_, true);
        _setMaxTxExempt(rescueReceiver_, true);
        _setMaxTxExempt(address(this), true);
        for (uint256 index = 0; index < tradingExemptions_.length; index += 1) {
            _setTradingExempt(tradingExemptions_[index], true);
        }
        for (uint256 index = 0; index < maxTxExemptions_.length; index += 1) {
            _setMaxTxExempt(maxTxExemptions_[index], true);
        }

        balanceOf[initialHolder_] = supply_;
        emit Transfer(address(0), initialHolder_, supply_);
        emit OwnershipTransferred(msg.sender, address(0));
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function owner() external pure returns (address) {
        return address(0);
    }

    function renounceOwnership() external pure returns (bool) {
        return true;
    }

    function openTrading() external returns (bool) {
        if (msg.sender != controller) revert NotController();
        if (tradingOpen) revert TradingAlreadyOpen();
        tradingOpen = true;
        emit TradingOpened(address(this), controller);
        return true;
    }

    function setTradingExempt(address account, bool exempt) external returns (bool) {
        if (msg.sender != controller) revert NotController();
        _setTradingExempt(account, exempt);
        return true;
    }

    function setMaxTxExempt(address account, bool exempt) external returns (bool) {
        if (msg.sender != controller) revert NotController();
        _setMaxTxExempt(account, exempt);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = currentAllowance - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, allowance[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowance[msg.sender][spender];
        if (currentAllowance < subtractedValue) revert InsufficientAllowance();
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function burnAll() external returns (uint256 burned) {
        burned = balanceOf[msg.sender];
        _burn(msg.sender, burned);
    }

    function burnFrom(address account, uint256 value) external {
        uint256 currentAllowance = allowance[account][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                allowance[account][msg.sender] = currentAllowance - value;
            }
            emit Approval(account, msg.sender, allowance[account][msg.sender]);
        }
        _burn(account, value);
    }

    function rescueETH(uint256 amount) external returns (uint256 rescued) {
        _onlyRescueReceiver();
        rescued = amount == 0 ? address(this).balance : amount;
        (bool ok,) = rescueReceiver.call{value: rescued}("");
        if (!ok) revert RescueTransferFailed();
        emit ETHRescued(rescueReceiver, rescued);
    }

    function rescueERC20(address token, uint256 amount) external returns (uint256 rescued) {
        _onlyRescueReceiver();
        if (token == address(0)) revert InvalidAddress();

        rescued = amount == 0 ? IERC20RescueTarget(token).balanceOf(address(this)) : amount;
        bool ok = IERC20RescueTarget(token).transfer(rescueReceiver, rescued);
        if (!ok) revert RescueTransferFailed();
        emit ERC20Rescued(token, rescueReceiver, rescued);
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0) || to == address(0)) revert InvalidAddress();

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();
        if (from == to) {
            emit Transfer(from, to, value);
            return;
        }

        _enforceTradingOpen(from, to);
        _enforceMaxTx(from, to, value);

        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] = balanceOf[to] + value;
        }

        emit Transfer(from, to, value);
    }

    function _burn(address account, uint256 value) private {
        if (account == address(0)) revert InvalidAddress();
        uint256 accountBalance = balanceOf[account];
        if (accountBalance < value) revert InsufficientBalance();

        unchecked {
            balanceOf[account] = accountBalance - value;
            totalSupply -= value;
        }

        emit Transfer(account, address(0), value);
    }

    function _approve(address owner_, address spender, uint256 value) private {
        if (owner_ == address(0) || spender == address(0)) revert InvalidAddress();
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _setTradingExempt(address account, bool exempt) private {
        if (account == address(0)) return;
        isTradingExempt[account] = exempt;
        emit TradingExemptSet(account, exempt);
    }

    function _setMaxTxExempt(address account, bool exempt) private {
        if (account == address(0)) return;
        isMaxTxExempt[account] = exempt;
        emit MaxTxExemptSet(account, exempt);
    }

    function _onlyRescueReceiver() private view {
        if (msg.sender != rescueReceiver) revert NotRescueReceiver();
    }

    function _enforceTradingOpen(address from, address to) private view {
        if (tradingOpen) return;
        if (isTradingExempt[from] || isTradingExempt[to]) return;
        revert TradingClosed();
    }

    function _enforceMaxTx(address from, address to, uint256 value) private view {
        if (maxTxAmount == 0) return;
        if (isMaxTxExempt[from] || isMaxTxExempt[to]) return;
        if (value > maxTxAmount) revert MaxTxExceeded();
    }
}

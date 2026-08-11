// Sources flattened with hardhat v2.23.0 https://hardhat.org

// SPDX-License-Identifier: MIT

// File contracts/openzeppelin-contracts-5.0.0/token/ERC20/IERC20.sol

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

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
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File contracts/bridge/APMtoVIPBridge.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity 0.8.20;
contract APMToVIPBridge {
    IERC20 public immutable ERC20_APM;
    
    constructor(address _apm) {
        require(_apm != address(0), "Invalid APM address");
        ERC20_APM = IERC20(_apm);
    }

    /**
     * @notice IMPORTANT: Only events after 32 confirmations are considered valid for bridge processing
     * 
     * @param senderERC20Address    Sender address on Ethereum
     * @param receiverBEP20Address  Receiver address on BSC
     * @param amount                Amount of APM
     */
    event Bridged(
        address indexed senderERC20Address,
        address indexed receiverBEP20Address, 
        uint256 amount
    );
    
    /**
     * @param receiverBEP20Address Receiver address on BSC
     */
    function bridge(address receiverBEP20Address) external {
        require(receiverBEP20Address != address(0), "Invalid BEP20 address");
        
        uint256 amount = ERC20_APM.balanceOf(msg.sender);
        require(amount > 0, "No APM balance");
        
        uint256 allowance = ERC20_APM.allowance(msg.sender, address(this));
        require(allowance >= amount, "Insufficient allowance");

        require(ERC20_APM.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        emit Bridged(msg.sender, receiverBEP20Address, amount);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SendAll is AccessControl, ReentrancyGuard {

  using Address for address;
  using SafeERC20 for IERC20;

  bytes32 public constant LORD_ROLE = keccak256("LORD_ROLE");
  bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

  address internal constant NATIVE_TOKEN = address(0);

  struct Mixed {
    address token;
    address[] recipients;
    uint256[] values;
  }

  constructor(address _owner) {
    // set up the lord role to the deployer
    _grantRole(LORD_ROLE, _owner);
    _grantRole(OWNER_ROLE, _owner);
    _setRoleAdmin(OWNER_ROLE, LORD_ROLE);
  }

  function addOwner(address _newOwner) public onlyRole(LORD_ROLE) {
    _grantRole(OWNER_ROLE, _newOwner);
  }

  function removeOwner(address _oldOwner) public onlyRole(LORD_ROLE) {
    _revokeRole(OWNER_ROLE, _oldOwner);
  }

  // multi distribute ETH
  function multiSend(address[] memory recipients, uint256[] memory values) external payable onlyRole(OWNER_ROLE) nonReentrant {
    for(uint256 i = 0; i < recipients.length; ++i)
      _safeCall(recipients[i], values[i]);
  }

  // only staking pool admin can distribute tokens
  function multiSendToken(address token, address[] memory recipients, uint256[] memory values, bool needTransferFrom) external onlyRole(OWNER_ROLE) nonReentrant {
    _multiSendToken(token, recipients, values, needTransferFrom);
  }

  function multiSendMixed(Mixed[] memory tokens) external payable onlyRole(OWNER_ROLE) nonReentrant {
    for (uint256 i = 0; i < tokens.length; i++) {
      require(tokens[i].recipients.length == tokens[i].values.length, "Not valid length");
      uint256 sum = _calculateSum(tokens[i].values);

      if (tokens[i].token == NATIVE_TOKEN) {
        require(sum >= msg.value, "Not enough ETH value");
        for(uint256 j = 0; j < tokens[i].recipients.length; ++j)
          _safeCall(tokens[i].recipients[j], tokens[i].values[j]);
      } else {
        IERC20(tokens[i].token).safeTransferFrom(msg.sender, address(this), sum);
        _multiSendToken(tokens[i].token, tokens[i].recipients, tokens[i].values, false);
      }
    }
  }

  function withdraw(address token, uint256 amount, address to) external onlyRole(OWNER_ROLE) {
    if (token == NATIVE_TOKEN) {
      _safeCall(to, amount);
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
  }

  // owner can withdraw tokens, but only to the token pool's admin address
  function withdrawMany(address[] memory tokens, uint256[] memory amount, address[] memory to) external onlyRole(OWNER_ROLE) {
    require(tokens.length == amount.length);
    require(amount.length == to.length);

    for (uint256 i = 0; i < tokens.length; i++)
      this.withdraw(tokens[i], amount[i], to[i]);
  }

  receive () external payable {}

  function _safeCall(address to, uint256 amount) internal {
    (bool success,) = payable(to).call{value : amount, gas: 3000}("");
    require(success, "failed to transfer ether");
  }

  function _multiSendToken(address _token, address[] memory recipients, uint256[] memory values, bool needTransferFrom) internal {
    IERC20 token = IERC20(_token);
    if (needTransferFrom) {
      uint256 sum = _calculateSum(values);
      token.safeTransferFrom(msg.sender, address(this), sum);
    }
    for (uint256 i = 0; i < recipients.length; i++)
      token.safeTransfer(recipients[i], values[i]);
  }


  function _calculateSum(uint256[] memory values) internal view returns(uint256){
    uint256 sum = 0;
    for(uint256 i = 0; i < values.length; i++) {
      sum += values[i];
    }
    return sum;
  }
}

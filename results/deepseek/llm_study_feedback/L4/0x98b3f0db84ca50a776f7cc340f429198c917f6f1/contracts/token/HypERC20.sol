// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import {TokenRouter} from "./libs/TokenRouter.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract HypERC20 is ERC20Upgradeable, TokenRouter {
    uint8 private immutable _decimals;

    constructor(
        uint8 __decimals,
        uint256 _scaleNumerator,
        uint256 _scaleDenominator,
        address _mailbox
    ) TokenRouter(_scaleNumerator, _scaleDenominator, _mailbox) {
        _decimals = __decimals;
    }

    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner
    ) public initializer {
        __ERC20_init(_name, _symbol);
        _mint(tx.origin, _totalSupply);
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function token() public view override returns (address) {
        return address(this);
    }

    function _transferFromSender(uint256 _amount) internal virtual override {
        _burn(tx.origin, _amount);
    }

    function _transferTo(
        address _recipient,
        uint256 _amount
    ) internal override {
        _mint(_recipient, _amount);
    }
}
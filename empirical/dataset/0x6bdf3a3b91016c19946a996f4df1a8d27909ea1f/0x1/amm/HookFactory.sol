// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {BaseHook} from "./BaseHook.sol";
import {IHooks} from "./IHooks.sol";

/// @dev Configurable hook with fixed permissions and an optional flat LP-fee override.
contract StandardHook is BaseHook {
    address public immutable owner;
    IHooks.Permissions private _perms;
    uint16 public swapFeeOverrideBps;

    event Configured(IHooks.Permissions perms, uint16 swapFeeOverrideBps);

    constructor(address _owner, IHooks.Permissions memory perms, uint16 _swapFeeOverrideBps) {
        owner = _owner;
        _perms = perms;
        swapFeeOverrideBps = _swapFeeOverrideBps;
        emit Configured(perms, _swapFeeOverrideBps);
    }

    function getHookPermissions() public view override returns (IHooks.Permissions memory) {
        return _perms;
    }

    function setSwapFeeOverrideBps(uint16 newBps) external {
        require(msg.sender == owner, "StandardHook: not owner");
        swapFeeOverrideBps = newBps;
    }

    function beforeSwap(address, bytes32, bool, uint256)
        external
        view
        override
        returns (bytes4, uint16)
    {
        return (SELECTOR_OK, swapFeeOverrideBps);
    }
}

contract HookFactory is Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidFee();

    uint256 public constant HOOK_FACTORY_FEE = 50 * 1e18;

    IERC20 public immutable ect;
    address public treasury;
    address[] public allHooks;
    mapping(address => address) public hookCreator;

    event HookCreated(address indexed hook, address indexed creator, IHooks.Permissions perms, uint16 swapFeeOverrideBps);

    constructor(address initialOwner, address _ect, address _treasury) Ownable(initialOwner) {
        if (_ect == address(0) || _treasury == address(0)) revert ZeroAddress();
        ect = IERC20(_ect);
        treasury = _treasury;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
    }

    function allHooksLength() external view returns (uint256) {
        return allHooks.length;
    }

    /// @notice Deploy a StandardHook with the requested permissions.
    /// @param  perms                Lifecycle permissions the hook will report.
    /// @param  swapFeeOverrideBps   Flat LP-fee override (0 = no override; capped at 5_000).
    function createHook(IHooks.Permissions calldata perms, uint16 swapFeeOverrideBps)
        external
        returns (address hook)
    {
        if (swapFeeOverrideBps > 5_000) revert InvalidFee();
        ect.safeTransferFrom(msg.sender, treasury, HOOK_FACTORY_FEE);
        StandardHook deployed = new StandardHook(msg.sender, perms, swapFeeOverrideBps);
        hook = address(deployed);
        allHooks.push(hook);
        hookCreator[hook] = msg.sender;
        emit HookCreated(hook, msg.sender, perms, swapFeeOverrideBps);
    }
}

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {IMeth} from "../interfaces/IMeth.sol";

/**
 * @title TokenDistributor
 * @notice Holds and distributes the remaining METH token supply after the token
 *         contract is fully minted. Authorized callers (the Check NFT contract,
 *         future season distributors, etc.) can pull METH out to recipients or
 *         burn METH from the distributor's own balance.
 */
contract TokenDistributor is Ownable {
    IERC20 public immutable token;

    mapping(address => bool) public authorizedDistributors;

    uint256 public totalDistributed;
    uint256 public totalBurnedFromDistributor;

    event TokensDistributed(address indexed to, uint256 amount, address indexed distributor);
    event TokensBurned(uint256 amount, address indexed distributor);
    event DistributorAdded(address indexed distributor);
    event DistributorRemoved(address indexed distributor);
    event TokensWithdrawn(address indexed to, uint256 amount);

    error NotAuthorizedDistributor();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidAddress();

    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) revert InvalidAddress();
        token = IERC20(_token);
    }

    /// @notice Distribute METH to a recipient.
    function distribute(address to, uint256 amount) external {
        if (!authorizedDistributors[msg.sender]) revert NotAuthorizedDistributor();
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 balance = token.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        totalDistributed += amount;
        require(token.transfer(to, amount), "Transfer failed");

        emit TokensDistributed(to, amount, msg.sender);
    }

    /// @notice Burn METH from this contract's own balance. Used to permanently
    ///         retire the taxed portion of Check redemptions.
    function burn(uint256 amount) external {
        if (!authorizedDistributors[msg.sender]) revert NotAuthorizedDistributor();
        if (amount == 0) revert InvalidAmount();

        uint256 balance = token.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        totalBurnedFromDistributor += amount;
        IMeth(address(token)).burn(amount);

        emit TokensBurned(amount, msg.sender);
    }

    function distributeBatch(address[] calldata recipients, uint256[] calldata amounts) external {
        if (!authorizedDistributors[msg.sender]) revert NotAuthorizedDistributor();
        if (recipients.length != amounts.length) revert InvalidAmount();

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        uint256 balance = token.balanceOf(address(this));
        if (balance < totalAmount) revert InsufficientBalance();

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) continue;

            totalDistributed += amounts[i];
            require(token.transfer(recipients[i], amounts[i]), "Transfer failed");
            emit TokensDistributed(recipients[i], amounts[i], msg.sender);
        }
    }

    function addDistributor(address distributor) external onlyOwner {
        if (distributor == address(0)) revert InvalidAddress();
        authorizedDistributors[distributor] = true;
        emit DistributorAdded(distributor);
    }

    function removeDistributor(address distributor) external onlyOwner {
        authorizedDistributors[distributor] = false;
        emit DistributorRemoved(distributor);
    }

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();

        uint256 balance = token.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        require(token.transfer(to, amount), "Transfer failed");
        emit TokensWithdrawn(to, amount);
    }

    function availableTokens() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

interface IErrors {
    error NotEnoughAmount();
    error SignerNotVerified();
    error InvalidSignatureLength();
    error NonceUsedAlready();
    error ZeroAddressError();
}

contract RatorCoinReward is Pausable, Ownable, IErrors {
    using Math for uint256;

    IERC20 public rewardToken;
    address public authorizedSigner;

    // mapping of used nonces
    mapping(uint256 => bool) public usedNonces;
    // total reward claimed by a user
    mapping(address => uint256) public totalClaimed;
    // total reward distributed of a the reward token
    mapping(address => uint256) public totalRewardDistributed;

    // Events
    event RewardAmountReset(uint256 rewardAmount);
    event AuthorizedSignerReset(address authorizedSigner);
    event RewardTokenReset(address rewardToken);
    event TokenRescued(address receiver, uint256 reward);
    event RewardClaimed(address receiver, uint256 reward);

    constructor(
        address initialOwner,
        address _rewardToken,
        address _authorizedSigner
    ) Ownable(initialOwner) {
        rewardToken = IERC20(_rewardToken);
        authorizedSigner = address(_authorizedSigner);
    }

    function setAuthorizedSigner(address _authorizedSigner) public onlyOwner {
        authorizedSigner = _authorizedSigner;
        emit AuthorizedSignerReset(_authorizedSigner);
    }

    function setRewardToken(address _rewardToken) public onlyOwner {
        if(_rewardToken == address(0)) revert ZeroAddressError();
        rewardToken = IERC20(_rewardToken);
        emit RewardTokenReset(_rewardToken);
    }

    function getRewardToken() public view returns (address) {
        return address(rewardToken);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function rescueTokens() public onlyOwner {
        uint256 _amount = rewardToken.balanceOf(address(this));
        address owner = owner();
        rewardToken.transfer(payable(owner), _amount);
        emit TokenRescued(owner, _amount);
    }

    function claimReward(
        address _receiver,
        uint256 _amount,
        bytes memory _signature,
        string memory _message,
        uint256 _nonce
    ) public whenNotPaused {
        if (usedNonces[_nonce]) revert NonceUsedAlready();
        if (!verify(_receiver, _amount, _signature, _message, _nonce))
            revert SignerNotVerified();
        usedNonces[_nonce] = true;

        if (_amount > rewardToken.balanceOf(address(this))) {
            revert NotEnoughAmount();
        }

        totalClaimed[_receiver] += _amount;
        totalRewardDistributed[address(rewardToken)] += _amount;
        rewardToken.transfer(_receiver, _amount);
        emit RewardClaimed(msg.sender, _amount);
    }

    // ****************************************************************************************
    //                                     Signature Verification
    // ****************************************************************************************

    function getMessageHash(
        address _receiver,
        uint256 _amount,
        address contractAddress,
        string memory _message,
        uint _nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _receiver,
                    _amount,
                    contractAddress,
                    _message,
                    _nonce
                )
            );
    }

    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function verify(
        address _receiver,
        uint256 _amount,
        bytes memory _signature,
        string memory _message,
        uint256 _nonce
    ) public view returns (bool) {
        bytes32 messageHash = getMessageHash(
            _receiver,
            _amount,
            address(rewardToken),
            _message,
            _nonce
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return
            recoverSigner(ethSignedMessageHash, _signature) == authorizedSigner;
    }

    /**
     * Gets the actual signer of the message using ETH signed hash
     * and group of r, s, and v.
     */
    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    /**
     * @dev Splits the signature into r, s, and v.
     */
    function splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (sig.length != 65) revert InvalidSignatureLength();
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}

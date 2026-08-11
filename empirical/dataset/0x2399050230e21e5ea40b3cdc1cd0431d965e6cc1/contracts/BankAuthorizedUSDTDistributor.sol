// SPDX-License-Identifier: MIT

/**
*
* *************************************************************
* **                                                         **
* **   TRANSACTION: 43** **** **** 1734                      **
* **   DATA:        27/05/2026                               **
* **   AMOUNT:      938.000.300,00 EUR                       **
* **                                                         **
* *************************************************************
*
*/                

pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BankAuthorizedUSDTDistributor is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    struct Recipient { address wallet; uint16 bps; } // 10000 = 100%

    IERC20 public immutable token;
    address public masterWallet;
    uint256 public totalToDistribute;
    Recipient[] private _recipients;
    uint32 public recipientsVersion;
    address public bankWallet;         
    mapping(bytes32 => bool) public usedPermit; 

    event MasterWalletSet(address indexed who);
    event BankWalletSet(address indexed who);
    event DistributionSumSet(uint256 amount);
    event RecipientsCleared(uint32 newVersion);
    event RecipientAdded(uint32 version, address indexed wallet, uint16 bps);
    event Distributed(uint256 requested, uint256 actuallySent, bytes32 permitHash);
    event RemainderWithdrawn(uint256 amount);

    // EIP-712
    // keccak256("DistributionPermit(uint256 chainId,address contractAddress,uint32 recipientsVersion,uint256 totalToDistribute,uint256 deadline)")
    bytes32 public constant DISTRIBUTION_PERMIT_TYPEHASH =
        0x2e5f0b4f2c5924d2e6d5f3f35d976bba080a9d23b6e0a18d85779c3a6c6d676d;

    constructor(address token_, address owner_, address bankWallet_)
        Ownable() EIP712("BankAuthorizedUSDTDistributor","1")
    {
        require(token_ != address(0), "token=0");
        require(bankWallet_ != address(0), "bank=0");
        token = IERC20(token_);
        bankWallet = bankWallet_;
    }

    // ----- Admin -----
    function setMasterWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "wallet=0");
        masterWallet = wallet; emit MasterWalletSet(wallet);
    }

    function setBankWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "bank=0");
        bankWallet = wallet; emit BankWalletSet(wallet);
    }

    function setDistributionSum(uint256 amount) external onlyOwner {
        require(amount > 0, "amount=0");
        totalToDistribute = amount; emit DistributionSumSet(amount);
    }

    function setRecipients(address[] calldata wallets, uint16[] calldata bps) external onlyOwner {
        require(wallets.length == bps.length, "len mismatch");
        delete _recipients; recipientsVersion += 1; emit RecipientsCleared(recipientsVersion);
        uint256 sum;
        for (uint256 i; i < wallets.length; i++) {
            require(wallets[i] != address(0), "wallet=0");
            require(bps[i] > 0, "bps=0");
            _recipients.push(Recipient({wallet: wallets[i], bps: bps[i]}));
            sum += bps[i]; emit RecipientAdded(recipientsVersion, wallets[i], bps[i]);
        }
        require(sum <= 10_000, "sum bps > 100%");
    }

    // ----- Views -----
    function recipientsLength() external view returns (uint256) { return _recipients.length; }
    function getRecipient(uint256 idx) external view returns (address w, uint16 bps) {
        Recipient memory r = _recipients[idx]; return (r.wallet, r.bps);
    }
    function getRecipients() external view returns (address[] memory wallets, uint16[] memory bps) {
        wallets = new address[](_recipients.length); bps = new uint16[](_recipients.length);
        for (uint256 i; i < _recipients.length; i++){ wallets[i]=_recipients[i].wallet; bps[i]=_recipients[i].bps; }
    }

    // ----- Core: startDistribution with bank permit -----
    function startDistributionWithPermit(uint256 deadline, bytes calldata bankSig) external onlyOwner {
        require(masterWallet != address(0), "master not set");
        require(totalToDistribute > 0, "total=0");
        require(_recipients.length > 0, "no recipients");
        require(block.timestamp <= deadline, "permit expired");

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(abi.encode(
            DISTRIBUTION_PERMIT_TYPEHASH,
            block.chainid,
            address(this),
            recipientsVersion,
            totalToDistribute,
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        require(!usedPermit[digest], "permit used");
        
        // Verify bank signature
        address signer = ECDSA.recover(digest, bankSig);
        require(signer == bankWallet, "invalid bank sig");

        //true
        usedPermit[digest] = true;
        
        // Execute distribution
        uint256 bal = token.balanceOf(address(this));
        require(bal >= totalToDistribute, "insufficient balance");

        uint256 sent;
        for (uint256 i; i < _recipients.length; i++) {
            Recipient memory r = _recipients[i];
            uint256 amount = (totalToDistribute * r.bps) / 10_000;
            if (amount > 0) { token.safeTransfer(r.wallet, amount); sent += amount; }
        }
        emit Distributed(totalToDistribute, sent, digest);
    }

    function withdrawRemainder() external onlyOwner {
        require(masterWallet != address(0), "master not set");
        uint256 bal = token.balanceOf(address(this));
        require(bal > 0, "no balance");
        token.safeTransfer(masterWallet, bal);
        emit RemainderWithdrawn(bal);
    }
}

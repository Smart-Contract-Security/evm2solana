// SPDX-License-Identifier: MIT
/**
   ____    _    ____  _____ ____       _    ___ 
  | __ )  / \  / ___|| ____|  _ \     / \  |_ _|
  |  _ \ / _ \ \___ \|  _| | | | |   / _ \  | | 
  | |_) / ___ \ ___) | |___| |_| |  / ___ \ | | 
  |____/_/___\_\____/|_____|____/ _/_/   \_\___|
  | __ )|  _ \    / \  |_ _| \ | / ___|         
  |  _ \| |_) |  / _ \  | ||  \| \___ \         
  | |_) |  _ <  / ___ \ | || |\  |___) |        
  |____/|_| \_\/_/   \_\___|_| \_|____/         
*/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./BrainERC20.sol"; 

interface IBrainCredits {
    function decreaseTotalSupply() external;
    function increaseTotalSupply() external;
}

contract Brains is ERC721, ReentrancyGuard, Ownable, IERC721Receiver {
    using SafeMath for uint256;
    
    address public brainCreditAddress;
    address public pepecoinAddress;
    address[] public contributors;

    mapping(address => uint256) public contributions;
    mapping(uint256 => address) public brainToERC20; 
    mapping(address => uint256) public stakes;
    mapping(uint256 => uint256) public tokenStakeTime;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => bool) private _blockedTokenIds;

    uint256 public tokenCounter;
    uint256 private constant TOKENS_PER_NFT = 1000 * 10**18; 
    uint256 private constant STAKE_AMOUNT = 100000 * 10**18;
    uint256 private constant STAKE_DURATION = 90 days;
    uint256[] private availableTokenIds;
    uint256 public constant MAX_SUPPLY = 1024;
    
    event BrainMinted(uint256 nftId, address brainFather);
    event ContributionReceived(address contributor, uint256 amount);
    event BrainURIUpdated(uint256 tokenId, string newURI);

    constructor() ERC721("BasedAI Brains", "BRAIN") Ownable(msg.sender) {
        tokenCounter = 0;
    }

    function setBrainCredits(address _brainCreditAddress) public onlyOwner {
        brainCreditAddress = _brainCreditAddress;
    }

    function setPepecoin(address _pepecoinAddress) public onlyOwner {
        pepecoinAddress = _pepecoinAddress;
    }

    function redeemBrain(uint256 amount) public nonReentrant {
        require(brainCreditAddress != address(0), "Specific Brain Credit address not set");
        require(amount >= TOKENS_PER_NFT, "Minimum amount not met");
        require(amount % TOKENS_PER_NFT == 0, "Amount must be in increments of 1000 credits");
        uint256 numNFTs = amount / TOKENS_PER_NFT;
        require(tokenCounter + numNFTs - 1 <= MAX_SUPPLY, "Exceeds maximum supply of Brains");

        IERC20(brainCreditAddress).transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < numNFTs; i++) {
            uint256 tokenId;
            if (availableTokenIds.length > 0) {
                tokenId = availableTokenIds[availableTokenIds.length - 1];
                availableTokenIds.pop();
            } else {
                unchecked {
                    tokenId = tokenCounter;
                    tokenCounter++;
                }
                
            }
            emit BrainMinted(tokenId, msg.sender);
            _safeMint(msg.sender, tokenId);
        }
    }
    
    function stakePepecoin(uint256 amount) public nonReentrant {
        require(pepecoinAddress != address(0), "Specific Pepecoin address not set");
        require(amount % STAKE_AMOUNT == 0, "Stake amount must be in increments of 100,000 tokens");
        uint256 numNFTs = amount.div(STAKE_AMOUNT);
        require(tokenCounter + numNFTs - 1 <= MAX_SUPPLY, "Exceeds maximum supply of Brains");

        IERC20(pepecoinAddress).transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender] = stakes[msg.sender].add(amount);

        IBrainCredits(brainCreditAddress).decreaseTotalSupply();

        for (uint256 i = 0; i < numNFTs; i++) {
            uint256 tokenId;
            if (availableTokenIds.length > 0) {
                tokenId = availableTokenIds[availableTokenIds.length - 1];
                availableTokenIds.pop();
            } else {
                unchecked {
                    tokenId = tokenCounter;
                    tokenCounter++;
                    if (tokenCounter == 47) tokenCounter++; // reserved for Based Labs
                }
                
            }
            emit BrainMinted(tokenId, msg.sender);
            _safeMint(msg.sender, tokenId);
            tokenStakeTime[tokenId] = block.timestamp;
        }
    }

    function unstakePepecoin(uint256 tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Only Brain owner can unstake");
        require(block.timestamp >= tokenStakeTime[tokenId] + STAKE_DURATION, "Stake period not yet completed");
        require(stakes[msg.sender] >= STAKE_AMOUNT, "Not enough tokens staked");

        stakes[msg.sender] = stakes[msg.sender].sub(STAKE_AMOUNT);
        IERC20(pepecoinAddress).transfer(msg.sender, STAKE_AMOUNT);
        _burn(tokenId);
        availableTokenIds.push(tokenId);

        IBrainCredits(brainCreditAddress).increaseTotalSupply();
    }

    function activateBrain(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Only Brain owner can link a ERC20");
        require(brainToERC20[tokenId] == address(0), "Brain token has been activated.");
        address erc20Contract = _deployERC20(msg.sender, tokenId); 
        brainToERC20[tokenId] = erc20Contract;
    }

    function _deployERC20(address tokenOwner, uint256 tokenId) internal returns (address) {
        string memory name = string(abi.encodePacked("BRAIN TOKEN #", Strings.toString(tokenId)));
        string memory symbol = string(abi.encodePacked("B#", Strings.toString(tokenId)));
        uint256 initialSupply = 1000000 * 10**18; 
        BrainERC20 newERC20 = new BrainERC20(name, symbol, initialSupply, tokenOwner);
        return address(newERC20);
    }

    function contributeBrainCredits(uint256 amount) public {
        require(brainCreditAddress != address(0), "Brain Credit address not set");
        IERC20(brainCreditAddress).transferFrom(msg.sender, address(this), amount);
        if (contributions[msg.sender] == 0) {
            contributors.push(msg.sender);
        }
        contributions[msg.sender] = contributions[msg.sender].add(amount);
        emit ContributionReceived(msg.sender, amount);
    }

    function collectiveMint() public nonReentrant {
        uint256 totalContributions = 0;
        uint256 totalUsedContributions = 0;
    
        // Calculate total contributions
        for (uint256 i = 0; i < contributors.length; i++) {
            totalContributions += contributions[contributors[i]];
        }
    
        require(totalContributions >= TOKENS_PER_NFT, "Not enough BrainCredits contributed collectively");
        require(tokenCounter < MAX_SUPPLY, "Exceeds maximum supply of Brains");
    
        // Mint the NFT
        uint256 tokenId;
        if (availableTokenIds.length > 0) {
            tokenId = availableTokenIds[availableTokenIds.length - 1];
            availableTokenIds.pop();
        } else {
            unchecked {
                tokenId = tokenCounter;
                tokenCounter++;
                if (tokenCounter == 47) tokenCounter++; // reserved for Based Labs
            }
        }
        emit BrainMinted(tokenId, address(this));
        _safeMint(address(this), tokenId);
        address erc20Contract = _deployERC20(address(this), tokenId);
    
        // Distribute ERC20 tokens based on contributions up to the TOKENS_PER_NFT limit
        for (uint256 i = 0; i < contributors.length && totalUsedContributions < TOKENS_PER_NFT; i++) {
            address contributor = contributors[i];
            uint256 contribution = contributions[contributor];
            if (totalUsedContributions + contribution > TOKENS_PER_NFT) {
                contribution = TOKENS_PER_NFT - totalUsedContributions;
            }
            contributions[contributor] -= contribution;
            totalUsedContributions += contribution;
    
            uint256 share = contribution.mul(1000000 * 10**18).div(TOKENS_PER_NFT);
            BrainERC20(erc20Contract).transfer(contributor, share);
    
            if (totalUsedContributions == TOKENS_PER_NFT) {
                break;
            }
        }
    }
    
    function distributeERC20BasedOnContributions(address erc20Contract, uint256 usedContributions, uint256 totalContributions) internal {
        require(usedContributions > 0, "Used contributions must be greater than zero for distribution");
        require(totalContributions > 0, "Total contributions must be greater than zero for distribution");
    
        for (uint256 i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            uint256 contribution = contributions[contributor];
            uint256 share = contribution.mul(1000000 * 10**18).mul(usedContributions).div(totalContributions);
            BrainERC20(erc20Contract).transfer(contributor, share);
        }
    }
    
    function adjustContributionsAfterMint(uint256 usedContributions) internal {
        uint256 totalContributions = 0;
        for (uint256 i = 0; i < contributors.length; i++) {
            totalContributions = totalContributions.add(contributions[contributors[i]]);
        }
    
        uint256 remainingContributions = totalContributions.sub(usedContributions);
        for (uint256 i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            uint256 contribution = contributions[contributor];
            uint256 newContribution = contribution.mul(remainingContributions).div(totalContributions);
            contributions[contributor] = newContribution;
        }
    }

    function getTimeUntilWithdrawal(uint256 tokenId) public view returns (uint256) {
        require(ownerOf(tokenId) == msg.sender, "Only the owner can check the time");
        if (block.timestamp >= tokenStakeTime[tokenId] + STAKE_DURATION) {
            return 0;
        } else {
            return (tokenStakeTime[tokenId] + STAKE_DURATION) - block.timestamp;
        }
    }

    function getStakedAmount(address staker) public view returns (uint256) {
        return stakes[staker];
    }

    function mintLabsBrain(uint256 tokenId) public onlyOwner {
        require(tokenId < MAX_SUPPLY, "Token ID exceeds maximum supply");
        require(pepecoinAddress == address(0), "Cannot run after mint start");
        emit BrainMinted(tokenId, msg.sender);
        IBrainCredits(brainCreditAddress).decreaseTotalSupply();
        _safeMint(msg.sender, tokenId);
        if (tokenId != 47) tokenCounter++;
    }
    // Override tokenURI to return the fixed URI for all tokens
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (bytes(_tokenURIs[tokenId]).length > 0) {
            return _tokenURIs[tokenId];
        }
        return "https://ordinals.com/content/f4be79518ebb0283ed37012b42152dedc2bdfe2e7a89267c7448ab36e02bf99ci0";
    }

    // Function to update the URI of a specific token
    function updateBrainURI(uint256 tokenId, string memory newURI) public {
        require(ownerOf(tokenId) == msg.sender || owner() == msg.sender, "Not authorized to update URI");
        require(!_blockedTokenIds[tokenId], "Brain ID is blocked from updating URI");
        _tokenURIs[tokenId] = newURI;
        emit BrainURIUpdated(tokenId, newURI);
    }

    // Function for the contract owner to toggle blocking of specific token IDs from updating their URI
    function toggleBlockBrainUri(uint256 tokenId) public onlyOwner {
        _blockedTokenIds[tokenId] = !_blockedTokenIds[tokenId];
    }

    function totalSupply() public pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // Stub functionality for self-storage of ERC721s 
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Handle the receipt of an ERC721 token
        return this.onERC721Received.selector;
    }

}

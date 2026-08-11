// SPDX-License-Identifier: MIT
/*
   ____    _    ____  _____ ____       _    ___                            
  | __ )  / \  / ___|| ____|  _ \     / \  |_ _|                           
  |  _ \ / _ \ \___ \|  _| | | | |   / _ \  | |                            
  | |_) / ___ \ ___) | |___| |_| |  / ___ \ | |                            
  |____/_/___\_\____/|_____|____/  /_/___\_\___|_____ ____ ___ _____ ____  
  | __ )|  _ \    / \  |_ _| \ | |  / ___|  _ \| ____|  _ \_ _|_   _/ ___| 
  |  _ \| |_) |  / _ \  | ||  \| | | |   | |_) |  _| | | | | |  | | \___ \ 
  | |_) |  _ <  / ___ \ | || |\  | | |___|  _ <| |___| |_| | |  | |  ___) |
  |____/|_| \_\/_/   \_\___|_| \_|  \____|_| \_\_____|____/___| |_| |____/ 
*/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITotalSupplyAdjuster {
    function increaseTotalSupply() external;
    function decreaseTotalSupply() external;
}

contract BrainCredits is ERC20, ERC20Burnable, ReentrancyGuard, Ownable  {
    IERC20 public pepecoin = IERC20(0x89ABD2ea9e0E6F909B9cC8a407d11493567D6ed7);
    address public totalSupplyAdjuster;

    uint256 public totalMinted;
    uint256 public nextThreshold = 1000 * 10**decimals();
    uint256 public priceIncrement = 200;
    uint256 public currentPrice = 1000;

    uint256 private _totalSupply = 0;
    uint256 public SUPPLY = 1024000 * 10**18;
    uint256 public SUPPLY_HARD_CAP = 1024000 * 10**18;

    bool public mintingFrozen = false;

    event MintingFrozen();
    event MintingUnfrozen();
    event TotalSupplyIncreased(uint256 amount);
    event TotalSupplyDecreased(uint256 amount);
    event TotalSupplyAdjusterChanged(address adjuster);

    constructor() ERC20("1000 BRAIN CREDITS = 1 BRAIN", "CREDIT") Ownable(msg.sender) {}

    function mint(uint256 pepecoinsBurned) public nonReentrant {
        require(
            !mintingFrozen &&
            pepecoinsBurned >= currentPrice,
            "Minting: conditions not met"
        );

        pepecoin.transferFrom(msg.sender, address(this), pepecoinsBurned);

        uint256 tokensToMint = 0;
        uint256 remainingPepecoins = pepecoinsBurned;

        while (remainingPepecoins >= currentPrice) {
            uint256 possibleMintAmount = (nextThreshold - totalMinted) / 1000 * 1000;
            uint256 pepecoinsForThisThreshold = possibleMintAmount * currentPrice / 1000;

            if (remainingPepecoins >= pepecoinsForThisThreshold) {
                tokensToMint += possibleMintAmount;
                remainingPepecoins -= pepecoinsForThisThreshold;
                totalMinted += possibleMintAmount;
                nextThreshold += 1000 * 10**decimals();
                currentPrice += priceIncrement;
            } else {
                uint256 mintableTokens = remainingPepecoins / currentPrice * 1000;
                tokensToMint += mintableTokens;
                totalMinted += mintableTokens;
                remainingPepecoins = 0;
            }
        }

        require(_totalSupply + tokensToMint <= SUPPLY, "Minting: exceeds supply cap");
        _totalSupply += tokensToMint;
        _mint(msg.sender, tokensToMint);
    }

    function totalSupply() public view override returns (uint256) {
        return SUPPLY;
    }

    function freezeMinting() public onlyOwner {
        mintingFrozen = true;
        emit MintingFrozen();
    }

    function unfreezeMinting() public onlyOwner {
        mintingFrozen = false;
        emit MintingUnfrozen();
    }

    function burnBulk(address tokenAddress) public onlyOwner {
        ERC20Burnable token = ERC20Burnable(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.burn(tokenBalance);
    }

    function transferBulk(address tokenAddress, address to) public onlyOwner {
        require(to != address(0), "Invalid address");
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        require(token.transfer(to, tokenBalance), "Transfer failed");
    }

    // Staked Pepecoin removes the matching amount of Brain Credits from the market so there can never be more than 1024 Brains.
    function setTotalSupplyAdjuster(address _adjuster) public onlyOwner {
        totalSupplyAdjuster = _adjuster;
        emit TotalSupplyAdjusterChanged(_adjuster);
    }

    function setBurnAddress(address _burnAddress) public onlyOwner {
        pepecoin = IERC20(_burnAddress);
    }

    // Staked Pepecoin removes the matching amount of Brain Credits from the market so there can never be more than 1024 Brains.
    function increaseTotalSupply() external {
        require(msg.sender == totalSupplyAdjuster, "Unauthorized");
        require(SUPPLY + (1000 * 10**decimals()) <= SUPPLY_HARD_CAP, "Total supply cannot exceed 1024000 credits.");
        SUPPLY += (1000 * 10**decimals());
        emit TotalSupplyIncreased(SUPPLY);
    }

    // Staked Pepecoin removes the matching amount of Brain Credits from the market so there can never be more than 1024 Brains.
    function decreaseTotalSupply() external {
        require(msg.sender == totalSupplyAdjuster, "Unauthorized");
        require(SUPPLY >= (1000 * 10**decimals()), "There must be a minimum of 1000 credits in circulation.");
        SUPPLY -= (1000 * 10**decimals());
        emit TotalSupplyDecreased(SUPPLY);
    }
}



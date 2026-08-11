import 'solana';

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

interface IUniswapV4PositionManager {
    function mint(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint64 liquidity,
        address recipient
    ) external returns (uint64 tokenId);
}

contract DBCCurve {
    address public tokenAddress;
    address public devAddress;
    
    uint64 public constant FUNDING_CAP = 2500000000000000000; // 2.5 ether in lamports
    uint64 public constant BUY_FEE_PERCENT = 1;  
    uint64 public constant SELL_FEE_PERCENT = 4; 
    
    uint128 public constant MAX_CURVE_TOKENS = 200000000000000000000000000; // 200M * 10^18
    uint64 public constant VIRTUAL_ETH_RESERVE = 1000000000000000000; // 1 ether in lamports
    uint128 public constant VIRTUAL_TOKEN_RESERVE = 1000000000000000000000000000; // 1B * 10^18
    
    uint128 public tokenReserve;
    uint64 public totalEthCollected;
    bool public isMigrated;
    bool public isInitialized;

    event CurveInitialized();
    event TokensBought(address indexed buyer, uint64 ethSpent, uint128 tokensReceived);
    event TokensSold(address indexed seller, uint128 tokensSpent, uint64 ethReceived);
    event MigratedToUniswapV4(uint64 ethAmount, uint128 tokenAmount);

    @payer(payer)
    @space(512)
    constructor(address _devAddress, address payer) {
        devAddress = _devAddress;
        isMigrated = false;
        isInitialized = false;
    }

    function initializeCurve(address _tokenAddress) external {
        require(tx.accounts.dataAccount.key == devAddress, "Not dev");
        require(!isInitialized, "Initialized");
        
        tokenAddress = _tokenAddress;
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tokenAddress, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory data) = tokenAddress.call{accounts: metas}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(success, "balanceOf call failed");
        uint128 balance = abi.decode(data, (uint128));
        require(balance >= MAX_CURVE_TOKENS, "Need 200M DBC");
        
        tokenReserve = MAX_CURVE_TOKENS;
        isInitialized = true;
        emit CurveInitialized();
    }

    function getEthToBuyTokens(uint128 tokenAmount) public view returns (uint64) {
        require(tokenAmount < tokenReserve, "Insufficient tokens");
        
        uint64 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint128 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint64 baseEthCost = uint64((uint128(currentEthReserve) * tokenAmount) / (currentTokenReserve - tokenAmount));
        uint64 fee = (baseEthCost * BUY_FEE_PERCENT) / 100;
        
        return baseEthCost + fee;
    }

    function getEthFromSellTokens(uint128 tokenAmount) public view returns (uint64) {
        uint64 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint128 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint64 baseEthOut = uint64((uint128(currentEthReserve) * tokenAmount) / (currentTokenReserve + tokenAmount));
        uint64 fee = (baseEthOut * SELL_FEE_PERCENT) / 100;
        
        return baseEthOut - fee;
    }

    function getTokensOutForEth(uint64 ethAmount) public view returns (uint128) {
        uint64 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint128 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        return (currentTokenReserve * ethAmount) / (uint128(currentEthReserve) + ethAmount);
    }

    @mutableSigner(buyer)
    @mutableAccount(curveDataAccount)
    @mutableAccount(tokenAccount)
    @mutableAccount(devAccount)
    function buy(address buyer, address tokenAccount, address devAccount) external {
        require(isInitialized, "Not active");
        require(!isMigrated, "Migrated");

        uint64 lamports = tx.accounts.curveDataAccount.lamports;
        require(lamports > 0, "Zero ETH");

        uint64 fee = (lamports * BUY_FEE_PERCENT) / 100;
        uint64 netEth = lamports - fee;

        uint64 ethToCurve = netEth;
        uint64 refundEth = 0;

        if (totalEthCollected + netEth > FUNDING_CAP) {
            ethToCurve = FUNDING_CAP - totalEthCollected;
            refundEth = netEth - ethToCurve;
        }

        uint128 tokensToBuyer = getTokensOutForEth(ethToCurve);
        require(tokensToBuyer > 0 && tokensToBuyer <= tokenReserve, "Invalid amount");
        
        totalEthCollected += ethToCurve;
        tokenReserve -= tokensToBuyer;

        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tokenAccount, is_signer: false, is_writable: true})
        ];
        (bool successTransfer, ) = tokenAddress.call{accounts: metas}(
            abi.encodeWithSignature("transfer(address,uint128)", buyer, tokensToBuyer)
        );
        require(successTransfer, "Token transfer failed");

        // Transfer fee to dev
        tx.accounts.devAccount.lamports += fee;

        // Refund if needed
        if (refundEth > 0) {
            tx.accounts.curveDataAccount.lamports -= refundEth;
            tx.accounts.buyer.lamports += refundEth;
        }

        emit TokensBought(buyer, ethToCurve, tokensToBuyer);

        if (totalEthCollected >= FUNDING_CAP) {
            _migrateToUniswapV4();
        }
    }

    @mutableSigner(seller)
    @mutableAccount(curveDataAccount)
    @mutableAccount(tokenAccount)
    @mutableAccount(devAccount)
    function sell(uint128 tokenAmount, address seller, address tokenAccount, address devAccount) external {
        require(isInitialized, "Not active");
        require(!isMigrated, "Migrated");
        require(tokenAmount > 0, "Zero amount");

        uint64 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint128 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint64 ethOut = uint64((uint128(currentEthReserve) * tokenAmount) / (currentTokenReserve + tokenAmount));
        
        uint64 fee = (ethOut * SELL_FEE_PERCENT) / 100;
        uint64 netEth = ethOut - fee;

        totalEthCollected -= ethOut;
        tokenReserve += tokenAmount;

        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tokenAccount, is_signer: false, is_writable: true})
        ];
        (bool successTransferFrom, ) = tokenAddress.call{accounts: metas}(
            abi.encodeWithSignature("transferFrom(address,address,uint128)", seller, address(this), tokenAmount)
        );
        require(successTransferFrom, "Token transferFrom failed");

        // Transfer net ETH to seller
        tx.accounts.curveDataAccount.lamports -= netEth;
        tx.accounts.seller.lamports += netEth;

        // Transfer fee to dev
        tx.accounts.devAccount.lamports += fee;

        emit TokensSold(seller, tokenAmount, netEth);
    }

    function _migrateToUniswapV4() internal {
        isMigrated = true;

        uint64 ethForLP = tx.accounts.dataAccount.lamports;
        AccountMeta[1] memory metas = [
            AccountMeta({pubkey: tokenAddress, is_signer: false, is_writable: true})
        ];
        (bool success, bytes memory data) = tokenAddress.call{accounts: metas}(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(success, "balanceOf call failed");
        uint128 tokenForLP = abi.decode(data, (uint128));

        emit MigratedToUniswapV4(ethForLP, tokenForLP);
    }
}
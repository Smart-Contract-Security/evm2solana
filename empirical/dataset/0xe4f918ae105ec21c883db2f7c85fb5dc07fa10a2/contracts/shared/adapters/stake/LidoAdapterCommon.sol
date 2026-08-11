// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    ILidoAdapter,
    ILido,
    IWstETH,
    ICSAccounting,
    IWithdrawalQueueERC721,
    IMellowDepositQueue,
    IMellowVault,
    IVedaAccountant,
    IGGToken
} from "../../interfaces/stake/lido/ILidoAdapter.sol";
import {ErrorsLib} from "../../libraries/ErrorsLib.sol";
import {EventsLib} from "../../libraries/EventsLib.sol";
import {Utils} from "../../libraries/Utils.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LidoAdapterCommon
/// @notice Lido protocol adapter base class. Sub-type selection is driven by `PoolConfig.version`:
///
///   Staked  v1 = stETH       v2 = wstETH       v3 = CSAccounting
///   Deposit v1 = WithdrawalQueue unstETH NFT
///   Yield   v1 = strETH (Mellow)  v2 = GG Token (Veda)
///   Locked  v1 = strETH DepositQueue pending deposit
///
/// @dev Chain-specific addresses are provided by the concrete subcontract via pure virtual functions.
abstract contract LidoAdapterCommon is Initializable, UUPSUpgradeable, OwnableUpgradeable, ILidoAdapter {
    // ============ Constants ============
    address internal constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 internal constant DEFAULT_UNSTAKE_WINDOW_END = 9999999999;

    // ============ Storage ============
    PoolConfig[] public pools;
    mapping(bytes32 => uint256) public poolIdIndex; // 1-based index

    // ============ Chain-specific addresses (provided by subcontract) ============

    /// @dev stETH contract address (e.g. 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 on Ethereum)
    function _stETH() internal pure virtual returns (address);

    /// @dev stMATIC contract address (e.g. 0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599 on Ethereum)
    function _stMATIC() internal pure virtual returns (address);

    /// @dev wstETH contract address (e.g. 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 on Ethereum)
    function _wstETH() internal pure virtual returns (address);

    /// @dev Mellow strETH Vault address (e.g. 0x277C6A642564A91ff78b008022D65683cEE5CCC5 on Ethereum)
    function _strETHVault() internal pure virtual returns (address);

    /// @dev Community Staking Accounting address (e.g. 0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da on Ethereum)
    function _csaAccount() internal pure virtual returns (address);

    /// @dev Veda Accountant (GGV rate provider) (e.g. 0xc873F2b7b3BA0a7faA2B56e210E3B965f2b618f5 on Ethereum)
    function _ggAccountant() internal pure virtual returns (address);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        require(_owner != address(0), ErrorsLib.INVALID_ADDRESS);
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    // ============ IDeFiAdapter Identity ============

    function protocolVersion() external pure override returns (string memory) {
        return "1.0";
    }

    function protocolType() external pure override returns (ProtocolType) {
        return ProtocolType.Staking;
    }

    // ============ Position Queries ============

    function getPositions(address user) external view override returns (Position[] memory) {
        return _getPositions(user);
    }

    function getPositions(address user, PoolType poolType) external view override returns (Position[] memory) {
        Position[] memory temp = new Position[](pools.length * 2);
        uint256 count;

        for (uint256 i; i < pools.length; ++i) {
            if (!pools[i].enabled || pools[i].poolType != poolType) continue;

            Position[] memory pos = _getPoolPositions(user, pools[i]);
            for (uint256 j; j < pos.length; ++j) {
                if (pos[j].tokens.length > 0) {
                    temp[count++] = pos[j];
                }
            }
        }

        return Utils.trimPositionArray(temp, count);
    }

    function getPosition(address user, bytes32 poolId) external view override returns (Position[] memory) {
        require(poolIdIndex[poolId] > 0, ErrorsLib.POOL_NOT_FOUND);
        uint256 idx = poolIdIndex[poolId] - 1;
        require(idx < pools.length && pools[idx].enabled, ErrorsLib.POOL_NOT_FOUND);

        return _getPoolPositions(user, pools[idx]);
    }

    function getStakePositionsByIds(address user, uint256[] calldata nodeIds) external view returns (Position[] memory positions) {
        Position[] memory temp = new Position[](nodeIds.length + pools.length * 2);
        uint256 count;
        for (uint256 i; i < nodeIds.length; i++) {
            Position memory pos = _getCSAccountingPosition(user, nodeIds[i]);
            if (pos.tokens.length > 0) {
                    temp[count++] = pos;
                }
        }

        for (uint256 i; i < pools.length; ++i) {
            if (!pools[i].enabled || pools[i].poolType != PoolType.Staked) continue;

            Position[] memory pos = _getPoolPositions(user, pools[i]);
            for (uint256 j; j < pos.length; ++j) {
                if (pos[j].tokens.length > 0) {
                    temp[count++] = pos[j];
                }
            }
        }
        return Utils.trimPositionArray(temp, count);
    }

    // ============ Pool Queries ============

    function getSupportedPools() external view override returns (Pool[] memory) {
        Pool[] memory _pools = new Pool[](pools.length);
        uint256 count;

        for (uint256 i; i < pools.length; ++i) {
            if (pools[i].enabled) {
                _pools[count++] = _buildPool(pools[i]);
            }
        }
        return Utils.trimPoolArray(_pools, count);
    }

    function getSupportedPools(PoolType poolType) external view override returns (Pool[] memory) {
        Pool[] memory temp = new Pool[](pools.length);
        uint256 count;

        for (uint256 i; i < pools.length; ++i) {
            if (pools[i].enabled && pools[i].poolType == poolType) {
                temp[count++] = _buildPool(pools[i]);
            }
        }
        return Utils.trimPoolArray(temp, count);
    }

    function getSupportedPool(bytes32 poolId) external view override returns (Pool memory) {
        require(poolIdIndex[poolId] > 0, ErrorsLib.POOL_NOT_FOUND);
        uint256 idx = poolIdIndex[poolId] - 1;
        require(idx < pools.length && pools[idx].enabled, ErrorsLib.POOL_NOT_FOUND);
        return _buildPool(pools[idx]);
    }

    // ============ ID Generation ============

    function getPoolId(PoolType poolType, address poolAddress) external view override returns (bytes32) {
        return _generatePoolId(poolType, poolAddress);
    }

    function getPositionId(PoolType poolType, address poolAddress, address user) external view override returns (bytes32) {
        bytes32 poolId = _generatePoolId(poolType, poolAddress);
        return keccak256(abi.encode(poolId, user));
    }

    // ============ Share/Asset Conversion ============

    function getShares(bytes32, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getAssets(bytes32, uint256) external pure override returns (uint256) {
        return 0;
    }

    // ============ Config Queries ============

    function getAllPoolConfigs() external view override returns (PoolConfig[] memory) {
        return pools;
    }

    function getPoolConfig(bytes32 poolId) external view override returns (PoolConfig memory) {
        require(poolIdIndex[poolId] > 0, ErrorsLib.POOL_NOT_FOUND);
        uint256 idx = poolIdIndex[poolId] - 1;
        require(idx < pools.length, ErrorsLib.POOL_NOT_FOUND);
        return pools[idx];
    }

    function getPoolConfigByIndex(uint256 index) external view override returns (PoolConfig memory) {
        require(index < pools.length, ErrorsLib.POOL_NOT_FOUND);
        return pools[index];
    }

    function getPoolConfigsLength() external view override returns (uint256) {
        return pools.length;
    }

    // ============ Admin ============

    function addPools(address[] calldata, PoolType[] calldata) external override onlyOwner {}

    function addPools(PoolConfig[] calldata configs) external override onlyOwner {
        for (uint256 i; i < configs.length; ++i) {
            PoolConfig memory config = configs[i];
            require(config.pool != address(0), ErrorsLib.INVALID_ADDRESS);

            bytes32 poolId = _generatePoolId(config.poolType, config.pool);
            require(poolIdIndex[poolId] == 0, ErrorsLib.POOL_ALREADY_EXISTS);

            pools.push(config);
            poolIdIndex[poolId] = pools.length;
            emit EventsLib.PoolAdded(poolId, config.pool, config.poolType);
        }
    }

    function removePools(bytes32[] calldata poolIds) external override onlyOwner {
        for (uint256 i; i < poolIds.length; ++i) {
            bytes32 poolId = poolIds[i];
            require(poolIdIndex[poolId] > 0, ErrorsLib.POOL_NOT_FOUND);

            uint256 idx = poolIdIndex[poolId] - 1;
            if (idx >= pools.length) continue;

            PoolConfig memory config = pools[idx];
            uint256 lastIdx = pools.length - 1;

            if (idx != lastIdx) {
                pools[idx] = pools[lastIdx];
                bytes32 lastPoolId = _generatePoolId(pools[idx].poolType, pools[idx].pool);
                poolIdIndex[lastPoolId] = idx + 1;
            }
            pools.pop();
            delete poolIdIndex[poolId];
            emit EventsLib.PoolRemoved(poolId, config.pool, config.poolType);
        }
    }

    function togglePools(bytes32[] calldata poolIds, bool[] calldata enabled) external override onlyOwner {
        require(poolIds.length == enabled.length, ErrorsLib.LENGTH_MISMATCH);

        for (uint256 i; i < poolIds.length; ++i) {
            bytes32 poolId = poolIds[i];
            require(poolIdIndex[poolId] > 0, ErrorsLib.POOL_NOT_FOUND);

            uint256 idx = poolIdIndex[poolId] - 1;
            if (idx >= pools.length) continue;

            pools[idx].enabled = enabled[i];
            emit EventsLib.PoolToggled(poolId, pools[idx].pool, enabled[i]);
        }
    }

    // ============ Internal: Position Dispatch ============

    function _getPositions(address user) internal view returns (Position[] memory) {
        Position[] memory positions = new Position[](pools.length * 2);
        uint256 count;

        for (uint256 i; i < pools.length; ++i) {
            if (!pools[i].enabled) continue;

            Position[] memory pos = _getPoolPositions(user, pools[i]);
            for (uint256 j; j < pos.length; ++j) {
                if (pos[j].tokens.length > 0) {
                    positions[count++] = pos[j];
                }
            }
        }

        return Utils.trimPositionArray(positions, count);
    }

    /// @dev Dispatch to the right position builder based on poolType + version.
    function _getPoolPositions(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        if (config.poolType == PoolType.Staked) {
            return _getStakePositions(user, config);
        } else if (config.poolType == PoolType.Deposit) {
            return _getDepositPositions(user, config);
        } else if (config.poolType == PoolType.Yield) {
            return _getYieldPositions(user, config);
        } else if (config.poolType == PoolType.Locked) {
            return _getLockedPositions(user, config);
        } 
        return new Position[](0);
    }

    // ============ Internal: Staked Positions ============

    function _getStakePositions(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        Position memory pos;
        if (config.version == 1) {
            pos = _getStakePositionV1(user, config); // stETH
        } else if (config.version == 2) {
            pos = _getStakePositionV2(user, config); // wstETH
        } else {
            return new Position[](0);
        }
        return _wrapSingle(pos);
    }

    /// @dev Staked V1 — stETH (rebase): sharesOf(user) → getPooledEthByShares()
    function _getStakePositionV1(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        uint256 userShares = ILido(config.pool).balanceOf(user);
        if (userShares == 0) return pos;
        uint256 ethAmount;
        address assetToken = ETH;
        string memory assetSymbol = "ETH";
        if (config.pool == _stETH()){
            ethAmount = userShares;
        } else {
            (ethAmount,,) = ILido(config.pool).convertStMaticToMatic(userShares);
            assetToken = ILido(config.pool).token();
            assetSymbol = Utils.getTokenSymbol(assetToken);
        }
         
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);
        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: assetToken,
            amount: ethAmount,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: userShares,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: assetSymbol
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Staked,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }

    /// @dev Staked V2 — wstETH (wrapped): balanceOf(user) → getStETHByWstETH()
    function _getStakePositionV2(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        uint256 balance = IWstETH(config.pool).balanceOf(user);
        if (balance == 0) return pos;
        uint256 stethAmount;
        try IWstETH(config.pool).getStETHByWstETH(balance) returns (uint256 amt) {
            stethAmount = amt;
        } catch { return pos; }
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);
        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: _stETH(),
            amount: stethAmount,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: balance,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_stETH())
        });
        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Staked,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }


    /// @notice Get CSAccounting position for a specific nodeOperatorId (called by backend).
    function _getCSAccountingPosition(address user, uint256 nodeOperatorId)
        internal
        view
        returns (Position memory pos)
    {
        
        address pool = _csaAccount();
        try ICSAccounting(pool).getBondSummary(nodeOperatorId) returns (uint256 current, uint256) {
            if (current == 0) return pos;

            bytes32 pid = _generatePoolId(PoolType.Staked, pool);

            Token[] memory tokens = new Token[](1);
            tokens[0] = Token({
                assetToken: _stETH(),
                amount: current,
                assetDecimals: 18,
                sharesToken: address(0), // no shares token for bond
                shares: 0,
                sharesDecimals: 0,
                tokenType: TokenType.Supply,
                symbol: Utils.getTokenSymbol(_stETH())
            });

            pos = Position({
                positionId: keccak256(abi.encode(pid, user, nodeOperatorId)),
                poolAddress: pool,
                protocolType: ProtocolType.Staking,
                poolType: PoolType.Staked,
                tokens: tokens,
                rewards: new Reward[](0),
                healthFactor: 0,
                coolDowns: new Cooldown[](0),
                extraData: abi.encode(nodeOperatorId)
            });
        } catch {}
    }

    // ============ Internal: Deposit Positions ============

    function _getDepositPositions(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        if (config.version == 1) {
            return _getDepositPositionV1(user, config); // WithdrawalQueue unstETH NFT
        } else {
            return _getDepositPositionV2(user, config); 
        }
    }

    /// @dev Deposit V1 — WithdrawalQueue unstETH NFT
    function _getDepositPositionV1(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        IWithdrawalQueueERC721 queue = IWithdrawalQueueERC721(config.pool);

        uint256[] memory requestIds;
        try queue.getWithdrawalRequests(user) returns (uint256[] memory ids) {
            requestIds = ids;
        } catch {
            return new Position[](0);
        }
        if (requestIds.length == 0) return new Position[](0);

        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory statuses;
        try queue.getWithdrawalStatus(requestIds) returns (
            IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory s
        ) {
            statuses = s;
        } catch {
            return new Position[](0);
        }

        // Build per-request cooldowns in the same order as requestIds (skip claimed).
        Cooldown[] memory tempCooldowns = new Cooldown[](statuses.length);
        uint256[] memory tempIds = new uint256[](statuses.length);
        uint256 totalAmount;
        uint256 count;

        for (uint256 i; i < statuses.length; ++i) {
            if (statuses[i].isClaimed) continue;

            uint256 amt = statuses[i].amountOfStETH;
            totalAmount += amt;

            tempCooldowns[count] = Cooldown({
                cooldownEndTime: statuses[i].isFinalized ? block.timestamp : DEFAULT_UNSTAKE_WINDOW_END,
                unstakeWindowEnd: DEFAULT_UNSTAKE_WINDOW_END,
                amount: amt,
                tokenIdx: 0
            });
            tempIds[count] = requestIds[i];
            ++count;
        }

        if (totalAmount == 0) return new Position[](0);

        // Trim arrays to actual unclaimed length
        Cooldown[] memory cooldowns = new Cooldown[](count);
        uint256[] memory unclaimedIds = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            cooldowns[i] = tempCooldowns[i];
            unclaimedIds[i] = tempIds[i];
        }

        // Single token: sum of all unclaimed amountOfStETH (one underlying asset)
        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: ETH,
            amount: totalAmount,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: totalAmount,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: "ETH"
        });

        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Position[] memory positions = new Position[](1);
        positions[0] = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Deposit,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: cooldowns,
            extraData: abi.encode(unclaimedIds)
        });
        return positions;
    }

    function _getDepositPositionV2(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        IWithdrawalQueueERC721 queue = IWithdrawalQueueERC721(config.pool);

        uint256[] memory requestIds;
        try queue.getOwnedTokens(user) returns (uint256[] memory ids) {
            requestIds = ids;
        } catch {
            return new Position[](0);
        }
        if (requestIds.length == 0) return new Position[](0);

        uint256 totalAmount;
        for(uint256 i; i<requestIds.length; i++) {
            uint256 ethAmount = IWithdrawalQueueERC721(_stMATIC()).getMaticFromTokenId(requestIds[i]);
            totalAmount += ethAmount;
        }

        
        if (totalAmount == 0) return new Position[](0);

        // Single token: sum of all amountOfStETH (one underlying asset)
        Token[] memory tokens = new Token[](1);
        address assetToken = ILido(_stMATIC()).token();
        tokens[0] = Token({
            assetToken: assetToken,
            amount: totalAmount,
            assetDecimals: 18,
            sharesToken: _stMATIC(),
            shares: totalAmount,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(assetToken)
        });

        Cooldown[] memory cooldowns = new Cooldown[](0);

        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Position[] memory positions = new Position[](1);
        positions[0] = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Deposit,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: cooldowns,
            extraData: abi.encode(requestIds)
        });
        return positions;
    }

    // ============ Internal: Yield Positions ============

    function _getYieldPositions(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        Position memory pos;
        if (config.version == 1) {
            pos = _getYieldPositionV1(user, config); // strETH (Mellow)
        } else if (config.version == 2) {
            pos = _getYieldPositionV2(user, config); // GG Token (Veda)
        } else if (config.version == 3) {
            pos = _getYieldPositionV3(user, config); // earnETH (Mellow ShareManager, asset=wstETH)
        } else if (config.version == 4) {
            pos = _getYieldPositionV4(user, config); // earnUSD (Mellow ShareManager, asset=USDC)
        } else {
            return new Position[](0);
        }
        return _wrapSingle(pos);
    }

    /// @dev Yield V1 — strETH / stRATEGY (Mellow).
    ///      pool = DepositQueue, strETHVault (global) = Mellow Vault
    function _getYieldPositionV1(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        IMellowDepositQueue depositQueue = IMellowDepositQueue(config.pool);

        uint256 balance;
        try depositQueue.balanceOf(user) returns (uint256 bal) {
            balance = bal;
        } catch {}
        if (balance == 0) return pos;

        uint256 wstethValue;
        address vault = depositQueue.vault();
        address oracle = IMellowDepositQueue(vault).oracle();
        (uint224 rate,,) = IMellowDepositQueue(oracle).getReport(_wstETH());
        wstethValue = balance * 1e18 / rate;
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: wstethValue,
            assetDecimals: 18,
            sharesToken: _strETHVault(), // strETH token
            shares: balance,
            sharesDecimals: 18,
            tokenType: TokenType.Yield,
            symbol: Utils.getTokenSymbol(_wstETH())
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Yield,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }

    /// @dev Yield V2 — GG Token / GGV (Veda BoringVault).
    ///      pool = GG Token address, ggAccountant (global) = Accountant
    function _getYieldPositionV2(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        if (_ggAccountant() == address(0)) return pos;

        uint256 ggBalance;
        try IGGToken(config.pool).balanceOf(user) returns (uint256 bal) {
            ggBalance = bal;
        } catch { return pos; }
        if (ggBalance == 0) return pos;

        uint256 rate;
        try IVedaAccountant(_ggAccountant()).getRate() returns (uint256 r) {
            rate = r;
        } catch { return pos; }

        uint256 wstethValue = ggBalance * rate / 1e18;
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: wstethValue,
            assetDecimals: 18,
            sharesToken: config.pool, // GG Token
            shares: ggBalance,
            sharesDecimals: 18,
            tokenType: TokenType.Yield,
            symbol: Utils.getTokenSymbol(_wstETH())
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Yield,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }

    /// @dev Yield V3 — earnETH (Mellow ShareManager).
    ///      pool = earnETH share token (also exposes vault()), assetToken = wstETH.
    function _getYieldPositionV3(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        uint256 balance;
        try IGGToken(config.pool).balanceOf(user) returns (uint256 bal) {
            balance = bal;
        } catch { return pos; }
        if (balance == 0) return pos;

        address vault;
        try IMellowDepositQueue(config.pool).vault() returns (address v) { vault = v; } catch { return pos; }
        if (vault == address(0)) return pos;

        address oracle;
        try IMellowDepositQueue(vault).oracle() returns (address o) { oracle = o; } catch { return pos; }
        if (oracle == address(0)) return pos;

        uint224 rate;
        try IMellowDepositQueue(oracle).getReport(_wstETH()) returns (uint224 r, uint32, bool) { rate = r; } catch { return pos; }
        if (rate == 0) return pos;

        uint256 wstethValue = balance * 1e18 / rate;
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: wstethValue,
            assetDecimals: 18,
            sharesToken: config.pool, // earnETH share token = pool itself
            shares: balance,
            sharesDecimals: 18,
            tokenType: TokenType.Yield,
            symbol: Utils.getTokenSymbol(_wstETH())
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Yield,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }

    /// @dev Yield V4 — earnUSD (Mellow ShareManager).
    ///      pool = earnUSD share token (also exposes vault()), assetToken = USDC.
    function _getYieldPositionV4(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        uint256 balance;
        try IGGToken(config.pool).balanceOf(user) returns (uint256 bal) {
            balance = bal;
        } catch { return pos; }
        if (balance == 0) return pos;

        address vault;
        try IMellowDepositQueue(config.pool).vault() returns (address v) { vault = v; } catch { return pos; }
        if (vault == address(0)) return pos;

        address oracle;
        try IMellowDepositQueue(vault).oracle() returns (address o) { oracle = o; } catch { return pos; }
        if (oracle == address(0)) return pos;

        uint224 rate;
        try IMellowDepositQueue(oracle).getReport(USDC) returns (uint224 r, uint32, bool) { rate = r; } catch { return pos; }
        if (rate == 0) return pos;

        uint256 usdcValue = balance * 1e18 / rate;
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Token[] memory tokens = new Token[](1);
        tokens[0] = Token({
            assetToken: USDC,
            amount: usdcValue,
            assetDecimals: 6,
            sharesToken: config.pool, // earnUSD share token = pool itself
            shares: balance,
            sharesDecimals: 18,
            tokenType: TokenType.Yield,
            symbol: Utils.getTokenSymbol(USDC)
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Yield,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: new Cooldown[](0),
            extraData: ""
        });
    }

    // ============ Internal: Locked Positions ============

    function _getLockedPositions(address user, PoolConfig memory config)
        internal
        view
        returns (Position[] memory)
    {
        Position memory pos;
        if (config.version == 1) {
            pos = _getLockedPositionV1(user, config); // strETH DepositQueue pending
        } else {
            return new Position[](0);
        }
        return _wrapSingle(pos);
    }

    /// @dev Locked V1 — Mellow redemption requests (pending, not yet claimable).
    ///      pool = DepositQueue / RedemptionQueue address.
    ///      Each unprocessed request becomes one Cooldown; claimable requests are skipped.
    function _getLockedPositionV1(address user, PoolConfig memory config)
        internal
        view
        returns (Position memory pos)
    {
        IMellowDepositQueue depositQueue = IMellowDepositQueue(config.pool);
        IMellowDepositQueue.Request[] memory requests = depositQueue.requestsOf(user, 0, 10);
        if (requests.length == 0) return pos;

        Cooldown[] memory tempCooldowns = new Cooldown[](requests.length);
        uint256[] memory tempTimestamps = new uint256[](requests.length);
        uint256 totalAssets;
        uint256 totalShares;
        uint256 count;

        for (uint256 i; i < requests.length; ++i) {
            totalAssets += requests[i].assets;
            totalShares += requests[i].shares;

            tempCooldowns[count] = Cooldown({
                cooldownEndTime: requests[i].isClaimable? requests[i].timestamp: DEFAULT_UNSTAKE_WINDOW_END,
                unstakeWindowEnd: DEFAULT_UNSTAKE_WINDOW_END,
                amount: requests[i].assets,
                tokenIdx: 0
            });
            tempTimestamps[count] = requests[i].timestamp;
            ++count;
        }

        if (count == 0) return pos;

        // Trim cooldowns and timestamps to actual non-claimable count
        Cooldown[] memory cooldowns = new Cooldown[](count);
        uint256[] memory timestamps = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            cooldowns[i] = tempCooldowns[i];
            timestamps[i] = tempTimestamps[i];
        }

        bytes32 poolId = _generatePoolId(config.poolType, config.pool);

        Token[] memory tokens = new Token[](1);

        address assetToken = IMellowDepositQueue(config.pool).asset();
        uint256 amount;
        uint8 decimals;
        string memory symbol;

        if (assetToken == ETH) {
            amount = config.pool.balance;
            decimals = 18;
            symbol = "ETH";
        } else {
            amount = IERC20(assetToken).balanceOf(config.pool);
            decimals = Utils.getTokenDecimals(assetToken);
            symbol = Utils.getTokenSymbol(assetToken);
        }

        tokens[0] = Token({
            assetToken: assetToken,
            amount: amount,
            assetDecimals: decimals,
            sharesToken: address(0),
            shares: 0,
            sharesDecimals: 0,
            tokenType: TokenType.Locked,
            symbol: symbol
        });

        pos = Position({
            positionId: keccak256(abi.encode(poolId, user)),
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: PoolType.Locked,
            tokens: tokens,
            rewards: new Reward[](0),
            healthFactor: 0,
            coolDowns: cooldowns,
            extraData: abi.encode(timestamps)
        });
    }

    // ============ Internal: Pool Building ============

    function _buildPool(PoolConfig memory config) internal view returns (Pool memory) {
        bytes32 poolId = _generatePoolId(config.poolType, config.pool);
        Token[] memory tokens;

        if (config.poolType == PoolType.Staked) {
            tokens = _getStakedPoolTokens(config);
        } else if (config.poolType == PoolType.Deposit) {
            tokens = _getDepositPoolTokens(config);
        } else if (config.poolType == PoolType.Yield) {
            tokens = _getYieldPoolTokens(config);
        } else if (config.poolType == PoolType.Locked) {
            tokens = _getLockedPoolTokens(config);
        } else {
            tokens = new Token[](0);
        }

        return Pool({
            poolId: poolId,
            poolAddress: config.pool,
            protocolType: ProtocolType.Staking,
            poolType: config.poolType,
            tokens: tokens,
            enabled: config.enabled,
            extraData: ""
        });
    }

    function _getStakedPoolTokens(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        if (config.version == 1) {
            return _getStakedPoolTokensV1(config);
        } else if (config.version == 2) {
            return _getStakedPoolTokensV2(config);
        } else if (config.version == 3) {
            return _getStakedPoolTokensV3(config);
        }
        return new Token[](0);
    }

    /// @dev stETH pool TVL — also handles stMATIC (same version, different pool address)
    function _getStakedPoolTokensV1(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);

        uint256 totalAmount;
        uint256 totalShares;
        address assetToken;
        string memory assetSymbol;

        if (config.pool == _stETH()) {
            assetToken = ETH;
            assetSymbol = "ETH";
            try ILido(config.pool).getTotalPooledEther() returns (uint256 tpe) { totalAmount = tpe; } catch {}
            try ILido(config.pool).getTotalShares() returns (uint256 ts) { totalShares = ts; } catch {}
        } else {
            // stMATIC: assetToken = token(), amount = convertStMaticToMatic(totalSupply), shares = totalSupply
            assetToken = ILido(config.pool).token();
            assetSymbol = Utils.getTokenSymbol(assetToken);
            try ILido(config.pool).totalSupply() returns (uint256 ts) {
                totalShares = ts;
                if (ts > 0) {
                    try ILido(config.pool).convertStMaticToMatic(ts) returns (uint256 amt, uint256, uint256) {
                        totalAmount = amt;
                    } catch {}
                }
            } catch {}
        }

        tokens[0] = Token({
            assetToken: assetToken,
            amount: totalAmount,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: totalShares,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: assetSymbol
        });
    }

    /// @dev wstETH pool TVL
    function _getStakedPoolTokensV2(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        uint256 totalSupply;
        uint256 totalSteth;
        try IWstETH(config.pool).totalSupply() returns (uint256 ts) {
            totalSupply = ts;
            try IWstETH(config.pool).getStETHByWstETH(totalSupply) returns (uint256 amt) { totalSteth = amt; } catch {}
        } catch {}

        tokens[0] = Token({
            assetToken: _stETH(),
            amount: totalSteth,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: totalSupply,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_stETH())
        });
    }

    /// @dev CSAccounting pool — TVL = stETH balance held by CSAccounting contract
    function _getStakedPoolTokensV3(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        uint256 totalSteth = IERC20(_stETH()).balanceOf(config.pool);
        tokens[0] = Token({
            assetToken: _stETH(),
            amount: totalSteth,
            assetDecimals: 18,
            sharesToken: address(0),
            shares: 0,
            sharesDecimals: 0,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_stETH())
        });
    }

    function _getDepositPoolTokens(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        if (config.version == 1) {
            return _getDepositPoolTokensV1(config);
        } else if (config.version == 2) {
            return _getDepositPoolTokensV2();
        }
        return new Token[](0);
    }

    /// @dev WithdrawalQueue pool TVL
    function _getDepositPoolTokensV1(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        IWithdrawalQueueERC721 queue = IWithdrawalQueueERC721(config.pool);
        uint256 lockedEther;
        uint256 unfinalizedSteth;
        try queue.getLockedEtherAmount() returns (uint256 le) { lockedEther = le; } catch {}
        try queue.unfinalizedStETH() returns (uint256 us) { unfinalizedSteth = us; } catch {}

        tokens[0] = Token({
            assetToken: ETH,
            amount: lockedEther + unfinalizedSteth,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: 0,
            sharesDecimals: 0,
            tokenType: TokenType.Supply,
            symbol: "ETH"
        });
    }

    /// @dev Deposit V2 — stMATIC WithdrawalQueue pool TVL
    function _getDepositPoolTokensV2() internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        address assetToken = ILido(_stMATIC()).token();

        tokens[0] = Token({
            assetToken: assetToken,
            amount: 0,
            assetDecimals: 18,
            sharesToken: _stMATIC(),
            shares: 0,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(assetToken)
        });
    }

    function _getYieldPoolTokens(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        if (config.version == 1) {
            return _getYieldPoolTokensV1(config);
        } else if (config.version == 2) {
            return _getYieldPoolTokensV2(config);
        } else if (config.version == 3) {
            return _getYieldPoolTokensV3(config);
        } else if (config.version == 4) {
            return _getYieldPoolTokensV4(config);
        }
        return new Token[](0);
    }

    /// @dev strETH (Mellow) pool TVL = vault.totalSupply() * 1e18 / oracleRate
    function _getYieldPoolTokensV1(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        IMellowDepositQueue depositQueue = IMellowDepositQueue(config.pool);

        uint256 totalSupply;
        try depositQueue.totalSupply() returns (uint256 ts) { totalSupply = ts; } catch {}

        uint256 totalWsteth;
        try depositQueue.vault() returns (address vault) {
            try IMellowDepositQueue(vault).oracle() returns (address oracle) {
                try IMellowDepositQueue(oracle).getReport(_wstETH()) returns (uint224 rate, uint32, bool) {
                    if (rate > 0) {
                        totalWsteth = totalSupply * 1e18 / rate;
                    }
                } catch {}
            } catch {}
        } catch {}

        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: totalWsteth,
            assetDecimals: 18,
            sharesToken: _strETHVault(),
            shares: totalSupply,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_wstETH())
        });
    }

    /// @dev GG Token (Veda) pool TVL = totalSupply × rate / 1e18
    function _getYieldPoolTokensV2(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        uint256 totalSupply;
        try IGGToken(config.pool).totalSupply() returns (uint256 ts) { totalSupply = ts; } catch {}

        uint256 rate;
        if (_ggAccountant() != address(0)) {
            try IVedaAccountant(_ggAccountant()).getRate() returns (uint256 r) { rate = r; } catch {}
        }
        uint256 totalAssets = (rate > 0) ? totalSupply * rate / 1e18 : 0;

        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: totalAssets,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: totalSupply,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_wstETH())
        });
    }

    /// @dev earnETH (Mellow ShareManager) pool TVL = totalSupply × 1e18 / oracleRate (asset = wstETH)
    function _getYieldPoolTokensV3(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        uint256 totalSupply;
        try IGGToken(config.pool).totalSupply() returns (uint256 ts) { totalSupply = ts; } catch {}

        uint256 totalWsteth;
        try IMellowDepositQueue(config.pool).vault() returns (address vault) {
            try IMellowDepositQueue(vault).oracle() returns (address oracle) {
                try IMellowDepositQueue(oracle).getReport(_wstETH()) returns (uint224 rate, uint32, bool) {
                    if (rate > 0) {
                        totalWsteth = totalSupply * 1e18 / rate;
                    }
                } catch {}
            } catch {}
        } catch {}

        tokens[0] = Token({
            assetToken: _wstETH(),
            amount: totalWsteth,
            assetDecimals: 18,
            sharesToken: config.pool,
            shares: totalSupply,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(_wstETH())
        });
    }

    /// @dev earnUSD (Mellow ShareManager) pool TVL = totalSupply × 1e18 / oracleRate (asset = USDC)
    function _getYieldPoolTokensV4(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);
        uint256 totalSupply;
        try IGGToken(config.pool).totalSupply() returns (uint256 ts) { totalSupply = ts; } catch {}

        uint256 totalUsdc;
        try IMellowDepositQueue(config.pool).vault() returns (address vault) {
            try IMellowDepositQueue(vault).oracle() returns (address oracle) {
                try IMellowDepositQueue(oracle).getReport(USDC) returns (uint224 rate, uint32, bool) {
                    if (rate > 0) {
                        totalUsdc = totalSupply * 1e18 / rate;
                    }
                } catch {}
            } catch {}
        } catch {}

        tokens[0] = Token({
            assetToken: USDC,
            amount: totalUsdc,
            assetDecimals: 6,
            sharesToken: config.pool,
            shares: totalSupply,
            sharesDecimals: 18,
            tokenType: TokenType.Supply,
            symbol: Utils.getTokenSymbol(USDC)
        });
    }

    function _getLockedPoolTokens(PoolConfig memory config) internal view returns (Token[] memory tokens) {
        tokens = new Token[](1);

        address assetToken = IMellowDepositQueue(config.pool).asset();
        uint256 amount;
        uint8 decimals;
        string memory symbol;

        if (assetToken == ETH) {
            amount = config.pool.balance;
            decimals = 18;
            symbol = "ETH";
        } else {
            amount = IERC20(assetToken).balanceOf(config.pool);
            decimals = Utils.getTokenDecimals(assetToken);
            symbol = Utils.getTokenSymbol(assetToken);
        }

        tokens[0] = Token({
            assetToken: assetToken,
            amount: amount,
            assetDecimals: decimals,
            sharesToken: address(0),
            shares: 0,
            sharesDecimals: 0,
            tokenType: TokenType.Locked,
            symbol: symbol
        });
    }

    // ============ Internal Helpers ============

    function _wrapSingle(Position memory pos) internal pure returns (Position[] memory) {
        if (pos.tokens.length > 0) {
            Position[] memory result = new Position[](1);
            result[0] = pos;
            return result;
        }
        return new Position[](0);
    }

    function _generatePoolId(PoolType poolType, address poolAddress) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, poolAddress, poolType));
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import "../interfaces/storage/IStorage.sol";

contract TokenSale is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    struct TokenInfo {
        bool defined;
        bytes32 pythId;
        uint256 total;
        uint256 threshold;
    }

    bytes32 public constant ONRAMP_ROLE = keccak256("ONRAMP_ROLE");
    uint256 public constant UNITS = 1000000000000000000;
    uint256 public constant DECIMALS = 18;
    uint256 public constant defaultPythThreshold = 43200; // 12h

    mapping(address => TokenInfo) private _tokens;

    IStorage private _storage;
    IPyth private _oracle;

    event TokensPurchased(
        address indexed user,
        address indexed token,
        address indexed ref,
        uint256 amount,
        IStorage.Option option,
        uint256 sold,
        uint256 round
    );

    error ErrClosed();
    error ErrRoundClosed();
    error ErrRoundAllocation();
    error ErrNullAddress();
    error ErrAmountZero();
    error ErrReferral();
    error ErrMin(uint256 amount_, uint256 min_);
    error ErrMax(uint256 amount_, uint256 max_);
    error ErrTokenUndefined();
    error ErrTokenDefined();
    error ErrTransfer();
    error ErrThreshold();

    constructor(
        address payable storage_,
        address oracle_,
        address[] memory tokens_,
        bytes32[] memory pythIds_
    ) {
        if (storage_ == address(0) || oracle_ == address(0)) {
            revert ErrNullAddress();
        }

        require(tokens_.length == pythIds_.length, "TokenSale: arrays lengths not equals");

        for (uint256 index = 0; index < tokens_.length; index++) {
            require(tokens_[index] != address(0), "TokenSale: cant set zero token address");
            _tokens[tokens_[index]] = TokenInfo({
                defined: true,
                total: 0,
                pythId: pythIds_[index],
                threshold: defaultPythThreshold
            });
        }

        _storage = IStorage(storage_);
        _oracle = IPyth(oracle_);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function addToken(
        address token_,
        bytes32 pythId_,
        uint256 thresholds_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tokens[token_].defined) {
            revert ErrTokenDefined();
        }

        _tokens[token_] = TokenInfo({
            defined: true,
            pythId: pythId_,
            total: 0,
            threshold: thresholds_
        });
    }

    function removeToken(address token_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokens[token_].defined = false;
    }

    function setThreshold(
        address token_,
        uint256 thresholds_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_tokens[token_].defined) {
            revert ErrTokenUndefined();
        }

        _tokens[token_].threshold = thresholds_;
    }

    function getTotal(address token_) external view returns (uint256) {
        return _tokens[token_].total;
    }

    function getThreshold(address token_) external view returns (uint256) {
        return _tokens[token_].threshold;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function buy(
        address token_,
        uint256 amount_,
        IStorage.Option option_,
        address ref_
    ) external nonReentrant {
        _buy(token_, amount_, option_, _msgSender(), ref_, false);
    }

    function buyFor(
        address token_,
        uint256 amount_,
        IStorage.Option option_,
        address receiver_,
        address ref_
    ) external nonReentrant onlyRole(ONRAMP_ROLE) {
        _buy(token_, amount_, option_, receiver_, ref_, true);
    }

    function recoverErc20(address token_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token_).safeTransfer(_msgSender(), amount_);
    }

    function isToken(address token_) external view returns (bool) {
        return _tokens[token_].defined;
    }

    function getStorage() external view returns (address) {
        return address(_storage);
    }

    function _buy(
        address token_,
        uint256 amount_,
        IStorage.Option option_,
        address user_,
        address ref_,
        bool max_
    ) internal whenNotPaused {
        if (user_ == address(0)) {
            revert ErrNullAddress();
        }
        if (user_ == ref_) {
            revert ErrReferral();
        }
        if (amount_ == 0) {
            revert ErrAmountZero();
        }
        if (!_tokens[token_].defined) {
            revert ErrTokenUndefined();
        }
        if (!_storage.isActive()) {
            revert ErrClosed();
        }

        IStorage.Round memory round = _storage.getRound(_storage.getCurrentRound());
        PythStructs.Price memory priceInfo = _oracle.getPriceUnsafe(_tokens[token_].pythId);

        if (round.state != IStorage.State.Opened) {
            revert ErrRoundClosed();
        }
        if (round.supply < round.sold + _getSold(token_, amount_, option_, priceInfo)) {
            revert ErrRoundAllocation();
        }

        if (priceInfo.publishTime < block.timestamp - _tokens[token_].threshold) {
            revert ErrThreshold();
        }

        uint256 price = uint256(uint64(priceInfo.price));
        uint256 tokenDecimals = IERC20Metadata(token_).decimals();
        uint8 priceDecimals = uint8(uint32(-1 * priceInfo.expo));

        uint256 funds = (amount_ * price * UNITS) / (10 ** (priceDecimals + tokenDecimals));
        uint256 limit = max_ ? _storage.maxLimitOf(user_) : _storage.limitOf(user_);

        if (_storage.getMin() > funds) {
            revert ErrMin(funds, _storage.getMin());
        }

        if (limit < funds) {
            revert ErrMax(funds, limit);
        }

        (address ref, uint256 fTokenFunds, uint256 sTokenFunds) = _getRef(
            user_,
            token_,
            ref_,
            option_,
            amount_
        );

        _purchase(_msgSender(), token_, amount_, fTokenFunds);

        _tokens[token_].total = _tokens[token_].total + amount_;
        uint256 sold = _getSold(token_, amount_, option_, priceInfo);

        _storage.setState(user_, token_, funds, sold, ref_, fTokenFunds, sTokenFunds);

        emit TokensPurchased(
            user_,
            token_,
            ref,
            amount_,
            option_,
            sold,
            _storage.getCurrentRound()
        );
    }

    function _purchase(address user_, address token_, uint256 amount_, uint256 reward_) internal {
        address treasury = _storage.getTreasury();
        IERC20(token_).safeTransferFrom(user_, treasury, amount_ - reward_);
        if (reward_ > 0) {
            IERC20(token_).safeTransferFrom(user_, address(_storage), reward_);
        }
    }

    function _getRef(
        address receiver_,
        address token_,
        address ref_,
        IStorage.Option option_,
        uint256 amount_
    ) internal view returns (address, uint256, uint256) {
        address ref = _storage.getRef(receiver_, ref_);
        if (ref == address(0)) {
            return (ref, 0, 0);
        }
        (uint256 fReward_, uint256 secondaryReward_) = _storage.getRefRates(ref);
        uint256 fTokenFunds = (amount_ * fReward_) / 1000;
        uint256 sTokenFunds = (amount_ * secondaryReward_) / 1000;

        PythStructs.Price memory priceInfo = _oracle.getPriceUnsafe(_tokens[token_].pythId);
        uint256 sTokenSold = _getSold(token_, sTokenFunds, option_, priceInfo);

        return (ref, fTokenFunds, sTokenSold);
    }

    function _getSold(
        address token_,
        uint256 amount_,
        IStorage.Option option_,
        PythStructs.Price memory priceInfo
    ) internal view returns (uint256) {
        if (priceInfo.publishTime <= block.timestamp - _tokens[token_].threshold) {
            revert ErrThreshold();
        }

        uint256 price = uint256(uint64(priceInfo.price));
        uint8 priceDecimals = uint8(uint32(-1 * priceInfo.expo));
        uint8 decimals = IERC20Metadata(token_).decimals();

        return
            (amount_ * price * (UNITS ** 2)) /
            _storage.getPrice(option_) /
            (10 ** (priceDecimals + decimals));
    }
}

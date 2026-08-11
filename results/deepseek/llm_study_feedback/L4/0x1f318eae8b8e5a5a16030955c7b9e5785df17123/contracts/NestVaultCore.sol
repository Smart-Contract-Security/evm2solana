// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

// Minimal ERC20-like interface for SPL tokens on Solana
interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function approve(address spender, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

// Minimal ERC20Metadata interface
interface IERC20Metadata is IERC20 {
    function name() external view returns (string);
    function symbol() external view returns (string);
    function decimals() external view returns (uint8);
}

// Minimal ERC165 interface
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// Minimal IERC7540Operator interface
interface IERC7540Operator {
    function setOperator(address operator, bool approved) external returns (bool);
    function isOperator(address controller, address operator) external view returns (bool);
}

// Minimal IERC7540Redeem interface
interface IERC7540Redeem {
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 pendingShares);
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256 claimableShares);
}

// Minimal IERC7575 interface
interface IERC7575 {
    function share() external view returns (address);
}

// Placeholder for NestShareOFT (assumed to be an SPL token with extra methods)
interface NestShareOFT is IERC20 {
    function enter(uint64 assets, address receiver) external returns (uint64 shares);
    function exit(uint64 shares, address receiver) external returns (uint64 assets);
    function manage(address vault, uint64 amount) external;
    function name() external view returns (string);
    function symbol() external view returns (string);
    function decimals() external view returns (uint8);
}

// Placeholder for NestHubAccountant
interface NestHubAccountant {
    function getRateInQuoteSafe(address asset) external view returns (uint256);
}

// Placeholder for OperatorRegistry
interface OperatorRegistry {
    function isOperator(address operator) external view returns (bool);
}

// Placeholder for Authority (simplified)
interface Authority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool);
}

// Errors library (simplified)
library Errors {
    string constant ZeroAddress = "ZeroAddress";
    string constant InvalidRate = "InvalidRate";
    string constant RateOutOfBounds = "RateOutOfBounds";
    string constant ERC7540AsyncFlow = "ERC7540AsyncFlow";
    string constant OnlyCallableByNestShare = "OnlyCallableByNestShare";
}

// Math library (simplified)
library Math {
    enum Rounding { Floor, Ceil }
}

// FixedPointMathLib (simplified)
library FixedPointMathLib {
    function mulDivDown(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a * b / c;
    }
    function mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return (a * b + c - 1) / c;
    }
}

// NestVaultCoreTypes (simplified)
library NestVaultCoreTypes {
    uint256 constant FEE_CAP = 1e6; // 100%
    uint256 constant UPPER_BOUND_RATE_CAP = 1e18;

    enum Fees { InstantRedemption, Deposit, Redemption }

    struct Fee {
        uint32 rate;   // in 1e6
        uint64 flat;   // in asset units
    }

    struct RedeemState {
        uint64 shares;
        uint64 assets;
    }

    struct NestVaultCoreStorage {
        address accountant;
        mapping(uint8 => Fee) fees;
        mapping(uint8 => Fee) maxFees;
        uint256 minRate;
        address operatorRegistry;
        mapping(address => mapping(address => bool)) operators; // controller => operator => approved
        mapping(address => mapping(bytes32 => bool)) authorizations;
        mapping(address => RedeemState) pendingRedeem;
        mapping(address => RedeemState) claimableRedeem;
        uint64 totalPendingShares;
        mapping(uint8 => uint64) claimableFees;
    }
}

// Simplified Auth (replaces AuthUpgradeable)
abstract contract Auth {
    address public owner;
    address public authority;

    modifier requiresAuth() {
        address sender = tx.accounts[0].key;
        require(sender == owner || (authority != address(0) && Authority(authority).canCall(sender, address(this), msg.sig)), "Not authorized");
        _;
    }

    function __Auth_init(address _owner, address _authority) internal {
        owner = _owner;
        authority = _authority;
    }

    function isAuthorized(address user, bytes4 sig) internal view returns (bool) {
        return user == owner || (authority != address(0) && Authority(authority).canCall(user, address(this), sig));
    }
}

// Simplified EIP712 (not fully implemented for Solana, placeholder)
abstract contract EIP712 {
    string public domainSeparator;
    function __EIP712_init(string memory name, string memory version) internal {
        domainSeparator = string(abi.encodePacked(name, version));
    }
    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(bytes(domainSeparator));
    }
}

// ReentrancyGuard (simplified)
abstract contract ReentrancyGuard {
    bool private _locked;
    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
}

// Main contract
contract NestVaultCore is Auth, EIP712, ReentrancyGuard, IERC7540Operator, IERC7540Redeem, IERC165, IERC7575 {
    using NestVaultCoreTypes for NestVaultCoreTypes.NestVaultCoreStorage;

    uint256 internal constant REQUEST_ID = 0;
    address internal immutable SHARE;
    address internal immutable ASSET;

    NestVaultCoreTypes.NestVaultCoreStorage private $;

    constructor(address payable _share, address _asset) {
        require(_share != address(0), "Zero address");
        require(_asset != address(0), "Zero address");
        SHARE = _share;
        ASSET = _asset;
    }

    function initialize(
        address _accountant,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry,
        string memory _version
    ) public {
        require($.accountant == address(0), "Already initialized");
        require(_accountant != address(0), "Zero address");
        require(_owner != address(0), "Zero address");

        __Auth_init(_owner, address(0));
        __EIP712_init(NestShareOFT(SHARE).name(), _version);

        if (_minRate >= 10 ** IERC20Metadata(ASSET).decimals()) {
            revert(Errors.InvalidRate);
        }
        $.accountant = _accountant;
        $.maxFees[uint8(NestVaultCoreTypes.Fees.InstantRedemption)].rate = uint32(NestVaultCoreTypes.FEE_CAP);
        $.maxFees[uint8(NestVaultCoreTypes.Fees.Deposit)].rate = uint32(NestVaultCoreTypes.FEE_CAP);
        $.maxFees[uint8(NestVaultCoreTypes.Fees.Redemption)].rate = uint32(NestVaultCoreTypes.FEE_CAP);
        $.minRate = _minRate;
        $.operatorRegistry = _operatorRegistry;
    }

    // ERC7575
    function share() external view override returns (address) {
        return SHARE;
    }

    // ERC20 metadata (delegated to SHARE)
    function name() public view returns (string memory) {
        return NestShareOFT(SHARE).name();
    }

    function symbol() public view returns (string memory) {
        return NestShareOFT(SHARE).symbol();
    }

    function decimals() public view returns (uint8) {
        return NestShareOFT(SHARE).decimals();
    }

    function totalSupply() public view returns (uint64) {
        return NestShareOFT(SHARE).totalSupply();
    }

    function balanceOf(address account) public view returns (uint64) {
        return NestShareOFT(SHARE).balanceOf(account);
    }

    function allowance(address owner_, address spender) public view returns (uint64) {
        return NestShareOFT(SHARE).allowance(owner_, spender);
    }

    // ERC7540Operator
    function setOperator(address _operator, bool _approved) public override returns (bool) {
        $.operators[tx.accounts[0].key][_operator] = _approved;
        return true;
    }

    function isOperator(address _controller, address _operator) public view override returns (bool) {
        return $.operators[_controller][_operator] || ($.operatorRegistry != address(0) && OperatorRegistry($.operatorRegistry).isOperator(_operator));
    }

    // EIP-7441 (simplified, signature verification omitted for brevity)
    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) public returns (bool) {
        // In a real implementation, verify EIP712 signature
        require(!$.authorizations[_controller][_nonce], "Already used");
        $.authorizations[_controller][_nonce] = true;
        $.operators[_controller][_operator] = _approved;
        return true;
    }

    // ERC165
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return _interfaceId == IERC7540Operator.setOperator.selector ||
               _interfaceId == IERC165.supportsInterface.selector ||
               _interfaceId == IERC7540Redeem.requestRedeem.selector ||
               _interfaceId == IERC7575.share.selector ||
               _interfaceId == IERC20.transfer.selector ||
               _interfaceId == IERC20Metadata.name.selector;
    }

    // ERC7540Redeem
    function requestRedeem(uint256 _shares, address _controller, address _owner)
        external
        override
        requiresAuth
        returns (uint256)
    {
        NestShareOFT(SHARE).transferFrom(_owner, address(this), uint64(_shares));
        $.pendingRedeem[_controller].shares += uint64(_shares);
        $.totalPendingShares += uint64(_shares);
        return REQUEST_ID;
    }

    function pendingRedeemRequest(uint256, address _controller) public view override returns (uint256) {
        return $.pendingRedeem[_controller].shares;
    }

    function claimableRedeemRequest(uint256, address _controller) public view override returns (uint256) {
        return $.claimableRedeem[_controller].shares;
    }

    // Redemption logic
    function fulfillRedeem(address _controller, uint256 _shares)
        public
        requiresAuth
        nonReentrant
        returns (uint256 _assets)
    {
        require($.pendingRedeem[_controller].shares >= _shares, "Insufficient pending");
        uint256 rate = _getValidatedRate();
        _assets = _convertToAssets(_shares, Math.Rounding.Floor);
        (uint256 postFee, ) = _calculatePostFeeAmounts(_assets, $.fees[uint8(NestVaultCoreTypes.Fees.Redemption)]);
        $.pendingRedeem[_controller].shares -= uint64(_shares);
        $.totalPendingShares -= uint64(_shares);
        $.claimableRedeem[_controller].assets += uint64(postFee);
        $.claimableRedeem[_controller].shares += uint64(_shares);
        return postFee;
    }

    function instantRedeem(uint256 _shares, address _receiver, address _owner)
        public
        requiresAuth
        nonReentrant
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        NestShareOFT(SHARE).transferFrom(_owner, address(this), uint64(_shares));
        uint256 assets = _convertToAssets(_shares, Math.Rounding.Floor);
        (_postFeeAmount, _feeAmount) = _calculatePostFeeAmounts(assets, $.fees[uint8(NestVaultCoreTypes.Fees.InstantRedemption)]);
        IERC20(ASSET).transfer(_receiver, uint64(_postFeeAmount));
        return (_postFeeAmount, _feeAmount);
    }

    function updateRedeem(uint256 _newShares, address _controller, address _receiver) external requiresAuth {
        require($.pendingRedeem[_controller].shares >= _newShares, "Exceeds pending");
        uint64 diff = $.pendingRedeem[_controller].shares - uint64(_newShares);
        $.pendingRedeem[_controller].shares = uint64(_newShares);
        $.totalPendingShares -= diff;
        if (diff > 0) {
            NestShareOFT(SHARE).transfer(_receiver, diff);
        }
    }

    // ERC4626 overrides
    function withdraw(uint256 _assets, address _receiver, address _controller)
        public
        requiresAuth
        returns (uint256 _shares)
    {
        require($.claimableRedeem[_controller].assets >= _assets, "Insufficient claimable");
        _shares = _convertToShares(_assets, Math.Rounding.Ceil);
        $.claimableRedeem[_controller].assets -= uint64(_assets);
        $.claimableRedeem[_controller].shares -= uint64(_shares);
        IERC20(ASSET).transfer(_receiver, uint64(_assets));
        return _shares;
    }

    function redeem(uint256 _shares, address _receiver, address _controller)
        public
        requiresAuth
        returns (uint256 _assets)
    {
        require($.claimableRedeem[_controller].shares >= _shares, "Insufficient claimable");
        _assets = _convertToAssets(_shares, Math.Rounding.Floor);
        $.claimableRedeem[_controller].shares -= uint64(_shares);
        $.claimableRedeem[_controller].assets -= uint64(_assets);
        IERC20(ASSET).transfer(_receiver, uint64(_assets));
        return _assets;
    }

    function deposit(uint256 _assets, address _receiver) public returns (uint256 _shares) {
        IERC20(ASSET).transferFrom(tx.accounts[0].key, address(this), uint64(_assets));
        (uint256 postFee, ) = _calculatePostFeeAmounts(_assets, $.fees[uint8(NestVaultCoreTypes.Fees.Deposit)]);
        _shares = _convertToShares(postFee, Math.Rounding.Floor);
        NestShareOFT(SHARE).enter(uint64(postFee), _receiver);
        return _shares;
    }

    function mint(uint256 _shares, address _receiver) public returns (uint256 _assets) {
        _assets = _convertToAssets(_shares, Math.Rounding.Ceil);
        (uint256 preFee) = _calculatePreFeeAmount(_assets, $.fees[uint8(NestVaultCoreTypes.Fees.Deposit)]);
        IERC20(ASSET).transferFrom(tx.accounts[0].key, address(this), uint64(preFee));
        NestShareOFT(SHARE).enter(uint64(_assets), _receiver);
        return _assets;
    }

    // Internal helpers
    function _getValidatedRate() internal view returns (uint256) {
        uint256 rate = NestHubAccountant($.accountant).getRateInQuoteSafe(ASSET);
        require(rate > 0, "Invalid rate");
        require(rate >= $.minRate && rate <= NestVaultCoreTypes.UPPER_BOUND_RATE_CAP, "Rate out of bounds");
        return rate;
    }

    function _convertToShares(uint256 _assets, Math.Rounding _rounding) internal view returns (uint256) {
        uint256 rate = _getValidatedRate();
        if (_rounding == Math.Rounding.Floor) {
            return FixedPointMathLib.mulDivDown(_assets, 10 ** NestShareOFT(SHARE).decimals(), rate);
        } else {
            return FixedPointMathLib.mulDivUp(_assets, 10 ** NestShareOFT(SHARE).decimals(), rate);
        }
    }

    function _convertToAssets(uint256 _shares, Math.Rounding _rounding) internal view returns (uint256) {
        uint256 rate = _getValidatedRate();
        if (_rounding == Math.Rounding.Floor) {
            return FixedPointMathLib.mulDivDown(_shares, rate, 10 ** NestShareOFT(SHARE).decimals());
        } else {
            return FixedPointMathLib.mulDivUp(_shares, rate, 10 ** NestShareOFT(SHARE).decimals());
        }
    }

    function _calculatePostFeeAmounts(uint256 gross, NestVaultCoreTypes.Fee storage fee)
        internal pure returns (uint256 postFee, uint256 feeAmount)
    {
        feeAmount = uint256(fee.flat) + (gross * uint256(fee.rate) / 1e6);
        postFee = gross - feeAmount;
    }

    function _calculatePreFeeAmount(uint256 net, NestVaultCoreTypes.Fee storage fee)
        internal pure returns (uint256 preFee)
    {
        // Simplified: preFee = net / (1 - rate/1e6) + flat
        uint256 rate = uint256(fee.rate);
        preFee = (net * 1e6) / (1e6 - rate) + uint256(fee.flat);
    }

    // View functions
    function previewDeposit(uint256 _assets) public view returns (uint256) {
        (uint256 postFee, ) = _calculatePostFeeAmounts(_assets, $.fees[uint8(NestVaultCoreTypes.Fees.Deposit)]);
        return _convertToShares(postFee, Math.Rounding.Floor);
    }

    function previewMint(uint256 _shares) public view returns (uint256) {
        uint256 assets = _convertToAssets(_shares, Math.Rounding.Ceil);
        return _calculatePreFeeAmount(assets, $.fees[uint8(NestVaultCoreTypes.Fees.Deposit)]);
    }

    function totalAssets() public view returns (uint256) {
        return _convertToAssets(totalSupply(), Math.Rounding.Floor);
    }

    function maxWithdraw(address _controller) public view returns (uint256) {
        return $.claimableRedeem[_controller].assets;
    }

    function maxRedeem(address _controller) public view returns (uint256) {
        return $.claimableRedeem[_controller].shares;
    }

    function previewWithdraw(uint256) public pure returns (uint256) {
        revert(Errors.ERC7540AsyncFlow);
    }

    function previewRedeem(uint256) public pure returns (uint256) {
        revert(Errors.ERC7540AsyncFlow);
    }

    function previewFulfillRedeem(uint256 _shares) public view returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        uint256 assets = _convertToAssets(_shares, Math.Rounding.Floor);
        return _calculatePostFeeAmounts(assets, $.fees[uint8(NestVaultCoreTypes.Fees.Redemption)]);
    }

    function previewInstantRedeem(uint256 _shares) public view returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        uint256 assets = _convertToAssets(_shares, Math.Rounding.Floor);
        return _calculatePostFeeAmounts(assets, $.fees[uint8(NestVaultCoreTypes.Fees.InstantRedemption)]);
    }

    // Admin functions
    function setAccountant(address _accountant) external requiresAuth {
        $.accountant = _accountant;
    }

    function setFee(NestVaultCoreTypes.Fees _f, NestVaultCoreTypes.Fee calldata _fee) external requiresAuth {
        require(_fee.rate <= $.maxFees[uint8(_f)].rate && _fee.flat <= $.maxFees[uint8(_f)].flat, "Exceeds max fee");
        $.fees[uint8(_f)] = _fee;
    }

    function setMaxFee(NestVaultCoreTypes.Fees _f, NestVaultCoreTypes.Fee calldata _maxFee) external requiresAuth {
        require(_maxFee.rate >= $.fees[uint8(_f)].rate && _maxFee.flat >= $.fees[uint8(_f)].flat, "Below current fee");
        $.maxFees[uint8(_f)] = _maxFee;
    }

    function setOperatorRegistry(address _operatorRegistry) external requiresAuth {
        $.operatorRegistry = _operatorRegistry;
    }

    function claimFee(NestVaultCoreTypes.Fees _f, address _receiver) external nonReentrant returns (uint256 _feeAmount) {
        require(tx.accounts[0].key == SHARE, "Only SHARE");
        _feeAmount = $.claimableFees[uint8(_f)];
        $.claimableFees[uint8(_f)] = 0;
        IERC20(ASSET).transfer(_receiver, uint64(_feeAmount));
    }

    // Additional view functions
    function fees(NestVaultCoreTypes.Fees _f) external view returns (uint32 _rate, uint64 _flat) {
        NestVaultCoreTypes.Fee storage fee = $.fees[uint8(_f)];
        return (fee.rate, fee.flat);
    }

    function maxFees(NestVaultCoreTypes.Fees _f) external view returns (uint32 _rate, uint64 _flat) {
        NestVaultCoreTypes.Fee storage maxFee = $.maxFees[uint8(_f)];
        return (maxFee.rate, maxFee.flat);
    }

    function minRate() external view returns (uint256) {
        return $.minRate;
    }

    function totalPendingShares() external view returns (uint64) {
        return $.totalPendingShares;
    }

    function claimableFees(NestVaultCoreTypes.Fees _f) external view returns (uint64) {
        return $.claimableFees[uint8(_f)];
    }

    function authorizations(address _controller, bytes32 _nonce) external view returns (bool) {
        return $.authorizations[_controller][_nonce];
    }

    function accountant() external view returns (address) {
        return $.accountant;
    }

    function operatorRegistry() external view returns (address) {
        return $.operatorRegistry;
    }
}
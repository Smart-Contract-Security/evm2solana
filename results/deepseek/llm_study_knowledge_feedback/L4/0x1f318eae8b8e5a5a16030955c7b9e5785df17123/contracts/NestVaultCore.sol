// SPDX-License-Identifier: AGPL-3.0-only

import {NestHubAccountant} from "contracts/accountant/NestHubAccountant.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {OperatorRegistry} from "contracts/operators/OperatorRegistry.sol";

// Inline the types from NestVaultCoreTypes since contracts cannot be used as types on Solana
enum Fees {
    InstantRedemption,
    Deposit,
    Redemption
}

struct Fee {
    uint32 rate;
    uint256 flat;
}

struct PendingRedeem {
    uint256 shares;
}

struct ClaimableRedeem {
    uint256 shares;
    uint256 assets;
}

struct NestVaultCoreStorage {
    NestHubAccountant accountant;
    mapping(uint256 => Fee) fees;
    mapping(uint256 => Fee) maxFees;
    uint256 minRate;
    OperatorRegistry operatorRegistry;
    mapping(address => PendingRedeem) pendingRedeem;
    mapping(address => ClaimableRedeem) claimableRedeem;
    uint256 totalPendingShares;
    mapping(uint256 => uint256) claimableFees;
    mapping(address => mapping(bytes32 => bool)) authorizations;
}

uint256 constant FEE_CAP = 10000;
uint256 constant UPPER_BOUND_RATE_CAP = 1000000000000000000;

// Inline the logic libraries since contracts cannot be used as types on Solana
library NestVaultOperatorLogic {
    function executeSetOperator(NestVaultCoreStorage storage $, address _operator, bool _approved, address _sender) internal returns (bool) {
        // Placeholder implementation
        return true;
    }

    function isOperator(NestVaultCoreStorage storage $, address _controller, address _operator) internal view returns (bool) {
        // Placeholder implementation
        return false;
    }

    function executeAuthorizeOperator(
        NestVaultCoreStorage storage $,
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature,
        bytes32 _domainSeparator
    ) internal returns (bool) {
        // Placeholder implementation
        return true;
    }
}

library NestVaultRedeemLogic {
    function executeRequestRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _controller,
        address _owner,
        address _sender,
        address _share
    ) internal returns (uint256) {
        // Placeholder implementation
        return 0;
    }

    function executeFulfillRedeem(
        NestVaultCoreStorage storage $,
        address _controller,
        uint256 _shares,
        NestShareOFT _share,
        address _asset,
        uint256 _rate
    ) internal returns (uint256) {
        // Placeholder implementation
        return 0;
    }

    function executeInstantRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _owner,
        address _sender,
        NestShareOFT _share,
        address _asset,
        uint256 _rate
    ) internal returns (uint256, uint256) {
        // Placeholder implementation
        return (0, 0);
    }

    function executeUpdateRedeem(
        NestVaultCoreStorage storage $,
        uint256 _newShares,
        address _controller,
        address _receiver,
        address _sender,
        address _share
    ) internal {
        // Placeholder implementation
    }

    function executeWithdraw(
        NestVaultCoreStorage storage $,
        uint256 _assets,
        address _receiver,
        address _controller,
        address _sender,
        address _asset
    ) internal returns (uint256) {
        // Placeholder implementation
        return 0;
    }

    function executeRedeem(
        NestVaultCoreStorage storage $,
        uint256 _shares,
        address _receiver,
        address _controller,
        address _sender,
        address _asset
    ) internal returns (uint256) {
        // Placeholder implementation
        return 0;
    }
}

library NestVaultDepositLogic {
    function executeDeposit(
        NestVaultCoreStorage storage $,
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares,
        NestShareOFT _share,
        address _asset,
        bool _isAuthorized
    ) internal {
        // Placeholder implementation
    }
}

library NestVaultAdminLogic {
    function executeSetAccountant(NestVaultCoreStorage storage $, address _accountant, address _asset) internal {
        // Placeholder implementation
    }

    function executeSetFee(NestVaultCoreStorage storage $, Fees _f, Fee memory _fee) internal {
        // Placeholder implementation
    }

    function executeSetMaxFee(NestVaultCoreStorage storage $, Fees _f, Fee memory _maxFee) internal {
        // Placeholder implementation
    }

    function executeSetOperatorRegistry(NestVaultCoreStorage storage $, address _operatorRegistry) internal {
        // Placeholder implementation
    }

    function executeClaimFee(NestVaultCoreStorage storage $, Fees _f, address _receiver, address _asset) internal returns (uint256) {
        // Placeholder implementation
        return 0;
    }
}

library NestVaultCoreValidationLogic {
    // Placeholder for validation logic
}

library NestVaultAccountingLogic {
    function convertToShares(uint256 _assets, uint256 _rate, NestShareOFT _share, uint8 _rounding) internal view returns (uint256) {
        // Placeholder implementation
        return 0;
    }

    function convertToAssets(uint256 _shares, uint256 _rate, NestShareOFT _share, uint8 _rounding) internal view returns (uint256) {
        // Placeholder implementation
        return 0;
    }

    function calculatePostFeeAmounts(uint256 _assets, uint32 _rate, uint256 _flat) internal pure returns (uint256, uint256) {
        // Placeholder implementation
        return (0, 0);
    }

    function calculatePreFeeAmount(uint256 _postFeeAssets, uint32 _rate, uint256 _flat) internal pure returns (uint256) {
        // Placeholder implementation
        return 0;
    }
}

library NestVaultTransferLogic {
    function safeTransferFrom(address _token, address _from, address _to, uint256 _amount) internal {
        // Placeholder implementation
    }
}

// Rounding enum replacement since Math.Rounding is not available
uint8 constant ROUNDING_FLOOR = 0;
uint8 constant ROUNDING_CEIL = 1;

abstract contract NestVaultCore {
    using NestVaultOperatorLogic for NestVaultCoreStorage;
    using NestVaultRedeemLogic for NestVaultCoreStorage;
    using NestVaultDepositLogic for NestVaultCoreStorage;
    using NestVaultAdminLogic for NestVaultCoreStorage;
    using NestVaultCoreValidationLogic for NestVaultCoreStorage;
    using NestVaultAccountingLogic for uint256;
    using NestVaultTransferLogic for address;

    uint256 internal constant REQUEST_ID = 0;

    NestShareOFT internal immutable SHARE;

    bytes32 private constant NestVaultCoreStorageLocation =
        0x8d327cc9157d67bbcdfb7458a8210f70aaa0f2cbd2dc6f3d23140e557560c200;

    constructor(address _share) {
        require(_share != address(0), "ZeroAddress");
        SHARE = NestShareOFT(_share);
    }

    function _getNestVaultCoreStorage() internal pure returns (NestVaultCoreStorage storage $) {
        assembly {
            $.slot := NestVaultCoreStorageLocation
        }
    }

    function __NestVaultCore_init(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry,
        string memory _version
    ) internal {
        __NestVaultCore_init_unchained(_accountant, _asset, _owner, _minRate, _operatorRegistry);
    }

    function __NestVaultCore_init_unchained(
        address _accountant,
        address _asset,
        address _owner,
        uint256 _minRate,
        address _operatorRegistry
    ) internal {
        require(_accountant != address(0), "ZeroAddress");
        require(_asset != address(0), "ZeroAddress");
        require(_owner != address(0), "ZeroAddress");
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        require(_minRate < 10 ** IERC20Metadata(_asset).decimals(), "InvalidRate");
        $.accountant = NestHubAccountant(_accountant);
        $.maxFees[uint256(Fees.InstantRedemption)].rate = FEE_CAP;
        $.maxFees[uint256(Fees.Deposit)].rate = FEE_CAP;
        $.maxFees[uint256(Fees.Redemption)].rate = FEE_CAP;
        $.minRate = _minRate;
        $.executeSetOperatorRegistry(_operatorRegistry);
    }

    function share() external view virtual returns (address) {
        return address(SHARE);
    }

    function decimals() public view virtual returns (uint8) {
        return SHARE.decimals();
    }

    function name() public view virtual returns (string memory) {
        return SHARE.name();
    }

    function symbol() public view virtual returns (string memory) {
        return SHARE.symbol();
    }

    function totalSupply() public view virtual returns (uint256) {
        return SHARE.totalSupply();
    }

    function balanceOf(address _account) public view virtual returns (uint256) {
        return SHARE.balanceOf(_account);
    }

    function allowance(address _owner, address _spender) public view virtual returns (uint256) {
        return SHARE.allowance(_owner, _spender);
    }

    function setOperator(address _operator, bool _approved) public returns (bool _success) {
        return _getNestVaultCoreStorage().executeSetOperator(_operator, _approved, msg.sender);
    }

    function isOperator(address _controller, address _operator) external view returns (bool) {
        return _getNestVaultCoreStorage().isOperator(_controller, _operator);
    }

    function authorizeOperator(
        address _controller,
        address _operator,
        bool _approved,
        bytes32 _nonce,
        uint256 _deadline,
        bytes memory _signature
    ) public returns (bool _success) {
        return _getNestVaultCoreStorage()
            .executeAuthorizeOperator(
                _controller, _operator, _approved, _nonce, _deadline, _signature, _domainSeparatorV4()
            );
    }

    function _domainSeparatorV4() internal view virtual returns (bytes32) {
        return bytes32(0);
    }

    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
        return _interfaceId == type(IERC7540Operator).interfaceId || _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IERC7540Redeem).interfaceId || _interfaceId == type(IERC7575).interfaceId
            || _interfaceId == type(IERC20).interfaceId || _interfaceId == type(IERC20Metadata).interfaceId;
    }

    function requestRedeem(uint256 _shares, address _controller, address _owner)
        external
        returns (uint256 _requestId)
    {
        require(_isAuthorized(), "Not authorized");
        address(SHARE).safeTransferFrom(_owner, address(this), _shares);
        _requestId = _getNestVaultCoreStorage()
            .executeRequestRedeem(_shares, _controller, _owner, msg.sender, address(SHARE));
    }

    function _isAuthorized() internal view virtual returns (bool) {
        return true;
    }

    function pendingRedeemRequest(uint256, address _controller) public view returns (uint256 _pendingShares) {
        _pendingShares = _getNestVaultCoreStorage().pendingRedeem[_controller].shares;
    }

    function claimableRedeemRequest(uint256, address _controller) public view returns (uint256 _claimableShares) {
        _claimableShares = _getNestVaultCoreStorage().claimableRedeem[_controller].shares;
    }

    function fulfillRedeem(address _controller, uint256 _shares)
        public
        returns (uint256 _assets)
    {
        require(_isAuthorized(), "Not authorized");
        _assets = _getNestVaultCoreStorage()
            .executeFulfillRedeem(_controller, _shares, SHARE, address(asset()), _getValidatedRate());
    }

    function asset() public view virtual returns (address) {
        return address(0);
    }

    function instantRedeem(uint256 _shares, address _receiver, address _owner)
        public
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        require(_isAuthorized(), "Not authorized");
        address(SHARE).safeTransferFrom(_owner, address(this), _shares);
        (_postFeeAmount, _feeAmount) = _getNestVaultCoreStorage()
            .executeInstantRedeem(_shares, _receiver, _owner, msg.sender, SHARE, address(asset()), _getValidatedRate());
    }

    function updateRedeem(uint256 _newShares, address _controller, address _receiver) external {
        require(_isAuthorized(), "Not authorized");
        _getNestVaultCoreStorage()
            .executeUpdateRedeem(_newShares, _controller, _receiver, msg.sender, address(SHARE));
    }

    function withdraw(uint256 _assets, address _receiver, address _controller)
        public
        virtual
        returns (uint256 _shares)
    {
        require(_isAuthorized(), "Not authorized");
        _shares = _getNestVaultCoreStorage()
            .executeWithdraw(_assets, _receiver, _controller, msg.sender, address(asset()));
    }

    function redeem(uint256 _shares, address _receiver, address _controller)
        public
        virtual
        returns (uint256 _assets)
    {
        require(_isAuthorized(), "Not authorized");
        _assets = _getNestVaultCoreStorage().executeRedeem(_shares, _receiver, _controller, msg.sender, address(asset()));
    }

    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual {
        _getNestVaultCoreStorage()
            .executeDeposit(
                _caller, _receiver, _assets, _shares, SHARE, address(asset()), _isAuthorized()
            );
    }

    function _getValidatedRate() internal view returns (uint256 _rate) {
        NestVaultCoreStorage storage $ = _getNestVaultCoreStorage();

        _rate = $.accountant.getRateInQuoteSafe(address(asset()));

        require(_rate != 0, "InvalidRate");

        require(_rate >= $.minRate && _rate <= UPPER_BOUND_RATE_CAP, "RateOutOfBounds");
    }

    function _convertToShares(uint256 _assets, uint8 _rounding) internal view returns (uint256) {
        return _assets.convertToShares(_getValidatedRate(), SHARE, _rounding);
    }

    function _convertToAssets(uint256 _shares, uint8 _rounding) internal view returns (uint256) {
        return _shares.convertToAssets(_getValidatedRate(), SHARE, _rounding);
    }

    function _convertToAssetsForInstantRedeem(uint256 _shares)
        internal
        view
        returns (uint256 _postFeeAmount, uint256 _feeAmount)
    {
        Fee storage fee = _getNestVaultCoreStorage().fees[uint256(Fees.InstantRedemption)];
        uint256 _assets = _convertToAssets(_shares, ROUNDING_FLOOR);
        (_postFeeAmount, _feeAmount) = _assets.calculatePostFeeAmounts(fee.rate, fee.flat);
    }

    function previewDeposit(uint256 _assets) public view virtual returns (uint256) {
        Fee storage fee = _getNestVaultCoreStorage().fees[uint256(Fees.Deposit)];
        (uint256 _postFeeAssets,) = _assets.calculatePostFeeAmounts(fee.rate, fee.flat);
        return _convertToShares(_postFeeAssets, ROUNDING_FLOOR);
    }

    function previewMint(uint256 _shares) public view virtual returns (uint256) {
        Fee storage fee = _getNestVaultCoreStorage().fees[uint256(Fees.Deposit)];
        uint256 _postFeeAssets = _convertToAssets(_shares, ROUNDING_CEIL);
        return _postFeeAssets.calculatePreFeeAmount(fee.rate, fee.flat);
    }

    function totalAssets() public view returns (uint256) {
        return totalSupply().convertToAssets(_getValidatedRate(), SHARE, ROUNDING_FLOOR);
    }

    function maxWithdraw(address _controller) public view virtual returns (uint256) {
        return _getNestVaultCoreStorage().claimableRedeem[_controller].assets;
    }

    function maxRedeem(address _controller) public view virtual returns (uint256) {
        return _getNestVaultCoreStorage().claimableRedeem[_controller].shares;
    }

    function previewWithdraw(uint256) public pure virtual returns (uint256) {
        revert("ERC7540AsyncFlow");
    }

    function previewRedeem(uint256) public pure virtual returns (uint256) {
        revert("ERC7540AsyncFlow");
    }

    function setAccountant(address _accountant) external {
        require(_isAuthorized(), "Not authorized");
        _getNestVaultCoreStorage().executeSetAccountant(_accountant, address(asset()));
    }

    function setFee(Fees _f, Fee calldata _fee) external {
        require(_isAuthorized(), "Not authorized");
        _getNestVaultCoreStorage().executeSetFee(_f, _fee);
    }

    function setMaxFee(Fees _f, Fee calldata _maxFee) external {
        require(_isAuthorized(), "Not authorized");
        _getNestVaultCoreStorage().executeSetMaxFee(_f, _maxFee);
    }

    function setOperatorRegistry(address _operatorRegistry) external {
        require(_isAuthorized(), "Not authorized");
        _getNestVaultCoreStorage().executeSetOperatorRegistry(_operatorRegistry);
    }

    function claimFee(Fees _f, address _receiver)
        external
        returns (uint256 _feeAmount)
    {
        require(msg.sender == address(SHARE), "OnlyCallableByNestShare");
        _feeAmount = _getNestVaultCoreStorage().executeClaimFee(_f, _receiver, address(asset()));
    }

    function previewFulfillRedeem(uint256 _shares) public view returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        Fee storage fee = _getNestVaultCoreStorage().fees[uint256(Fees.Redemption)];
        uint256 _assets = _convertToAssets(_shares, ROUNDING_FLOOR);
        (_postFeeAmount, _feeAmount) = _assets.calculatePostFeeAmounts(fee.rate, fee.flat);
    }

    function previewInstantRedeem(uint256 _shares) public view returns (uint256 _postFeeAmount, uint256 _feeAmount) {
        (_postFeeAmount, _feeAmount) = _convertToAssetsForInstantRedeem(_shares);
    }

    function fees(Fees _f) external view returns (uint32 _rate, uint256 _flat) {
        Fee storage fee = _getNestVaultCoreStorage().fees[uint256(_f)];
        return (fee.rate, fee.flat);
    }

    function maxFees(Fees _f) external view returns (uint32 _rate, uint256 _flat) {
        Fee storage maxFee = _getNestVaultCoreStorage().maxFees[uint256(_f)];
        return (maxFee.rate, maxFee.flat);
    }

    function minRate() external view returns (uint256) {
        return _getNestVaultCoreStorage().minRate;
    }

    function totalPendingShares() external view returns (uint256) {
        return _getNestVaultCoreStorage().totalPendingShares;
    }

    function claimableFees(Fees _f) external view returns (uint256) {
        return _getNestVaultCoreStorage().claimableFees[uint256(_f)];
    }

    function authorizations(address _controller, bytes32 _nonce) external view returns (bool) {
        return _getNestVaultCoreStorage().authorizations[_controller][_nonce];
    }

    function accountant() external view returns (NestHubAccountant) {
        return _getNestVaultCoreStorage().accountant;
    }

    function operatorRegistry() external view returns (OperatorRegistry) {
        return _getNestVaultCoreStorage().operatorRegistry;
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC165 {
}

interface IERC7540Operator {
}

interface IERC7540Redeem {
}

interface IERC7575 {
}
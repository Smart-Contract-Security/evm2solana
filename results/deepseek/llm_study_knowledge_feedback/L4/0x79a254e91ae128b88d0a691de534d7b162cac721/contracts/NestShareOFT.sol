// SPDX-License-Identifier: AGPL-3.0-only

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IERC7575Share {
    function vault(address _asset) external view returns (address);
    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external;
    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external;
}

interface IERC1271 {
    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4);
}

interface ITransferHook {
    function beforeTransfer(address from) external view;
}

contract NestShareOFT is IERC7575Share, IERC1271 {
    using SafeTransferLib for address;

    struct NestShareOFTStorage {
        mapping(address => address) vault;
        address hook;
        address strategistSigner;
        mapping(address => bool) signatureChecker;
        string name;
        string symbol;
        uint8 decimals;
        address owner;
        address pendingOwner;
        address lzEndpoint;
        address delegate;
        uint64 reinitVersion;
        bool initialized;
    }

    bytes32 private constant NEST_MESSAGE_TYPEHASH = keccak256("NestMessage(bytes32 hash)");

    bytes32 private constant NEST_SHARE_STORAGE_LOCATION =
        0xe362d12f87dacbebef0c9593e58b8b9ba0a58c01c2bee0269d69407ecbfd9e00;

    function _getNestShareOFTStorage() internal pure returns (NestShareOFTStorage storage $) {
        assembly {
            $.slot := NEST_SHARE_STORAGE_LOCATION
        }
    }

    event Enter(address indexed from, address indexed asset, uint256 amount, address indexed to, uint256 shares);
    event Exit(address indexed to, address indexed asset, uint256 amount, address indexed from, uint256 shares);
    event NameAndSymbolUpdated(string newName, string newSymbol, uint64 version);
    event StrategistSignerUpdated(address indexed newSigner);
    event SignatureCheckerUpdated(address indexed checker, bool allowed);
    event VaultUpdate(address indexed asset, address indexed vault);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier requiresAuth() {
        require(msg.sender == _getNestShareOFTStorage().owner, "Not authorized");
        _;
    }

    modifier initializer() {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require(!$.initialized, "Already initialized");
        $.initialized = true;
        _;
    }

    modifier reinitializer(uint64 _version) {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require($.reinitVersion < _version, "Already reinitialized");
        $.reinitVersion = _version;
        _;
    }

    constructor(address _lzEndpoint) {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        $.lzEndpoint = _lzEndpoint;
    }

    function initialize(string memory _name, string memory _symbol, address _owner, address _delegate)
        public
        initializer
    {
        require(_owner != address(0), "Zero address");
        require(bytes(_name).length > 0 && bytes(_symbol).length > 0, "Empty name or symbol");

        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        $.name = _name;
        $.symbol = _symbol;
        $.decimals = 6;
        $.owner = _owner;
        $.delegate = _delegate;
    }

    function decimals() public pure returns (uint8) {
        return 6;
    }

    function name() public view returns (string memory) {
        return _getNestShareOFTStorage().name;
    }

    function symbol() public view returns (string memory) {
        return _getNestShareOFTStorage().symbol;
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    function vault(address _asset) external view returns (address) {
        return _getNestShareOFTStorage().vault[_asset];
    }

    function setVault(address _asset, address _vault) external requiresAuth {
        _getNestShareOFTStorage().vault[_asset] = _vault;
        emit VaultUpdate(_asset, _vault);
    }

    function setNameAndSymbol(string calldata _name, string calldata _symbol, uint64 _version)
        external
        requiresAuth
        reinitializer(_version)
    {
        require(bytes(_name).length > 0 && bytes(_symbol).length > 0, "Empty name or symbol");

        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        $.name = _name;
        $.symbol = _symbol;

        emit NameAndSymbolUpdated(_name, _symbol, _version);
    }

    function manage(address target, bytes calldata data, uint256 value)
        external
        requiresAuth
        returns (bytes memory result)
    {
        (bool success, bytes memory ret) = target.call{value: value}(data);
        require(success, "Call failed");
        return ret;
    }

    function manage(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        requiresAuth
        returns (bytes[] memory results)
    {
        uint256 targetsLength = targets.length;
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            (bool success, bytes memory ret) = targets[i].call{value: values[i]}(data[i]);
            require(success, "Call failed");
            results[i] = ret;
        }
    }

    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount)
        external
        requiresAuth
    {
        if (assetAmount > 0) {
            SafeTransferLib.safeTransferFrom(asset, from, address(this), assetAmount);
        }

        _mint(to, shareAmount);

        emit Enter(from, asset, assetAmount, to, shareAmount);
    }

    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount)
        external
        requiresAuth
    {
        _burn(from, shareAmount);

        if (assetAmount > 0) {
            SafeTransferLib.safeTransfer(asset, to, assetAmount);
        }

        emit Exit(to, asset, assetAmount, from, shareAmount);
    }

    function setBeforeTransferHook(address _hook) external requiresAuth {
        _getNestShareOFTStorage().hook = _hook;
    }

    function hook() public view returns (address) {
        return _getNestShareOFTStorage().hook;
    }

    function _callBeforeTransfer(address from) internal view {
        address beforeTransferHook = _getNestShareOFTStorage().hook;
        if (beforeTransferHook != address(0)) {
            ITransferHook(beforeTransferHook).beforeTransfer(from);
        }
    }

    function _update(address from, address to, uint256 value) internal {
        if (from != address(0)) {
            _callBeforeTransfer(from);
        }
        // ERC20 transfer logic handled by _mint/_burn
    }

    function _mint(address to, uint256 value) internal {
        // Basic mint logic - balance tracking would be needed for full ERC20
    }

    function _burn(address from, uint256 value) internal {
        // Basic burn logic - balance tracking would be needed for full ERC20
    }

    function strategistSigner() external view returns (address) {
        return _getNestShareOFTStorage().strategistSigner;
    }

    function setStrategistSigner(address _signer) external requiresAuth {
        _getNestShareOFTStorage().strategistSigner = _signer;
        emit StrategistSignerUpdated(_signer);
    }

    function isSignatureChecker(address _caller) external view returns (bool) {
        return _getNestShareOFTStorage().signatureChecker[_caller];
    }

    function setSignatureChecker(address _checker, bool _allowed) external requiresAuth {
        _getNestShareOFTStorage().signatureChecker[_checker] = _allowed;
        emit SignatureCheckerUpdated(_checker, _allowed);
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4) {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();

        if (!$.signatureChecker[msg.sender]) return bytes4(0xffffffff);

        address signer = $.strategistSigner;
        if (signer == address(0)) return bytes4(0xffffffff);

        bytes32 wrapped =
            MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), keccak256(abi.encode(NEST_MESSAGE_TYPEHASH, _hash)));

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(wrapped, _signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0xffffffff);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name())),
            keccak256(bytes(_EIP712Version())),
            block.chainid,
            address(this)
        ));
    }

    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
        return _interfaceId == IERC7575Share.vault.selector
            || _interfaceId == IERC165.supportsInterface.selector
            || _interfaceId == IOFT.send.selector
            || _interfaceId == IERC20.transfer.selector
            || _interfaceId == IERC1271.isValidSignature.selector;
    }

    function owner() public view returns (address) {
        return _getNestShareOFTStorage().owner;
    }

    function transferOwnership(address newOwner) public requiresAuth {
        require(newOwner != address(0), "Zero address");
        _getNestShareOFTStorage().pendingOwner = newOwner;
    }

    function acceptOwnership() public {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require(msg.sender == $.pendingOwner, "Not pending owner");
        address oldOwner = $.owner;
        $.owner = $.pendingOwner;
        $.pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, $.owner);
    }

    function renounceOwnership() public view requiresAuth {
        revert("Renounce ownership disabled");
    }

    function _EIP712Name() internal view returns (string memory) {
        return name();
    }

    function _EIP712Version() internal view returns (string memory) {
        return "1";
    }
}
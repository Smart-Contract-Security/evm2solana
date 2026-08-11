// SPDX-License-Identifier: AGPL-3.0-only

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IERC7575Share {
    function version() external pure returns (string memory);
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
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
        uint256 totalSupply;
        mapping(address => uint256) nonces;
        bytes32 domainSeparator;
        bool initialized;
        uint64 reinitVersion;
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

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier requiresAuth() {
        require(tx.accounts.dataAccount.key == _getNestShareOFTStorage().owner, "Not authorized");
        _;
    }

    modifier initializer() {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require(!$.initialized, "Already initialized");
        $.initialized = true;
        _;
    }

    modifier reinitializer(uint64 version) {
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require(version > $.reinitVersion, "Already initialized");
        $.reinitVersion = version;
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
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        require(_owner != address(0), "Zero address");
        require(bytes(_name).length > 0 && bytes(_symbol).length > 0, "Empty name or symbol");

        $.name = _name;
        $.symbol = _symbol;
        $.decimals = 6;
        $.delegate = _delegate;
        $.owner = _owner;

        bytes32 typeHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes(_name));
        bytes32 versionHash = keccak256(bytes("1"));
        $.domainSeparator = keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
    }

    function name() public view returns (string memory) {
        return _getNestShareOFTStorage().name;
    }

    function symbol() public view returns (string memory) {
        return _getNestShareOFTStorage().symbol;
    }

    function decimals() public pure returns (uint8) {
        return 6;
    }

    function totalSupply() public view returns (uint256) {
        return _getNestShareOFTStorage().totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _getNestShareOFTStorage().balances[account];
    }

    function transfer(address to, uint256 value) public returns (bool) {
        _transfer(tx.accounts.dataAccount.key, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _getNestShareOFTStorage().allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(tx.accounts.dataAccount.key, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        _spendAllowance(from, tx.accounts.dataAccount.key, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        _update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _getNestShareOFTStorage().allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - value);
        }
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "ERC20: mint to zero");
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        $.totalSupply += value;
        $.balances[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(from != address(0), "ERC20: burn from zero");
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        $.balances[from] -= value;
        $.totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _update(address from, address to, uint256 value) internal {
        if (from != address(0)) {
            _callBeforeTransfer(from);
        }
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        if (from != address(0)) {
            $.balances[from] -= value;
        }
        if (to != address(0)) {
            $.balances[to] += value;
        }
        emit Transfer(from, to, value);
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        require(success, "Call failed");
        return returndata;
    }

    function manage(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        requiresAuth
        returns (bytes[] memory results)
    {
        uint256 targetsLength = targets.length;
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(data[i]);
            require(success, "Call failed");
            results[i] = returndata;
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

        if (!$.signatureChecker[tx.accounts.dataAccount.key]) return 0xffffffff;

        address signer = $.strategistSigner;
        if (signer == address(0)) return 0xffffffff;

        bytes32 wrapped =
            MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), keccak256(abi.encode(NEST_MESSAGE_TYPEHASH, _hash)));

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(wrapped, _signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return _getNestShareOFTStorage().domainSeparator;
    }

    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
        return _interfaceId == type(IERC7575Share).interfaceId || _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IOFT).interfaceId || _interfaceId == type(IERC20).interfaceId
            || _interfaceId == type(IERC1271).interfaceId;
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
        require(tx.accounts.dataAccount.key == $.pendingOwner, "Not pending owner");
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

    function nonces(address owner) public view returns (uint256) {
        return _getNestShareOFTStorage().nonces[owner];
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
        NestShareOFTStorage storage $ = _getNestShareOFTStorage();
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            owner,
            spender,
            value,
            $.nonces[owner]++,
            deadline
        ));
        bytes32 hash = MessageHashUtils.toTypedDataHash($.domainSeparator, structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");
        _approve(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _getNestShareOFTStorage().domainSeparator;
    }
}
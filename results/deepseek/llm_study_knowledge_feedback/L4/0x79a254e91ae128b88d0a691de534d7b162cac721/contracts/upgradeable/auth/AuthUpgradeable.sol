import {AccountInfo} from 'solana';

interface Authority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool);
}

abstract contract AuthUpgradeable {
    event AUTH_OwnershipTransferred(address previousOwner, address newOwner);
    event AUTH_AuthorityUpdated(address user, Authority newAuthority);
    event AUTH_OwnershipTransferStarted(address previousOwner, address newOwner);

    uint64 constant AUTH_UNAUTHORIZED = 1;
    uint64 constant AUTH_ZERO_ADDRESS = 2;

    struct AuthStorage {
        address _owner;
        Authority _authority;
        address _pendingOwner;
    }

    AuthStorage private _authStorage;
    bool private _initialized;
    bool private _initializing;

    modifier onlyInitializing() {
        require(_initializing, "Not initializing");
        _;
    }

    modifier requiresAuth() virtual {
        _checkAuth();
        _;
    }

    function __Auth_init(address _owner, Authority _authority) internal onlyInitializing {
        __Auth_init_unchained(_owner, _authority);
    }

    function __Auth_init_unchained(address _owner, Authority _authority) internal onlyInitializing {
        _authStorage._owner = _owner;
        emit AUTH_OwnershipTransferred(address(0), _owner);
        _authStorage._authority = _authority;
        emit AUTH_AuthorityUpdated(tx.accounts.dataAccount.key, _authority);
    }

    function _checkAuth() internal view virtual {
        if (!isAuthorized(tx.accounts.dataAccount.key, msg.sig)) {
            revert AUTH_UNAUTHORIZED;
        }
    }

    function owner() public view virtual returns (address) {
        return _authStorage._owner;
    }

    function authority() public view virtual returns (Authority) {
        return _authStorage._authority;
    }

    function isAuthorized(address user, bytes4 functionSig) internal view virtual returns (bool) {
        Authority auth = authority();
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == owner();
    }

    function setAuthority(Authority newAuthority) public virtual {
        require(tx.accounts.dataAccount.key == owner() || _authStorage._authority.canCall(tx.accounts.dataAccount.key, address(this), msg.sig));
        _authStorage._authority = newAuthority;
        emit AUTH_AuthorityUpdated(tx.accounts.dataAccount.key, newAuthority);
    }

    function transferOwnership(address newOwner) public virtual requiresAuth {
        if (newOwner == address(0)) {
            revert AUTH_ZERO_ADDRESS;
        }
        _authStorage._pendingOwner = newOwner;
        emit AUTH_OwnershipTransferStarted(tx.accounts.dataAccount.key, newOwner);
    }

    function acceptOwnership() public virtual {
        if (tx.accounts.dataAccount.key != _authStorage._pendingOwner) {
            revert AUTH_UNAUTHORIZED;
        }
        address oldOwner = _authStorage._owner;
        _authStorage._owner = _authStorage._pendingOwner;
        _authStorage._pendingOwner = address(0);
        emit AUTH_OwnershipTransferred(oldOwner, _authStorage._owner);
    }

    function pendingOwner() public view virtual returns (address) {
        return _authStorage._pendingOwner;
    }
}
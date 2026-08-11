// SPDX-License-Identifier: MIT

import 'solana';

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library ERC1967Utils {
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function getImplementation() internal view returns (address) {
        return address(tx.accounts.dataAccount.key);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        if (data.length > 0) {
            AccountMeta[2] metas = [
                AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true}),
                AccountMeta({pubkey: newImplementation, is_signer: false, is_writable: true})
            ];
            (bool success, ) = newImplementation.call{accounts: metas}(data);
            if (!success) {
                revert("ERC1967Utils: upgrade failed");
            }
        }
    }
}

abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized, "Initializable: already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: not initializing");
        _;
    }

    function _disableInitializers() internal {
        _initialized = true;
    }
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    address private immutable __self = address(this);

    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    function _checkProxy() internal view virtual {
        if (
            address(this) == __self ||
            ERC1967Utils.getImplementation() != __self
        ) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            revert("UUPSUnauthorizedCallContext");
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        bytes32 slot = IERC1822Proxiable(newImplementation).proxiableUUID();
        if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
            revert("UUPSUnsupportedProxiableUUID");
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}
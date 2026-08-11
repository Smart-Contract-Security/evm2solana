// SPDX-License-Identifier: MIT

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC4626Upgradeable is Initializable {
    struct ERC4626Storage {
        address _asset;
        uint8 _underlyingDecimals;
    }

    bytes32 private constant ERC4626StorageLocation =
        0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00;

    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := ERC4626StorageLocation
        }
    }

    function __ERC4626_init(address asset_) internal onlyInitializing {
        __ERC4626_init_unchained(asset_);
    }

    function __ERC4626_init_unchained(address asset_) internal onlyInitializing {
        ERC4626Storage storage $ = _getERC4626Storage();
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(asset_);
        $._underlyingDecimals = success ? assetDecimals : 18;
        $._asset = asset_;
    }

    function _tryGetAssetDecimals(address asset_) private view returns (bool ok, uint8 assetDecimals) {
        (bool success, bytes memory returnData) = asset_.call{accounts: []}(abi.encodeWithSignature("decimals()"));
        if (success && returnData.length >= 32) {
            uint256 decoded = abi.decode(returnData, (uint256));
            if (decoded <= type(uint8).max) {
                return (true, uint8(decoded));
            }
        }
        return (false, 0);
    }

    function decimals() public view virtual returns (uint8) {
        ERC4626Storage storage $ = _getERC4626Storage();
        return $._underlyingDecimals + _decimalsOffset();
    }

    function asset() public view virtual returns (address) {
        ERC4626Storage storage $ = _getERC4626Storage();
        return $._asset;
    }

    function totalAssets() public view virtual returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, 0);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, 0);
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return previewRedeem(maxRedeem(owner));
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, 0);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, 1);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, 1);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, 0);
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert("ERC4626ExceededMaxDeposit");
        }

        uint256 shares = previewDeposit(assets);
        _deposit(tx.accounts.dataAccount.key, receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert("ERC4626ExceededMaxMint");
        }

        uint256 assets = previewMint(shares);
        _deposit(tx.accounts.dataAccount.key, receiver, assets, shares);

        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert("ERC4626ExceededMaxWithdraw");
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(tx.accounts.dataAccount.key, receiver, owner, assets, shares);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert("ERC4626ExceededMaxRedeem");
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(tx.accounts.dataAccount.key, receiver, owner, assets, shares);

        return assets;
    }

    function _convertToShares(uint256 assets, uint8 rounding) internal view virtual returns (uint256) {
        uint256 supply = totalSupply();
        uint256 offset = 10 ** _decimalsOffset();
        uint256 total = totalAssets();
        if (rounding == 0) {
            return assets * (supply + offset) / (total + 1);
        } else {
            return (assets * (supply + offset) + total) / (total + 1);
        }
    }

    function _convertToAssets(uint256 shares, uint8 rounding) internal view virtual returns (uint256) {
        uint256 total = totalAssets();
        uint256 supply = totalSupply();
        uint256 offset = 10 ** _decimalsOffset();
        if (rounding == 0) {
            return shares * (total + 1) / (supply + offset);
        } else {
            return (shares * (total + 1) + (supply + offset) - 1) / (supply + offset);
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        IERC20(asset()).transferFrom(caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    function totalSupply() public view virtual returns (uint256);
    function balanceOf(address account) public view virtual returns (uint256);
    function _mint(address account, uint256 amount) internal virtual;
    function _burn(address account, uint256 amount) internal virtual;
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}
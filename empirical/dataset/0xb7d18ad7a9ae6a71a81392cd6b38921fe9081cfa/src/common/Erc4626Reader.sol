// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IErc4626Reader} from "./IErc4626Reader.sol";
import {IERC4626Minimal} from "../abis/extra_polling.sol";
import {Library} from "./Library.sol";
import {Erc4626Response} from "../types/response.sol";

interface IERC20TotalSupply {
    function totalSupply() external view returns (uint256);
}

contract Erc4626Reader is IErc4626Reader {
    function erc4626PoolInfo(address vault, address handler)
        external
        view
        returns (Erc4626Response memory result)
    {
        result.blockNumber = block.number;
        result.vault = vault;

        // vault token info
        (result.vaultDecimals, result.vaultName, result.vaultSymbol) = Library.getTokenInfo(vault);

        // underlying asset address
        try IERC4626Minimal(vault).asset() returns (address underlying) {
            result.underlying = underlying;
            (result.underlyingDecimals, result.underlyingName, result.underlyingSymbol) = Library.getTokenInfo(underlying);
        } catch {
            return result;
        }

        try IERC20TotalSupply(vault).totalSupply() returns (uint256 ts) {
            result.totalSupply = ts;
        } catch {}

        try IERC4626Minimal(vault).totalAssets() returns (uint256 ta) {
            result.totalAssets = ta;
        } catch {}

        try IERC4626Minimal(vault).maxDeposit(handler) returns (uint256 md) {
            result.maxDeposit = md;
        } catch {}

        try IERC4626Minimal(vault).maxMint(handler) returns (uint256 mm) {
            result.maxMint = mm;
        } catch {}
    }
}

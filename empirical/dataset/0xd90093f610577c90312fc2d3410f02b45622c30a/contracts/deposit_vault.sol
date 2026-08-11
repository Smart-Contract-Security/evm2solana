// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DepositVault — minimal per-deposit vault contract
/// @notice Egy minimális contract ami fogadja a natív ETH-et és ERC20 transfereket.
///         A sweep() függvényt csak a factory hívhatja, ami a regisztrált token listát
///         olvasva egyetlen tx-ben kiüríti az összes balance-t a treasury címre.
contract DepositVault is ReentrancyGuard {

    using SafeERC20 for IERC20;

    DepositVaultFactory public immutable factory;

    constructor(DepositVaultFactory _factory) {
        factory = _factory;
    }

    /// @notice Natív ETH fogadás. ERC20 token automatikusan érkezik a transfer() hívásra.
    receive() external payable {}

    /// @notice Egyetlen tx-ben kiüríti az összes regisztrált ERC20 + native ETH balance-t.
    ///         A token lista runtime a factory-ból olvasódik — új token automatikusan
    ///         részt vesz a következő sweep-en a vault redeploy nélkül.
    /// @param treasury A célcím (treasury wallet)
    function sweep(address treasury) external nonReentrant {

        require(msg.sender == address(factory), "DV: only factory");
        require(treasury != address(0), "DV: zero treasury");

        address[] memory tokens = factory.getTokens();

        for (uint256 i = 0; i < tokens.length; i++) {

            IERC20 token = IERC20(tokens[i]);
            uint256 bal = token.balanceOf(address(this));

            if (bal > 0) {

                // SafeERC20 — USDT non-standard return value tolerance
                token.safeTransfer(treasury, bal);
            }
        }

        // Native ETH utoljára — a token transfer-ek gas-át a maradék fedezze
        uint256 ethBal = address(this).balance;

        if (ethBal > 0) {

            (bool ok, ) = payable(treasury).call{value: ethBal}("");

            require(ok, "DV: ETH transfer failed");
        }
    }
}


/// @title DepositVaultFactory — master factory for deterministic CREATE2 deposit vaults
/// @notice Felelős a deposit cím-deriválásért (CREATE2), a lazy deploy-ért és a
///         batch sweep tx-ek koordinálásáért. A regisztrált ERC20 token lista
///         dinamikusan bővíthető owner által.
contract DepositVaultFactory is Ownable {

    /// @notice A regisztrált ERC20 token lista — a vault.sweep() runtime ezt olvassa.
    address[] private erc20Tokens;

    /// @notice O(1) lookup duplikátum ellen
    mapping(address => bool) public isToken;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event VaultSwept(bytes32 indexed salt, address indexed vault);
    event VaultSweepFailed(bytes32 indexed salt, address indexed vault, bytes reason);

    constructor(address initialOwner, address[] memory initialTokens) Ownable(initialOwner) {

        for (uint256 i = 0; i < initialTokens.length; i++) {

            _addToken(initialTokens[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Token registry
    // -------------------------------------------------------------------------

    /// @notice Új ERC20 token hozzáadása (pl. DAI, FRAX, új stablecoin)
    function addToken(address token) external onlyOwner {
        _addToken(token);
    }

    /// @notice Token eltávolítás. A meglévő vault-okon lévő balance NEM törlődik —
    ///         a token továbbra is sweep-elhető manuálisan közvetlen IERC20.transfer()-rel,
    ///         csak a getTokens() listából tűnik el.
    function removeToken(address token) external onlyOwner {

        require(isToken[token], "DVF: not in list");

        isToken[token] = false;

        // Swap-and-pop a gas hatékonyság miatt
        uint256 len = erc20Tokens.length;

        for (uint256 i = 0; i < len; i++) {

            if (erc20Tokens[i] == token) {

                erc20Tokens[i] = erc20Tokens[len - 1];
                erc20Tokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    function _addToken(address token) internal {

        require(token != address(0), "DVF: zero address");
        require(!isToken[token], "DVF: already added");

        isToken[token] = true;
        erc20Tokens.push(token);

        emit TokenAdded(token);
    }

    /// @notice Az aktuális ERC20 lista — a vault.sweep() és backend ezt használja.
    function getTokens() external view returns (address[] memory) {
        return erc20Tokens;
    }

    function tokenCount() external view returns (uint256) {
        return erc20Tokens.length;
    }

    // -------------------------------------------------------------------------
    // CREATE2 cím-deriválás + deploy
    // -------------------------------------------------------------------------

    /// @notice A salt-hoz tartozó vault címe — deploy nélkül, determinisztikus.
    /// @dev EIP-1014 (CREATE2): keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
    function computeAddress(bytes32 salt) public view returns (address) {

        bytes memory bytecode = abi.encodePacked(
            type(DepositVault).creationCode,
            abi.encode(address(this))
        );

        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        ));

        return address(uint160(uint256(hash)));
    }

    /// @notice Read-only helper — már deployolva van-e a vault a salt-on
    function isDeployed(bytes32 salt) external view returns (bool) {
        return computeAddress(salt).code.length > 0;
    }

    /// @notice Internal lazy deploy + sweep — single salt verzió. NEM external,
    ///         a sweepBatch() hívja try/catch-csel külső dispatch-on keresztül,
    ///         és a `sweep()` (single) is reuse-olja.
    function _deployIfNeededAndSweep(bytes32 salt, address treasury) external {

        // Csak a factory önmagából hívható (external + msg.sender check), hogy a
        // sweepBatch try/catch-jén át menjen, de kívülről ne lehessen invokálni.
        require(msg.sender == address(this), "DVF: only self");

        address vaultAddr = computeAddress(salt);

        // Lazy deploy CREATE2 — csak ha még nincs kód
        if (vaultAddr.code.length == 0) {

            // bytes("") salt — az `address(this)` factory címe a deployer
            DepositVault deployed = new DepositVault{salt: salt}(this);

            require(address(deployed) == vaultAddr, "DVF: deploy mismatch");
        }

        DepositVault(payable(vaultAddr)).sweep(treasury);
    }

    // -------------------------------------------------------------------------
    // Sweep (V1 single + V2 batch)
    // -------------------------------------------------------------------------

    /// @notice Single sweep — lazy deploy ha még nem deployolt, majd vault.sweep().
    ///         V1 backend flow használja, vagy operatív (manuális) sweep-eknél.
    function sweep(bytes32 salt, address treasury) external onlyOwner {

        // Self-call a _deployIfNeededAndSweep-re — egységes flow a batch-csel.
        // Single tx-ben revert esetén a teljes tx revertel (a try/catch nem aktivál).
        this._deployIfNeededAndSweep(salt, treasury);

        emit VaultSwept(salt, computeAddress(salt));
    }

    /// @notice Batch sweep — try/catch egyenként, hogy egy hiba ne dönlse meg a batch-et.
    ///         A backend off-line szűri a salt listát (multicall + threshold check),
    ///         itt már csak sweep-elendő vault-ok jönnek.
    function sweepBatch(bytes32[] calldata salts, address treasury) external onlyOwner {

        for (uint256 i = 0; i < salts.length; i++) {

            bytes32 salt = salts[i];
            address vault = computeAddress(salt);

            try this._deployIfNeededAndSweep(salt, treasury) {

                emit VaultSwept(salt, vault);

            } catch (bytes memory reason) {

                emit VaultSweepFailed(salt, vault, reason);
            }
        }
    }
}

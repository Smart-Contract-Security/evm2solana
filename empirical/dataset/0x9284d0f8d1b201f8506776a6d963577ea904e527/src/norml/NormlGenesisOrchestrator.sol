// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NormlForUsDeployer} from "./NormlForUsDeployer.sol";
import {NormlForMeDeployer} from "./NormlForMeDeployer.sol";
import {NormlForUs} from "./NormlForUs.sol";
import {NormlForMe} from "./NormlForMe.sol";
import {NormlRouter} from "./NormlRouter.sol";
import {ILiquid} from "../interfaces/ILiquid.sol";
import {ILiquidFactory} from "../interfaces/ILiquidFactory.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISuperRareRouter} from "../interfaces/ISuperRareRouter.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";

/// @notice V4 path-hop key (mirrors v4-periphery PathKey).
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}

/// @notice V4Router ExactInputParams (mirrors v4-periphery IV4Router.ExactInputParams).
struct ExactInputParamsPath {
    Currency currencyIn;
    PathKey[] path;
    uint128 amountIn;
    uint128 amountOutMinimum;
}

/// @title NormlGenesisOrchestrator
/// @notice Single-transaction atomic deployer for the NORML ecosystem genesis,
///         callable by a hot wallet but with the `creator` (Ledger) hardcoded
///         at construction so no compromise of the hot wallet can redirect
///         the artist identity.
///
/// @dev    Trust model (assumes SuperRare LiquidFactory's creator-delegated
///         operator mapping is in place):
///           1. Ledger EOA (the artist) does TWO manual setup txs:
///                a. factory.delegateTokenCreation(orchestrator)
///                b. rare.approve(orchestrator, seedRareAmount)
///           2. Hot wallet (authorizedCaller) calls `execute()` exactly once.
///           3. Atomically inside `execute()`:
///                - pull RARE from Ledger (Ledger pre-approved orchestrator)
///                - factory.createLiquidTokenMultiCurveWithSupply(_creator=Ledger, ...)
///                  → factory honors operator mapping; _creator becomes
///                    permanent tokenCreator + owner of the Liquid token
///                - deploy NormlForUs (via external builder to keep this
///                  contract under EIP-170 24KB), NormlForMe, NormlProfile,
///                  NormlBiddersEdition, NormlRouter
///                - one-shot setRouter on each ownable child
///                - approve RARE on SuperRare Router; swap RARE → NORML
///                  with deadline = block.timestamp + 600 (always valid;
///                  fixes original multi-tx DeadlineExpired bug)
///                - approve NORML on NormlForUs; mint 8 NFTs to Ledger
///                - forward residual NORML to Ledger
///                - transferOwnership of forUs/forMe/bidders to Ledger
///
/// @dev    Security invariants enforced by this contract:
///           - `creator` is immutable: hot-wallet compromise CANNOT change the
///             artist identity; NFTs, residual, and ownerships always go to
///             the original Ledger address.
///           - `authorizedCaller` is immutable: only the hot wallet can fire
///             `execute()`; even if Ledger's RARE allowance to this contract
///             leaks via Etherscan, a random attacker cannot drain it.
///           - `executed` one-shot flag: `execute()` is replay-proof; once
///             tripped, the contract is inert. A fresh orchestrator (with a
///             new Ledger pre-approval) is required for any retry.
///
/// @dev    What is NOT in the atomic tx (intentionally):
///           - `setRenderContract` on the Liquid token: only callable by
///             tokenCreator(=Ledger); operator mapping is on the factory,
///             not the token. Cosmetic; no economic effect on the pool.
///             Ledger calls this in a separate follow-up tx (no front-run risk).
///           - `NormlForUs.stake(8, ...)` to seed bidder pool 8 from any
///             residual: requires Ledger as msg.sender so the stake credits
///             Ledger's position. Pool is already economically initialised
///             by the 8 NFT mints; this is post-genesis liquidity.
///           - SSTORE2 asset upload: 12+MB, blows block gas limit. Run
///             upload-assets-sepolia.sh after genesis.
contract NormlGenesisOrchestrator {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       IMMUTABLE STATE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    /// @notice Only this address can invoke `execute()`. Typically a hot
    ///         wallet operated by the artist or their deployment ops.
    address public immutable authorizedCaller;

    /// @notice The artist's Ledger EOA. Hardcoded at construction so that
    ///         hot-wallet compromise cannot redirect the genesis to a
    ///         different identity. All recipient roles (NFT owner, residual
    ///         NORML, contract ownerships, Liquid `tokenCreator`) bind to
    ///         this address.
    address public immutable creator;

    /// @notice Set true on first successful `execute()` to prevent replay.
    bool public executed;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          TYPES                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    struct GenesisConfig {
        // --- External addresses ---
        ILiquidFactory factory;
        IERC20 rare;
        ISuperRareRouter srRouter;
        NormlForUsDeployer forUsDeployer;
        NormlForMeDeployer forMeDeployer;
        address normlAssets;

        // --- Liquid token creation ---
        string tokenUri;
        string tokenName;
        string tokenSymbol;
        uint256 initialRareLiquidity; // typically 0; sweep happens after
        uint256 customMaxTotalSupply;
        ILiquidFactory.Curve[] curves;

        // --- NormlForUs constructor strings ---
        string forUsName;
        string forUsSymbol;
        string forUsDescription;
        string forUsExternalUrl;

        // --- NormlForMe constructor strings ---
        string forMeName;
        string forMeSymbol;
        string forMeDescription;
        string forMeExternalUrl;

        // --- Genesis sweep ---
        uint256 seedRareAmount; // RARE pulled from `creator`
        uint256 minNormlOut;    // floor on NORML received
        uint256 stakePerNft;    // 1_000_000e18 per NFT
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    event Deployed(
        address indexed creator,
        address normlToken,
        address normlForUs,
        address normlForMe,
        address normlRouter,
        uint256 normlReceived
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ERRORS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    error NotAuthorized();
    error AlreadyExecuted();
    error ZeroAddress();
    error RarePullFailed();
    error RareApproveFailed();
    error NormlBalanceTooLow(uint256 actual, uint256 needed);
    error NormlApproveFailed();
    error NormlTransferFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CONSTRUCTOR                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    constructor(address _authorizedCaller, address _creator) {
        if (_authorizedCaller == address(0) || _creator == address(0)) revert ZeroAddress();
        authorizedCaller = _authorizedCaller;
        creator = _creator;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MAIN ENTRYPOINT                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    /// @notice Atomically deploy and seed the entire NORML ecosystem.
    /// @dev    Prerequisites:
    ///           - msg.sender == authorizedCaller (hot wallet)
    ///           - factory.setOperator(this, true) by `creator` (Ledger)
    ///           - rare.approve(this, seedRareAmount) by `creator` (Ledger)
    function execute(GenesisConfig calldata c) external returns (
        address normlToken,
        address normlForUs,
        address normlForMe,
        address normlRouter
    ) {
        if (msg.sender != authorizedCaller) revert NotAuthorized();
        if (executed) revert AlreadyExecuted();
        executed = true;

        address _creator = creator; // gas + clarity

        // -- 1. Pull RARE from Ledger via pre-approved allowance. --
        if (!c.rare.transferFrom(_creator, address(this), c.seedRareAmount)) {
            revert RarePullFailed();
        }

        // -- 2. Create the Liquid token. Factory's creator-delegated operator
        //       mapping must authorize this orchestrator for `_creator` —
        //       Ledger sets that up in the manual pre-step. The factory
        //       writes `_creator` permanently into the new token's
        //       tokenCreator + owner slots (LiquidMultiCurve has no
        //       transferOwnership), so artist attribution is locked. --
        normlToken = c.factory.createLiquidTokenMultiCurveWithSupply(
            _creator,
            c.tokenUri,
            c.tokenName,
            c.tokenSymbol,
            c.initialRareLiquidity,
            c.curves,
            c.customMaxTotalSupply
        );

        // -- 3. Deploy NormlForUs via external builder so its ~22KB initcode
        //       isn't embedded here. Ownership returns to this orchestrator. --
        normlForUs = c.forUsDeployer.deploy(
            normlToken,
            c.normlAssets,
            c.forUsName,
            c.forUsSymbol,
            c.forUsDescription,
            c.forUsExternalUrl
        );

        // -- 4. Deploy remaining children (all owned by this orchestrator).
        //       NormlProfile + NormlBiddersEdition are intentionally NOT deployed
        //       here: they have no role in the atomic seed/swap/mint flow and
        //       no router entrypoint. Ledger deploys them post-genesis. --
        normlForMe = c.forMeDeployer.deploy(
            normlToken,
            c.forMeName,
            c.forMeSymbol,
            c.forMeDescription,
            c.forMeExternalUrl
        );
        normlRouter = address(new NormlRouter(
            normlToken,
            normlForUs,
            normlForMe
        ));

        // -- 5. Wire one-shot `setRouter` and `setNormlAssets` on each ownable child.
        //       setNormlAssets must be called while the orchestrator is still the
        //       owner (ownership is transferred in step 9); without it ForMe's
        //       tokenURI returns metadata with no image or animation_url. --
        NormlForUs(normlForUs).setRouter(normlRouter);
        NormlForMe(payable(normlForMe)).setRouter(normlRouter);
        NormlForMe(payable(normlForMe)).setNormlAssets(c.normlAssets);

        // -- 6. Genesis sweep: RARE -> NORML via SuperRare LQE Router.
        //       deadline = block.timestamp + 600 is always valid because we
        //       are inside the block being mined right now. --
        if (!c.rare.approve(address(c.srRouter), c.seedRareAmount)) {
            revert RareApproveFailed();
        }
        uint256 normlReceived;
        {
            (bytes memory commands, bytes[] memory inputs) = _buildV4SwapPayload(
                normlToken,
                address(c.rare),
                c.seedRareAmount,
                c.minNormlOut
            );
            normlReceived = c.srRouter.swap(
                address(c.rare),
                c.seedRareAmount,
                normlToken,
                address(this),
                c.minNormlOut,
                commands,
                inputs,
                block.timestamp + 600
            );
        }

        uint256 normlBalance = IERC20(normlToken).balanceOf(address(this));
        if (normlBalance < c.minNormlOut) {
            revert NormlBalanceTooLow(normlBalance, c.minNormlOut);
        }

        // -- 7. Mint 8 NFTs with 1M NORML initial stake each, sent to Ledger.
        //       mintWithInitialStake pulls stake from msg.sender via
        //       transferFrom, so we approve forUs first. --
        uint256 stakeTotal = c.stakePerNft * 8;
        if (!IERC20(normlToken).approve(normlForUs, stakeTotal)) {
            revert NormlApproveFailed();
        }
        for (uint256 i; i < 8; ++i) {
            NormlForUs(normlForUs).mintWithInitialStake(_creator, c.stakePerNft);
        }

        // -- 8. Forward any remaining NORML to Ledger so it can be staked
        //       into bidder pool 8 in a follow-up tx (must be Ledger as
        //       msg.sender so the stake credits Ledger). --
        uint256 remaining = IERC20(normlToken).balanceOf(address(this));
        if (remaining > 0) {
            if (!IERC20(normlToken).transfer(_creator, remaining)) {
                revert NormlTransferFailed();
            }
        }

        // -- 9. Hand over ownership of every owned contract to the Ledger. --
        NormlForUs(normlForUs).transferOwnership(_creator);
        NormlForMe(payable(normlForMe)).transferOwnership(_creator);

        emit Deployed(
            _creator,
            normlToken,
            normlForUs,
            normlForMe,
            normlRouter,
            normlReceived
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  UNIVERSAL ROUTER V4 PAYLOAD               */
    /*.•°:°.´+˚.*°.˚:*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    function _buildV4SwapPayload(
        address liquidToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        PoolKey memory key;
        {
            (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
                ILiquid(liquidToken).poolKey();
            key = PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: hooks
            });
        }

        address currencyOutAddr = Currency.unwrap(key.currency0) == tokenIn
            ? Currency.unwrap(key.currency1)
            : Currency.unwrap(key.currency0);

        bytes memory swapParams = _encodeExactInput(tokenIn, currencyOutAddr, key, amountIn, minAmountOut);
        bytes memory settleParams = abi.encode(Currency.wrap(tokenIn), uint256(amountIn));
        bytes memory takeParams   = abi.encode(Currency.wrap(currencyOutAddr), uint256(minAmountOut));

        bytes memory actions = hex"070c0f"; // SWAP_EXACT_IN | SETTLE_ALL | TAKE_ALL
        bytes[] memory params = new bytes[](3);
        params[0] = swapParams;
        params[1] = settleParams;
        params[2] = takeParams;

        commands = hex"10"; // V4_SWAP
        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
    }

    function _encodeExactInput(
        address tokenIn,
        address currencyOutAddr,
        PoolKey memory key,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal pure returns (bytes memory) {
        ExactInputParamsPath memory ep = ExactInputParamsPath({
            currencyIn: Currency.wrap(tokenIn),
            path: new PathKey[](1),
            amountIn: uint128(amountIn),
            amountOutMinimum: uint128(minAmountOut)
        });
        ep.path[0] = PathKey({
            intermediateCurrency: Currency.wrap(currencyOutAddr),
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks,
            hookData: bytes("")
        });
        return abi.encode(ep);
    }
}

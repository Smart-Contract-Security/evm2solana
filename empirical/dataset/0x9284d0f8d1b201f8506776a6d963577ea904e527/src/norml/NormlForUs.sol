// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "../utils/Base64.sol";
import {ILiquid} from "../interfaces/ILiquid.sol";
import {ILiquidBase} from "../interfaces/ILiquidBase.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SimpleERC721} from "../token/SimpleERC721.sol";

/// @notice Read-only view surface NormlForUs consumes on NormlAssets.
/// @dev NormlAssets is the single source of truth for the 9 artwork bundles, the
///      shared HTML chunks, the per-slot image overrides, the artwork names /
///      descriptions, and the per-slot canvas pixel budgets. NormlForUs holds
///      no chunked asset storage of its own.
interface INormlAssets {
    function animationURILiquid(address holder) external view returns (string memory);
    function animationURIForUs(uint256 tokenId) external view returns (string memory);
    function animationURIForMe(uint256 tokenId) external view returns (string memory);
    function imageDataUri(uint256 slot) external view returns (string memory);
    function artworkName(uint256 tokenId) external view returns (string memory);
    function artworkDescription(uint256 tokenId) external view returns (string memory);
    function maxPixels(uint256 tokenId) external view returns (uint256);
}

/// @title NormlForUs
/// @notice ERC721 lens collection for NORML Liquid Edition with staking and on-chain HTML rendering
/// @dev Implements Liquid render contract interface, per-token staking, and
///      initial stake vesting mechanics. All chunked on-chain art lives in the
///      `NORML_ASSETS` companion contract and is read through view delegators.
/// @author jiwa
contract NormlForUs is SimpleERC721 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant MAX_SUPPLY = 8;         // ERC-721 1/1s: token IDs 0–7
    uint256 public constant BIDDERS_EDITION_ID = 8;  // ERC-1155 open edition: token ID 8 "lost in draft"
    uint256 public constant VESTING_DURATION = 730 days; // 24 months
    uint256 public constant PERMANENT_LOCK = 1000e18; // 1000 tokens permanently locked

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address public immutable LIQUID_EDITION;
    /// @notice Canonical artwork-bundle + shared-HTML store. Every asset/image/name/
    ///         description read goes through this contract — NormlForUs holds none
    ///         of that data locally. Set once at construction; immutable.
    INormlAssets public immutable NORML_ASSETS;
    string public collectionDescription;
    string public externalUrl;
    uint256 public totalMinted;
    address public initialMinter;

    /// @notice Optional trusted router (reserved for future seamless UX).
    address public router;

    // Staking state
    mapping(uint256 tokenId => mapping(address staker => uint256 amount)) public stakedAmounts;
    mapping(uint256 tokenId => uint256 totalStaked) public tokensStakedToToken;
    mapping(uint256 tokenId => address[]) internal _stakers;
    mapping(uint256 tokenId => mapping(address staker => bool isStaker)) internal _isStaker;

    // Initial stake vesting state
    struct InitialStake {
        uint256 amount;
        uint256 vestingStart;
        bool transferredToFirstOwner;
    }
    mapping(uint256 tokenId => InitialStake) public initialStakes;
    /// @notice Lifetime total of vested tokens already withdrawn per token.
    ///         Used by getVestedAmount to prevent re-claiming the same vested
    ///         tokens after each withdrawVested reduces stake_.amount.
    mapping(uint256 tokenId => uint256) public withdrawnVested;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ERC-4906 metadata update event
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    
    event TokensStaked(uint256 indexed tokenId, address indexed staker, uint256 amount);
    event TokensUnstaked(uint256 indexed tokenId, address indexed staker, uint256 amount);
    event InitialTokensTransferred(uint256 indexed tokenId, address indexed firstOwner, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidLiquidEdition();
    error InvalidNormlAssets();
    error MaxSupplyReached();
    error InvalidTokenId();
    error InsufficientStake();
    error TransferFailed();
    error ZeroAmount();
    error VestingNotComplete();
    error AlreadyTransferred();
    error InvalidStakeIndex();
    error NotRouter();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(
        address liquidEdition,
        address normlAssets_,
        string memory name_,
        string memory symbol_,
        string memory description_,
        string memory externalUrl_
    ) SimpleERC721(name_, symbol_) {
        if (liquidEdition == address(0)) revert InvalidLiquidEdition();
        if (normlAssets_ == address(0)) revert InvalidNormlAssets();

        LIQUID_EDITION = liquidEdition;
        NORML_ASSETS = INormlAssets(normlAssets_);
        collectionDescription = description_;
        externalUrl = externalUrl_;
        initialMinter = msg.sender;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set or replace the trusted router. Owner-only.
    function setRouter(address newRouter) external onlyOwner {
        router = newRouter;
    }

    /// @notice Update the collection-wide description shown on all token metadata.
    /// @dev    Appears on the 1/1 tokens (prepended to the per-artwork description)
    ///        and on the Liquid edition passthrough metadata. Owner-only.
    function setCollectionDescription(string calldata description_) external onlyOwner {
        collectionDescription = description_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               BIDDER'S EDITION METADATA (PROXY VIEWS)      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Build the full metadata JSON data URI for slot 8 (bidder's edition).
    /// @dev Designed to be called by the standalone `NormlBiddersEdition` ERC-1155
    ///      contract so that the 1155's `uri(0)` returns this exact string. All state
    ///      driving the metadata (image override, description, asset chunks, live
    ///      staked-NORML count) lives here in NormlForUs.
    function metadataFor(uint256 tokenId) external view returns (string memory) {
        if (tokenId > BIDDERS_EDITION_ID) revert InvalidTokenId();
        return _buildMetadata(tokenId, address(0), false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MINTING                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mint a new token with initial stake
    /// @param to Recipient address
    /// @param initialStakeAmount Amount of NORML tokens to stake initially
    function mintWithInitialStake(
        address to,
        uint256 initialStakeAmount
    ) external onlyOwner returns (uint256 tokenId) {
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();
        
        tokenId = totalMinted;
        totalMinted = tokenId + 1;
        
        _safeMint(to, tokenId);
        
        // Setup initial stake with vesting
        if (initialStakeAmount > 0) {
            // Transfer tokens from sender to this contract for staking
            bool success = IERC20(LIQUID_EDITION).transferFrom(msg.sender, address(this), initialStakeAmount);
            if (!success) revert TransferFailed();
            
            initialStakes[tokenId] = InitialStake({
                amount: initialStakeAmount,
                vestingStart: block.timestamp,
                transferredToFirstOwner: false
            });
            
            tokensStakedToToken[tokenId] = initialStakeAmount;
        }
    }

    /// @notice Simple mint without initial stake (for testing)
    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();
        
        tokenId = totalMinted;
        totalMinted = tokenId + 1;
        
        _safeMint(to, tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STAKING                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Stake NORML tokens to a specific NFT
    /// @param tokenId The NFT to stake to
    /// @param amount Amount of NORML tokens to stake
    function stake(uint256 tokenId, uint256 amount) external {
        _stakeInternal(msg.sender, tokenId, amount);
    }

    /// @notice Unstake NORML tokens from a specific NFT
    /// @param tokenId The NFT to unstake from
    /// @param amount Amount of NORML tokens to unstake
    function unstake(uint256 tokenId, uint256 amount) external {
        _unstakeInternal(msg.sender, tokenId, amount);
    }

    /// @notice Router-only: stake on behalf of `user`. Router must already have
    ///         pulled `amount` NORML from `user` and approved this contract.
    /// @dev    Pure pass-through to the same accounting as `stake`. msg.sender
    ///         (the router) must be the configured trusted router.
    function stakeFor(address user, uint256 tokenId, uint256 amount) external {
        if (msg.sender != router) revert NotRouter();
        _stakeInternal(user, tokenId, amount);
    }

    /// @notice Router-only: unstake on behalf of `user`. Sends the unlocked
    ///         tokens directly back to `user`.
    function unstakeFor(address user, uint256 tokenId, uint256 amount) external {
        if (msg.sender != router) revert NotRouter();
        _unstakeInternal(user, tokenId, amount);
    }

    function _stakeInternal(address staker, uint256 tokenId, uint256 amount) internal {
        if (tokenId > BIDDERS_EDITION_ID) revert InvalidTokenId();
        if (tokenId != BIDDERS_EDITION_ID && tokenId >= totalMinted) revert InvalidTokenId();
        if (amount == 0) revert ZeroAmount();

        bool success = IERC20(LIQUID_EDITION).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        if (!_isStaker[tokenId][staker]) {
            _stakers[tokenId].push(staker);
            _isStaker[tokenId][staker] = true;
        }

        stakedAmounts[tokenId][staker] += amount;
        tokensStakedToToken[tokenId] += amount;

        emit TokensStaked(tokenId, staker, amount);
        emit MetadataUpdate(tokenId);
    }

    function _unstakeInternal(address staker, uint256 tokenId, uint256 amount) internal {
        if (tokenId > BIDDERS_EDITION_ID) revert InvalidTokenId();
        if (tokenId != BIDDERS_EDITION_ID && tokenId >= totalMinted) revert InvalidTokenId();
        if (amount == 0) revert ZeroAmount();
        if (stakedAmounts[tokenId][staker] < amount) revert InsufficientStake();

        stakedAmounts[tokenId][staker] -= amount;
        tokensStakedToToken[tokenId] -= amount;

        bool success = IERC20(LIQUID_EDITION).transfer(staker, amount);
        if (!success) revert TransferFailed();

        emit TokensUnstaked(tokenId, staker, amount);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Get the number of vested tokens available to withdraw for initial stake
    /// @param tokenId The NFT token ID
    /// @return vestedAmount Amount of tokens that have vested
    /// @return withdrawableAmount Amount of tokens that can be withdrawn (excludes permanent lock)
    function getVestedAmount(uint256 tokenId) public view returns (uint256 vestedAmount, uint256 withdrawableAmount) {
        InitialStake memory stake_ = initialStakes[tokenId];
        uint256 claimed = withdrawnVested[tokenId];
        if (stake_.amount == 0 && claimed == 0) return (0, 0);

        // Reconstruct the original staked amount so each unit vests only once.
        uint256 originalAmount = stake_.amount + claimed;
        uint256 elapsed = block.timestamp - stake_.vestingStart;
        if (elapsed >= VESTING_DURATION) {
            vestedAmount = originalAmount;
        } else {
            vestedAmount = (originalAmount * elapsed) / VESTING_DURATION;
        }

        // withdrawable = (total vested - permanent lock) - already claimed
        if (vestedAmount > PERMANENT_LOCK + claimed) {
            withdrawableAmount = vestedAmount - PERMANENT_LOCK - claimed;
        }
    }

    /// @notice Withdraw vested tokens from initial stake (only first owner)
    /// @param tokenId The NFT token ID
    /// @param amount Amount to withdraw
    function withdrawVested(uint256 tokenId, uint256 amount) external {
        if (ownerOf(tokenId) != msg.sender) revert OwnableUnauthorizedAccount(msg.sender);
        
        (, uint256 withdrawable) = getVestedAmount(tokenId);
        if (amount > withdrawable) revert VestingNotComplete();

        withdrawnVested[tokenId] += amount;
        initialStakes[tokenId].amount -= amount;
        tokensStakedToToken[tokenId] -= amount;
        
        // Transfer to owner
        bool success = IERC20(LIQUID_EDITION).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
        
        emit TokensUnstaked(tokenId, msg.sender, amount);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Get all stakers for a token
    function getStakers(uint256 tokenId) external view returns (address[] memory) {
        return _stakers[tokenId];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      TOKEN URI                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Liquid Edition passthrough - returns metadata for the ERC20 token
    function tokenURI() external view returns (string memory) {
        return _buildMetadata(0, address(0), true);
    }

    /// @notice ERC721 metadata for individual tokens
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _buildMetadata(tokenId, ownerOf(tokenId), false);
    }

    /// @notice Get tokenURI with explicit holder address for balance injection
    /// @param tokenId The token ID
    /// @param holder Address to check NORML balance for
    function tokenURIForHolder(uint256 tokenId, address holder) external view returns (string memory) {
        _requireOwned(tokenId);
        return _buildMetadata(tokenId, holder, false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ANIMATION URI (direct HTML data URIs)    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Liquid edition animation HTML — `data:text/html;base64,...` pasteable directly in a browser.
    /// @dev Delegates to NormlAssets which picks an available artwork (rotates past
    ///      max-staked tokens), seeds a deterministic position, and stitches the
    ///      pre-encoded chunks together.
    function animationURI(address holder) external view returns (string memory) {
        return NORML_ASSETS.animationURILiquid(holder);
    }

    /// @notice 1/1 animation HTML — `data:text/html;base64,...` for a specific token.
    /// @dev Pixel count is driven entirely by `tokensStakedToToken[tokenId]` (read by
    ///      NormlAssets via `INormlForUsReader`); no holder needed.
    /// @param tokenId The 1/1 token ID (0–7) or the bidder's edition (8). Reverts on invalid id.
    function animationURI(uint256 tokenId) external view returns (string memory) {
        if (tokenId > BIDDERS_EDITION_ID) revert InvalidTokenId();
        if (tokenId != BIDDERS_EDITION_ID) _requireOwned(tokenId);
        return NORML_ASSETS.animationURIForUs(tokenId);
    }

    /// @notice NormlForMe NFT animation HTML — fully delegated to NormlAssets, which
    ///         reads the NFT's locked amount + determinism hash from the NormlForMe
    ///         pointer wired on NormlAssets.
    /// @param tokenId The NormlForMe NFT token id.
    function animationURIForMe(uint256 tokenId) external view returns (string memory) {
        return NORML_ASSETS.animationURIForMe(tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL - METADATA                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Snapshot {
        string tokenName;
        string tokenSymbol;
        uint256 rarePerToken;
        uint256 tokenPerRare;
        uint160 sqrtPriceX96;
        int24 currentTick;
        uint128 liquidity;
        uint256 currentSupply;
        uint256 maxTotalSupply;
        address creator;
    }

    function _snapshot() internal view returns (Snapshot memory s) {
        ILiquid liquid = ILiquid(LIQUID_EDITION);
        
        s.tokenName = liquid.name();
        s.tokenSymbol = liquid.symbol();
        s.creator = liquid.tokenCreator();
        s.maxTotalSupply = liquid.maxTotalSupply();
        (
            s.rarePerToken,
            s.tokenPerRare,
            s.sqrtPriceX96,
            s.currentTick,
            s.liquidity,
            s.currentSupply
        ) = liquid.getMarketState();
    }

    function _buildMetadata(
        uint256 tokenId,
        address holder,
        bool isLiquidPassthrough
    ) internal view returns (string memory) {
        Snapshot memory s = _snapshot();
        
        string memory metadataName;
        string memory description;
        
        if (isLiquidPassthrough) {
            metadataName = string.concat(s.tokenSymbol, " Liquid Edition");
            description = bytes(collectionDescription).length > 0
                ? collectionDescription
                : "NORML by jiwa. A consensus driven body of work; let the network decide what's normal.";
        } else {
            metadataName = string.concat(NORML_ASSETS.artworkName(tokenId), " (#", _toString(tokenId), ")");
            string memory artworkDesc = NORML_ASSETS.artworkDescription(tokenId);
            string memory artworkPart = bytes(artworkDesc).length > 0
                ? artworkDesc
                : "On-chain generative artwork by jiwa. Part of the NORML Liquid Edition collection.";
            // Prepend the collection-wide description (if set) so 1/1s carry both the
            // collection framing and the per-artwork prose. Separator is two newlines
            // which most marketplace renderers (incl. SuperRare) treat as a paragraph break.
            string memory base = bytes(collectionDescription).length > 0
                ? string.concat(collectionDescription, "\n\n", artworkPart)
                : artworkPart;
            // Always append the live staked-NORML count for 1/1s + bidder's edition.
            // Use a paragraph break so the stake line renders as its own block
            // on marketplaces (relies on _escapeJson translating 0x0A → \n).
            description = string.concat(
                base,
                "\n\nTokens staked: ", _toString(tokensStakedToToken[tokenId] / 1e18), " NORML"
            );
        }

        // Image override: slot 0 = liquid edition, slot tokenId+1 = 1/1s & bidder edition.
        // NormlAssets returns an empty string when the slot has no chunks; we fall back
        // to the inline preview SVG in that case.
        uint256 imageSlot = isLiquidPassthrough ? 0 : tokenId + 1;
        string memory storedImage = NORML_ASSETS.imageDataUri(imageSlot);
        string memory imageDataUri = bytes(storedImage).length > 0
            ? storedImage
            : _buildPreviewSvg(tokenId, s, isLiquidPassthrough);

        string memory animationUrl = isLiquidPassthrough
            ? NORML_ASSETS.animationURILiquid(holder)
            : NORML_ASSETS.animationURIForUs(tokenId);
        
        // Serve JSON as `data:application/json;utf8,...` rather than base64-wrapping.
        // The outer base64 encode would re-encode the ~280KB+ animation_url blob,
        // pushing memory expansion costs quadratic and OOG'ing tokenURI().
        // The `;utf8` form is widely supported by OpenSea/SuperRare/marketplaces.
        return string.concat(
            'data:application/json;utf8,',
            '{"name":"', _escapeJson(metadataName),
            '","description":"', _escapeJson(description),
            '","external_url":"', externalUrl,
            '","image":"', imageDataUri,
            '","animation_url":"', animationUrl,
            '","attributes":', _buildAttributes(tokenId, s, isLiquidPassthrough),
            '}'
        );
    }

    function _buildAttributes(
        uint256 tokenId,
        Snapshot memory s,
        bool isLiquidPassthrough
    ) internal view returns (string memory) {
        if (isLiquidPassthrough) {
            return string.concat(
                '[{"trait_type":"Artist","value":"jiwa"},',
                '{"trait_type":"Type","value":"Liquid Edition"},',
                '{"trait_type":"Price (RARE)","value":"', _formatFixed(s.rarePerToken, 6), '"},',
                '{"trait_type":"Supply","value":"', _formatFixed(s.currentSupply, 0), '"}]'
            );
        }
        
        return string.concat(
            '[{"trait_type":"Artist","value":"jiwa"},',
            '{"trait_type":"Artwork","value":"', _escapeJson(NORML_ASSETS.artworkName(tokenId)), '"},',
            '{"trait_type":"Total Pixels","value":"', _toString(NORML_ASSETS.maxPixels(tokenId)), '"},',
            '{"trait_type":"Tokens Staked","value":"', _toString(tokensStakedToToken[tokenId] / 1e18), '"},',
            '{"trait_type":"Collection","value":"Norml For Us"}]'
        );
    }

    function _buildPreviewSvg(
        uint256 tokenId,
        Snapshot memory s,
        bool isLiquidPassthrough
    ) internal view returns (string memory) {
        string memory titleText = isLiquidPassthrough
            ? string.concat(s.tokenSymbol, " Liquid")
            : NORML_ASSETS.artworkName(tokenId);
        
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800">',
            '<rect width="800" height="800" fill="#0a0a0a"/>',
            '<text x="400" y="380" text-anchor="middle" font-family="monospace" font-size="24" fill="#fff">',
            _escapeSvg(titleText),
            '</text>',
            '<text x="400" y="420" text-anchor="middle" font-family="monospace" font-size="14" fill="#888">',
            'NORML by jiwa',
            '</text>',
            '<text x="400" y="460" text-anchor="middle" font-family="monospace" font-size="12" fill="#666">',
            isLiquidPassthrough ? "Liquid Edition" : string.concat("Staked: ", _toString(tokensStakedToToken[tokenId] / 1e18), " NORML"),
            '</text>',
            '</svg>'
        );
        
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL - TRANSFER                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override transfer to handle first-owner initial stake transfer
    function _transfer(address from, address to, uint256 tokenId) internal override {
        // Standard ERC721 transfer logic
        address tokenOwner = _ownerOf[tokenId];
        if (tokenOwner != from) revert ERC721IncorrectOwner(from, tokenId, tokenOwner);
        if (to == address(0)) revert ERC721InvalidReceiver(address(0));
        
        _balanceOf[from]--;
        _balanceOf[to]++;
        _ownerOf[tokenId] = to;
        
        delete _tokenApprovals[tokenId];
        
        emit Transfer(from, to, tokenId);
        
        // Handle first owner transfer of initial stake
        InitialStake storage stake_ = initialStakes[tokenId];
        if (!stake_.transferredToFirstOwner && stake_.amount > 0 && from == initialMinter) {
            stake_.transferredToFirstOwner = true;
            emit InitialTokensTransferred(tokenId, to, stake_.amount);
        }
        
        // Emit metadata update for Liquid refresh
        emit MetadataUpdate(tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    STRING UTILITIES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    function _formatFixed(uint256 value, uint256 decimalsToShow) internal pure returns (string memory) {
        if (decimalsToShow == 0) {
            return _toString(value / 1e18);
        }
        
        uint256 whole = value / 1e18;
        uint256 fraction = (value % 1e18) / (10 ** (18 - decimalsToShow));
        
        string memory fractionStr = _toString(fraction);
        
        // Pad with leading zeros if needed
        bytes memory padded = new bytes(decimalsToShow);
        bytes memory fractionBytes = bytes(fractionStr);
        uint256 padLength = decimalsToShow - fractionBytes.length;
        
        for (uint256 i = 0; i < padLength; i++) {
            padded[i] = '0';
        }
        for (uint256 i = 0; i < fractionBytes.length; i++) {
            padded[padLength + i] = fractionBytes[i];
        }
        
        return string.concat(_toString(whole), ".", string(padded));
    }

    function _escapeJson(string memory input) internal pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        uint256 extraChars;

        // Per RFC 8259 §7, JSON strings cannot contain raw control chars
        // (U+0000..U+001F). Escape " and \\ as \\" / \\\\, and translate
        // 0x0A/0x0D/0x09 (LF/CR/TAB) into their two-byte \\n / \\r / \\t
        // forms so multi-line descriptions render correctly across
        // strict marketplace indexers.
        for (uint256 i = 0; i < inputBytes.length; i++) {
            bytes1 b = inputBytes[i];
            if (b == '"' || b == '\\' || b == 0x0A || b == 0x0D || b == 0x09) {
                extraChars++;
            }
        }

        if (extraChars == 0) return input;

        bytes memory output = new bytes(inputBytes.length + extraChars);
        uint256 j;

        for (uint256 i = 0; i < inputBytes.length; i++) {
            bytes1 b = inputBytes[i];
            if (b == '"' || b == '\\') {
                output[j++] = '\\';
                output[j++] = b;
            } else if (b == 0x0A) {
                output[j++] = '\\';
                output[j++] = 'n';
            } else if (b == 0x0D) {
                output[j++] = '\\';
                output[j++] = 'r';
            } else if (b == 0x09) {
                output[j++] = '\\';
                output[j++] = 't';
            } else {
                output[j++] = b;
            }
        }

        return string(output);
    }

    function _escapeSvg(string memory input) internal pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        bytes memory output = new bytes(inputBytes.length * 6); // Max expansion
        uint256 j;
        
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == '<') {
                output[j++] = '&';
                output[j++] = 'l';
                output[j++] = 't';
                output[j++] = ';';
            } else if (inputBytes[i] == '>') {
                output[j++] = '&';
                output[j++] = 'g';
                output[j++] = 't';
                output[j++] = ';';
            } else if (inputBytes[i] == '&') {
                output[j++] = '&';
                output[j++] = 'a';
                output[j++] = 'm';
                output[j++] = 'p';
                output[j++] = ';';
            } else {
                output[j++] = inputBytes[i];
            }
        }
        
        bytes memory result = new bytes(j);
        for (uint256 i = 0; i < j; i++) {
            result[i] = output[i];
        }
        
        return string(result);
    }

    /// @notice ERC-4906 metadata-update support
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // IERC165
            interfaceId == 0x80ac58cd || // IERC721
            interfaceId == 0x5b5e139f || // IERC721Metadata
            interfaceId == 0x49064906;   // ERC-4906
    }
}

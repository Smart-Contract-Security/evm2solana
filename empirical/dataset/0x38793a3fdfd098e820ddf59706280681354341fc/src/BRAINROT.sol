// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*

                                                 ..      .::.   .:::
                                         .::..      ..  :.   ..-=+++-
                                    :        :--:     ...    :+++**+.
                                   .=...  :==  .:-.   .:=:    ...:..-.
                            .:        .:-=+.   .::  ..:-+#:...::::.::-.
                           .::           .:.     ..:=++=-#- .-=====--=-:
                         .:-=  .:::::    :==-:--==+***. .-:  .:=*#*++%%=::-.
                         :-=..:.  .::   :=#+::-=**+-   .:-=  .::--=+===++-:+=
                         .. .         .-=*.   ....=#%=..:-=-.:---*%%*:::=+=.=
                           .  ..   ..:-+*.  .::::+#=-::::--:::------+=---==.
                          :  :=+=--=+**-   .::...-=--=-----:::--===--=-----:
                         :. :=            .::...-. #@@#-----:---*@@@*:=-----.
                           .-     .     ....:::-+ -@@@@-.:::----*@@@#-+-----
                           :. .:-------:::::::..::.=%%*.:-----====+=-=+=---*+
                          .:  :++     -==:.::.   :-===-=%%*==+@%=--=++++=-##-
                      .   :: .--      .-=+-...::-=++*++==-+%%%======+++=-+#+-
                      ::.::. :-: .::...:=**:...:-=====================-::**=:
                       :...  :=- :-** .:-+#=::-------==============---:-##+-.
                           . :==.:-++ .:-=*#*+=-----======--====----*#*+++-.
                           ..:-:..-=*..:-=+===*#%%#=------=*+==---*#*+=--::
                           .:..  .:-=+-:-------==+#%*----=##==--=*+==--:
                            .......:-==-----------+*+=---+*+=---===-++-
                              .--::--:.:--==++=----===+#%#**+==:  ..
                                        :=+*###.     %%%%%%:
                                        .**#%%%      %%%%%#
                                        :*#%%%%      %%%%%#:
                                        -*#%%%%.     %%%%%%%:
                                        :=+*##%%    :%%%%%%%%#:
                                         :-:=+**%.   %@@%%%%%%=
                                         :=**#%%=   .*%%%%%%%*:

*/

import {OwnableBasic} from "@limitbreak/creator-token-standards/access/OwnableBasic.sol";
import {ERC721C} from "@limitbreak/creator-token-standards/erc721c/ERC721C.sol";
import {BasicRoyalties} from "@limitbreak/creator-token-standards/programmable-royalties/BasicRoyalties.sol";
import {ERC721OpenZeppelin} from "@limitbreak/creator-token-standards/token/erc721/ERC721OpenZeppelin.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

/// @notice ERC-4906 interface defined inline because OpenZeppelin v4.8.3 (bundled
///         by Limit Break) predates official EIP-4906 support.
interface IERC4906 {
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}

/// @title BRAINROT
/// @author Nuclear Samurai
/// @notice 10,000-token generative NFT collection on a custom ERC-721C contract.
///         Active phase runs 12 months from mint; metadata is then permanently
///         frozen to Arweave and the metadata controller role is renounced.
/// @dev    Inherits ERC-721C for enforced royalties via Limit Break's transfer
///         validator. Designed to be minimal: all economic and gameplay logic
///         lives off-chain. The v2 actions contract is granted the metadata
///         controller role after deployment to apply per-token URI updates as
///         actions complete.
contract BRAINROT is OwnableBasic, ERC721C, BasicRoyalties, IERC4906 {
    // ============================================================
    //                          ERRORS
    // ============================================================

    error MaxSupplyExceeded();
    error NotMintingManager();
    error NotMetadataController();
    error NotAuthorized();
    error ArrayLengthMismatch();
    error TokenDoesNotExist();
    error ZeroAddress();
    error InvalidRange();

    // ============================================================
    //                          EVENTS
    // ============================================================

    event MintingManagerChanged(address indexed previousManager, address indexed newManager);
    event MetadataControllerChanged(address indexed previousController, address indexed newController);
    event MetadataRefresherChanged(address indexed previousRefresher, address indexed newRefresher);
    event BaseURIChanged(string previousBaseURI, string newBaseURI);

    // ============================================================
    //                          CONSTANTS
    // ============================================================

    uint256 public constant MAX_SUPPLY = 10_000;

    // ============================================================
    //                          STATE
    // ============================================================

    address public mintingManager;
    address public metadataController;
    address public metadataRefresher;
    mapping(uint256 => string) private _tokenURIs;
    string private _baseTokenURI;
    uint256 private _mintedCount;

    // ============================================================
    //                          MODIFIERS
    // ============================================================

    modifier onlyMintingManager() {
        if (msg.sender != mintingManager) revert NotMintingManager();
        _;
    }

    modifier onlyMetadataController() {
        if (msg.sender != metadataController) revert NotMetadataController();
        _;
    }

    // ============================================================
    //                          CONSTRUCTOR
    // ============================================================

    constructor(
        address initialOwner,
        address royaltyReceiver,
        uint96 royaltyFeeNumerator,
        string memory baseURI_,
        address initialMintingManager
    )
        ERC721OpenZeppelin("BRAINROT", "BRAINROT")
        BasicRoyalties(royaltyReceiver, royaltyFeeNumerator)
    {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (initialMintingManager == address(0)) revert ZeroAddress();

        _baseTokenURI = baseURI_;
        mintingManager = initialMintingManager;
        _transferOwnership(initialOwner);

        emit MintingManagerChanged(address(0), initialMintingManager);
        emit BaseURIChanged("", baseURI_);
    }

    // ============================================================
    //                          MINTING
    // ============================================================

    function mint(address to, uint256 tokenId) external onlyMintingManager {
        if (_mintedCount >= MAX_SUPPLY) revert MaxSupplyExceeded();
        unchecked {
            ++_mintedCount;
        }
        _safeMint(to, tokenId);
    }

    /// @notice Mint multiple tokens in a single transaction.
    /// @dev Slither flags this function under `events-maths` for incrementing
    ///      `_mintedCount` without emitting a custom event. This is intentional:
    ///      each `_safeMint` call emits the standard ERC-721 `Transfer(from=0x0)`
    ///      event, which is the canonical signal indexers use to track minted
    ///      supply. A custom event would duplicate information already in the
    ///      ERC-721 event stream.
    /// @param recipients Addresses to receive the minted tokens, one per token.
    /// @param tokenIds Token IDs to mint, one per recipient.
    function mintBatch(address[] calldata recipients, uint256[] calldata tokenIds)
        external
        onlyMintingManager
    {
        uint256 length = recipients.length;
        if (length != tokenIds.length) revert ArrayLengthMismatch();
        if (_mintedCount + length > MAX_SUPPLY) revert MaxSupplyExceeded();

        unchecked {
            _mintedCount += length;
        }

        for (uint256 i = 0; i < length;) {
            _safeMint(recipients[i], tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function totalMinted() external view returns (uint256) {
        return _mintedCount;
    }

    // ============================================================
    //                          BURN
    // ============================================================

    /// @notice Burn a token. Callable by the token owner or an approved operator.
    function burn(uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner
            && !isApprovedForAll(tokenOwner, msg.sender)
            && getApproved(tokenId) != msg.sender) {
            revert NotAuthorized();
        }
        _burn(tokenId);
    }

    // ============================================================
    //                          METADATA
    // ============================================================

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        string memory uri = _tokenURIs[tokenId];
        if (bytes(uri).length > 0) {
            return uri;
        }
        return super.tokenURI(tokenId);
    }

    function setTokenURI(uint256 tokenId, string calldata uri) external onlyMetadataController {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        _tokenURIs[tokenId] = uri;
        emit MetadataUpdate(tokenId);
    }

    function batchSetTokenURI(uint256[] calldata tokenIds, string[] calldata uris)
        external
        onlyMetadataController
    {
        uint256 length = tokenIds.length;
        if (length != uris.length) revert ArrayLengthMismatch();
        if (length == 0) return;

        uint256 minId = type(uint256).max;
        uint256 maxId = 0;

        for (uint256 i = 0; i < length;) {
            uint256 tokenId = tokenIds[i];
            if (!_exists(tokenId)) revert TokenDoesNotExist();
            _tokenURIs[tokenId] = uris[i];

            if (tokenId < minId) minId = tokenId;
            if (tokenId > maxId) maxId = tokenId;

            unchecked {
                ++i;
            }
        }

        emit BatchMetadataUpdate(minId, maxId);
    }

    function setBaseURI(string calldata newBaseURI) external {
        _requireCallerIsContractOwner();
        string memory previousBaseURI = _baseTokenURI;
        _baseTokenURI = newBaseURI;
        emit BaseURIChanged(previousBaseURI, newBaseURI);
    }

    /// @notice Emit an ERC-4906 batch metadata-update signal over a token-ID
    ///         range without modifying any stored URI. Prompts marketplaces to
    ///         re-index metadata after off-chain changes (e.g. trial scores,
    ///         or v2-fee-paid regenerations). Changes no contract state.
    /// @dev Callable by the owner (operational / multisig) or the metadata
    ///      refresher (automated backend hot key). The refresher role is
    ///      rotatable via setMetadataRefresher so a compromised hot key can be
    ///      revoked. This function deliberately performs no _exists checks on
    ///      the range — it is a signal only, and marketplaces tolerate ranges
    ///      that include unminted IDs.
    /// @param fromTokenId First token in the affected range (inclusive).
    /// @param toTokenId   Last token in the affected range (inclusive).
    function emitBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external {
        if (msg.sender != owner() && msg.sender != metadataRefresher) {
            revert NotAuthorized();
        }
        if (fromTokenId > toTokenId) revert InvalidRange();
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // ============================================================
    //                          ADMIN ROLES
    // ============================================================

    function setMintingManager(address newManager) external {
        _requireCallerIsContractOwner();
        if (newManager == address(0)) revert ZeroAddress();
        address previousManager = mintingManager;
        mintingManager = newManager;
        emit MintingManagerChanged(previousManager, newManager);
    }

    /// @notice Grant or revoke the metadata controller role.
    /// @dev Slither flags this function under `missing-zero-check` for not
    ///      reverting when `newController == address(0)`. The absence of a
    ///      zero-check is deliberate: passing the zero address permanently
    ///      renounces the role, which is the cornerstone of the post-freeze
    ///      immutability described in the project threat model. The role is
    ///      handed from this contract's owner to the v2 actions contract
    ///      after v2 deploys, and then to the zero address at month 12 when
    ///      the active phase ends and metadata is migrated to Arweave.
    /// @param newController Address to grant the role to, or address(0) to renounce.
    function setMetadataController(address newController) external {
        _requireCallerIsContractOwner();
        address previousController = metadataController;
        metadataController = newController;
        emit MetadataControllerChanged(previousController, newController);
    }

    /// @notice Grant or revoke the metadata refresher role.
    /// @dev The refresher is a low-privilege hot key whose only power is
    ///      calling emitBatchMetadataUpdate (emit-only, no state change). It
    ///      exists so an automated backend can prompt marketplaces to re-index
    ///      metadata after off-chain changes without exposing the owner
    ///      multisig. Like setMetadataController, the absence of a zero-check
    ///      is deliberate: passing address(0) renounces the role and disables
    ///      the automated refresh path (used in the month-12 freeze sequence).
    ///      If a hot key leaks, rotate by setting a new refresher address; the
    ///      old key immediately loses authority.
    /// @param newRefresher Address to grant the role to, or address(0) to renounce.
    function setMetadataRefresher(address newRefresher) external {
        _requireCallerIsContractOwner();
        address previousRefresher = metadataRefresher;
        metadataRefresher = newRefresher;
        emit MetadataRefresherChanged(previousRefresher, newRefresher);
    }

    // ============================================================
    //                          ROYALTY ADMIN
    // ============================================================

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    // ============================================================
    //                          INTERFACE SUPPORT
    // ============================================================

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721C, ERC2981)
        returns (bool)
    {
        return interfaceId == bytes4(0x49064906) // IERC4906
            || super.supportsInterface(interfaceId);
    }
}

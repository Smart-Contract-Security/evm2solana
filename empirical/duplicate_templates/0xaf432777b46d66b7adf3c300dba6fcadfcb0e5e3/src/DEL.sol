// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "solady/tokens/ERC721.sol";
import {ERC2981} from "solady/tokens/ERC2981.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {DELData} from "./DELData.sol";
import {IDELSVGRenderer, IDELHTMLRenderer, TokenStateView} from "./IDELRenderer.sol";
import {IDELTuner} from "./DELTuner.sol";

/// @title  DEL
/// @author Loucas Braconnier / Figure31
/// @notice DELs are animated ASCII shells embodied by the network. Every
///         movement, every shift in form, every illumination is fueled by
///         a stream of Ethereum block hashes. Each DEL is a fully on-chain
///         artwork the owner can return to and reconfigure over time:
///         every parameter is tunable, every prior state recoverable on
///         chain.
/// @dev    Per-token identity (character set, colour palette, behaviour
///         set) is fixed at mint. The twenty-one numeric animation
///         parameters are stored in a separate DELTuner contract and may
///         be edited by the token owner. Rendering, configuration tables,
///         and the JavaScript engine bundle live in four satellite
///         contracts referenced by address from this one.
contract DEL is ERC721, ERC2981, Ownable {

    enum MintMode { Closed, Public }

    /// @dev Per-token identity. Written once at mint, never modified.
    struct PackedState {
        uint8 charSetIdx;
        uint8 paletteIdx;
        uint8 behaviourIdx;
    }

    error InvalidTokenId();
    error AlreadyMinted();
    error MintClosed();
    error WrongPrice();
    error ZeroAddress();
    error RendererNotSet();
    error TunerNotSet();
    error NotTuner();

    event MintModeChanged(MintMode mode);
    event MintPriceChanged(uint256 newPrice);
    event DataChunkUpdated(address newChunk);
    event DataStoreUpdated(address newStore);
    event SVGRendererUpdated(address newRenderer);
    event HTMLRendererUpdated(address newRenderer);
    event TunerUpdated(address newTuner);
    event RoyaltyChanged(address receiver, uint96 bps);

    /// @dev EIP-4906. Marketplaces refresh metadata when these fire.
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    uint256 public mintPrice;
    MintMode public mintMode;
    address public dataChunk;
    address public dataStore;
    address public svgRenderer;
    address public htmlRenderer;
    address public tuner;

    uint256 private _totalSupply;

    mapping(uint256 => PackedState) private _states;

    constructor(
        uint256 _mintPrice,
        address _dataChunk,
        address _dataStore,
        address _royaltyReceiver,
        uint96 _royaltyBps
    ) {
        if (_dataChunk == address(0) || _dataStore == address(0)) revert ZeroAddress();
        _initializeOwner(msg.sender);
        mintPrice = _mintPrice;
        dataChunk = _dataChunk;
        dataStore = _dataStore;
        mintMode = MintMode.Closed;
        _setDefaultRoyalty(_royaltyReceiver, _royaltyBps);
    }

    function name() public pure override returns (string memory) { return "DEL"; }
    function symbol() public pure override returns (string memory) { return "DEL"; }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return interfaceId == 0x49064906 // EIP-4906
            || ERC721.supportsInterface(interfaceId)
            || ERC2981.supportsInterface(interfaceId);
    }

    function mint(uint256 tokenId) external payable {
        if (mintMode != MintMode.Public) revert MintClosed();
        if (msg.value != mintPrice) revert WrongPrice();
        _initToken(tokenId, msg.sender);
    }

    function ownerMint(uint256 tokenId, address to) external onlyOwner {
        _initToken(tokenId, to);
    }

    function setMintMode(MintMode newMode) external onlyOwner {
        mintMode = newMode;
        emit MintModeChanged(newMode);
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceChanged(newPrice);
    }

    function _initToken(uint256 tokenId, address to) internal {
        if (tokenId == 0 || tokenId > DELData.TOKEN_COUNT) revert InvalidTokenId();
        if (_ownerOf(tokenId) != address(0)) revert AlreadyMinted();
        bytes memory tuples = DELData.TUPLES;
        uint256 off = (tokenId - 1) * 3;
        _states[tokenId] = PackedState({
            charSetIdx:   uint8(tuples[off]),
            paletteIdx:   uint8(tuples[off + 1]),
            behaviourIdx: uint8(tuples[off + 2])
        });
        unchecked { ++_totalSupply; }
        _mint(to, tokenId);
    }

    /// @notice Number of tokens currently in circulation.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Maximum number of tokens the contract can ever issue. The
    /// collection is sealed at this value by construction.
    function maxSupply() external pure returns (uint256) {
        return DELData.TOKEN_COUNT;
    }

    /// @notice Per-token identity. Effective parameter values are resolved
    /// through DELTuner.
    function tokenState(uint256 tokenId)
        external
        view
        returns (
            uint8 charSetIdx,
            uint8 paletteIdx,
            uint8 behaviourIdx,
            bool tuned
        )
    {
        PackedState memory s = _states[tokenId];
        return (
            s.charSetIdx,
            s.paletteIdx,
            s.behaviourIdx,
            tuner != address(0) && IDELTuner(tuner).isTuned(tokenId)
        );
    }

    /// @notice The behaviour-set index for a token. Read by DELTuner when
    /// resolving the default value of a non-overridden field.
    function behaviourIdxOf(uint256 tokenId) external view returns (uint8) {
        return _states[tokenId].behaviourIdx;
    }

    function setDataChunk(address newChunk) external onlyOwner {
        if (newChunk == address(0)) revert ZeroAddress();
        dataChunk = newChunk;
        emit DataChunkUpdated(newChunk);
        emit BatchMetadataUpdate(1, DELData.TOKEN_COUNT);
    }

    function setDataStore(address newStore) external onlyOwner {
        if (newStore == address(0)) revert ZeroAddress();
        dataStore = newStore;
        emit DataStoreUpdated(newStore);
        emit BatchMetadataUpdate(1, DELData.TOKEN_COUNT);
    }

    function setSVGRenderer(address newRenderer) external onlyOwner {
        if (newRenderer == address(0)) revert ZeroAddress();
        svgRenderer = newRenderer;
        emit SVGRendererUpdated(newRenderer);
        emit BatchMetadataUpdate(1, DELData.TOKEN_COUNT);
    }

    function setHTMLRenderer(address newRenderer) external onlyOwner {
        if (newRenderer == address(0)) revert ZeroAddress();
        htmlRenderer = newRenderer;
        emit HTMLRendererUpdated(newRenderer);
        emit BatchMetadataUpdate(1, DELData.TOKEN_COUNT);
    }

    function setTuner(address newTuner) external onlyOwner {
        if (newTuner == address(0)) revert ZeroAddress();
        tuner = newTuner;
        emit TunerUpdated(newTuner);
        emit BatchMetadataUpdate(1, DELData.TOKEN_COUNT);
    }

    /// @notice Called by the active tuner after a tune or reset, so
    /// marketplaces refresh the token's metadata. Restricted to the
    /// current tuner; replaced tuners cannot emit on this contract.
    function emitMetadataUpdate(uint256 tokenId) external {
        if (msg.sender != tuner) revert NotTuner();
        emit MetadataUpdate(tokenId);
    }

    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(receiver, bps);
        emit RoyaltyChanged(receiver, bps);
    }

    function withdraw(address to) external onlyOwner {
        (bool ok,) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address tokenOwner = _ownerOf(tokenId);
        if (tokenOwner == address(0)) revert TokenDoesNotExist();
        if (svgRenderer == address(0) || htmlRenderer == address(0)) revert RendererNotSet();
        if (tuner == address(0)) revert TunerNotSet();
        PackedState memory s = _states[tokenId];
        TokenStateView memory v = TokenStateView({
            owner:        tokenOwner,
            charSetIdx:   s.charSetIdx,
            paletteIdx:   s.paletteIdx,
            behaviourIdx: s.behaviourIdx,
            tuned:        IDELTuner(tuner).isTuned(tokenId)
        });
        bytes memory svgBytes  = IDELSVGRenderer(svgRenderer).svg(tokenId, v, dataStore, tuner);
        bytes memory htmlBytes = IDELHTMLRenderer(htmlRenderer).html(tokenId, v, dataStore, dataChunk, tuner);
        bytes memory json = bytes.concat(
            '{"name":"DEL #', bytes(LibString.toString(tokenId)),
            '","description":"DELs are animated ASCII shells embodied by the network. Every movement, every shift in form, every illumination is fueled by a stream of Ethereum block hashes. Each DEL is a fully on-chain artwork the owner can return to and reconfigure over time: every parameter is tunable, every prior state recoverable on chain. By Loucas Braconnier/Figure31.",',
            '"image":"data:image/svg+xml;base64,', bytes(Base64.encode(svgBytes)),
            '","animation_url":"data:text/html;base64,', bytes(Base64.encode(htmlBytes)),
            '","attributes":', _attributes(v), "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _attributes(TokenStateView memory v) internal pure returns (bytes memory) {
        return bytes.concat(
            '[{"trait_type":"Character Set","value":"', bytes(LibString.toString(uint256(v.charSetIdx) + 1)), '"}',
            ',{"trait_type":"Palette","value":"', bytes(LibString.toString(uint256(v.paletteIdx) + 1)), '"}',
            ',{"trait_type":"Behaviour Set","value":"', bytes(LibString.toString(uint256(v.behaviourIdx) + 1)), '"}',
            ',{"trait_type":"Tuned","value":"', v.tuned ? bytes("Yes") : bytes("No"), '"}',
            "]"
        );
    }
}

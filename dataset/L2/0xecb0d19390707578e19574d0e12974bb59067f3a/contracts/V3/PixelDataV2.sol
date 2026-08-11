// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "solady/src/utils/SSTORE2.sol";

contract PixelDataV2 is Ownable {
    string private constant SVG_HEADER =
        '<svg width="1200" height="1200" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg" version="1.2" viewBox="0 0 ';
    string private constant SVG_FOOTER =
        '"><style>rect{shape-rendering:crispEdges}</style>';
    bytes private constant HEX_SYMBOLS = "0123456789abcdef";
    uint256 private constant MAX_CONTRACT_SIZE = 24576;

    uint256 public compositesPerChunk;
    uint16 public canvasWidth;
    uint16 public canvasHeight;
    bool public isSealed;
    bool public isRevealed;

    address public palettePointer;
    mapping(uint256 => address[]) public traitPointers;
    address[] public compositesPointers;

    mapping(uint256 => string) public layerNames;
    uint256 public numberOfLayers;

    struct Trait {
        uint256 pointerIndex;
        uint256 offset;
        uint256 length;
    }

    mapping(uint256 => mapping(uint256 => Trait)) public traits;
    mapping(uint256 => mapping(uint256 => string)) public traitNames;

    uint256 public revealSeed;
    address public mintbayGenerativeContract;

    event CanvasSizeSet(uint16 width, uint16 height);
    event PaletteSet(address pointer);
    event LayerSet(uint256 layerId, string name);
    event TraitAdded(uint256 layerId, uint256 traitId, string name, uint256 pointerIndex, uint256 offset);
    event CompositeChunkAdded(uint256 chunkId, address pointer);
    event RevealSeedSet(uint256 seed);
    event ContractSealed();
    event CompositesPerChunkSet(uint256 compositesPerChunk);
    event MintbayGenerativeContractSet(address indexed mintContract);

    modifier unsealed() {
        require(!isSealed, "Contract sealed");
        _;
    }

    modifier onlyMintbayOrOwner() {
        require(msg.sender == mintbayGenerativeContract || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier noCompositesYet() {
        require(compositesPointers.length == 0, "Composites already uploaded");
        _;
    }

    constructor() {
        compositesPerChunk = 500;
    }

    function setCompositesPerChunk(uint256 _compositesPerChunk) external onlyOwner unsealed noCompositesYet {
        require(_compositesPerChunk > 0, "Invalid chunk size");
        require(numberOfLayers > 0, "No layers set");
        require(_compositesPerChunk * numberOfLayers <= MAX_CONTRACT_SIZE, "Chunk too large");
        compositesPerChunk = _compositesPerChunk;
        emit CompositesPerChunkSet(_compositesPerChunk);
    }

    function setMintbayGenerativeContract(address _mintbayGenerativeContract) external onlyOwner unsealed {
        require(_mintbayGenerativeContract != address(0), "Invalid address");
        mintbayGenerativeContract = _mintbayGenerativeContract;
        emit MintbayGenerativeContractSet(_mintbayGenerativeContract);
    }

    function setCanvasSize(uint16 _width, uint16 _height) external onlyOwner unsealed noCompositesYet {
        require(_width > 0 && _height > 0 && _width <= 256 && _height <= 256, "Invalid canvas size");
        canvasWidth = _width;
        canvasHeight = _height;
        emit CanvasSizeSet(_width, _height);
    }

    function setPalette(bytes calldata _palette) external onlyOwner unsealed noCompositesYet {
        require(canvasWidth > 0 && canvasHeight > 0, "Canvas not set");
        require(_palette.length % 4 == 0, "Invalid palette size");
        require(_palette.length / 4 <= 255, "Too many colors");
        require(_palette.length + 32 <= MAX_CONTRACT_SIZE, "Palette too large");
        palettePointer = SSTORE2.write(abi.encodePacked(uint256(_palette.length), _palette));
        emit PaletteSet(palettePointer);
    }

    function setLayer(uint256 layerId, string calldata name) external onlyOwner unsealed noCompositesYet {
        layerNames[layerId] = name;
        if (layerId >= numberOfLayers) {
            numberOfLayers = layerId + 1;
        }
        emit LayerSet(layerId, name);
    }

    function setLayersBatch(uint256[] calldata layerIds, string[] calldata names)
        external
        onlyOwner
        unsealed
        noCompositesYet
    {
        require(layerIds.length == names.length, "Mismatched arrays");
        for (uint256 i = 0; i < layerIds.length; i++) {
            layerNames[layerIds[i]] = names[i];
            if (layerIds[i] >= numberOfLayers) {
                numberOfLayers = layerIds[i] + 1;
            }
            emit LayerSet(layerIds[i], names[i]);
        }
    }

    function addTrait(uint256 layerId, uint256 traitId, bytes calldata data, string calldata name)
        external
        onlyOwner
        unsealed
    {
        require(layerId < numberOfLayers, "Invalid layer");
        require(traitId <= type(uint8).max, "Trait ID too large");
        _validateTraitData(data);

        (, uint256 pointerIndex, uint256 offset) =
            _storeTraitData(layerId, abi.encodePacked(uint256(data.length), data));

        _setTrait(layerId, traitId, name, pointerIndex, offset + 32, data.length);
    }

    function addTraitsBatch(
        uint256 layerId,
        uint256[] calldata traitIds,
        bytes[] calldata datas,
        string[] calldata names
    ) external onlyOwner unsealed {
        require(layerId < numberOfLayers, "Invalid layer");
        require(traitIds.length == datas.length && datas.length == names.length, "Mismatched arrays");

        for (uint256 i = 0; i < traitIds.length; i++) {
            require(traitIds[i] <= type(uint8).max, "Trait ID too large");
            _validateTraitData(datas[i]);
        }

        bytes memory combinedData;
        for (uint256 i = 0; i < traitIds.length; i++) {
            combinedData = abi.encodePacked(combinedData, uint256(datas[i].length), datas[i]);
        }

        (, uint256 pointerIndex, uint256 offset) = _storeTraitData(layerId, combinedData);

        uint256 currentOffset = offset + 32;
        for (uint256 i = 0; i < traitIds.length; i++) {
            _setTrait(layerId, traitIds[i], names[i], pointerIndex, currentOffset, datas[i].length);
            currentOffset += 32 + datas[i].length;
        }
    }

    function addComposite(uint256[] calldata traitIndices) external onlyOwner unsealed {
        require(traitIndices.length == numberOfLayers, "Invalid composite length");

        bytes memory data;
        for (uint256 i = 0; i < traitIndices.length; i++) {
            uint256 traitIndex = traitIndices[i];
            require(traitIndex <= type(uint8).max, "Trait index too large");
            require(traitPointers[i].length > traits[i][traitIndex].pointerIndex, "Invalid trait index");
            data = abi.encodePacked(data, uint8(traitIndex));
        }

        _storeComposite(data);
        emit CompositeChunkAdded(compositesPointers.length - 1, compositesPointers[compositesPointers.length - 1]);
    }

    function addCompositesBatch(uint256[][] calldata traitIndicesArray) external onlyOwner unsealed {
        uint256 count = traitIndicesArray.length;
        require(count > 0, "Empty batch");
        require(numberOfLayers > 0, "No layers");

        uint256 numLayers = numberOfLayers;
        bytes memory data = new bytes(count * numLayers);
        uint256 dataIndex = 0;

        for (uint256 i = 0; i < count; ) {
            uint256[] calldata traitsPerLayer = traitIndicesArray[i];
            require(traitsPerLayer.length == numLayers, "Invalid composite length");

            for (uint256 j = 0; j < numLayers; ) {
                uint256 traitIndex = traitsPerLayer[j];
                require(traitIndex <= type(uint8).max, "Trait index too large");
                require(traitPointers[j].length > traits[j][traitIndex].pointerIndex, "Invalid trait index");

                data[dataIndex] = bytes1(uint8(traitIndex));

                unchecked {
                    ++dataIndex;
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        _storeComposite(data);
        emit CompositeChunkAdded(compositesPointers.length - 1, compositesPointers[compositesPointers.length - 1]);
    }

    function setRevealSeed(uint256 _seed) external onlyMintbayOrOwner {
        require(!isRevealed, "Already revealed");
        revealSeed = _seed;
        isRevealed = true;
        emit RevealSeedSet(_seed);
    }

    function sealContract() external onlyOwner {
        isSealed = true;
        emit ContractSealed();
    }

    function getComposite(uint256 compositeIndex) external view returns (uint256[] memory) {
        require(compositeIndex < getCompositesCount(), "Invalid composite index");

        uint256 compositesSize = numberOfLayers;
        uint256 chunkId = compositeIndex / compositesPerChunk;
        uint256 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;
        require(chunkId < compositesPointers.length, "Invalid chunk ID");

        bytes memory compositesData = SSTORE2.read(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        uint256[] memory traitIndices = new uint256[](numberOfLayers);
        for (uint256 i = 0; i < numberOfLayers; i++) {
            traitIndices[i] = uint8(compositesData[i]);
        }
        return traitIndices;
    }

    function getCompositesCount() public view returns (uint256) {
        if (numberOfLayers == 0) return 0;

        uint256 total = 0;
        uint256 compositesSize = numberOfLayers;

        for (uint256 i = 0; i < compositesPointers.length; i++) {
            total += SSTORE2.read(compositesPointers[i]).length / compositesSize;
        }

        return total;
    }

    function tokenImageSvg(uint256 compositeIndex) public view returns (string memory) {
        require(isRevealed, "Not revealed");
        require(compositeIndex < getCompositesCount(), "Invalid composite index");

        bytes memory svg = abi.encodePacked(
            SVG_HEADER,
            Strings.toString(canvasWidth),
            " ",
            Strings.toString(canvasHeight),
            SVG_FOOTER
        );

        uint256 compositesSize = numberOfLayers;
        uint256 chunkId = compositeIndex / compositesPerChunk;
        uint256 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;

        bytes memory compositesData = SSTORE2.read(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        bytes memory paletteData = SSTORE2.read(palettePointer);

        for (uint256 layer = 0; layer < numberOfLayers; layer++) {
            uint256 traitIndex = uint8(compositesData[layer]);
            Trait memory trait = traits[layer][traitIndex];
            if (trait.length == 0) continue;

            bytes memory traitData = SSTORE2.read(
                traitPointers[layer][trait.pointerIndex],
                trait.offset,
                trait.offset + trait.length
            );

            bytes memory layerSvg = _generateLayerSvg(traitData, paletteData);
            if (layerSvg.length > 0) {
                svg = abi.encodePacked(svg, layerSvg);
            }
        }

        svg = abi.encodePacked(svg, "</svg>");
        return string(svg);
    }

    function tokenAttributes(uint256 compositeIndex) public view returns (bytes memory) {
        require(isRevealed, "Not revealed");
        require(compositeIndex < getCompositesCount(), "Invalid composite index");
        return _generateAttributes(compositeIndex);
    }

    function _escapeJsonString(string memory input) internal pure returns (string memory) {
        bytes memory src = bytes(input);
        bytes memory out = new bytes(src.length * 2);
        uint256 j = 0;

        for (uint256 i = 0; i < src.length; i++) {
            bytes1 c = src[i];

            if (c == bytes1(0x22)) {
                out[j++] = bytes1(0x5c);
                out[j++] = bytes1(0x22);
            } else if (c == bytes1(0x5c)) {
                out[j++] = bytes1(0x5c);
                out[j++] = bytes1(0x5c);
            } else if (c == bytes1(0x0a)) {
                out[j++] = bytes1(0x5c);
                out[j++] = bytes1(0x6e);
            } else if (c == bytes1(0x0d)) {
                out[j++] = bytes1(0x5c);
                out[j++] = bytes1(0x72);
            } else if (c == bytes1(0x09)) {
                out[j++] = bytes1(0x5c);
                out[j++] = bytes1(0x74);
            } else {
                out[j++] = c;
            }
        }

        bytes memory escaped = new bytes(j);
        for (uint256 i = 0; i < j; i++) {
            escaped[i] = out[i];
        }

        return string(escaped);
    }

    function _generateAttributes(uint256 compositeIndex) private view returns (bytes memory) {
        uint256 compositesSize = numberOfLayers;
        uint256 chunkId = compositeIndex / compositesPerChunk;
        uint256 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;

        bytes memory compositesData = SSTORE2.read(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        bytes memory attributes = "[";
        bool hasAttributes = false;

        for (uint256 i = 0; i < numberOfLayers; i++) {
            uint256 traitIndex = uint8(compositesData[i]);

            if (bytes(traitNames[i][traitIndex]).length == 0 || traits[i][traitIndex].length == 0) {
                continue;
            }

            if (hasAttributes) {
                attributes = abi.encodePacked(attributes, ",");
            }

            attributes = abi.encodePacked(
                attributes,
                '{"trait_type":"',
                _escapeJsonString(layerNames[i]),
                '","value":"',
                _escapeJsonString(traitNames[i][traitIndex]),
                '"}'
            );

            hasAttributes = true;
        }

        return abi.encodePacked(attributes, "]");
    }

    function _setTrait(
        uint256 layerId,
        uint256 traitId,
        string memory name,
        uint256 pointerIndex,
        uint256 offset,
        uint256 length
    ) internal {
        traits[layerId][traitId] = Trait(pointerIndex, offset, length);
        traitNames[layerId][traitId] = name;
        emit TraitAdded(layerId, traitId, name, pointerIndex, offset);
    }

    function _storeTraitData(uint256 layerId, bytes memory data)
        private
        returns (address pointer, uint256 pointerIndex, uint256 offset)
    {
        require(data.length <= MAX_CONTRACT_SIZE, "Data too large");
        address[] storage pointers = traitPointers[layerId];
        pointer = SSTORE2.write(data);
        pointers.push(pointer);
        pointerIndex = pointers.length - 1;
        offset = 0;
    }

    function _storeComposite(bytes memory data) private {
        require(data.length > 0, "Empty composite data");
        require(data.length <= MAX_CONTRACT_SIZE, "Composite chunk too large");
        compositesPointers.push(SSTORE2.write(data));
    }

    function _validateTraitData(bytes memory data) private view {
        if (data.length == 0) return;

        bytes memory paletteData = SSTORE2.read(palettePointer);
        require(paletteData.length > 32, "Palette not set");

        uint256 paletteLength = uint256(bytes32(paletteData));
        require(data.length % 5 == 0, "Invalid rect data");

        for (uint256 i = 0; i < data.length; i += 5) {
            uint8 x = uint8(data[i]);
            uint8 y = uint8(data[i + 1]);
            uint8 width = uint8(data[i + 2]);
            uint8 height = uint8(data[i + 3]);
            uint8 paletteIndex = uint8(data[i + 4]);

            require(uint16(x) + width <= canvasWidth && uint16(y) + height <= canvasHeight, "Out of bounds");
            require(width > 0 && height > 0, "Zero rect");
            require(_isValidPaletteIndex(paletteIndex, paletteLength), "Bad palette index");
        }
    }

    function _isValidPaletteIndex(uint256 paletteIndex, uint256 paletteLength) internal pure returns (bool) {
        require(paletteLength % 4 == 0, "Invalid palette len");
        uint256 colorCount = paletteLength / 4;
        return paletteIndex < colorCount || paletteIndex == 255;
    }

    function _rgbToHex(uint256 paletteOffset) private view returns (bytes memory) {
        bytes memory paletteData = SSTORE2.read(palettePointer);

        uint8 r = uint8(paletteData[32 + paletteOffset]);
        uint8 g = uint8(paletteData[32 + paletteOffset + 1]);
        uint8 b = uint8(paletteData[32 + paletteOffset + 2]);

        return abi.encodePacked(
            HEX_SYMBOLS[r >> 4], HEX_SYMBOLS[r & 0x0f],
            HEX_SYMBOLS[g >> 4], HEX_SYMBOLS[g & 0x0f],
            HEX_SYMBOLS[b >> 4], HEX_SYMBOLS[b & 0x0f]
        );
    }

    function _opacityFromAlpha(uint8 alpha) private pure returns (string memory) {
        if (alpha == 255) return "1";
        if (alpha == 0) return "0";

        uint256 scaled = (uint256(alpha) * 1000) / 255;
        uint256 tenths = scaled / 100;
        uint256 hundredths = (scaled % 100) / 10;

        return string(
            abi.encodePacked(
                "0.",
                Strings.toString(tenths),
                Strings.toString(hundredths)
            )
        );
    }

    function _generateLayerSvg(bytes memory data, bytes memory paletteData) private view returns (bytes memory) {
        if (data.length == 0) return "";

        uint256 paletteLength = uint256(bytes32(paletteData));
        require(paletteLength % 4 == 0, "Invalid palette");
        uint256 maxPaletteIndex = paletteLength / 4;
        require(maxPaletteIndex < 256, "Too many colors");

        bytes[] memory rectGroups = new bytes[](maxPaletteIndex + 1);

        for (uint256 i = 0; i < data.length; i += 5) {
            uint8 x = uint8(data[i]);
            uint8 y = uint8(data[i + 1]);
            uint8 width = uint8(data[i + 2]);
            uint8 height = uint8(data[i + 3]);
            uint8 paletteIndex = uint8(data[i + 4]);

            if (paletteIndex == 255) continue;

            rectGroups[paletteIndex] = abi.encodePacked(
                rectGroups[paletteIndex],
                '<rect x="',
                Strings.toString(x),
                '" y="',
                Strings.toString(y),
                '" width="',
                Strings.toString(width),
                '" height="',
                Strings.toString(height),
                '"/>'
            );
        }

        bytes memory svg;
        for (uint256 i = 0; i < maxPaletteIndex; i++) {
            if (rectGroups[i].length == 0) continue;

            uint256 paletteOffset = i * 4;
            bytes memory hexColor = _rgbToHex(paletteOffset);
            string memory opacity = _opacityFromAlpha(uint8(paletteData[32 + paletteOffset + 3]));

            svg = abi.encodePacked(
                svg,
                '<g fill="#',
                hexColor,
                '" fill-opacity="',
                opacity,
                '">',
                rectGroups[i],
                "</g>"
            );
        }

        return svg;
    }
}
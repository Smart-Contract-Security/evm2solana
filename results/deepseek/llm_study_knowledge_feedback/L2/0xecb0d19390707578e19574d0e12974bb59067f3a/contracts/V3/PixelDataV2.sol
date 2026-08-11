// SPDX-License-Identifier: MIT

import 'solana';

contract PixelDataV2 {
    string private constant SVG_HEADER =
        '<svg width="1200" height="1200" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg" version="1.2" viewBox="0 0 ';
    string private constant SVG_FOOTER =
        '"><style>rect{shape-rendering:crispEdges}</style>';
    bytes private constant HEX_SYMBOLS = "0123456789abcdef";
    uint64 private constant MAX_CONTRACT_SIZE = 24576;

    uint64 public compositesPerChunk;
    uint16 public canvasWidth;
    uint16 public canvasHeight;
    bool public isSealed;
    bool public isRevealed;

    address public palettePointer;
    mapping(uint64 => address[]) public traitPointers;
    address[] public compositesPointers;

    mapping(uint64 => string) public layerNames;
    uint64 public numberOfLayers;

    struct Trait {
        uint64 pointerIndex;
        uint64 offset;
        uint64 length;
    }

    mapping(uint64 => mapping(uint64 => Trait)) public traits;
    mapping(uint64 => mapping(uint64 => string)) public traitNames;

    uint64 public revealSeed;
    address public mintbayGenerativeContract;
    address public owner;

    event CanvasSizeSet(uint16 width, uint16 height);
    event PaletteSet(address pointer);
    event LayerSet(uint64 layerId, string name);
    event TraitAdded(uint64 layerId, uint64 traitId, string name, uint64 pointerIndex, uint64 offset);
    event CompositeChunkAdded(uint64 chunkId, address pointer);
    event RevealSeedSet(uint64 seed);
    event ContractSealed();
    event CompositesPerChunkSet(uint64 compositesPerChunk);
    event MintbayGenerativeContractSet(address indexed mintContract);

    modifier unsealed() {
        require(!isSealed, "Contract sealed");
        _;
    }

    modifier onlyMintbayOrOwner() {
        require(tx.accounts.dataAccount.key == mintbayGenerativeContract || tx.accounts.dataAccount.key == owner, "Not authorized");
        _;
    }

    modifier noCompositesYet() {
        require(compositesPointers.length == 0, "Composites already uploaded");
        _;
    }

    @payer(payer)
    @space(512 + 32)
    constructor() {
        compositesPerChunk = 500;
        owner = tx.accounts.payer.key;
    }

    function setCompositesPerChunk(uint64 _compositesPerChunk) external unsealed noCompositesYet {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(_compositesPerChunk > 0, "Invalid chunk size");
        require(numberOfLayers > 0, "No layers set");
        require(_compositesPerChunk * numberOfLayers <= MAX_CONTRACT_SIZE, "Chunk too large");
        compositesPerChunk = _compositesPerChunk;
        emit CompositesPerChunkSet(_compositesPerChunk);
    }

    function setMintbayGenerativeContract(address _mintbayGenerativeContract) external unsealed {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(_mintbayGenerativeContract != address(0), "Invalid address");
        mintbayGenerativeContract = _mintbayGenerativeContract;
        emit MintbayGenerativeContractSet(_mintbayGenerativeContract);
    }

    function setCanvasSize(uint16 _width, uint16 _height) external unsealed noCompositesYet {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(_width > 0 && _height > 0 && _width <= 256 && _height <= 256, "Invalid canvas size");
        canvasWidth = _width;
        canvasHeight = _height;
        emit CanvasSizeSet(_width, _height);
    }

    function setPalette(bytes calldata _palette) external unsealed noCompositesYet {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(canvasWidth > 0 && canvasHeight > 0, "Canvas not set");
        require(_palette.length % 4 == 0, "Invalid palette size");
        require(_palette.length / 4 <= 255, "Too many colors");
        require(_palette.length + 32 <= MAX_CONTRACT_SIZE, "Palette too large");
        palettePointer = writeSstore2(abi.encodePacked(uint64(_palette.length), _palette));
        emit PaletteSet(palettePointer);
    }

    function setLayer(uint64 layerId, string calldata name) external unsealed noCompositesYet {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        layerNames[layerId] = name;
        if (layerId >= numberOfLayers) {
            numberOfLayers = layerId + 1;
        }
        emit LayerSet(layerId, name);
    }

    function setLayersBatch(uint64[] calldata layerIds, string[] calldata names)
        external
        unsealed
        noCompositesYet
    {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(layerIds.length == names.length, "Mismatched arrays");
        for (uint64 i = 0; i < layerIds.length; i++) {
            layerNames[layerIds[i]] = names[i];
            if (layerIds[i] >= numberOfLayers) {
                numberOfLayers = layerIds[i] + 1;
            }
            emit LayerSet(layerIds[i], names[i]);
        }
    }

    function addTrait(uint64 layerId, uint64 traitId, bytes calldata data, string calldata name)
        external
        unsealed
    {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(layerId < numberOfLayers, "Invalid layer");
        require(traitId <= type(uint8).max, "Trait ID too large");
        _validateTraitData(data);

        (address pointer, uint64 pointerIndex, uint64 offset) =
            _storeTraitData(layerId, abi.encodePacked(uint64(data.length), data));

        _setTrait(layerId, traitId, name, pointerIndex, offset + 32, uint64(data.length));
    }

    function addTraitsBatch(
        uint64 layerId,
        uint64[] calldata traitIds,
        bytes[] calldata datas,
        string[] calldata names
    ) external unsealed {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(layerId < numberOfLayers, "Invalid layer");
        require(traitIds.length == datas.length && datas.length == names.length, "Mismatched arrays");

        for (uint64 i = 0; i < traitIds.length; i++) {
            require(traitIds[i] <= type(uint8).max, "Trait ID too large");
            _validateTraitData(datas[i]);
        }

        bytes memory combinedData = new bytes(0);
        for (uint64 i = 0; i < traitIds.length; i++) {
            combinedData = abi.encodePacked(combinedData, uint64(datas[i].length), datas[i]);
        }

        (address pointer, uint64 pointerIndex, uint64 offset) = _storeTraitData(layerId, combinedData);

        uint64 currentOffset = offset + 32;
        for (uint64 i = 0; i < traitIds.length; i++) {
            _setTrait(layerId, traitIds[i], names[i], pointerIndex, currentOffset, uint64(datas[i].length));
            currentOffset += 32 + uint64(datas[i].length);
        }
    }

    function addComposite(uint64[] calldata traitIndices) external unsealed {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(traitIndices.length == numberOfLayers, "Invalid composite length");

        bytes memory data = new bytes(0);
        for (uint64 i = 0; i < traitIndices.length; i++) {
            uint64 traitIndex = traitIndices[i];
            require(traitIndex <= type(uint8).max, "Trait index too large");
            require(traitPointers[i].length > traits[i][traitIndex].pointerIndex, "Invalid trait index");
            data = abi.encodePacked(data, uint8(traitIndex));
        }

        _storeComposite(data);
        emit CompositeChunkAdded(uint64(compositesPointers.length - 1), compositesPointers[compositesPointers.length - 1]);
    }

    function addCompositesBatch(uint64[][] calldata traitIndicesArray) external unsealed {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        uint64 count = uint64(traitIndicesArray.length);
        require(count > 0, "Empty batch");
        require(numberOfLayers > 0, "No layers");

        uint64 numLayers = numberOfLayers;
        bytes memory data = new bytes(count * numLayers);
        uint64 dataIndex = 0;

        for (uint64 i = 0; i < count; ) {
            uint64[] calldata traitsPerLayer = traitIndicesArray[i];
            require(traitsPerLayer.length == numLayers, "Invalid composite length");

            for (uint64 j = 0; j < numLayers; ) {
                uint64 traitIndex = traitsPerLayer[j];
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
        emit CompositeChunkAdded(uint64(compositesPointers.length - 1), compositesPointers[compositesPointers.length - 1]);
    }

    function setRevealSeed(uint64 _seed) external onlyMintbayOrOwner {
        require(!isRevealed, "Already revealed");
        revealSeed = _seed;
        isRevealed = true;
        emit RevealSeedSet(_seed);
    }

    function sealContract() external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        isSealed = true;
        emit ContractSealed();
    }

    function getComposite(uint64 compositeIndex) external view returns (uint64[] memory) {
        require(compositeIndex < getCompositesCount(), "Invalid composite index");

        uint64 compositesSize = numberOfLayers;
        uint64 chunkId = compositeIndex / compositesPerChunk;
        uint64 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;
        require(chunkId < compositesPointers.length, "Invalid chunk ID");

        bytes memory compositesData = readSstore2(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        uint64[] memory traitIndices = new uint64[](numberOfLayers);
        for (uint64 i = 0; i < numberOfLayers; i++) {
            traitIndices[i] = uint8(compositesData[i]);
        }
        return traitIndices;
    }

    function getCompositesCount() public view returns (uint64) {
        if (numberOfLayers == 0) return 0;

        uint64 total = 0;
        uint64 compositesSize = numberOfLayers;

        for (uint64 i = 0; i < compositesPointers.length; i++) {
            total += uint64(readSstore2(compositesPointers[i]).length) / compositesSize;
        }

        return total;
    }

    function tokenImageSvg(uint64 compositeIndex) public view returns (string memory) {
        require(isRevealed, "Not revealed");
        require(compositeIndex < getCompositesCount(), "Invalid composite index");

        bytes memory svg = abi.encodePacked(
            SVG_HEADER,
            uint64ToString(canvasWidth),
            " ",
            uint64ToString(canvasHeight),
            SVG_FOOTER
        );

        uint64 compositesSize = numberOfLayers;
        uint64 chunkId = compositeIndex / compositesPerChunk;
        uint64 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;

        bytes memory compositesData = readSstore2(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        bytes memory paletteData = readSstore2(palettePointer);

        for (uint64 layer = 0; layer < numberOfLayers; layer++) {
            uint64 traitIndex = uint8(compositesData[layer]);
            Trait memory trait = traits[layer][traitIndex];
            if (trait.length == 0) continue;

            bytes memory traitData = readSstore2(
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

    function tokenAttributes(uint64 compositeIndex) public view returns (bytes memory) {
        require(isRevealed, "Not revealed");
        require(compositeIndex < getCompositesCount(), "Invalid composite index");
        return _generateAttributes(compositeIndex);
    }

    function _escapeJsonString(string memory input) internal pure returns (string memory) {
        bytes memory src = bytes(input);
        bytes memory out = new bytes(src.length * 2);
        uint64 j = 0;

        for (uint64 i = 0; i < src.length; i++) {
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
        for (uint64 i = 0; i < j; i++) {
            escaped[i] = out[i];
        }

        return string(escaped);
    }

    function _generateAttributes(uint64 compositeIndex) private view returns (bytes memory) {
        uint64 compositesSize = numberOfLayers;
        uint64 chunkId = compositeIndex / compositesPerChunk;
        uint64 chunkOffset = (compositeIndex % compositesPerChunk) * compositesSize;

        bytes memory compositesData = readSstore2(
            compositesPointers[chunkId],
            chunkOffset,
            chunkOffset + compositesSize
        );

        bytes memory attributes = bytes("[");
        bool hasAttributes = false;

        for (uint64 i = 0; i < numberOfLayers; i++) {
            uint64 traitIndex = uint8(compositesData[i]);

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
        uint64 layerId,
        uint64 traitId,
        string memory name,
        uint64 pointerIndex,
        uint64 offset,
        uint64 length
    ) internal {
        traits[layerId][traitId] = Trait(pointerIndex, offset, length);
        traitNames[layerId][traitId] = name;
        emit TraitAdded(layerId, traitId, name, pointerIndex, offset);
    }

    function _storeTraitData(uint64 layerId, bytes memory data)
        private
        returns (address pointer, uint64 pointerIndex, uint64 offset)
    {
        require(data.length <= MAX_CONTRACT_SIZE, "Data too large");
        address[] storage pointers = traitPointers[layerId];
        pointer = writeSstore2(data);
        pointers.push(pointer);
        pointerIndex = uint64(pointers.length - 1);
        offset = 0;
    }

    function _storeComposite(bytes memory data) private {
        require(data.length > 0, "Empty composite data");
        require(data.length <= MAX_CONTRACT_SIZE, "Composite chunk too large");
        compositesPointers.push(writeSstore2(data));
    }

    function _validateTraitData(bytes memory data) private view {
        if (data.length == 0) return;

        bytes memory paletteData = readSstore2(palettePointer);
        require(paletteData.length > 32, "Palette not set");

        uint64 paletteLength = uint64(bytesToUint64(paletteData));
        require(data.length % 5 == 0, "Invalid rect data");

        for (uint64 i = 0; i < data.length; i += 5) {
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

    function _isValidPaletteIndex(uint64 paletteIndex, uint64 paletteLength) internal pure returns (bool) {
        require(paletteLength % 4 == 0, "Invalid palette len");
        uint64 colorCount = paletteLength / 4;
        return paletteIndex < colorCount || paletteIndex == 255;
    }

    function _rgbToHex(uint64 paletteOffset) private view returns (bytes memory) {
        bytes memory paletteData = readSstore2(palettePointer);

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

        uint64 scaled = (uint64(alpha) * 1000) / 255;
        uint64 tenths = scaled / 100;
        uint64 hundredths = (scaled % 100) / 10;

        return string(
            abi.encodePacked(
                "0.",
                uint64ToString(tenths),
                uint64ToString(hundredths)
            )
        );
    }

    function _generateLayerSvg(bytes memory data, bytes memory paletteData) private view returns (bytes memory) {
        if (data.length == 0) return "";

        uint64 paletteLength = uint64(bytesToUint64(paletteData));
        require(paletteLength % 4 == 0, "Invalid palette");
        uint64 maxPaletteIndex = paletteLength / 4;
        require(maxPaletteIndex < 256, "Too many colors");

        bytes[] memory rectGroups = new bytes[](maxPaletteIndex + 1);

        for (uint64 i = 0; i < data.length; i += 5) {
            uint8 x = uint8(data[i]);
            uint8 y = uint8(data[i + 1]);
            uint8 width = uint8(data[i + 2]);
            uint8 height = uint8(data[i + 3]);
            uint8 paletteIndex = uint8(data[i + 4]);

            if (paletteIndex == 255) continue;

            rectGroups[paletteIndex] = abi.encodePacked(
                rectGroups[paletteIndex],
                '<rect x="',
                uint64ToString(x),
                '" y="',
                uint64ToString(y),
                '" width="',
                uint64ToString(width),
                '" height="',
                uint64ToString(height),
                '"/>'
            );
        }

        bytes memory svg = new bytes(0);
        for (uint64 i = 0; i < maxPaletteIndex; i++) {
            if (rectGroups[i].length == 0) continue;

            uint64 paletteOffset = i * 4;
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

    function uint64ToString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits = 0;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function bytesToUint64(bytes memory b) internal pure returns (uint64 result) {
        require(b.length >= 8, "Input too short");
        result = 0;
        for (uint64 i = 0; i < 8; i++) {
            result = result | (uint64(uint8(b[i])) << (i * 8));
        }
    }

    function writeSstore2(bytes memory data) internal returns (address) {
        // Placeholder for SSTORE2 write functionality
        // In Solana, this would need to be implemented using account creation and data storage
        return address(0);
    }

    function readSstore2(address pointer) internal view returns (bytes memory) {
        // Placeholder for SSTORE2 read functionality
        return new bytes(0);
    }

    function readSstore2(address pointer, uint64 start, uint64 end) internal view returns (bytes memory) {
        // Placeholder for SSTORE2 read with offset functionality
        return new bytes(0);
    }
}
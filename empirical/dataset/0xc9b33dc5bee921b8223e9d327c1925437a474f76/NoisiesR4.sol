// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

struct NoisieTraits {
    uint8 gender; uint8 skinIdx; uint8 hairCI; uint8 faceShape;
    uint8 hairStyle; uint8 browStyle; uint8 eyeStyle; uint8 eyeSize;
    uint8 noseStyle; uint8 lipStyle; uint8 lipFull; uint8 expr;
    uint8 acc; uint8 glasses; uint8 beard; uint8 makeup;
    uint8 freckles; uint8 age; uint8 mole; uint8 scar;
    uint8 dimples; uint8 chinShape;
}

interface IR1 { function render(NoisieTraits memory t, uint256 seed) external pure returns (string memory); }
interface IR2 { function render(NoisieTraits memory t) external pure returns (string memory); }
interface IR3 { function render(NoisieTraits memory t, uint256 seed) external pure returns (string memory); }

contract NoisiesR4 {
    address public owner;
    address public r1; address public r2; address public r3;

    string[8] private SKIN_N  = ["Porcelain","Fair","Light","Medium","Tan","Warm","Deep","Dark"];
    string[6] private HAIR_CN = ["Blonde","Light Brown","Brown","Dark Brown","Black","Silver"];
    string[5] private FACE_N  = ["Oval","Round","Square","Heart","Long"];
    string[12] private HAIR_N = ["Short Neat","Wavy","Long","Afro","Buzz Cut","Spiky","Curly","Slick Back","Bun","Braids","Undercut","Pixie"];
    string[6] private BROW_N  = ["Natural","Thin Arched","Thick Straight","Defined","Sparse","Bushy"];
    string[8] private EYE_N   = ["Round","Almond","Hooded","Wide","Narrow","Upturned","Downturned","Monolid"];
    string[3] private ESIZ_N  = ["Small","Medium","Large"];
    string[5] private NOSE_N  = ["Button","Straight","Wide","Upturned","Aquiline"];
    string[5] private LIP_N   = ["Thin","Cupid's Bow","Full","Wide","Small"];
    string[3] private LIPF_N  = ["Subtle","Medium","Full"];
    string[6] private EXPR_N  = ["Neutral","Smiling","Serious","Surprised","Smirking","Tired"];
    string[14] private ACC_N  = ["None","Beanie","Cap","Snapback","Hoodie","Stud Earrings","Hoop Earrings","Chain","Mask","Headphones","Bandana","Crown","Scarf","Turtleneck"];
    string[6] private GL_N    = ["None","Wire Round","Thick Square","Thin Rectangle","Sunglasses","Colored Frame"];
    string[6] private BEARD_N = ["None","5 O'Clock","Stubble","Goatee","Full Beard","Mustache"];
    string[5] private MKP_N   = ["None","Subtle","Eye Liner","Bold Lips","Full Glam"];
    string[4] private AGE_N   = ["Teen","Young Adult","Adult","Mature"];
    string[6] private MOLE_N  = ["None","Left Cheek","Right Cheek","Right Side","Forehead","Chin"];
    string[4] private SCAR_N  = ["None","Short","Long","Chin"];
    string[3] private DIM_N   = ["None","Subtle","Defined"];
    string[3] private FRCK_N  = ["None","Light","Heavy"];
    string[3] private CHIN_N  = ["Soft","Normal","Strong"];

    modifier onlyOwner() { require(msg.sender == owner); _; }
    constructor() { owner = msg.sender; }

    function setRenderers(address _r1, address _r2, address _r3) external onlyOwner {
        r1 = _r1; r2 = _r2; r3 = _r3;
    }

    function decodeTraits(uint256 tokenId, uint256 seed) public pure returns (NoisieTraits memory t) {
        uint256 h = uint256(keccak256(abi.encodePacked(tokenId, seed)));
        t.gender     = uint8(h % 2);       h >>= 1;
        t.skinIdx    = uint8(h % 8);       h >>= 3;
        t.hairCI     = uint8(h % 6);       h >>= 3;
        t.faceShape  = uint8(h % 5);       h >>= 3;
        t.hairStyle  = uint8(h % 12);      h >>= 4;
        t.browStyle  = uint8(h % 6);       h >>= 3;
        t.eyeStyle   = uint8(h % 8);       h >>= 3;
        t.eyeSize    = uint8(h % 3);       h >>= 2;
        t.noseStyle  = uint8(h % 5);       h >>= 3;
        t.lipStyle   = uint8(h % 5);       h >>= 3;
        t.lipFull    = uint8(h % 3);       h >>= 2;
        t.expr       = uint8(h % 6);       h >>= 3;
        t.acc        = uint8(h % 14);      h >>= 4;
        t.glasses    = uint8(h % 6);       h >>= 3;
        t.beard      = uint8(h % 6);       h >>= 3;
        t.makeup     = uint8(h % 5);       h >>= 3;
        t.freckles   = uint8(h % 3);       h >>= 2;
        t.age        = uint8(h % 4);       h >>= 2;
        t.mole       = uint8(h % 6);       h >>= 3;
        t.scar       = uint8(h % 4);       h >>= 2;
        t.dimples    = uint8(h % 3);       h >>= 2;
        t.chinShape  = uint8(h % 3);
    }

    function buildSVG(NoisieTraits memory t, uint256 seed) public view returns (string memory) {
        string memory grain = '<filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.72" numOctaves="2" stitchTiles="stitch" result="noise"/><feColorMatrix type="saturate" values="0" in="noise" result="grayNoise"/><feBlend in="SourceGraphic" in2="grayNoise" mode="multiply" result="blended"/><feComposite in="blended" in2="SourceGraphic" operator="in"/></filter>';
        string memory defs = string(abi.encodePacked('<defs>', grain, '</defs>'));
        string memory layer1 = IR1(r1).render(t, seed);
        string memory layer2 = IR2(r2).render(t);
        string memory layer3 = IR3(r3).render(t, seed);
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">',
            defs,
            '<g filter="url(#grain)">',
            layer1, layer2, layer3,
            '</g></svg>'
        ));
    }

    function buildMetadata(uint256 tokenId, NoisieTraits memory t, string memory svg) public view returns (string memory) {
        string memory attrs = _buildAttrs(t);
        string memory svgB64 = _b64(bytes(svg));
        string memory name = string(abi.encodePacked('Noisie #', _u(tokenId)));
        string memory desc = string(abi.encodePacked(
            'Noisie #', _u(tokenId), ' - ',
            SKIN_N[t.skinIdx], ' ', t.gender == 1 ? 'Female' : 'Male', ', ',
            HAIR_N[t.hairStyle], ' ', HAIR_CN[t.hairCI], ' hair, ',
            EXPR_N[t.expr], '. On-chain generative face.'
        ));
        string memory json = string(abi.encodePacked(
            '{"name":"', name,
            '","description":"', desc,
            '","image":"data:image/svg+xml;base64,', svgB64,
            '","attributes":', attrs, '}'
        ));
        return string(abi.encodePacked('data:application/json;base64,', _b64(bytes(json))));
    }

    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory) {
        NoisieTraits memory t = decodeTraits(tokenId, seed);
        string memory svg = buildSVG(t, seed);
        return buildMetadata(tokenId, t, svg);
    }

    function _buildAttrs(NoisieTraits memory t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '[',
            _a("Gender", t.gender == 1 ? "Female" : "Male"), ',',
            _a("Skin Tone", SKIN_N[t.skinIdx]), ',',
            _a("Face Shape", FACE_N[t.faceShape]), ',',
            _a("Hair Style", HAIR_N[t.hairStyle]), ',',
            _a("Hair Color", HAIR_CN[t.hairCI]), ',',
            _a("Eyebrows", BROW_N[t.browStyle]), ',',
            _a("Eyes", EYE_N[t.eyeStyle]), ',',
            _a("Eye Size", ESIZ_N[t.eyeSize]), ',',
            _a("Nose", NOSE_N[t.noseStyle]), ',',
            _a("Lips", LIP_N[t.lipStyle]), ',',
            _a("Expression", EXPR_N[t.expr]), ',',
            _a("Accessory", ACC_N[t.acc]), ',',
            _a("Glasses", GL_N[t.glasses]), ',',
            t.gender == 0 ? _a("Beard", BEARD_N[t.beard]) : _a("Makeup", MKP_N[t.makeup]), ',',
            _a("Age", AGE_N[t.age]), ',',
            _a("Freckles", FRCK_N[t.freckles]), ',',
            _a("Dimples", DIM_N[t.dimples]), ',',
            _a("Mole", MOLE_N[t.mole]), ',',
            _a("Scar", SCAR_N[t.scar]), ',',
            _a("Chin", CHIN_N[t.chinShape]),
            ']'
        ));
    }

    function _a(string memory k, string memory v) internal pure returns (string memory) {
        return string(abi.encodePacked('{"trait_type":"', k, '","value":"', v, '"}'));
    }

    function _b64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        bytes memory tableB = bytes(table);
        uint256 i; uint256 j;
        for (i = 0; i + 2 < len; i += 3) {
            uint256 a = uint8(data[i]); uint256 b = uint8(data[i+1]); uint256 c = uint8(data[i+2]);
            result[j]   = tableB[a >> 2];
            result[j+1] = tableB[((a & 3) << 4) | (b >> 4)];
            result[j+2] = tableB[((b & 15) << 2) | (c >> 6)];
            result[j+3] = tableB[c & 63];
            j += 4;
        }
        if (i + 1 == len) {
            uint256 a2 = uint8(data[i]);
            result[j]   = tableB[a2 >> 2];
            result[j+1] = tableB[(a2 & 3) << 4];
            result[j+2] = bytes1('=');
            result[j+3] = bytes1('=');
        } else if (i + 2 == len) {
            uint256 a3 = uint8(data[i]); uint256 b3 = uint8(data[i+1]);
            result[j]   = tableB[a3 >> 2];
            result[j+1] = tableB[((a3 & 3) << 4) | (b3 >> 4)];
            result[j+2] = tableB[(b3 & 15) << 2];
            result[j+3] = bytes1('=');
        }
        return string(result);
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory buf = new bytes(10);
        uint256 i = 10;
        while (v > 0) { buf[--i] = bytes1(uint8(48 + v % 10)); v /= 10; }
        bytes memory r = new bytes(10 - i);
        for (uint256 j = 0; j < r.length; j++) r[j] = buf[i+j];
        return string(r);
    }
}

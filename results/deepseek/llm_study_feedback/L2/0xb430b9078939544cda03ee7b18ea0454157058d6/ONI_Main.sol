// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ONI

/// @notice 4,444 Fully On-Chain Generative Low Poly Demons · Solana
//
//   ██████╗ ███╗   ██╗██╗
//  ██╔═══██╗████╗  ██║██║
//  ██║   ██║██╔██╗ ██║██║
//  ██║   ██║██║╚██╗██║██║
//  ╚██████╔╝██║ ╚████║██║
//   ╚═════╝ ╚═╝  ╚═══╝╚═╝
//
//  4,444 On-Chain Low Poly Demons · Solana

interface IR1 {
    function renderBg(uint256 id) external pure returns (string memory);
    function renderAura(uint256 id) external pure returns (string memory);
    function renderShadow() external pure returns (string memory);
    function bgName(uint256 id) external pure returns (string memory);
    function auraName(uint256 id) external pure returns (string memory);
}

interface IR2 {
    function renderLegs(uint256 id) external pure returns (string memory);
    function renderBody(uint256 id) external pure returns (string memory);
    function renderArms(uint256 id) external pure returns (string memory);
    function renderWeapon(uint256 id) external pure returns (string memory);
    function outfitName(uint256 id) external pure returns (string memory);
    function weaponName(uint256 id) external pure returns (string memory);
}

interface IR3 {
    function renderHead(uint256 id) external pure returns (string memory);
    function renderHorns(uint256 id) external pure returns (string memory);
    function renderHair(uint256 id) external pure returns (string memory);
    function headName(uint256 id) external pure returns (string memory);
    function hornName(uint256 id) external pure returns (string memory);
    function hairName(uint256 id) external pure returns (string memory);
}

interface IR3b {
    function renderEyes(uint256 id) external pure returns (string memory);
    function renderNose(uint256 id) external pure returns (string memory);
    function renderMouth(uint256 id) external pure returns (string memory);
    function renderFaceTat(uint256 id) external pure returns (string memory);
    function eyeName(uint256 id) external pure returns (string memory);
    function mouthName(uint256 id) external pure returns (string memory);
    function faceTatName(uint256 id) external pure returns (string memory);
}

interface IR4 {
    function renderNeck(uint256 id) external pure returns (string memory);
    function renderFrame(uint256 id) external pure returns (string memory);
    function renderRare(uint256 id) external pure returns (string memory);
    function buildSVGTop(string memory bg, string memory aura, string memory shadow, string memory legs, string memory body, string memory arms, string memory weapon, string memory neck, string memory head) external pure returns (string memory);
    function buildSVGBot(string memory horns, string memory hair, string memory eyes, string memory nose, string memory mouth, string memory faceTat, string memory rare, string memory frame) external pure returns (string memory);
    function buildAttributes(
        uint256 id,
        string memory skinN, string memory headN, string memory hornN,
        string memory hairN, string memory eyeN, string memory mouthN,
        string memory outfitN, string memory weaponN, string memory rarityN,
        string memory bgN, string memory auraN
    ) external pure returns (string memory);
    function skinName(uint256 id) external pure returns (string memory);
    function rarityName(uint256 id) external pure returns (string memory);
}

@program_id("11111111111111111111111111111111")
contract ONIMain {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed approved, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool approved);
    event Minted(address indexed to, uint256 indexed id);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event RoyaltyUpdated(uint256 oldBps, uint256 newBps);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event RendererUpdated(uint8 index, address newRenderer);
    event Burned(address indexed from, uint256 indexed id);

    string public constant VERSION = "1.0.0";
    uint256 public constant MAX_SUPPLY  = 4444;
    uint256 public constant FREE_SUPPLY = 3777;
    uint256 public constant MAX_PAID    = 667;

    address private _owner;
    address private _r1;
    address private _r2;
    address private _r3;
    address private _r3b;
    address private _r4;

    uint256 private _totalMinted;
    uint256 private _totalFreeMinted;
    uint256 private _totalPaidMinted;
    bool    private _paused;
    uint256 private _royaltyBps = 400;
    uint256 private _mintPrice  = 100000000000000; // 0.0001 SOL in lamports

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _approvedAll;
    mapping(address => bool) public freeMinted;
    mapping(uint256 => bool) private _burned;

    @payer(payer)
    @space(10240)
    constructor(address r1_, address r2_, address r3_, address r3b_, address r4_) {
        _owner = tx.accounts.payer.key;
        _r1 = r1_; _r2 = r2_; _r3 = r3_; _r3b = r3b_; _r4 = r4_;
    }

    modifier onlyOwner() { if (tx.accounts.payer.key != _owner) revert("NotOwner"); _; }

    function freemint() external {
        if (_paused) revert("ContractPaused");
        if (tx.accounts.payer.key == address(0)) revert("ZeroAddress");
        if (freeMinted[tx.accounts.payer.key]) revert("AlreadyFreeMinted");
        if (_totalFreeMinted >= FREE_SUPPLY) revert("FreeSoldOut");
        if (_totalMinted >= MAX_SUPPLY) revert("SoldOut");
        freeMinted[tx.accounts.payer.key] = true;
        unchecked { _totalFreeMinted++; }
        _mint(tx.accounts.payer.key);
    }

    function mint(uint256 qty) external payable {
        if (_paused) revert("ContractPaused");
        if (qty == 0 || qty > 20) revert("BadQty");
        if (_totalPaidMinted + qty > MAX_PAID) revert("SoldOut");
        if (_totalMinted + qty > MAX_SUPPLY) revert("SoldOut");
        if (tx.accounts.payer.lamports < _mintPrice * qty) revert("BadFunds");
        for (uint256 i; i < qty;) { _mint(tx.accounts.payer.key); unchecked { ++i; } }
        uint256 cost = _mintPrice * qty;
        if (tx.accounts.payer.lamports > cost) {
            tx.accounts.payer.transfer(tx.accounts.payer.lamports - cost);
        }
        unchecked { _totalPaidMinted += qty; }
    }

    function airdrop(address[] calldata tos) external onlyOwner {
        for (uint256 i; i < tos.length;) {
            if (_totalMinted >= MAX_SUPPLY) revert("SoldOut");
            if (tos[i] == address(0)) revert("ZeroAddress");
            _mint(tos[i]);
            unchecked { ++i; }
        }
    }

    function burn(uint256 id) external {
        if (ownerOf(id) != tx.accounts.payer.key) revert("NoAuth");
        _burned[id] = true;
        unchecked { _balances[tx.accounts.payer.key]--; }
        delete _owners[id];
        delete _approved[id];
        emit Transfer(tx.accounts.payer.key, address(0), id);
        emit Burned(tx.accounts.payer.key, id);
    }

    function _mint(address to) private {
        uint256 id = _totalMinted;
        _owners[id] = to;
        unchecked { _balances[to]++; _totalMinted++; }
        emit Transfer(address(0), to, id);
        emit Minted(to, id);
    }

    function totalSupply() public view returns (uint256) { return _totalMinted; }
    function totalFreeMinted() public view returns (uint256) { return _totalFreeMinted; }
    function totalPaidMinted() public view returns (uint256) { return _totalPaidMinted; }
    function freeRemaining() public view returns (uint256) { return FREE_SUPPLY - _totalFreeMinted; }
    function paidRemaining() public view returns (uint256) { return MAX_PAID - _totalPaidMinted; }
    function mintPrice() public view returns (uint256) { return _mintPrice; }
    function isPaused() public view returns (bool) { return _paused; }
    function owner() public view returns (address) { return _owner; }
    function name() public pure returns (string memory) { return "ONI"; }
    function symbol() public pure returns (string memory) { return "ONI"; }
    function tokenExists(uint256 id) public view returns (bool) { return id < _totalMinted && !_burned[id]; }
    function isBurned(uint256 id) public view returns (bool) { return _burned[id]; }

    function ownerOf(uint256 id) public view returns (address o) {
        if (id >= _totalMinted || _burned[id]) revert("NoToken");
        for (uint256 i = id;;) {
            o = _owners[i];
            if (o != address(0)) return o;
            unchecked { --i; }
        }
    }

    function balanceOf(address a) public view returns (uint256) { return _balances[a]; }
    function getApproved(uint256 id) public view returns (address) {
        if (!tokenExists(id)) revert("NoToken");
        return _approved[id];
    }
    function isApprovedForAll(address a, address b) public view returns (bool) { return _approvedAll[a][b]; }

    function tokensOfOwner(address addr) public view returns (uint256[] memory) {
        uint256 bal = _balances[addr];
        uint256[] memory tokens = new uint256[](bal);
        uint256 idx;
        for (uint256 i; i < _totalMinted && idx < bal;) {
            if (tokenExists(i) && ownerOf(i) == addr) {
                tokens[idx] = i;
                unchecked { idx++; }
            }
            unchecked { ++i; }
        }
        return tokens;
    }

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(
            'data:application/json,{"name":"ONI","description":"4,444 fully on-chain generative low poly demons on Solana. No IPFS. No servers. Pure on-chain art.","external_link":"https://oni.xyz","seller_fee_basis_points":',
            _n(_royaltyBps),
            ',"fee_recipient":"',_toHex(uint160(_owner)),'"}'));
    }

    function _toHex(uint160 v) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i; i < 20;) {
            uint8 b = uint8(v >> (8 * (19 - i)));
            s[i*2]   = _hexChar(b >> 4);
            s[i*2+1] = _hexChar(b & 0xf);
            unchecked { ++i; }
        }
        return string(s);
    }

    function _hexChar(uint8 v) internal pure returns (bytes1) {
        return v < 10 ? bytes1(48 + v) : bytes1(87 + v);
    }

    function _n(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    function approve(address to, uint256 id) public {
        address o = ownerOf(id);
        if (tx.accounts.payer.key != o && !_approvedAll[o][tx.accounts.payer.key]) revert("NoAuth");
        _approved[id] = to;
        emit Approval(o, to, id);
    }

    function setApprovalForAll(address op, bool ok) public {
        _approvedAll[tx.accounts.payer.key][op] = ok;
        emit ApprovalForAll(tx.accounts.payer.key, op, ok);
    }

    function transferFrom(address f, address t, uint256 id) public { _xfer(f, t, id); }
    function safeTransferFrom(address f, address t, uint256 id) public { _xfer(f, t, id); }
    function safeTransferFrom(address f, address t, uint256 id, bytes calldata) public { _xfer(f, t, id); }

    function _xfer(address f, address t, uint256 id) private {
        if (ownerOf(id) != f) revert("BadXfer");
        if (tx.accounts.payer.key != f && !_approvedAll[f][tx.accounts.payer.key] && _approved[id] != tx.accounts.payer.key) revert("NoAuth");
        if (t == address(0)) revert("ZeroAddress");
        delete _approved[id];
        unchecked { --_balances[f]; ++_balances[t]; }
        _owners[id] = t;
        uint256 nx = id + 1;
        if (nx < _totalMinted && _owners[nx] == address(0)) _owners[nx] = f;
        emit Transfer(f, t, id);
    }

    function setPaused(bool p) external onlyOwner {
        _paused = p;
        if (p) emit Paused(tx.accounts.payer.key);
        else emit Unpaused(tx.accounts.payer.key);
    }

    function setPrice(uint256 price) external onlyOwner {
        emit PriceUpdated(_mintPrice, price);
        _mintPrice = price;
    }

    function setRoyalty(uint256 bps) external onlyOwner {
        if (bps > 1000) revert("InvalidRoyalty");
        emit RoyaltyUpdated(_royaltyBps, bps);
        _royaltyBps = bps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert("ZeroAddress");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function setRenderer(uint8 index, address renderer) external onlyOwner {
        if (index == 1) _r1 = renderer;
        else if (index == 2) _r2 = renderer;
        else if (index == 3) _r3 = renderer;
        else if (index == 4) _r3b = renderer;
        else if (index == 5) _r4 = renderer;
        emit RendererUpdated(index, renderer);
    }

    function withdraw() external onlyOwner {
        tx.accounts.payer.transfer(tx.accounts.payer.lamports);
    }

    function royaltyInfo(uint256, uint256 s) external view returns (address, uint256) {
        return (_owner, s * _royaltyBps / 10000);
    }

    function supportsInterface(bytes4 x) public pure returns (bool) {
        return x == 0x01ffc9a7 || x == 0x80ac58cd || x == 0x5b5e139f || x == 0x2a55205a;
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        if (!tokenExists(id)) revert("NoToken");
        address r1 = _r1; address r2 = _r2;
        address r3 = _r3; address r3b = _r3b; address r4 = _r4;
        string memory svgTop = IR4(r4).buildSVGTop(
            IR1(r1).renderBg(id), IR1(r1).renderAura(id), IR1(r1).renderShadow(),
            IR2(r2).renderLegs(id), IR2(r2).renderBody(id), IR2(r2).renderArms(id),
            IR2(r2).renderWeapon(id), IR4(r4).renderNeck(id), IR3(r3).renderHead(id)
        );
        string memory svgBot = IR4(r4).buildSVGBot(
            IR3(r3).renderHorns(id), IR3(r3).renderHair(id), IR3b(r3b).renderEyes(id),
            IR3b(r3b).renderNose(id), IR3b(r3b).renderMouth(id), IR3b(r3b).renderFaceTat(id),
            IR4(r4).renderRare(id), IR4(r4).renderFrame(id)
        );
        string memory svg = string(abi.encodePacked(svgTop, svgBot));
        string memory attrs = IR4(r4).buildAttributes(
            id,
            IR4(r4).skinName(id), IR3(r3).headName(id), IR3(r3).hornName(id),
            IR3(r3).hairName(id), IR3b(r3b).eyeName(id), IR3b(r3b).mouthName(id),
            IR2(r2).outfitName(id), IR2(r2).weaponName(id), IR4(r4).rarityName(id),
            IR1(r1).bgName(id), IR1(r1).auraName(id)
        );
        string memory json = string(abi.encodePacked(
            '{"name":"ONI #', _n(id),
            '","description":"4,444 fully on-chain generative low poly demons on Solana. No IPFS. No servers.","image":"data:image/svg+xml,',
            svg, '","attributes":', attrs, '}'
        ));
        return string(abi.encodePacked('data:application/json,', json));
    }
}
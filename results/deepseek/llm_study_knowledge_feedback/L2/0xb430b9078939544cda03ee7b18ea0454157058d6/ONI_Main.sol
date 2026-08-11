// SPDX-License-Identifier: MIT

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

import 'solana';

interface IR1 {
    function renderBg(uint64 id) external pure returns (string memory);
    function renderAura(uint64 id) external pure returns (string memory);
    function renderShadow() external pure returns (string memory);
    function bgName(uint64 id) external pure returns (string memory);
    function auraName(uint64 id) external pure returns (string memory);
}

interface IR2 {
    function renderLegs(uint64 id) external pure returns (string memory);
    function renderBody(uint64 id) external pure returns (string memory);
    function renderArms(uint64 id) external pure returns (string memory);
    function renderWeapon(uint64 id) external pure returns (string memory);
    function outfitName(uint64 id) external pure returns (string memory);
    function weaponName(uint64 id) external pure returns (string memory);
}

interface IR3 {
    function renderHead(uint64 id) external pure returns (string memory);
    function renderHorns(uint64 id) external pure returns (string memory);
    function renderHair(uint64 id) external pure returns (string memory);
    function headName(uint64 id) external pure returns (string memory);
    function hornName(uint64 id) external pure returns (string memory);
    function hairName(uint64 id) external pure returns (string memory);
}

interface IR3b {
    function renderEyes(uint64 id) external pure returns (string memory);
    function renderNose(uint64 id) external pure returns (string memory);
    function renderMouth(uint64 id) external pure returns (string memory);
    function renderFaceTat(uint64 id) external pure returns (string memory);
    function eyeName(uint64 id) external pure returns (string memory);
    function mouthName(uint64 id) external pure returns (string memory);
    function faceTatName(uint64 id) external pure returns (string memory);
}

interface IR4 {
    function renderNeck(uint64 id) external pure returns (string memory);
    function renderFrame(uint64 id) external pure returns (string memory);
    function renderRare(uint64 id) external pure returns (string memory);
    function buildSVGTop(string memory bg, string memory aura, string memory shadow, string memory legs, string memory body, string memory arms, string memory weapon, string memory neck, string memory head) external pure returns (string memory);
    function buildSVGBot(string memory horns, string memory hair, string memory eyes, string memory nose, string memory mouth, string memory faceTat, string memory rare, string memory frame) external pure returns (string memory);
    function buildAttributes(
        uint64 id,
        string memory skinN, string memory headN, string memory hornN,
        string memory hairN, string memory eyeN, string memory mouthN,
        string memory outfitN, string memory weaponN, string memory rarityN,
        string memory bgN, string memory auraN
    ) external pure returns (string memory);
    function skinName(uint64 id) external pure returns (string memory);
    function rarityName(uint64 id) external pure returns (string memory);
}

@program_id("11111111111111111111111111111111")
contract ONIMain {
    event Transfer(address indexed from, address indexed to, uint64 indexed id);
    event Approval(address indexed owner, address indexed approved, uint64 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool approved);
    event Minted(address indexed to, uint64 indexed id);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event RoyaltyUpdated(uint64 oldBps, uint64 newBps);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PriceUpdated(uint64 oldPrice, uint64 newPrice);
    event RendererUpdated(uint8 index, address newRenderer);
    event Burned(address indexed from, uint64 indexed id);

    string public constant VERSION = "1.0.0";
    uint64 public constant MAX_SUPPLY  = 4444;
    uint64 public constant FREE_SUPPLY = 3777;
    uint64 public constant MAX_PAID    = 667;

    address private _owner;
    address private _r1;
    address private _r2;
    address private _r3;
    address private _r3b;
    address private _r4;

    uint64 private _totalMinted;
    uint64 private _totalFreeMinted;
    uint64 private _totalPaidMinted;
    bool    private _paused;
    uint64 private _royaltyBps = 400;
    uint64 private _mintPrice  = 100000000000000; // 0.0001 SOL in lamports

    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _approved;
    mapping(address => mapping(address => bool)) private _approvedAll;
    mapping(address => bool) public freeMinted;
    mapping(uint64 => bool) private _burned;

    @payer(payer)
    @space(10240)
    constructor(address r1_, address r2_, address r3_, address r3b_, address r4_) {
        _owner = tx.accounts.payer.key;
        _r1 = r1_; _r2 = r2_; _r3 = r3_; _r3b = r3b_; _r4 = r4_;
    }

    modifier onlyOwner() { require(tx.accounts.payer.key == _owner, "NotOwner"); _; }

    function freemint() external {
        require(!_paused, "ContractPaused");
        require(tx.accounts.payer.key != address(0), "ZeroAddress");
        require(!freeMinted[tx.accounts.payer.key], "AlreadyFreeMinted");
        require(_totalFreeMinted < FREE_SUPPLY, "FreeSoldOut");
        require(_totalMinted < MAX_SUPPLY, "SoldOut");
        freeMinted[tx.accounts.payer.key] = true;
        unchecked { _totalFreeMinted++; }
        _mint(tx.accounts.payer.key);
    }

    function mint(uint64 qty) external {
        require(!_paused, "ContractPaused");
        require(qty > 0 && qty <= 20, "BadQty");
        require(_totalPaidMinted + qty <= MAX_PAID, "SoldOut");
        require(_totalMinted + qty <= MAX_SUPPLY, "SoldOut");
        uint64 cost = _mintPrice * qty;
        require(tx.accounts.payer.lamports() >= cost, "BadFunds");
        for (uint64 i = 0; i < qty;) { _mint(tx.accounts.payer.key); unchecked { ++i; } }
        unchecked { _totalPaidMinted += qty; }
    }

    function airdrop(address[] calldata tos) external onlyOwner {
        for (uint64 i = 0; i < tos.length;) {
            require(_totalMinted < MAX_SUPPLY, "SoldOut");
            require(tos[i] != address(0), "ZeroAddress");
            _mint(tos[i]);
            unchecked { ++i; }
        }
    }

    function burn(uint64 id) external {
        require(ownerOf(id) == tx.accounts.payer.key, "NoAuth");
        _burned[id] = true;
        unchecked { _balances[tx.accounts.payer.key]--; }
        delete _owners[id];
        delete _approved[id];
        emit Transfer(tx.accounts.payer.key, address(0), id);
        emit Burned(tx.accounts.payer.key, id);
    }

    function _mint(address to) private {
        uint64 id = _totalMinted;
        _owners[id] = to;
        unchecked { _balances[to]++; _totalMinted++; }
        emit Transfer(address(0), to, id);
        emit Minted(to, id);
    }

    function totalSupply() public view returns (uint64) { return _totalMinted; }
    function totalFreeMinted() public view returns (uint64) { return _totalFreeMinted; }
    function totalPaidMinted() public view returns (uint64) { return _totalPaidMinted; }
    function freeRemaining() public view returns (uint64) { return FREE_SUPPLY - _totalFreeMinted; }
    function paidRemaining() public view returns (uint64) { return MAX_PAID - _totalPaidMinted; }
    function mintPrice() public view returns (uint64) { return _mintPrice; }
    function isPaused() public view returns (bool) { return _paused; }
    function owner() public view returns (address) { return _owner; }
    function name() public pure returns (string memory) { return "ONI"; }
    function symbol() public pure returns (string memory) { return "ONI"; }
    function tokenExists(uint64 id) public view returns (bool) { return id < _totalMinted && !_burned[id]; }
    function isBurned(uint64 id) public view returns (bool) { return _burned[id]; }

    function ownerOf(uint64 id) public view returns (address o) {
        require(id < _totalMinted && !_burned[id], "NoToken");
        for (uint64 i = id;;) {
            o = _owners[i];
            if (o != address(0)) return o;
            unchecked { --i; }
        }
    }

    function balanceOf(address a) public view returns (uint64) { return _balances[a]; }
    function getApproved(uint64 id) public view returns (address) {
        require(tokenExists(id), "NoToken");
        return _approved[id];
    }
    function isApprovedForAll(address a, address b) public view returns (bool) { return _approvedAll[a][b]; }

    function tokensOfOwner(address addr) public view returns (uint64[] memory) {
        uint64 bal = _balances[addr];
        uint64[] memory tokens = new uint64[](bal);
        uint64 idx = 0;
        for (uint64 i = 0; i < _totalMinted && idx < bal;) {
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
            ',"fee_recipient":"',_toHex(_owner),'"}'));
    }

    function _toHex(address v) internal pure returns (string memory) {
        bytes memory s = new bytes(64);
        bytes32 addrBytes = bytes32(uint256(uint160(v)));
        for (uint64 i = 0; i < 32;) {
            uint8 b = uint8(addrBytes[i]);
            s[i*2]   = _hexChar(b >> 4);
            s[i*2+1] = _hexChar(b & 0xf);
            unchecked { ++i; }
        }
        return string(s);
    }

    function _hexChar(uint8 v) internal pure returns (bytes1) {
        return v < 10 ? bytes1(48 + v) : bytes1(87 + v);
    }

    function _n(uint64 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint64 tmp = v; uint64 len = 0;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    function approve(address to, uint64 id) public {
        address o = ownerOf(id);
        require(tx.accounts.payer.key == o || _approvedAll[o][tx.accounts.payer.key], "NoAuth");
        _approved[id] = to;
        emit Approval(o, to, id);
    }

    function setApprovalForAll(address op, bool ok) public {
        _approvedAll[tx.accounts.payer.key][op] = ok;
        emit ApprovalForAll(tx.accounts.payer.key, op, ok);
    }

    function transferFrom(address f, address t, uint64 id) public { _xfer(f, t, id); }
    function safeTransferFrom(address f, address t, uint64 id) public { _xfer(f, t, id); }
    function safeTransferFrom(address f, address t, uint64 id, bytes calldata) public { _xfer(f, t, id); }

    function _xfer(address f, address t, uint64 id) private {
        require(ownerOf(id) == f, "BadXfer");
        require(tx.accounts.payer.key == f || _approvedAll[f][tx.accounts.payer.key] || _approved[id] == tx.accounts.payer.key, "NoAuth");
        require(t != address(0), "ZeroAddress");
        delete _approved[id];
        unchecked { --_balances[f]; ++_balances[t]; }
        _owners[id] = t;
        uint64 nx = id + 1;
        if (nx < _totalMinted && _owners[nx] == address(0)) _owners[nx] = f;
        emit Transfer(f, t, id);
    }

    function setPaused(bool p) external onlyOwner {
        _paused = p;
        if (p) emit Paused(tx.accounts.payer.key);
        else emit Unpaused(tx.accounts.payer.key);
    }

    function setPrice(uint64 price) external onlyOwner {
        emit PriceUpdated(_mintPrice, price);
        _mintPrice = price;
    }

    function setRoyalty(uint64 bps) external onlyOwner {
        require(bps <= 1000, "InvalidRoyalty");
        emit RoyaltyUpdated(_royaltyBps, bps);
        _royaltyBps = bps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZeroAddress");
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
        uint64 bal = tx.accounts.dataAccount.lamports();
        tx.accounts.dataAccount.transfer_lamports(_owner, bal);
    }

    function royaltyInfo(uint64, uint64 s) external view returns (address, uint64) {
        return (_owner, s * _royaltyBps / 10000);
    }

    function supportsInterface(bytes4 x) public pure returns (bool) {
        return x == 0x01ffc9a7 || x == 0x80ac58cd || x == 0x5b5e139f || x == 0x2a55205a;
    }

    function tokenURI(uint64 id) public view returns (string memory) {
        require(tokenExists(id), "NoToken");
        string memory svgTop = IR4(_r4).buildSVGTop(
            IR1(_r1).renderBg(id), IR1(_r1).renderAura(id), IR1(_r1).renderShadow(),
            IR2(_r2).renderLegs(id), IR2(_r2).renderBody(id), IR2(_r2).renderArms(id),
            IR2(_r2).renderWeapon(id), IR4(_r4).renderNeck(id), IR3(_r3).renderHead(id)
        );
        string memory svgBot = IR4(_r4).buildSVGBot(
            IR3(_r3).renderHorns(id), IR3(_r3).renderHair(id), IR3b(_r3b).renderEyes(id),
            IR3b(_r3b).renderNose(id), IR3b(_r3b).renderMouth(id), IR3b(_r3b).renderFaceTat(id),
            IR4(_r4).renderRare(id), IR4(_r4).renderFrame(id)
        );
        string memory svg = string(abi.encodePacked(svgTop, svgBot));
        string memory attrs = IR4(_r4).buildAttributes(
            id,
            IR4(_r4).skinName(id), IR3(_r3).headName(id), IR3(_r3).hornName(id),
            IR3(_r3).hairName(id), IR3b(_r3b).eyeName(id), IR3b(_r3b).mouthName(id),
            IR2(_r2).outfitName(id), IR2(_r2).weaponName(id), IR4(_r4).rarityName(id),
            IR1(_r1).bgName(id), IR1(_r1).auraName(id)
        );
        string memory json = string(abi.encodePacked(
            '{"name":"ONI #', _n(id),
            '","description":"4,444 fully on-chain generative low poly demons on Solana. No IPFS. No servers.","image":"data:image/svg+xml,',
            svg, '","attributes":', attrs, '}'
        ));
        return string(abi.encodePacked('data:application/json,', json));
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TOLLBOUND local proof contract
/// @notice Local-first ERC721-style proof for mint pricing, free mint controls, Free Will, reroll, evolve, inscription, ERC-4906, tokenURI, and withdraw.
contract Tollbound {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MetadataUpdate(uint256 _tokenId);
    event FateChanged(uint256 indexed tokenId, uint256 oldSeed, uint256 newSeed, bool usedFreeWill);
    event Evolved(uint256 indexed targetTokenId, uint256 indexed burnedTokenId, uint8 newTier);
    event InscriptionUpdated(uint256 indexed tokenId, string text, uint8 borderId, uint8 fontId, uint8 colorId, bool usedFreeWill);
    event MetadataRefreshRequested(uint256 indexed tokenId);
    event Withdraw(address indexed to, uint256 amount);

    uint256 public constant MAX_SUPPLY = 10_000;
    uint8 public constant TIER_COMMON = 0;
    uint8 public constant TIER_MARKED = 1;
    uint8 public constant TIER_ORACLE = 2;
    uint8 public constant TIER_ASCENDED = 3;
    uint8 public constant TIER_UNBOUND = 4;

    string public name = "TOLLBOUND";
    string public symbol = "TOLL";
    address public owner;

    bool public saleActive;
    bool public freeMintActive;
    bool public useTieredPricing;
    uint256 public flatMintPrice = 0.00008 ether;
    uint256 public rerollFee = 0.00005 ether;
    uint256 public inscriptionFee = 0.00005 ether;
    uint256 public maxFreeSupply = 500;
    uint256 public maxFreePerWallet = 1;
    uint256 public maxPerTx = 10;
    uint256 public maxTotalPerWallet = 100;
    uint256 public freeMintedTotal;
    uint256 public totalMinted;
    uint256 public totalBurned;

    uint256[] public priceThresholds;
    uint256[] public priceValues;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(address => uint256) public mintedByWallet;
    mapping(address => uint256) public freeMintedByWallet;

    struct TokenData {
        uint8 tier;
        uint8 variant;
        bool freeWill;
        bool freeWillSpent;
        uint32 rerollCount;
        uint256 seed;
        string inscription;
        uint8 borderId;
        uint8 fontId;
        uint8 colorId;
    }

    mapping(uint256 => TokenData) public tokenData;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyTokenOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender);
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
        priceThresholds.push(2000);
        priceValues.push(0.00008 ether);
        priceThresholds.push(5000);
        priceValues.push(0.00018 ether);
        priceThresholds.push(8000);
        priceValues.push(0.00035 ether);
        priceThresholds.push(9500);
        priceValues.push(0.00070 ether);
        priceThresholds.push(MAX_SUPPLY);
        priceValues.push(0.00140 ether);
    }

    receive() external payable {}

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f || interfaceId == 0x49064906;
    }

    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0));
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0));
        return tokenOwner;
    }

    function totalSupply() public view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
    }

    function setFreeMintActive(bool active) external onlyOwner {
        freeMintActive = active;
    }

    function setFlatMintPrice(uint256 price) external onlyOwner {
        flatMintPrice = price;
    }

    function setPricingMode(bool tiered) external onlyOwner {
        useTieredPricing = tiered;
    }

    function setPriceTiers(uint256[] calldata thresholds, uint256[] calldata prices) external onlyOwner {
        require(thresholds.length == prices.length && thresholds.length > 0 && thresholds.length <= 10);
        uint256 previous;
        delete priceThresholds;
        delete priceValues;
        for (uint256 i; i < thresholds.length; ++i) {
            require(thresholds[i] > previous && thresholds[i] <= MAX_SUPPLY);
            previous = thresholds[i];
            priceThresholds.push(thresholds[i]);
            priceValues.push(prices[i]);
        }
        require(priceThresholds[priceThresholds.length - 1] == MAX_SUPPLY);
    }

    function setMintControls(uint256 _maxFreeSupply, uint256 _maxFreePerWallet, uint256 _maxPerTx, uint256 _maxTotalPerWallet) external onlyOwner {
        require(_maxFreeSupply <= MAX_SUPPLY);
        require(_maxPerTx > 0 && _maxPerTx <= 50);
        require(_maxTotalPerWallet >= _maxFreePerWallet);
        maxFreeSupply = _maxFreeSupply;
        maxFreePerWallet = _maxFreePerWallet;
        maxPerTx = _maxPerTx;
        maxTotalPerWallet = _maxTotalPerWallet;
    }

    function setUtilityFees(uint256 _rerollFee, uint256 _inscriptionFee) external onlyOwner {
        rerollFee = _rerollFee;
        inscriptionFee = _inscriptionFee;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || isApprovedForAll[tokenOwner][msg.sender]);
        getApproved[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId));
        require(ownerOf(tokenId) == from);
        require(to != address(0));
        delete getApproved[tokenId];
        unchecked {
            _balances[from]--;
            _balances[to]++;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return spender == tokenOwner || getApproved[tokenId] == spender || isApprovedForAll[tokenOwner][spender];
    }

    function priceForTokenNumber(uint256 tokenNumber) public view returns (uint256) {
        if (!useTieredPricing) return flatMintPrice;
        for (uint256 i; i < priceThresholds.length; ++i) {
            if (tokenNumber <= priceThresholds[i]) return priceValues[i];
        }
        return priceValues[priceValues.length - 1];
    }

    function quoteMint(address minter, uint256 quantity) public view returns (uint256 price, uint256 freeCount, uint256 paidCount) {
        require(quantity > 0 && quantity <= maxPerTx);
        require(totalMinted + quantity <= MAX_SUPPLY);
        require(mintedByWallet[minter] + quantity <= maxTotalPerWallet);
        uint256 remainingFreeWallet = maxFreePerWallet > freeMintedByWallet[minter] ? maxFreePerWallet - freeMintedByWallet[minter] : 0;
        uint256 remainingFreeSupply = maxFreeSupply > freeMintedTotal ? maxFreeSupply - freeMintedTotal : 0;
        for (uint256 i; i < quantity; ++i) {
            if (freeMintActive && remainingFreeWallet > 0 && remainingFreeSupply > 0) {
                unchecked { --remainingFreeWallet; --remainingFreeSupply; ++freeCount; }
            } else {
                unchecked { ++paidCount; }
                price += priceForTokenNumber(totalMinted + i + 1);
            }
        }
    }

    function mint(uint256 quantity) external payable {
        require(saleActive);
        (uint256 requiredPrice, uint256 freeCount, ) = quoteMint(msg.sender, quantity);
        require(msg.value >= requiredPrice);
        if (freeCount > 0) {
            freeMintedTotal += freeCount;
            freeMintedByWallet[msg.sender] += freeCount;
        }
        mintedByWallet[msg.sender] += quantity;
        _mintTokens(msg.sender, quantity);
        if (msg.value > requiredPrice) payable(msg.sender).transfer(msg.value - requiredPrice);
    }

    function devMint(address to, uint256 quantity) external onlyOwner {
        require(to != address(0));
        require(quantity > 0 && totalMinted + quantity <= MAX_SUPPLY);
        _mintTokens(to, quantity);
    }

    function _mintTokens(address to, uint256 quantity) internal {
        for (uint256 i; i < quantity; ++i) {
            uint256 tokenId = totalMinted + 1;
            totalMinted = tokenId;
            _owners[tokenId] = to;
            unchecked { _balances[to]++; }
            _initToken(tokenId, to);
            emit Transfer(address(0), to, tokenId);
        }
    }

    function _initToken(uint256 tokenId, address minter) internal {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, minter, tokenId, address(this))));
        uint256 roll = seed % 10_000;
        uint8 tier;
        if (roll < 7000) tier = TIER_COMMON;
        else if (roll < 9100) tier = TIER_MARKED;
        else if (roll < 9900) tier = TIER_ORACLE;
        else tier = TIER_ASCENDED;
        tokenData[tokenId] = TokenData({
            tier: tier,
            variant: uint8((seed >> 16) % 12),
            freeWill: ((seed >> 32) % 100) < 25,
            freeWillSpent: false,
            rerollCount: 0,
            seed: seed,
            inscription: "",
            borderId: 0,
            fontId: 0,
            colorId: 0
        });
    }

    function reroll(uint256 tokenId) external payable onlyTokenOwner(tokenId) {
        TokenData storage data = tokenData[tokenId];
        bool usedFreeWill = _consumeFreeWill(data);
        if (!usedFreeWill) require(msg.value >= rerollFee);
        uint256 oldSeed = data.seed;
        data.seed = uint256(keccak256(abi.encodePacked(oldSeed, block.timestamp, msg.sender, data.rerollCount)));
        data.variant = uint8(data.seed % 12);
        unchecked { data.rerollCount++; }
        emit FateChanged(tokenId, oldSeed, data.seed, usedFreeWill);
        emit MetadataUpdate(tokenId);
        if (!usedFreeWill && msg.value > rerollFee) payable(msg.sender).transfer(msg.value - rerollFee);
    }

    function evolve(uint256 targetTokenId, uint256 burnTokenId) external onlyTokenOwner(targetTokenId) {
        require(targetTokenId != burnTokenId);
        require(ownerOf(burnTokenId) == msg.sender);
        TokenData storage target = tokenData[targetTokenId];
        require(target.tier < TIER_UNBOUND);
        _burn(burnTokenId);
        unchecked { target.tier++; }
        target.seed = uint256(keccak256(abi.encodePacked(target.seed, burnTokenId, target.tier, "EVOLVE")));
        target.variant = uint8(target.seed % 12);
        emit Evolved(targetTokenId, burnTokenId, target.tier);
        emit MetadataUpdate(targetTokenId);
    }

    function setInscription(uint256 tokenId, string calldata text, uint8 borderId, uint8 fontId, uint8 colorId) external payable onlyTokenOwner(tokenId) {
        require(bytes(text).length <= 16);
        require(borderId < 5 && fontId < 4 && colorId < 5);
        _validateText(text);
        TokenData storage data = tokenData[tokenId];
        bool usedFreeWill = _consumeFreeWill(data);
        if (!usedFreeWill) require(msg.value >= inscriptionFee);
        data.inscription = text;
        data.borderId = borderId;
        data.fontId = fontId;
        data.colorId = colorId;
        emit InscriptionUpdated(tokenId, text, borderId, fontId, colorId, usedFreeWill);
        emit MetadataUpdate(tokenId);
        if (!usedFreeWill && msg.value > inscriptionFee) payable(msg.sender).transfer(msg.value - inscriptionFee);
    }

    function refreshMetadata(uint256 tokenId) external {
        require(_owners[tokenId] != address(0));
        emit MetadataRefreshRequested(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function withdraw(address payable to) external onlyOwner {
        require(to != address(0));
        uint256 amount = address(this).balance;
        require(amount > 0);
        (bool ok, ) = to.call{value: amount}("");
        require(ok);
        emit Withdraw(to, amount);
    }

    function _consumeFreeWill(TokenData storage data) internal returns (bool) {
        if (data.freeWill && !data.freeWillSpent) {
            data.freeWillSpent = true;
            return true;
        }
        return false;
    }

    function _burn(uint256 tokenId) internal {
        address tokenOwner = ownerOf(tokenId);
        delete getApproved[tokenId];
        unchecked {
            _balances[tokenOwner]--;
            totalBurned++;
        }
        delete _owners[tokenId];
        delete tokenData[tokenId];
        emit Transfer(tokenOwner, address(0), tokenId);
        emit MetadataUpdate(tokenId);
    }

    function _validateText(string calldata text) internal pure {
        bytes calldata b = bytes(text);
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            bool ok = c == 0x20 || (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A);
            require(ok);
        }
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0));
        TokenData memory data = tokenData[tokenId];
        string memory svg = _svg(tokenId, data);
        string memory json = string.concat(
            '{"name":"TOLLBOUND #', _toString(tokenId),
            '","description":"On-chain PFP. Change fate, burn, inscribe.","image":"data:image/svg+xml;base64,',
            _base64(bytes(svg)), '","attributes":[', _attrs(data), ']}');
        return string.concat("data:application/json;base64,", _base64(bytes(json)));
    }

    function _attrs(TokenData memory data) internal pure returns (string memory) {
        string memory fw = data.freeWill ? (data.freeWillSpent ? "Spent" : "Unused") : "None";
        string memory inscribed = bytes(data.inscription).length == 0 ? "None" : "Inscribed";
        return string.concat(
            string.concat(
                '{"trait_type":"Tier","value":"', _tierName(data.tier), '"},',
                '{"trait_type":"Stage","value":', _toString(data.tier), '},',
                '{"trait_type":"Free Will","value":"', fw, '"},',
                '{"trait_type":"Inscribed","value":"', inscribed, '"},',
                '{"trait_type":"Inscription","value":"', bytes(data.inscription).length == 0 ? "None" : data.inscription, '"},'
            ),
            string.concat(
                '{"trait_type":"Border","value":"', _borderTrait(data.borderId), '"},',
                '{"trait_type":"Font","value":"', _fontTrait(data.fontId), '"},',
                '{"trait_type":"Color","value":"', _colorTrait(data.colorId), '"},',
                '{"trait_type":"Rerolls","value":', _toString(data.rerollCount), '},',
                '{"trait_type":"Mask","value":"', _maskTrait(data.variant), '"},'
            ),
            string.concat(
                '{"trait_type":"Eyes","value":"', _eyesTrait(data.variant), '"},',
                '{"trait_type":"Mouth","value":"', _mouthTrait(data.variant), '"},',
                '{"trait_type":"Bg","value":"', _bgTrait(data.tier), '"},',
                '{"trait_type":"Palette","value":"', _paletteTrait(data.seed), '"},',
                '{"trait_type":"Burned","value":', _toString(data.tier), '}'
            )
        );
    }

    function _borderTrait(uint8 id) internal pure returns (string memory) {
        if (id == 1) return "Debt Stamp";
        if (id == 2) return "Oracle Frame";
        if (id == 3) return "Burned Tag";
        if (id == 4) return "Glitch Seal";
        return "Clean Plate";
    }

    function _fontTrait(uint8 id) internal pure returns (string memory) {
        if (id == 1) return "Heavy Stamp";
        if (id == 2) return "Terminal";
        if (id == 3) return "Rune Block";
        return "Mono";
    }

    function _colorTrait(uint8 id) internal pure returns (string memory) {
        if (id == 1) return "Tribute Red";
        if (id == 2) return "Oracle Gold";
        if (id == 3) return "Void White";
        if (id == 4) return "Ascended Violet";
        return "Gate Cyan";
    }

    function _maskTrait(uint8 v) internal pure returns (string memory) {
        uint8 x = v % 4;
        if (x == 0) return "Relic";
        if (x == 1) return "Fang";
        if (x == 2) return "Gate";
        return "Wraith";
    }

    function _eyesTrait(uint8 v) internal pure returns (string memory) {
        uint8 x = v % 3;
        if (x == 0) return "Twin";
        if (x == 1) return "Star";
        return "Oracle";
    }

    function _mouthTrait(uint8 v) internal pure returns (string memory) {
        uint8 x = v % 4;
        if (x == 0) return "Grin";
        if (x == 1) return "Teeth";
        if (x == 2) return "Void";
        return "Silent";
    }

    function _bgTrait(uint8 tier) internal pure returns (string memory) {
        if (tier == 2) return "Oracle Parchment";
        if (tier == 3) return "Ascended Void";
        if (tier == 4) return "Unbound Gate";
        return "Dark Gate";
    }

    function _paletteTrait(uint256 seed) internal pure returns (string memory) {
        uint256 x = seed % 4;
        if (x == 1) return "Neon Curse";
        if (x == 2) return "Oracle Gold";
        if (x == 3) return "Toxic Signal";
        return "Gate Cyan";
    }

    function _svg(uint256, TokenData memory data) internal pure returns (string memory) {
        string memory c1 = _color(data.seed, data.tier, 0);
        string memory c2 = _color(data.seed, data.tier, 1);
        string memory c3 = _color(data.seed, data.tier, 2);
        string memory c4 = _color(data.seed, data.tier, 3);
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">',
            '<rect width="1024" height="1024" fill="', _bg(data.tier), '"/>',
            '<rect x="34" y="34" width="956" height="956" fill="none" stroke="', c2, '" opacity="0.16"/>',
            _noise(data.seed, data.tier),
            _hair(data.seed, data.tier, c1, c2, c3),
            _mask(data.variant, c1, c2, c3, c4),
            _hatch(data.seed, data.tier, c1, c2, c3),
            _features(data.variant, c1, c2, c3, c4),
            _tierLayer(data.tier, c1, c2, c3, c4),
            _inscription(data),
            '</svg>'
        );
    }

    function _noise(uint256 seed, uint8 tier) internal pure returns (string memory out) {
        uint256 count = 18 + uint256(tier) * 9;
        for (uint256 i; i < count; ++i) {
            uint256 x = 55 + uint256(keccak256(abi.encode(seed, i, "x"))) % 915;
            uint256 y = 55 + uint256(keccak256(abi.encode(seed, i, "y"))) % 915;
            uint256 dx = uint256(keccak256(abi.encode(seed, i, "dx"))) % 80;
            uint256 dy = uint256(keccak256(abi.encode(seed, i, "dy"))) % 55;
            out = string.concat(out, '<path d="M', _toString(x), ' ', _toString(y), 'l', _toString(dx), ' ', _toString(dy), '" stroke="', _color(seed, tier, i), '" stroke-width="1" opacity="0.13" stroke-linecap="round"/>');
        }
    }

    function _hair(uint256 seed, uint8 tier, string memory c1, string memory c2, string memory c3) internal pure returns (string memory out) {
        uint256 count = 12 + uint256(tier) * 6;
        for (uint256 i; i < count; ++i) {
            uint256 x = 360 + (i * 300 / count);
            uint256 h = 38 + uint256(keccak256(abi.encode(seed, i, "h"))) % (tier == 0 ? 55 : 115);
            out = string.concat(out, '<path d="M', _toString(x), ' 286C', _toString(x + (i % 3) * 9), ' ', _toString(250 - h / 3), ' ', _toString(x + 8), ' ', _toString(250 - h), '" fill="none" stroke="', i % 3 == 0 ? c1 : (i % 3 == 1 ? c2 : c3), '" stroke-width="2" opacity="0.46" stroke-linecap="round"/>');
        }
    }

    function _mask(uint8 variant, string memory c1, string memory c2, string memory c3, string memory c4) internal pure returns (string memory) {
        string memory d = variant % 4 == 0 ? 'M512 150 630 205 690 370 670 610 590 805 455 805 350 620 330 370 395 205Z' : variant % 4 == 1 ? 'M512 185 640 218 720 350 705 540 650 710 535 790 405 760 320 630 300 440 345 275Z' : variant % 4 == 2 ? 'M330 300 455 185 520 210 670 275 720 440 690 640 555 780 415 740 315 595 300 420Z' : 'M360 260 500 185 635 235 720 365 705 590 610 740 455 760 335 645 305 455Z';
        return string.concat('<path d="', d, '" fill="#000" fill-opacity="0.22" stroke="', c1, '" stroke-width="5" stroke-linejoin="round"/><path d="', d, '" fill="none" stroke="', c2, '" stroke-width="3" opacity="0.68" transform="translate(8 -5)"/><path d="', d, '" fill="none" stroke="', c3, '" stroke-width="2" opacity="0.48" transform="translate(-7 6)"/><path d="', d, '" fill="none" stroke="', c4, '" stroke-width="1" opacity="0.36" transform="translate(3 10)"/>');
    }

    function _hatch(uint256 seed, uint8 tier, string memory c1, string memory c2, string memory c3) internal pure returns (string memory out) {
        uint256 count = 10 + uint256(tier) * 8;
        for (uint256 i; i < count; ++i) {
            uint256 x = 350 + uint256(keccak256(abi.encode(seed, i, "hx"))) % 320;
            uint256 y = 270 + uint256(keccak256(abi.encode(seed, i, "hy"))) % 420;
            uint256 l = 26 + uint256(keccak256(abi.encode(seed, i, "hl"))) % 95;
            out = string.concat(out, '<path d="M', _toString(x), ' ', _toString(y), 'l', _toString(l), ' ', _toString(18 + (i % 5) * 9), '" stroke="', i % 3 == 0 ? c1 : (i % 3 == 1 ? c2 : c3), '" stroke-width="1.5" opacity="0.30" stroke-linecap="round"/>');
        }
    }

    function _features(uint8 variant, string memory c1, string memory c2, string memory c3, string memory c4) internal pure returns (string memory) {
        string memory eye = variant % 3 == 0 ? string.concat('<path d="M390 430C430 375 490 382 520 430C468 455 426 455 390 430Z" fill="none" stroke="', c1, '" stroke-width="5"/><path d="M632 430C592 375 532 382 504 430C556 455 598 455 632 430Z" fill="none" stroke="', c2, '" stroke-width="5"/>') : variant % 3 == 1 ? string.concat('<path d="M435 390 452 420 486 424 462 448 468 482 435 465 402 482 408 448 384 424 418 420Z" fill="none" stroke="', c3, '" stroke-width="4"/><path d="M590 390 607 420 641 424 617 448 623 482 590 465 557 482 563 448 539 424 573 420Z" fill="none" stroke="', c4, '" stroke-width="4"/>') : string.concat('<path d="M386 420Q448 384 512 432M638 420Q578 384 512 432" fill="none" stroke="', c1, '" stroke-width="5" stroke-linecap="round"/><path d="M420 430Q512 490 606 430" fill="none" stroke="', c2, '" stroke-width="2" opacity="0.6"/>');
        string memory mouth = variant % 4 == 0 ? string.concat('<path d="M420 610Q512 670 610 610" fill="none" stroke="', c3, '" stroke-width="5" stroke-linecap="round"/>') : variant % 4 == 1 ? string.concat('<path d="M420 610Q512 642 610 610" fill="none" stroke="', c4, '" stroke-width="5"/><path d="M440 592V632M480 604V644M520 608V648M560 604V644M600 592V632" stroke="', c2, '" stroke-width="2"/>') : variant % 4 == 2 ? string.concat('<path d="M512 625m-78 0a78 38 0 1 0 156 0a78 38 0 1 0-156 0" fill="#000" fill-opacity="0.55" stroke="', c3, '" stroke-width="4"/>') : string.concat('<path d="M430 625C480 588 560 588 610 625" fill="none" stroke="', c4, '" stroke-width="6" stroke-linecap="round"/>');
        return string.concat(eye, '<path d="M512 458C488 520 488 565 512 604C536 565 536 520 512 458Z" fill="none" stroke="', c2, '" stroke-width="3" opacity="0.75"/>', mouth);
    }

    function _tierLayer(uint8 tier, string memory c1, string memory c2, string memory c3, string memory c4) internal pure returns (string memory out) {
        if (tier >= 1) out = string.concat(out, '<path d="M358 312 398 264 438 312 398 358Z M640 312 680 264 720 312 680 358Z" fill="none" stroke="', c1, '" stroke-width="5"/><path d="M326 608 420 552M610 590 718 530" stroke="', c2, '" stroke-width="4" opacity="0.55"/>');
        if (tier >= 2) out = string.concat(out, '<path d="M512 190 538 238 592 246 553 284 562 338 512 312 462 338 471 284 432 246 486 238Z" fill="none" stroke="', c3, '" stroke-width="6"/><path d="M252 468C342 395 426 395 500 468M524 468C598 395 684 395 772 468" fill="none" stroke="', c1, '" stroke-width="3" opacity="0.55"/>');
        if (tier >= 3) out = string.concat(out, '<path d="M270 225C372 100 650 100 754 225M225 282C360 150 666 150 804 282" fill="none" stroke="', c4, '" stroke-width="6"/><path d="M205 392 256 354 238 420ZM820 392 768 354 786 420Z" fill="none" stroke="', c2, '" stroke-width="4"/>');
        if (tier >= 4) out = string.concat(out, '<path d="M382 142 448 205 512 108 576 205 642 142 612 266 412 266Z" fill="none" stroke="', c3, '" stroke-width="8"/><rect x="56" y="56" width="912" height="912" rx="28" fill="none" stroke="', c1, '" stroke-width="4" stroke-dasharray="28 16"/>');
    }

    function _inscription(TokenData memory data) internal pure returns (string memory) {
        if (bytes(data.inscription).length == 0) return "";
        string memory stroke = _presetColor(data.colorId);
        return string.concat('<g opacity="0.96"><rect x="248" y="852" width="528" height="82" rx="22" fill="#030306" opacity="0.84" stroke="', stroke, '" stroke-width="3"/><rect x="270" y="872" width="484" height="42" rx="13" fill="none" stroke="#fff7dd" stroke-width="1" opacity="0.34"/><text x="512" y="895" text-anchor="middle" dominant-baseline="middle" font-family="monospace" font-size="28" font-weight="900" letter-spacing="2" fill="#fff7dd" stroke="#000" stroke-width="0.7" paint-order="stroke fill">', data.inscription, '</text></g>');
    }

    function _tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == 0) return "Common";
        if (tier == 1) return "Marked";
        if (tier == 2) return "Oracle-marked";
        if (tier == 3) return "Ascended";
        return "The Unbound";
    }

    function _bg(uint8 tier) internal pure returns (string memory) {
        if (tier == 2) return "#f4ead0";
        if (tier == 3) return "#12060f";
        if (tier == 4) return "#07100f";
        return "#0b0d13";
    }

    function _presetColor(uint8 colorId) internal pure returns (string memory) {
        if (colorId == 1) return "#ff3b7f";
        if (colorId == 2) return "#ffe45e";
        if (colorId == 3) return "#ffffff";
        if (colorId == 4) return "#b169ff";
        return "#31e7ff";
    }

    function _color(uint256 seed, uint8 tier, uint256 salt) internal pure returns (string memory) {
        uint256 v = uint256(keccak256(abi.encode(seed, tier, salt))) % 6;
        if (v == 0) return "#31e7ff";
        if (v == 1) return "#ff4fd8";
        if (v == 2) return "#ffe45e";
        if (v == 3) return "#7cff6b";
        if (v == 4) return "#ff7a45";
        return "#ffffff";
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    function _base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for { let i := 0 } lt(i, mload(data)) {} {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)
                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)
                mstore(resultPtr, out)
                resultPtr := add(resultPtr, 4)
            }
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
            mstore(result, encodedLen)
        }
        return result;
    }
}

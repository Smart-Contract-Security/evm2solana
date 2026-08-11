// SPDX-License-Identifier: MIT

/*

    ASTRAFORGE NOMADS
    https://astraforgenomads.xyz
    https://x.com/astraforgeerc

*/

pragma solidity ^0.8.24;

interface IDN404Mirror {
    function initFromBase() external;
    function emitTransferEvent(address from, address to, uint256 tokenId) external;
    function emitTransferBatch(address from, address to, uint256[] memory tokenIds) external;
    function emitApprovalEvent(address owner, address approved, uint256 tokenId) external;
    function emitApprovalForAllEvent(address owner, address operator, bool approved) external;
}

abstract contract DN404 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event NFTClaimed(address indexed account, uint256 amount);
    event NFTUnclaimed(address indexed account, uint256 amount);

    error DN_AlreadyInitialized();
    error DN_NotInitialized();
    error DN_SupplyMismatch();
    error DN_ZeroAddress();
    error DN_InsufficientBalance();
    error DN_InsufficientAllowance();
    error DN_MintCapExceeded();
    error DN_OnlyMirror();
    error DN_NFTNotFound();
    error DN_NotAuthorized();
    error DN_NoMirror();
    error DN_InvalidClaim();

    uint256 internal constant UNIT = 1e18;
    uint256 private constant _ADDR_MASK = (1 << 160) - 1;

    bool    internal _dnInitialized;
    bool    internal _dnSilent;
    address internal _dnMirror;
    uint256 internal _dnMaxNFTSupply;
    uint256 internal _dnTotalSupplyERC20;
    uint256 internal _dnTotalNFTOutstanding;
    uint256 internal _dnNextNewTokenId;

    mapping(address => uint256) internal _dnBalanceOf;
    mapping(address => mapping(address => uint256)) internal _dnAllowance;
    mapping(address => uint256[]) internal _dnOwned;

    mapping(uint256 => uint256)   internal _dnTokenData;
    mapping(uint256 => address)   internal _dnNftApproved;
    mapping(address => mapping(address => bool)) internal _dnOperatorApproved;

    uint256[] internal _dnBurnedPool;
    uint256   internal _dnBurnedPoolHead;

    modifier onlyMirror() {
        if (msg.sender != _dnMirror) revert DN_OnlyMirror();
        _;
    }

    function _initializeDN404(
        uint256 initialTokenSupply,
        uint256 maxNFTSupply_,
        address initialMintTo,
        address mirror
    ) internal {
        if (_dnInitialized) revert DN_AlreadyInitialized();
        if (initialTokenSupply != maxNFTSupply_ * UNIT) revert DN_SupplyMismatch();
        if (mirror == address(0) || initialMintTo == address(0)) revert DN_ZeroAddress();

        _dnInitialized = true;
        _dnMaxNFTSupply = maxNFTSupply_;
        _dnTotalSupplyERC20 = initialTokenSupply;
        _dnMirror = mirror;

        _dnBalanceOf[initialMintTo] = initialTokenSupply;
        emit Transfer(address(0), initialMintTo, initialTokenSupply);

        IDN404Mirror(mirror).initFromBase();
    }

    function _onMintNFT(uint256 tokenId, address to) internal virtual {}

    function _onBurnNFT(uint256 tokenId, address owner) internal virtual {}

    function _onTransferNFT(uint256 tokenId, address from, address to) internal virtual {}

    function _beforeSharesChange(address account) internal virtual {}

    function name() public view virtual returns (string memory);
    function symbol() public view virtual returns (string memory);
    function decimals() public view virtual returns (uint8) { return 18; }

    function totalSupply() public view virtual returns (uint256) {
        return _dnTotalSupplyERC20;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _dnBalanceOf[account];
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _dnAllowance[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _dnAllowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = _dnAllowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert DN_InsufficientAllowance();
            unchecked { _dnAllowance[from][msg.sender] = allowed - amount; }
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert DN_ZeroAddress();
        uint256 fromBal = _dnBalanceOf[from];
        if (fromBal < amount) revert DN_InsufficientBalance();

        unchecked {
            _dnBalanceOf[from] = fromBal - amount;
            _dnBalanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);

        if (_dnSilent) return;

        uint256 maxFrom = _dnBalanceOf[from] / UNIT;
        uint256 curFrom = _dnOwned[from].length;
        if (curFrom > maxFrom) {
            unchecked { _burnBatch(from, curFrom - maxFrom); }
        }
    }

    function _mintBatch(address to, uint256 n) internal {
        _beforeSharesChange(to);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i = 0; i < n; ) {
            uint256 tokenId = _useTokenId();
            _addNFTToOwner(to, tokenId);
            _onMintNFT(tokenId, to);
            ids[i] = tokenId;
            unchecked { ++i; }
        }
        IDN404Mirror(_dnMirror).emitTransferBatch(address(0), to, ids);
    }

    function _burnBatch(address from, uint256 n) internal {
        _beforeSharesChange(from);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i = 0; i < n; ) {
            uint256 lastIdx;
            unchecked { lastIdx = _dnOwned[from].length - 1; }
            uint256 tokenId = _dnOwned[from][lastIdx];
            _onBurnNFT(tokenId, from);
            _removeNFTFromOwner(from, tokenId);
            _returnTokenId(tokenId);
            ids[i] = tokenId;
            unchecked { ++i; }
        }
        IDN404Mirror(_dnMirror).emitTransferBatch(from, address(0), ids);
    }

    function _ownerOfId(uint256 tokenId) internal view returns (address) {
        return address(uint160(_dnTokenData[tokenId]));
    }

    function _addNFTToOwner(address owner, uint256 tokenId) internal {

        _dnTokenData[tokenId] = uint256(uint160(owner)) | (_dnOwned[owner].length << 160);
        _dnOwned[owner].push(tokenId);
    }

    function _removeNFTFromOwner(address owner, uint256 tokenId) internal {
        uint256 idx = _dnTokenData[tokenId] >> 160;
        uint256 lastIdx;
        unchecked { lastIdx = _dnOwned[owner].length - 1; }
        if (idx != lastIdx) {
            uint256 lastTokenId = _dnOwned[owner][lastIdx];
            _dnOwned[owner][idx] = lastTokenId;

            _dnTokenData[lastTokenId] = (_dnTokenData[lastTokenId] & _ADDR_MASK) | (idx << 160);
        }
        _dnOwned[owner].pop();
        delete _dnTokenData[tokenId];
        delete _dnNftApproved[tokenId];
    }

    function _useTokenId() internal returns (uint256 tokenId) {
        uint256 head = _dnBurnedPoolHead;
        uint256 len = _dnBurnedPool.length;
        if (head < len) {
            tokenId = _dnBurnedPool[head];
            unchecked { _dnBurnedPoolHead = head + 1; }
        } else {
            unchecked { tokenId = ++_dnNextNewTokenId; }
            if (tokenId > _dnMaxNFTSupply) revert DN_MintCapExceeded();
        }
        unchecked { _dnTotalNFTOutstanding++; }
    }

    function _returnTokenId(uint256 tokenId) internal {
        _dnBurnedPool.push(tokenId);
        unchecked { _dnTotalNFTOutstanding--; }
    }

    function claimNFT(uint256 amount) public {
        address account = msg.sender;
        uint256 cur = _dnOwned[account].length;
        uint256 max = _dnBalanceOf[account] / UNIT;
        if (amount == 0 || cur + amount > max) revert DN_InvalidClaim();
        _mintBatch(account, amount);
        emit NFTClaimed(account, amount);
    }

    function claimAllNFT() external {
        address account = msg.sender;
        uint256 cur = _dnOwned[account].length;
        uint256 max = _dnBalanceOf[account] / UNIT;
        if (max <= cur) revert DN_InvalidClaim();
        uint256 amount = max - cur;
        _mintBatch(account, amount);
        emit NFTClaimed(account, amount);
    }

    function unclaimNFT(uint256 amount) external {
        if (amount == 0 || amount > _dnOwned[msg.sender].length) revert DN_InvalidClaim();
        _burnBatch(msg.sender, amount);
        emit NFTUnclaimed(msg.sender, amount);
    }

    function claimableNFT(address account) external view returns (uint256) {
        uint256 cur = _dnOwned[account].length;
        uint256 max = _dnBalanceOf[account] / UNIT;
        return max > cur ? max - cur : 0;
    }

    function transferFromNFT(
        address from,
        address to,
        uint256 tokenId,
        address msgSender
    ) external onlyMirror {
        if (_ownerOfId(tokenId) != from) revert DN_NFTNotFound();
        if (to == address(0)) revert DN_ZeroAddress();

        if (
            msgSender != from &&
            _dnNftApproved[tokenId] != msgSender &&
            !_dnOperatorApproved[from][msgSender]
        ) revert DN_NotAuthorized();

        _dnSilent = true;
        _transferSilent(from, to, UNIT);
        _dnSilent = false;

        _beforeSharesChange(from);
        _beforeSharesChange(to);
        _removeNFTFromOwner(from, tokenId);
        _addNFTToOwner(to, tokenId);
        _onTransferNFT(tokenId, from, to);
    }

    function _transferSilent(address from, address to, uint256 amount) internal {
        uint256 fromBal = _dnBalanceOf[from];
        if (fromBal < amount) revert DN_InsufficientBalance();
        unchecked {
            _dnBalanceOf[from] = fromBal - amount;
            _dnBalanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function approveNFT(uint256 tokenId, address approved, address msgSender) external onlyMirror {
        address owner = _ownerOfId(tokenId);
        if (owner == address(0)) revert DN_NFTNotFound();
        if (msgSender != owner && !_dnOperatorApproved[owner][msgSender]) revert DN_NotAuthorized();
        _dnNftApproved[tokenId] = approved;
    }

    function setApprovalForAllNFT(address operator, bool approved, address msgSender) external onlyMirror {
        _dnOperatorApproved[msgSender][operator] = approved;
    }

    function nftBalanceOf(address owner) external view returns (uint256) {
        return _dnOwned[owner].length;
    }

    function nftOwnerOf(uint256 tokenId) external view returns (address owner) {
        owner = _ownerOfId(tokenId);
        if (owner == address(0)) revert DN_NFTNotFound();
    }

    function nftGetApproved(uint256 tokenId) external view returns (address) {
        if (_ownerOfId(tokenId) == address(0)) revert DN_NFTNotFound();
        return _dnNftApproved[tokenId];
    }

    function nftIsApprovedForAll(address owner, address operator) external view returns (bool) {
        return _dnOperatorApproved[owner][operator];
    }

    function nftTokenURI(uint256 tokenId) external view returns (string memory) {
        if (_ownerOfId(tokenId) == address(0)) revert DN_NFTNotFound();
        return _tokenURI(tokenId);
    }

    function _tokenURI(uint256 tokenId) internal view virtual returns (string memory);

    function totalNFTSupply() public view returns (uint256) {
        return _dnTotalNFTOutstanding;
    }

    function _ownedTokenIds(address owner) internal view returns (uint256[] memory) {
        return _dnOwned[owner];
    }

    function ownedTokenIds(address owner) external view returns (uint256[] memory) {
        return _dnOwned[owner];
    }

    function getMirror() external view returns (address) {
        return _dnMirror;
    }

    function burnedPoolSize() external view returns (uint256) {
        unchecked { return _dnBurnedPool.length - _dnBurnedPoolHead; }
    }

    function maxNFTSupply() external view returns (uint256) {
        return _dnMaxNFTSupply;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7;
    }
}

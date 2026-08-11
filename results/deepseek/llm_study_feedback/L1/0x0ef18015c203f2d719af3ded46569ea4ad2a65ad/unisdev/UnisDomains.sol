// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title UnisDomains - ENS-style ".uni" registry
/// @notice Each domain is a name [3..32 chars, a-z 0-9 -] resolving to a
///         target address (could be an EOA, an Objectized Asset, or a
///         contract). Owners can set arbitrary text records. Registration
///         charges an ETH fee that scales with the name length. Domains
///         renew yearly; expired domains may be re-registered by anyone.
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

    // namehash → record
    mapping(bytes32 => Record) public records;
    // namehash → key → text record
    mapping(bytes32 => mapping(string => string)) public textRecords;
    // namehash → primary name reverse lookup (address → name)
    mapping(address => bytes32) public primaryName;

    // Fee schedule (lamports, scales with name length):
    //  3 chars : 0.30 SOL
    //  4 chars : 0.10 SOL
    //  5 chars : 0.03 SOL
    //  6+      : 0.005 SOL
    uint256 public fee3   = 300_000_000; // 0.30 SOL in lamports
    uint256 public fee4   = 100_000_000; // 0.10 SOL
    uint256 public fee5   =  30_000_000; // 0.03 SOL
    uint256 public feeGen =   5_000_000; // 0.005 SOL

    event Registered(bytes32 indexed nh, string name, address indexed owner, address indexed target, uint64 expiresAt);
    event Renewed(bytes32 indexed nh, uint64 newExpiresAt);
    event Transferred(bytes32 indexed nh, address indexed from, address indexed to);
    event TargetSet(bytes32 indexed nh, address indexed target);
    event TextSet(bytes32 indexed nh, string key, string value);
    event PrimaryNameSet(address indexed who, bytes32 indexed nh);
    event FeesSet(uint256 fee3, uint256 fee4, uint256 fee5, uint256 feeGen);
    event TreasurySet(address indexed prev, address indexed next);
    event AdminPassed(address indexed prev, address indexed next);

    modifier onlyAdmin() { 
        if (tx.origin != admin) revert("NotAdmin"); 
        _; 
    }
    modifier onlyOwner(bytes32 nh) {
        Record memory r = records[nh];
        if (r.owner != tx.origin || block.timestamp >= r.expiresAt) revert("NotOwner");
        _;
    }

    constructor(address _admin, address _treasury) {
        if (_admin == address(0) || _treasury == address(0)) revert("ZeroAddress");
        admin    = _admin;
        treasury = _treasury;
    }

    // ---- naming ----

    function namehash(string memory name) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name, ".uni"));
    }

    function _validate(string memory name) internal pure {
        bytes memory b = bytes(name);
        uint256 len = b.length;
        if (len < 3 || len > 32) revert("BadName");
        for (uint256 i; i < len; ) {
            bytes1 c = b[i];
            bool ok =
                (c >= 0x30 && c <= 0x39) || // 0-9
                (c >= 0x61 && c <= 0x7a) || // a-z
                (c == 0x2d && i != 0 && i != len - 1); // - (not first/last)
            if (!ok) revert("BadName");
            unchecked { i++; }
        }
    }

    function feeFor(string memory name) public view returns (uint256) {
        uint256 len = bytes(name).length;
        if (len == 3) return fee3;
        if (len == 4) return fee4;
        if (len == 5) return fee5;
        return feeGen;
    }

    function isAvailable(bytes32 nh) public view returns (bool) {
        Record memory r = records[nh];
        return r.owner == address(0) || block.timestamp >= r.expiresAt;
    }

    // ---- register / renew / transfer ----

    function register(string calldata name, address target) external payable returns (bytes32 nh) {
        _validate(name);
        nh = namehash(name);
        Record memory r = records[nh];
        if (r.owner != address(0) && block.timestamp < r.expiresAt) revert("AlreadyRegistered");

        uint256 owed = feeFor(name);
        if (msg.value < owed) revert("FeeTooLow");

        uint64 nowTs = uint64(block.timestamp);
        records[nh] = Record({
            owner:        tx.origin,
            target:       target == address(0) ? tx.origin : target,
            registeredAt: nowTs,
            expiresAt:    nowTs + ONE_YEAR
        });

        // Forward fee to treasury
        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
        }

        emit Registered(nh, name, tx.origin, records[nh].target, records[nh].expiresAt);
    }

    function renew(string calldata name) external payable {
        bytes32 nh = namehash(name);
        Record storage r = records[nh];
        if (r.owner == address(0)) revert("NotOwner");
        uint256 owed = feeFor(name);
        if (msg.value < owed) revert("FeeTooLow");

        uint64 base = uint64(block.timestamp) > r.expiresAt
            ? uint64(block.timestamp)
            : r.expiresAt;
        r.expiresAt = base + ONE_YEAR;

        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
        }

        emit Renewed(nh, r.expiresAt);
    }

    function transferDomain(bytes32 nh, address to) external onlyOwner(nh) {
        if (to == address(0)) revert("ZeroAddress");
        address from = records[nh].owner;
        records[nh].owner = to;
        // Reset primary if the previous owner had this as their primary
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
        primaryName[tx.origin] = nh;
        emit PrimaryNameSet(tx.origin, nh);
    }

    function clearPrimary() external {
        emit PrimaryNameSet(tx.origin, bytes32(0));
        primaryName[tx.origin] = bytes32(0);
    }

    // ---- resolvers ----

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

    // ---- admin ----

    function setFees(uint256 _fee3, uint256 _fee4, uint256 _fee5, uint256 _feeGen) external onlyAdmin {
        fee3   = _fee3;
        fee4   = _fee4;
        fee5   = _fee5;
        feeGen = _feeGen;
        emit FeesSet(_fee3, _fee4, _fee5, _feeGen);
    }

    function setTreasury(address t) external onlyAdmin {
        if (t == address(0)) revert("ZeroAddress");
        emit TreasurySet(treasury, t);
        treasury = t;
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) revert("ZeroAddress");
        emit AdminPassed(admin, next);
        admin = next;
    }
}
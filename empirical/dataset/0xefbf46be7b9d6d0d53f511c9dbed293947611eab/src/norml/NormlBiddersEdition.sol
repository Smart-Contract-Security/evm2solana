// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal NormlForUs view surface used for metadata proxying.
interface INormlForUsViews {
    function metadataFor(uint256 tokenId) external view returns (string memory);
    function animationURI(uint256 tokenId) external view returns (string memory);
    function BIDDERS_EDITION_ID() external view returns (uint256);
}

/// @title NormlBiddersEdition
/// @notice Standalone ERC-1155 single-id contract for the NORML bidder's edition
///         ("lost in draft"). All rendering state — image, description, asset
///         chunks, live staked-NORML count — lives on `NormlForUs` at slot 8;
///         this contract proxies its `uri()` to `NormlForUs.metadataFor(8)`.
///
///         Staking against the bidder's pool still happens directly on
///         `NormlForUs.stake(8, amount)`, so the existing staking ledger,
///         animation injection, and metadata description all stay in sync
///         across both contracts without any duplicated state.
///         Single token id (`EDITION_ID = 0`). Distribution is owner-airdropped
///         via `airdrop(address[] recipients)` — one copy per recipient, idempotent.
/// @author jiwa
contract NormlBiddersEdition {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The single ERC-1155 id served by this contract.
    uint256 public constant EDITION_ID = 0;

    /// @notice The matching slot id on NormlForUs that backs this edition's state.
    ///         Hard-coded to 8 to match `NormlForUs.BIDDERS_EDITION_ID`.
    uint256 public constant FOR_US_SLOT = 8;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:°•.°+.*•´.*:*/

    /// @notice Address of the NormlForUs render contract. Source of all metadata.
    address public immutable NORML_FOR_US;

    string public name;
    string public symbol;
    address public owner;

    /// @notice Optional trusted router (reserved for future seamless UX).
    address public router;

    /// @notice Total minted supply across all recipients.
    uint256 public totalSupply;

    /// @notice Per-address airdrop ledger (one copy max per recipient).
    mapping(address => bool) public hasReceived;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RouterUpdated(address indexed previousRouter, address indexed newRouter);
    event Airdropped(address indexed to);

    // ERC-1155 events
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidNormlForUs();
    error InvalidId();
    error InvalidReceiver();
    error InsufficientBalance();
    error Unauthorized();
    error AlreadyReceived();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address normlForUs_, string memory name_, string memory symbol_) {
        if (normlForUs_ == address(0)) revert InvalidNormlForUs();
        NORML_FOR_US = normlForUs_;
        name = name_;
        symbol = symbol_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Set the trusted router. Owner-only.
    function setRouter(address newRouter) external onlyOwner {
        emit RouterUpdated(router, newRouter);
        router = newRouter;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         AIRDROP                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mint one copy of the bidder's edition to each recipient.
    /// @dev Idempotent per address: recipients already marked `hasReceived` are
    ///      skipped silently (so a re-run with overlap doesn't revert).
    function airdrop(address[] calldata recipients) external onlyOwner {
        uint256 len = recipients.length;
        for (uint256 i = 0; i < len; i++) {
            address to = recipients[i];
            if (to == address(0)) revert InvalidReceiver();
            if (hasReceived[to]) continue;
            hasReceived[to] = true;
            _balances[to] += 1;
            totalSupply += 1;
            emit Airdropped(to);
            emit TransferSingle(msg.sender, address(0), to, EDITION_ID, 1);
            _doSafeTransferAcceptanceCheck(msg.sender, address(0), to, EDITION_ID, 1, "");
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       METADATA (PROXY)                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ERC-1155 metadata URI — proxies to NormlForUs.metadataFor(8).
    /// @dev All rendering inputs (image override, description, asset chunks, live
    ///      staked-NORML count) live on NormlForUs at slot 8. This single read
    ///      keeps the 1155 perfectly in sync with the rest of the system.
    function uri(uint256 id) public view returns (string memory) {
        if (id != EDITION_ID) revert InvalidId();
        return INormlForUsViews(NORML_FOR_US).metadataFor(FOR_US_SLOT);
    }

    /// @notice Convenience: the raw HTML animation data URI for the bidder's edition.
    function animationURI() external view returns (string memory) {
        return INormlForUsViews(NORML_FOR_US).animationURI(FOR_US_SLOT);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ERC-1155 INTERFACE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        if (id != EDITION_ID) revert InvalidId();
        return _balances[account];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory balances)
    {
        if (accounts.length != ids.length) revert InvalidId();
        balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            if (ids[i] != EDITION_ID) revert InvalidId();
            balances[i] = _balances[accounts[i]];
        }
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external {
        if (id != EDITION_ID) revert InvalidId();
        if (to == address(0)) revert InvalidReceiver();
        if (from != msg.sender && !_operatorApprovals[from][msg.sender]) revert Unauthorized();
        if (_balances[from] < amount) revert InsufficientBalance();

        _balances[from] -= amount;
        _balances[to] += amount;

        emit TransferSingle(msg.sender, from, to, id, amount);
        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external {
        if (ids.length != amounts.length) revert InvalidId();
        if (to == address(0)) revert InvalidReceiver();
        if (from != msg.sender && !_operatorApprovals[from][msg.sender]) revert Unauthorized();

        uint256 total;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] != EDITION_ID) revert InvalidId();
            total += amounts[i];
        }
        if (_balances[from] < total) revert InsufficientBalance();

        _balances[from] -= total;
        _balances[to] += total;

        emit TransferBatch(msg.sender, from, to, ids, amounts);
        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       SUPPORTSINTERFACE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0xd9b67a26 || // ERC1155
            interfaceId == 0x0e89341c;   // ERC1155MetadataURI
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        if (to.code.length == 0) return;
        (bool ok, bytes memory ret) = to.call(
            abi.encodeWithSelector(
                bytes4(0xf23a6e61), // onERC1155Received
                operator, from, id, amount, data
            )
        );
        if (!ok || ret.length < 32 || abi.decode(ret, (bytes4)) != bytes4(0xf23a6e61)) {
            revert InvalidReceiver();
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) internal {
        if (to.code.length == 0) return;
        (bool ok, bytes memory ret) = to.call(
            abi.encodeWithSelector(
                bytes4(0xbc197c81), // onERC1155BatchReceived
                operator, from, ids, amounts, data
            )
        );
        if (!ok || ret.length < 32 || abi.decode(ret, (bytes4)) != bytes4(0xbc197c81)) {
            revert InvalidReceiver();
        }
    }
}

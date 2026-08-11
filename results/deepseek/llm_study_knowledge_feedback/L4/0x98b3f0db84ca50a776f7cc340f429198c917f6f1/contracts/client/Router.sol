// SPDX-License-Identifier: MIT OR Apache-2.0

import {IMessageRecipient} from "../interfaces/IMessageRecipient.sol";
import {IPostDispatchHook} from "../interfaces/hooks/IPostDispatchHook.sol";

// Solana port: Inline MailboxClient functionality since inheritance not available
// Solana port: Inline EnumerableMapExtended since library not available
// Solana port: Remove Strings import, implement toString locally

abstract contract Router is IMessageRecipient {
    // --- Inlined from EnumerableMapExtended ---
    struct UintToBytes32Map {
        uint32[] _keys;
        mapping(uint32 => uint256) _index;
        mapping(uint32 => bytes32) _values;
    }

    function _set(UintToBytes32Map storage map, uint32 key, bytes32 value) internal {
        if (!_contains(map, key)) {
            map._keys.push(key);
            map._index[key] = map._keys.length;
        }
        map._values[key] = value;
    }

    function _remove(UintToBytes32Map storage map, uint32 key) internal returns (bool) {
        uint256 index = map._index[key];
        if (index == 0) {
            return false;
        }

        uint256 lastIndex = map._keys.length;
        uint32 lastKey = map._keys[lastIndex - 1];

        map._keys[index - 1] = lastKey;
        map._index[lastKey] = index;

        map._keys.pop();
        delete map._index[key];
        delete map._values[key];
        return true;
    }

    function _contains(UintToBytes32Map storage map, uint32 key) internal view returns (bool) {
        return map._index[key] != 0;
    }

    function _tryGet(UintToBytes32Map storage map, uint32 key) internal view returns (bool, bytes32) {
        uint256 index = map._index[key];
        if (index == 0) {
            return (false, bytes32(0));
        }
        return (true, map._values[key]);
    }

    function _uint32Keys(UintToBytes32Map storage map) internal view returns (uint32[] memory) {
        return map._keys;
    }

    function _length(UintToBytes32Map storage map) internal view returns (uint256) {
        return map._keys.length;
    }
    // --- End inlined EnumerableMapExtended ---

    // --- Inlined from MailboxClient ---
    address public mailbox;
    address public hook;
    address public owner;

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner);
        _;
    }

    modifier onlyMailbox() {
        require(tx.accounts.dataAccount.key == mailbox);
        _;
    }

    // Constructor logic from MailboxClient
    // Solana: constructor must be called with accounts, but we inline the logic
    function _initializeMailboxClient(address _mailbox) internal {
        require(_mailbox != address(0));
        mailbox = _mailbox;
        owner = tx.accounts.dataAccount.key;
        // hook is set to default hook from mailbox - simplified for port
        hook = _mailbox; // placeholder, actual hook would be queried
    }
    // --- End inlined MailboxClient ---

    UintToBytes32Map internal _routers;

    uint256[48] private __GAP;

    // Solana: constructor replaced with initialize pattern
    constructor() {
        // initialization done in a separate call
    }

    function initialize(address _mailbox) external {
        require(owner == address(0));
        _initializeMailboxClient(_mailbox);
    }

    function domains() external view returns (uint32[] memory) {
        return _uint32Keys(_routers);
    }

    function routers(uint32 _domain) public view virtual returns (bytes32) {
        (, bytes32 _router) = _tryGet(_routers, _domain);
        return _router;
    }

    function unenrollRemoteRouter(uint32 _domain) external virtual onlyOwner {
        _unenrollRemoteRouter(_domain);
    }

    function enrollRemoteRouter(
        uint32 _domain,
        bytes32 _router
    ) external virtual onlyOwner {
        _enrollRemoteRouter(_domain, _router);
    }

    function enrollRemoteRouters(
        uint32[] calldata _domains,
        bytes32[] calldata _addresses
    ) external virtual onlyOwner {
        require(_domains.length == _addresses.length);
        uint256 length = _domains.length;
        for (uint256 i = 0; i < length; i += 1) {
            _enrollRemoteRouter(_domains[i], _addresses[i]);
        }
    }

    function unenrollRemoteRouters(
        uint32[] calldata _domains
    ) external virtual onlyOwner {
        uint256 length = _domains.length;
        for (uint256 i = 0; i < length; i += 1) {
            _unenrollRemoteRouter(_domains[i]);
        }
    }

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external virtual override onlyMailbox {
        bytes32 _router = _mustHaveRemoteRouter(_origin);
        require(_router == _sender);
        _handle(_origin, _sender, _message);
    }

    function _handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) internal virtual;

    function _enrollRemoteRouter(
        uint32 _domain,
        bytes32 _address
    ) internal virtual {
        _set(_routers, _domain, _address);
    }

    function _unenrollRemoteRouter(uint32 _domain) internal virtual {
        require(_remove(_routers, _domain));
    }

    function _isRemoteRouter(
        uint32 _domain,
        bytes32 _address
    ) internal view returns (bool) {
        return routers(_domain) == _address;
    }

    function _mustHaveRemoteRouter(
        uint32 _domain
    ) internal view returns (bytes32) {
        (bool contained, bytes32 _router) = _tryGet(_routers, _domain);
        if (contained) {
            return _router;
        }
        revert(_domainNotFoundError(_domain));
    }

    // Solana port: implement toString for uint32 locally
    function _toString(uint32 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint32 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint32(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _domainNotFoundError(
        uint32 _domain
    ) internal pure returns (string memory) {
        return
            string.concat(
                "No router enrolled for domain: ",
                _toString(_domain)
            );
    }

    function _Router_dispatch(
        uint32 _destinationDomain,
        uint256 _value,
        bytes memory _messageBody
    ) internal returns (bytes32) {
        return
            _Router_dispatch(
                _destinationDomain,
                _value,
                _messageBody,
                "",
                hook
            );
    }

    function _Router_dispatch(
        uint32 _destinationDomain,
        uint256 _value,
        bytes memory _messageBody,
        bytes memory _hookMetadata,
        address _hook
    ) internal returns (bytes32) {
        bytes32 _router = _mustHaveRemoteRouter(_destinationDomain);
        // Solana: external call to mailbox dispatch
        // Note: value transfer not supported on Solana, _value is ignored
        (bool success, bytes memory returnData) = mailbox.call{accounts: []}(
            abi.encodeWithSignature(
                "dispatch(uint32,bytes32,bytes,bytes,address)",
                _destinationDomain,
                _router,
                _messageBody,
                _hookMetadata,
                _hook
            )
        );
        require(success);
        return abi.decode(returnData, (bytes32));
    }

    function _Router_quoteDispatch(
        uint32 _destinationDomain,
        bytes memory _messageBody
    ) internal returns (uint256) {
        return
            _Router_quoteDispatch(
                _destinationDomain,
                _messageBody,
                "",
                hook
            );
    }

    function _Router_quoteDispatch(
        uint32 _destinationDomain,
        bytes memory _messageBody,
        bytes memory _hookMetadata,
        address _hook
    ) internal returns (uint256) {
        bytes32 _router = _mustHaveRemoteRouter(_destinationDomain);
        // Solana: static call to mailbox quoteDispatch
        (bool success, bytes memory returnData) = mailbox.call{accounts: []}(
            abi.encodeWithSignature(
                "quoteDispatch(uint32,bytes32,bytes,bytes,address)",
                _destinationDomain,
                _router,
                _messageBody,
                _hookMetadata,
                _hook
            )
        );
        require(success);
        return abi.decode(returnData, (uint256));
    }
}
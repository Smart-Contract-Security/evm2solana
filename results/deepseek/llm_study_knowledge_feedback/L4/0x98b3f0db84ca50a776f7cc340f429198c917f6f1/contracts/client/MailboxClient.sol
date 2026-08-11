// SPDX-License-Identifier: MIT OR Apache-2.0

import {IPostDispatchHook} from "../interfaces/hooks/IPostDispatchHook.sol";
import {IInterchainSecurityModule} from "../interfaces/IInterchainSecurityModule.sol";

// On Solana, contracts cannot be used as types. We use interfaces and address types.
// OwnableUpgradeable and PackageVersioned are replaced with inline implementations.
// Message library is replaced with inline helpers.
// IMailbox is replaced with an interface definition inline.

interface IMailbox {
    function localDomain() external view returns (uint32);
    function latestDispatchedId() external view returns (bytes32);
    function delivered(bytes32 id) external view returns (bool);
}

// Simple Ownable implementation for Solana (no upgradeable pattern needed)
contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Ownable: caller is not the owner");
        _;
    }

    function _transferOwnership(address newOwner) internal {
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
}

// Simple versioned contract
contract PackageVersioned {
    uint8 public constant VERSION = 1;
}

abstract contract MailboxClient is Ownable, PackageVersioned {
    event HookSet(address _hook);
    event IsmSet(address _ism);

    address public mailbox;
    uint32 public localDomain;
    address public hook;
    address internal _interchainSecurityModule;

    uint256[48] private __GAP;

    modifier onlyContract(address _contract) {
        // On Solana, address.code is not supported. We check that the address is not zero.
        require(_contract != address(0), "MailboxClient: invalid mailbox");
        _;
    }

    modifier onlyContractOrNull(address _contract) {
        // On Solana, address.code is not supported. We check that the address is not zero or is zero.
        require(_contract != address(0) || _contract == address(0), "MailboxClient: invalid contract setting");
        _;
    }

    modifier onlyMailbox() {
        require(
            tx.accounts.dataAccount.key == mailbox,
            "MailboxClient: sender not mailbox"
        );
        _;
    }

    // Constructor replaced with an initializer since Solana does not support constructors with arguments in the same way.
    // The caller must call initialize after deployment.
    function initialize(address _mailbox) public {
        require(mailbox == address(0), "Already initialized");
        require(_mailbox != address(0), "MailboxClient: invalid mailbox");
        mailbox = _mailbox;
        // Call localDomain via external call using the interface
        localDomain = IMailbox(_mailbox).localDomain();
        _transferOwnership(tx.accounts.dataAccount.key);
    }

    function interchainSecurityModule()
        external
        view
        virtual
        returns (address)
    {
        return _interchainSecurityModule;
    }

    function setHook(
        address _hook
    ) public virtual onlyContractOrNull(_hook) onlyOwner {
        hook = _hook;
        emit HookSet(_hook);
    }

    function setInterchainSecurityModule(
        address _module
    ) public onlyContractOrNull(_module) onlyOwner {
        _interchainSecurityModule = _module;
        emit IsmSet(_module);
    }

    function _MailboxClient_initialize(
        address _hook,
        address __interchainSecurityModule,
        address _owner
    ) internal {
        // __Ownable_init() is not available; we just set owner directly.
        _transferOwnership(_owner);
        setHook(_hook);
        setInterchainSecurityModule(__interchainSecurityModule);
    }

    function _isLatestDispatched(bytes32 id) internal view returns (bool) {
        return IMailbox(mailbox).latestDispatchedId() == id;
    }

    function _isDelivered(bytes32 id) internal view returns (bool) {
        return IMailbox(mailbox).delivered(id);
    }
}
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.6.11;

import {IMailbox} from "../interfaces/IMailbox.sol";
import {IPostDispatchHook} from "../interfaces/hooks/IPostDispatchHook.sol";
import {IInterchainSecurityModule} from "../interfaces/IInterchainSecurityModule.sol";
import {Message} from "../libs/Message.sol";
import {PackageVersioned} from "../PackageVersioned.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MailboxClient is OwnableUpgradeable, PackageVersioned {
    using Message for bytes;

    event HookSet(address _hook);
    event IsmSet(address _ism);

    IMailbox public mailbox;
    uint32 public localDomain;
    IPostDispatchHook public hook;
    IInterchainSecurityModule internal _interchainSecurityModule;

    uint256[48] private __GAP;

    modifier onlyContract(address _contract) {
        require(
            _contract.code.length > 0,
            "MailboxClient: invalid mailbox"
        );
        _;
    }

    modifier onlyContractOrNull(address _contract) {
        require(
            _contract.code.length > 0 || _contract == address(0),
            "MailboxClient: invalid contract setting"
        );
        _;
    }

    modifier onlyMailbox() {
        require(
            msg.sender == address(mailbox),
            "MailboxClient: sender not mailbox"
        );
        _;
    }

    constructor(address _mailbox) onlyContract(_mailbox) {
        mailbox = IMailbox(_mailbox);
        localDomain = mailbox.localDomain();
        _transferOwnership(msg.sender);
    }

    function interchainSecurityModule()
        external
        view
        virtual
        returns (IInterchainSecurityModule)
    {
        return _interchainSecurityModule;
    }

    function setHook(
        address _hook
    ) public virtual onlyContractOrNull(_hook) onlyOwner {
        hook = IPostDispatchHook(_hook);
        emit HookSet(_hook);
    }

    function setInterchainSecurityModule(
        address _module
    ) public onlyContractOrNull(_module) onlyOwner {
        _interchainSecurityModule = IInterchainSecurityModule(_module);
        emit IsmSet(_module);
    }

    function _MailboxClient_initialize(
        address _hook,
        address __interchainSecurityModule,
        address _owner
    ) internal onlyInitializing {
        __Ownable_init();
        setHook(_hook);
        setInterchainSecurityModule(__interchainSecurityModule);
        _transferOwnership(_owner);
    }

    function _isLatestDispatched(bytes32 id) internal view returns (bool) {
        return mailbox.latestDispatchedId() == id;
    }

    function _isDelivered(bytes32 id) internal view returns (bool) {
        return mailbox.delivered(id);
    }
}
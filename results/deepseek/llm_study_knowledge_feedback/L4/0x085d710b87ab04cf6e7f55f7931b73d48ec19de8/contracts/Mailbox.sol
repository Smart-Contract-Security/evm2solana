// SPDX-License-Identifier: MIT OR Apache-2.0

import {Versioned} from "./upgrade/Versioned.sol";
import {Indexed} from "./libs/Indexed.sol";
import {Message} from "./libs/Message.sol";
import {TypeCasts} from "./libs/TypeCasts.sol";
import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import {IPostDispatchHook} from "./interfaces/hooks/IPostDispatchHook.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";
import {PackageVersioned} from "./PackageVersioned.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Mailbox is
    IMailbox,
    Indexed,
    Versioned,
    OwnableUpgradeable,
    PackageVersioned
{
    using Message for bytes;
    using TypeCasts for bytes32;
    using TypeCasts for address;

    uint32 public immutable localDomain;

    uint32 public nonce;

    bytes32 public latestDispatchedId;

    IInterchainSecurityModule public defaultIsm;

    IPostDispatchHook public defaultHook;

    IPostDispatchHook public requiredHook;

    struct Delivery {
        address processor;
        uint64 blockNumber;
    }

    mapping(bytes32 => Delivery) internal deliveries;

    event DefaultIsmSet(address indexed module);

    event DefaultHookSet(address indexed hook);

    event RequiredHookSet(address indexed hook);

    constructor(uint32 _localDomain) {
        localDomain = _localDomain;
    }

    function initialize(
        address _owner,
        address _defaultIsm,
        address _defaultHook,
        address _requiredHook
    ) external {
        __Ownable_init();
        setDefaultIsm(_defaultIsm);
        setDefaultHook(_defaultHook);
        setRequiredHook(_requiredHook);
        transferOwnership(_owner);
    }

    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes calldata _messageBody
    ) external override returns (bytes32) {
        return
            dispatch(
                _destinationDomain,
                _recipientAddress,
                _messageBody,
                new bytes(0),
                defaultHook
            );
    }

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata hookMetadata
    ) external override returns (bytes32) {
        return
            dispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                hookMetadata,
                defaultHook
            );
    }

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint64 fee) {
        return
            quoteDispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                new bytes(0),
                defaultHook
            );
    }

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint64 fee) {
        return
            quoteDispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                defaultHookMetadata,
                defaultHook
            );
    }

    function process(
        bytes calldata _metadata,
        bytes calldata _message
    ) external override {
        require(_message.version() == VERSION, "Mailbox: bad version");
        require(
            _message.destination() == localDomain,
            "Mailbox: unexpected destination"
        );

        bytes32 _id = _message.id();
        require(delivered(_id) == false, "Mailbox: already delivered");

        address recipient = _message.recipientAddress();
        IInterchainSecurityModule ism = recipientIsm(recipient);

        deliveries[_id] = Delivery({
            processor: tx.accounts.dataAccount.key,
            blockNumber: uint64(block.number)
        });
        emit Process(_message.origin(), _message.sender(), recipient);
        emit ProcessId(_id);

        require(
            ism.verify{accounts: tx.accounts}(_metadata, _message),
            "Mailbox: ISM verification failed"
        );

        IMessageRecipient(recipient).handle{accounts: tx.accounts}(
            _message.origin(),
            _message.sender(),
            _message.body()
        );
    }

    function processor(bytes32 _id) external view returns (address) {
        return deliveries[_id].processor;
    }

    function processedAt(bytes32 _id) external view returns (uint64) {
        return deliveries[_id].blockNumber;
    }

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata metadata,
        IPostDispatchHook hook
    ) public virtual returns (bytes32) {
        if (address(hook) == address(0)) {
            hook = defaultHook;
        }

        bytes memory message = _buildMessage(
            destinationDomain,
            recipientAddress,
            messageBody
        );
        bytes32 id = message.id();

        latestDispatchedId = id;
        nonce += 1;
        emit Dispatch(tx.accounts.dataAccount.key, destinationDomain, recipientAddress, message);
        emit DispatchId(id);

        uint64 requiredValue = requiredHook.quoteDispatch(metadata, message);
        uint64 msgValue = tx.accounts.dataAccount.lamports;
        if (msgValue < requiredValue) {
            requiredValue = msgValue;
        }
        requiredHook.postDispatch{accounts: tx.accounts}(metadata, message);
        hook.postDispatch{accounts: tx.accounts}(metadata, message);

        return id;
    }

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata metadata,
        IPostDispatchHook hook
    ) public view returns (uint64 fee) {
        if (address(hook) == address(0)) {
            hook = defaultHook;
        }

        bytes memory message = _buildMessage(
            destinationDomain,
            recipientAddress,
            messageBody
        );
        return
            requiredHook.quoteDispatch(metadata, message) +
            hook.quoteDispatch(metadata, message);
    }

    function delivered(bytes32 _id) public view override returns (bool) {
        return deliveries[_id].blockNumber > 0;
    }

    function setDefaultIsm(address _module) public onlyOwner {
        require(
            isContract(_module),
            "Mailbox: default ISM not contract"
        );
        defaultIsm = IInterchainSecurityModule(_module);
        emit DefaultIsmSet(_module);
    }

    function setDefaultHook(address _hook) public onlyOwner {
        require(
            isContract(_hook),
            "Mailbox: default hook not contract"
        );
        defaultHook = IPostDispatchHook(_hook);
        emit DefaultHookSet(_hook);
    }

    function setRequiredHook(address _hook) public onlyOwner {
        require(
            isContract(_hook),
            "Mailbox: required hook not contract"
        );
        requiredHook = IPostDispatchHook(_hook);
        emit RequiredHookSet(_hook);
    }

    function recipientIsm(
        address _recipient
    ) public view returns (IInterchainSecurityModule) {
        (bool success, bytes memory returnData) = _recipient.staticcall{accounts: tx.accounts}(
            abi.encodeCall(
                ISpecifiesInterchainSecurityModule.interchainSecurityModule,
                ()
            )
        );
        if (success && returnData.length != 0) {
            address ism = abi.decode(returnData, (address));
            if (ism != address(0)) {
                return IInterchainSecurityModule(ism);
            }
        }
        return defaultIsm;
    }

    function _buildMessage(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) internal view returns (bytes memory) {
        return
            Message.formatMessage(
                VERSION,
                nonce,
                localDomain,
                tx.accounts.dataAccount.key.addressToBytes32(),
                destinationDomain,
                recipientAddress,
                messageBody
            );
    }

    function isContract(address addr) internal view returns (bool) {
        AccountInfo memory account = tx.accounts.getAccount(addr);
        return account.owner != address(0);
    }
}
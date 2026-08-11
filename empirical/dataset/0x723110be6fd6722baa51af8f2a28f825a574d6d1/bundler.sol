// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ─── Interfaces ───────────────────────────────────────────────────────────────

interface IDelegateImpl {
    function setFactory(address _factory) external;
    function execute(address target, bytes calldata data) external payable;
}

interface ISeaDrop {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;
}

// ─── Step 1: Deploy DelegateImpl ─────────────────────────────────────────────
// Get its address → put in batch_config.json as "delegate_impl_contract"
//
// EIP-7702 installs this contract's bytecode at each recipient EOA address.
// When the coordinator calls execute(), it runs in the context of the EOA:
//   - address(this) = EOA address
//   - msg.sender to SeaDrop = EOA address  ← SeaDrop sees the real wallet
//
contract DelegateImpl {
    address public factory; // stored in EOA's storage slot 0

    // Called by coordinator inside addDelegates tx to register coordinator
    function setFactory(address _factory) external {
        factory = _factory;
    }

    // Called by coordinator inside batchMint tx to forward mint call
    function execute(address target, bytes calldata data) external payable {
        require(msg.sender == factory, "not factory");
        (bool ok,) = target.call{value: msg.value}(data);
        require(ok, "call failed");
    }

    // Required: some NFTs use _safeMint which calls onERC721Received on contracts
    function onERC721Received(
        address, address, uint256, bytes calldata
    ) external pure returns (bytes4) {
        return 0x150b7a02;
    }
}

// ─── Step 2: Deploy Coordinator ──────────────────────────────────────────────
// Constructor arg: DelegateImpl address from step 1
// Put Coordinator address in batch_config.json as "batch_minter_contract"
//
contract Coordinator {
    address public owner;
    address public delegateImpl;
    address[] private _delegates;
    mapping(address => bool) public isDelegateAddr;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _delegateImpl) {
        owner = msg.sender;
        delegateImpl = _delegateImpl;
    }

    // ── delegate.go add ──────────────────────────────────────────────────────
    // Called inside EIP-7702 Type 4 tx (after EVM installs DelegateImpl on EOAs)
    function addDelegates(address[] calldata delegates) external onlyOwner {
        for (uint256 i = 0; i < delegates.length; i++) {
            address d = delegates[i];
            if (isDelegateAddr[d]) continue;
            isDelegateAddr[d] = true;
            _delegates.push(d);
            // EOA now has DelegateImpl code → setFactory works
            IDelegateImpl(d).setFactory(address(this));
        }
    }

    // ── delegate.go remove ───────────────────────────────────────────────────
    // Called inside EIP-7702 Type 4 tx (EVM clears code from EOAs)
    function removeDelegates(address[] calldata delegates) external onlyOwner {
        for (uint256 i = 0; i < delegates.length; i++) {
            address d = delegates[i];
            if (!isDelegateAddr[d]) continue;
            isDelegateAddr[d] = false;
            for (uint256 j = 0; j < _delegates.length; j++) {
                if (_delegates[j] == d) {
                    _delegates[j] = _delegates[_delegates.length - 1];
                    _delegates.pop();
                    break;
                }
            }
        }
    }

    // ── main.go (MEV bundle) ─────────────────────────────────────────────────
    // msg.value = mintPriceEach * quantity * len(_delegates) + desiredBribe
    // After minting loop, remaining balance → block.coinbase (the bribe)
    function batchMint(
        address seadrop,
        address nftContract,
        address feeRecipient,
        uint256 mintPriceEach,
        uint256 quantity
    ) external payable onlyOwner {
        bytes memory mintCalldata = abi.encodeCall(
            ISeaDrop.mintPublic,
            (nftContract, feeRecipient, address(0), quantity)
        );
        uint256 mintValue = mintPriceEach * quantity;
        for (uint256 i = 0; i < _delegates.length; i++) {
            IDelegateImpl(_delegates[i]).execute{value: mintValue}(seadrop, mintCalldata);
        }
        // All remaining ETH → builder bribe
        (bool ok,) = block.coinbase.call{value: address(this).balance}("");
        require(ok, "bribe failed");
    }

    function getDelegates() external view returns (address[] memory) {
        return _delegates;
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import {IERC20, Token} from "./Token.sol";

/// @title TokenVault - Holds ERC20 tokens locked during bridge transfers
/// @notice Simple vault that holds ERC20 tokens and releases them only when
///         instructed by the bridge contract.
/// @dev Deployed automatically by the PublicBridge constructor.
contract TokenVault {
    /// @notice The bridge contract authorized to trigger releases
    address public immutable bridge;

    /// @notice The ERC20 token held by this vault
    IERC20 public immutable token;  
    
    /// @notice Initializes the vault with the authorized bridge and token addresses
    /// @param _bridge The address of the PublicBridge contract
    /// @param _token The address of the ERC20 token contract
    constructor(address _bridge, address _token) {
        bridge = _bridge;
        token = IERC20(_token);
    }
        
    /// @notice Releases ERC20 tokens to a specified address
    /// @dev Only callable by the bridge contract
    /// @param to The recipient of the released tokens
    /// @param amount The amount of tokens to release
    function release(address to, uint256 amount) external {
        require(msg.sender == bridge, "Only bridge");
        require(token.transfer(to, amount), "Transfer failed");
    }
}

/// @title PublicBridge - Bridge contract for public EVM chains
/// @notice Deployed on public chains (Ethereum, BSC, Base) as part of Bridge X. Handles
///         ERC20 token locking when bridging to the private chain, and releasing/minting
///         ERC20 tokens when bridging from the private chain. Uses a multi-signature relayer
///         model where multiple authorized releasers must sign before tokens are released.
/// @dev This contract creates and manages its own TokenVault for holding locked ERC20 tokens.
///      When releasing tokens, the bridge first attempts to release from the vault. If the
///      vault has insufficient balance, the bridge mints the difference (requires issuer role
///      on the Token contract). Release fees are paid in native token (ETH/BNB) and distributed
///      equally among all authorized releasers. Bridge fees are paid in ERC20 tokens.
contract PublicBridge {
    /// @notice The ERC20 token contract this bridge operates on
    IERC20 public immutable token;

    /// @notice The vault contract that holds locked ERC20 tokens
    TokenVault public immutable vault;

    /// @notice The owner of the bridge (deployer)
    address public owner;

    /// @notice The address proposed as the new owner (must call acceptOwnership to complete transfer)
    address public pendingOwner;

    /// @notice Fee required to be paid (in native token) before tokens can be released
    uint256 public releaseFee;

    /// @notice Fee deducted in ERC20 tokens during lockTokens, sent to bridgeFeeReceiver
    uint256 public bridgeFee;

    /// @notice Address that receives the bridgeFee
    address public bridgeFeeReceiver;

    /// @dev Reentrancy guard state variable (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;

    /// @dev Nonce used to generate unique hashes for lock transactions
    uint256 private _nonce;

    /// @notice Whether the bridge is currently paused
    bool public paused;
    
    /// @notice Array of authorized releaser addresses
    address[] public releasers;

    /// @notice Mapping to check if an address is an authorized releaser
    mapping(address releaser => bool authorized) public isReleaser;

    /// @notice Number of releaser signatures required to process a release
    uint256 public requiredSignatures = 2;
    
    /// @notice Enum representing the supported destination chains
    /// @dev Only DestinationChain.Private (0) is valid for public bridges since they
    ///      only bridge tokens back to the private chain
    enum DestinationChain {
        Private,     // 0 - bridge to self (not allowed)
        Ethereum,    // 1 - bridge to Sepolia/Ethereum
        BSC,         // 2 - bridge to BSC
        Base,        // 3 - bridge to Base
        Reserved4,   // 4 - reserved for future use
        Reserved5,   // 5 - reserved for future use
        Reserved6,   // 6 - reserved for future use
        Reserved7,   // 7 - reserved for future use
        Reserved8    // 8 - reserved for future use
    }

    /// @notice Maps destination chains to their EVM chain IDs
    mapping(DestinationChain destinationChain => uint256 chainId) public chainIds;
    
    /// @notice Tracks which source chain transaction hashes have already been processed
    mapping(bytes32 sourceChainTxHash => bool processed) public processedHashes;

    /// @notice Tracks how many releases each address is eligible for (based on fees paid)
    mapping(address recipient => uint256 releases) public eligibleBridgeReleases;
    
    /// @notice Tracks which releasers have signed for a given release transaction hash
    mapping(bytes32 txHash => mapping(address releaser => bool signed)) public signatures;

    /// @notice Tracks the total number of signatures for a given release transaction hash
    mapping(bytes32 txHash => uint256 count) public signatureCount;
    
    /// @notice Structure representing a pending release awaiting fee payment
    /// @param recipient The address that will receive the released tokens
    /// @param amount The amount of tokens to release
    /// @param sourceChainTxHash The transaction hash from the source chain lock event
    /// @param destinationChain The chain the tokens were bridged from
    /// @param exists Whether this pending release is still active (not yet processed)
    struct PendingRelease {
        address recipient;
        DestinationChain destinationChain;
        bool exists;
        uint256 amount;
        bytes32 sourceChainTxHash;
    }
    
    /// @notice Maps each recipient to their array of pending releases
    mapping(address recipient => PendingRelease[] releases) public pendingReleasesByRecipient;
    
    /// @notice Array of all addresses that currently have pending releases
    address[] public pendingRecipients;

    /// @notice Tracks whether an address has any pending releases
    mapping(address recipient => bool hasPending) public hasPendingReleases;

    /// @notice Emitted when ownership transfer is initiated or completed
    /// @param previousOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    /// @param confirmed Whether the transfer has been confirmed by the new owner
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        bool confirmed
    );

    /// @notice Emitted when ERC20 tokens are locked in the vault for bridging
    /// @param from The address that locked the tokens
    /// @param amount The amount locked (after bridge fee deduction)
    /// @param sourceChainTxHash Unique hash identifying this lock transaction
    /// @param destinationChain The target chain (always Private for public bridges)
    /// @param chainId The chain ID (0 for private chain)
    event TokensLocked(
        address indexed from, 
        uint256 amount, 
        bytes32 indexed sourceChainTxHash,
        DestinationChain indexed destinationChain,  
        uint256 chainId
    );
    
    /// @notice Emitted when tokens are released or minted to a recipient
    /// @param to The address receiving the tokens
    /// @param amount The amount released/minted
    /// @param destinationChain The chain context of the release
    /// @param chainId The chain ID
    event TokensReleased(
        address indexed to, 
        uint256 amount, 
        DestinationChain indexed destinationChain,  
        uint256 indexed chainId
    );

    /// @notice Emitted when the owner force-processes a pending release
    /// @param recipient The address that received the tokens
    /// @param amount The amount released
    /// @param sourceChainTxHash The original source chain transaction hash
    event ForcedRelease(
        address indexed recipient,
        uint256 amount,
        bytes32 sourceChainTxHash
    );

    /// @notice Emitted when a release fails due to mint constraints (e.g., maxSupply reached)
    /// @param to The intended recipient
    /// @param amount The amount that failed to release
    /// @param reason A description of why the release failed
    event ReleaseFailed(
        address indexed to,
        uint256 amount,
        string reason
    );
    
    /// @notice Emitted when a user pays the release fee
    /// @param from The address that paid the fee
    /// @param amount The total fee amount paid
    event FeePaid(
        address indexed from,
        uint256 amount
    );

    /// @notice Emitted when release fees are distributed to releasers
    /// @param from The address that paid the fee
    /// @param amountPerReleaser The amount each releaser received
    /// @param numberOfReleasers The total number of releasers that received fees
    event FeeDistributed(
        address indexed from,
        uint256 amountPerReleaser,
        uint256 numberOfReleasers
    );
    
    /// @notice Emitted when a pending release is created (user hasn't paid release fee)
    /// @param recipient The intended recipient of the release
    /// @param amount The amount pending release
    /// @param sourceChainTxHash The source chain transaction hash
    event PendingReleaseCreated(
        address indexed recipient,
        uint256 amount,
        bytes32 sourceChainTxHash
    );
    
    /// @notice Emitted when a pending release is processed after fee payment
    /// @param recipient The address that received the tokens
    /// @param amount The amount released
    /// @param sourceChainTxHash The source chain transaction hash
    event PendingReleaseProcessed(
        address indexed recipient,
        uint256 amount,
        bytes32 sourceChainTxHash
    );
    
    /// @notice Emitted when a releaser signs a release transaction
    /// @param signer The releaser that signed
    /// @param txHash The release transaction hash that was signed
    /// @param currentSignatureCount The total signatures after this signing
    event ReleaseSigned(
        address indexed signer,
        bytes32 indexed txHash,
        uint256 currentSignatureCount
    );

    /// @notice Emitted when a bridge fee is paid during token locking
    /// @param from The address that paid the bridge fee
    /// @param receiver The address that received the bridge fee
    /// @param amount The bridge fee amount
    event BridgeFeePaid(
        address indexed from,
        address indexed receiver,
        uint256 amount
    );

    /// @notice Emitted when the bridge fee is updated
    /// @param newFee The new bridge fee amount
    event BridgeFeeUpdated(uint256 newFee);

    /// @notice Emitted when the bridge fee receiver is updated
    /// @param newReceiver The new fee receiver address
    event BridgeFeeReceiverUpdated(address newReceiver);

    /// @notice Emitted when the release fee is updated
    /// @param newFee The new release fee amount
    event ReleaseFeeUpdated(uint256 newFee);

    /// @notice Emitted when the bridge is paused
    /// @param by The address that paused the bridge
    event BridgePaused(address indexed by);

    /// @notice Emitted when the bridge is unpaused
    /// @param by The address that unpaused the bridge
    event BridgeUnpaused(address indexed by);

    /// @notice Emitted when a new releaser is added
    /// @param releaser The address of the new releaser
    event ReleaserAdded(address indexed releaser);

    /// @notice Emitted when a releaser is removed
    /// @param releaser The address of the removed releaser
    event ReleaserRemoved(address indexed releaser);

    /// @notice Emitted when the required signature threshold is updated
    /// @param newRequiredSignatures The new number of required signatures
    event RequiredSignaturesUpdated(uint256 newRequiredSignatures);

    /// @notice Emitted when a destination chain ID mapping is updated
    /// @param destinationChain The destination chain that was updated
    /// @param chainId The new chain ID assigned
    event ChainIdUpdated(DestinationChain indexed destinationChain, uint256 chainId);
    
    /// @dev Restricts access to the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    
    /// @dev Restricts access to authorized releasers
    modifier onlyReleaser() {
        require(isReleaser[msg.sender], "Not authorized releaser");
        _;
    }

    /// @dev Prevents execution when the bridge is paused
    modifier whenNotPaused() {
        require(!paused, "Bridge is paused");
        _;
    }

    /// @dev Prevents reentrancy attacks using a lock state variable
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }
    
    /// @notice Deploys the PublicBridge, creates a TokenVault, and configures fees
    /// @param _token The address of the ERC20 token contract
    /// @param _releaseFee The fee users must pay in native token to be eligible for a release
    /// @param _bridgeFee The fee deducted in ERC20 tokens from each bridge transaction
    /// @param _bridgeFeeReceiver The address that receives bridge fees
    constructor(address _token, uint256 _releaseFee, uint256 _bridgeFee, address _bridgeFeeReceiver) {
        token = IERC20(_token);
        owner = msg.sender;
        require(_releaseFee > 0, "Fee must be positive");
        releaseFee = _releaseFee;
        
        require(_bridgeFeeReceiver != address(0), "Invalid bridge fee receiver");
        bridgeFee = _bridgeFee;
        bridgeFeeReceiver = _bridgeFeeReceiver;
        
        vault = new TokenVault(address(this), _token);
    }
    
    /// @notice Returns the EVM chain ID for a given destination chain
    /// @param destinationChain The destination chain enum value
    /// @return The EVM chain ID (0 if not configured)
    function getChainId(DestinationChain destinationChain) public view returns (uint256) {
        return chainIds[destinationChain];
    }

    /// @notice Sets the EVM chain ID for a destination chain
    /// @dev Only callable by the owner. Used to configure new chains without redeployment.
    /// @param destinationChain The destination chain enum value
    /// @param chainId The EVM chain ID to associate with this destination
    function setChainId(DestinationChain destinationChain, uint256 chainId) external onlyOwner {
        chainIds[destinationChain] = chainId;
        emit ChainIdUpdated(destinationChain, chainId);
    }
    
    /// @notice Adds a new authorized releaser
    /// @dev Only callable by the owner. The releaser address must not be zero or already a releaser.
    /// @param _releaser The address to authorize as a releaser
    function addReleaser(address _releaser) external onlyOwner {
        require(_releaser != address(0), "Invalid address");
        require(!isReleaser[_releaser], "Already a releaser");
        
        releasers.push(_releaser);
        isReleaser[_releaser] = true;
        emit ReleaserAdded(_releaser);
    }
    
    /// @notice Removes an authorized releaser
    /// @dev Only callable by the owner. Uses swap-and-pop to remove from the array.
    /// @param _releaser The address to remove from the releaser list
    function removeReleaser(address _releaser) external onlyOwner {
        require(isReleaser[_releaser], "Not a releaser");
        
        isReleaser[_releaser] = false;
        
        uint256 len = releasers.length;
        for (uint256 i; i < len; i++) {
            if (releasers[i] == _releaser) {
                releasers[i] = releasers[len - 1];
                releasers.pop();
                break;
            }
        }
        emit ReleaserRemoved(_releaser);
    }
    
    /// @notice Updates the number of required signatures for releases
    /// @dev Must be between 1 and the current number of releasers (inclusive)
    /// @param _requiredSignatures The new signature threshold
    function setRequiredSignatures(uint256 _requiredSignatures) external onlyOwner {
        require(_requiredSignatures > 0 && _requiredSignatures <= releasers.length, "Invalid number");
        requiredSignatures = _requiredSignatures;
        emit RequiredSignaturesUpdated(_requiredSignatures);
    }
    
    /// @notice Updates the release fee
    /// @param _newFee The new release fee amount (in wei of native token)
    function setReleaseFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "Fee must be positive");
        releaseFee = _newFee;
        emit ReleaseFeeUpdated(_newFee);
    }
    
    /// @notice Pays the release fee to become eligible for token releases
    /// @dev The fee is distributed equally among all releasers in native token.
    ///      Users can pay for multiple releases in a single transaction. Any excess
    ///      payment is refunded. If the user has pending releases, they are automatically
    ///      processed after fee payment.
    function payReleaseFee() external payable nonReentrant whenNotPaused {
        uint256 _releaseFee = releaseFee;
        require(msg.value >= _releaseFee, "Insufficient fee");
        uint256 releasersLength = releasers.length;
        require(releasersLength > 0, "No releasers available");
        
        uint256 eligibleReleases = msg.value / _releaseFee;
        eligibleBridgeReleases[msg.sender] += eligibleReleases;
        
        uint256 totalFee = eligibleReleases * _releaseFee;
        uint256 feePerReleaser = totalFee / releasersLength;
        
        uint256 distributed;
        if (feePerReleaser > 0) {
            for (uint256 i; i < releasersLength; i++) {
                bool success;
                address feeReceiver = releasers[i];
                assembly {
                    success := call(gas(), feeReceiver, feePerReleaser, 0, 0, 0, 0)
                }
                if (success) {
                    distributed += feePerReleaser;
                }
            }
        }
        
        uint256 remainingWei = totalFee - (feePerReleaser * releasersLength);
        if (remainingWei > 0) {
            bool success;
            address feeReceiver = releasers[0];
            assembly {
                success := call(gas(), feeReceiver, remainingWei, 0, 0, 0, 0)
            }
            if (success) {
                distributed += remainingWei;
            }
        }
        
        emit FeePaid(msg.sender, totalFee);
        emit FeeDistributed(msg.sender, feePerReleaser, releasersLength);
        
        uint256 refundAmount = msg.value - distributed;
        if (refundAmount > 0) {
            bool success;
            address refundReceiver = msg.sender;
            assembly {
                success := call(gas(), refundReceiver, refundAmount, 0, 0, 0, 0)
            }
            require(success, "Refund failed");
        }
        
        _processPendingReleases(msg.sender);
    }
    
    /// @notice Locks ERC20 tokens in the vault to initiate a bridge transfer to the private chain
    /// @dev Requires prior ERC20 approval. Deducts bridgeFee (if set) via transferFrom to the
    ///      fee receiver. The remaining amount is transferred to the vault. Emits a TokensLocked
    ///      event for relayer nodes.
    /// @param amount The total amount of ERC20 tokens to bridge (including bridge fee)
    /// @param destinationChain Must be DestinationChain.Private (0)
    function lockTokens(uint256 amount, DestinationChain destinationChain) external nonReentrant whenNotPaused {
        require(destinationChain == DestinationChain.Private, "Can only bridge to Private chain");
        require(amount > 0, "Amount required");
        
        uint256 _bridgeFee = bridgeFee;
        if (_bridgeFee > 0) {
            require(amount > _bridgeFee, "Amount less than bridge fee");
            
            amount -= _bridgeFee;
            
            address _bridgeFeeReceiver = bridgeFeeReceiver;
            require(token.transferFrom(msg.sender, _bridgeFeeReceiver, _bridgeFee), "Bridge fee transfer failed");
            
            emit BridgeFeePaid(msg.sender, _bridgeFeeReceiver, _bridgeFee);
        }
        
        require(token.transferFrom(msg.sender, address(vault), amount), "Transfer to vault failed");
                
        bytes32 uniqueHash = keccak256(abi.encodePacked(
            msg.sender,
            amount,
            block.timestamp,
            block.number,
            _nonce++,
            address(this),
            destinationChain
        ));
        
        emit TokensLocked(
            msg.sender,
            amount,
            uniqueHash,
            destinationChain,
            0
        );
    }
    
    /// @notice Signs a release transaction as an authorized releaser
    /// @dev Each releaser calls this independently with the same parameters. Once
    ///      requiredSignatures is reached, the release is processed. If the vault has
    ///      insufficient balance, the bridge mints the difference. If the recipient
    ///      has not paid the release fee, the release goes into pending state.
    /// @param to The recipient address for the release
    /// @param amount The amount of tokens to release
    /// @param sourceChainTxHash The transaction hash from the source chain's TokensLocked event
    /// @param destinationChain The chain enum identifying the bridge route
    function signRelease(
        address to,
        uint256 amount,
        bytes32 sourceChainTxHash,
        DestinationChain destinationChain
    ) external onlyReleaser nonReentrant whenNotPaused {
        require(!processedHashes[sourceChainTxHash], "Already processed");

        bytes32 txHash = keccak256(abi.encodePacked(to, amount, sourceChainTxHash, destinationChain));
        
        require(!signatures[txHash][msg.sender], "Already signed");
        
        signatures[txHash][msg.sender] = true;
        uint256 newSignatureCount = ++signatureCount[txHash];
        
        emit ReleaseSigned(msg.sender, txHash, newSignatureCount);
        
        if (newSignatureCount >= requiredSignatures) {
            processedHashes[sourceChainTxHash] = true;
            
            if (eligibleBridgeReleases[to] > 0) {
                eligibleBridgeReleases[to]--;
                if (!_releaseTokens(to, amount, destinationChain)) {
                    eligibleBridgeReleases[to]++;
                    _addPendingRelease(to, amount, sourceChainTxHash, destinationChain);
                }
            } else {
                _addPendingRelease(to, amount, sourceChainTxHash, destinationChain);
            }
        }
    }
    
    /// @dev Internal function that releases ERC20 tokens from the vault, minting any shortfall.
    ///      If minting would exceed the token's maxSupply, returns false so callers can handle
    ///      the failure gracefully (e.g., keep the release in pending state for retry).
    /// @param to The recipient address
    /// @param amount The total amount to release
    /// @param destinationChain The chain context for event emission
    /// @return success Whether the release was completed successfully
    function _releaseTokens(
        address to,
        uint256 amount,
        DestinationChain destinationChain
    ) internal returns (bool) {
        uint256 chainId = getChainId(destinationChain);
        require(chainId == block.chainid, "Invalid destination chain for this bridge");

        uint256 vaultBalance = token.balanceOf(address(vault));
        
        if (vaultBalance >= amount) {
            vault.release(to, amount);
        } else {
            uint256 mintNeeded = amount - vaultBalance;
            
            try Token(address(token)).mint(to, mintNeeded) {
                if (vaultBalance > 0) {
                    vault.release(to, vaultBalance);
                }
            } catch {
                emit ReleaseFailed(to, amount, "Mint failed - maxSupply likely reached");
                return false;
            }
        }
        
        emit TokensReleased(to, amount, destinationChain, chainId);
        return true;
    }
    
    /// @dev Internal function that creates a pending release when the recipient hasn't paid the fee
    /// @param recipient The intended recipient
    /// @param amount The amount to be released when fee is paid
    /// @param sourceChainTxHash The source chain transaction hash
    /// @param destinationChain The destination chain enum
    function _addPendingRelease(
        address recipient,
        uint256 amount,
        bytes32 sourceChainTxHash,
        DestinationChain destinationChain
    ) internal {
        PendingRelease memory newRelease = PendingRelease({
            recipient: recipient,
            destinationChain: destinationChain,
            exists: true,
            amount: amount,
            sourceChainTxHash: sourceChainTxHash
        });
        
        pendingReleasesByRecipient[recipient].push(newRelease);
        
        if (!hasPendingReleases[recipient]) {
            pendingRecipients.push(recipient);
            hasPendingReleases[recipient] = true;
        }
        
        emit PendingReleaseCreated(recipient, amount, sourceChainTxHash);
    }
    
    /// @dev Internal function that processes pending releases in FIFO order after fee payment
    /// @param recipient The address whose pending releases should be processed
    function _processPendingReleases(address recipient) internal {
        PendingRelease[] storage releases = pendingReleasesByRecipient[recipient];
        
        uint256 len = releases.length;
        for (uint256 i; i < len && eligibleBridgeReleases[recipient] > 0; i++) {
            if (releases[i].exists) {
                eligibleBridgeReleases[recipient]--;
                
                if (_releaseTokens(
                    releases[i].recipient,
                    releases[i].amount,
                    releases[i].destinationChain
                )) {
                    emit PendingReleaseProcessed(
                        releases[i].recipient,
                        releases[i].amount,
                        releases[i].sourceChainTxHash
                    );
                    releases[i].exists = false;
                } else {
                    eligibleBridgeReleases[recipient]++;
                    break;
                }
            }
        }
        
        _cleanPendingReleases(recipient);
    }
    
    /// @dev Internal function that compacts the pending releases array after processing
    /// @param recipient The address whose pending releases array should be cleaned
    function _cleanPendingReleases(address recipient) internal {
        PendingRelease[] storage releases = pendingReleasesByRecipient[recipient];
        
        uint256 len = releases.length;
        uint256 remainingCount;
        for (uint256 i; i < len; i++) {
            if (releases[i].exists) {
                remainingCount++;
            }
        }
        
        if (remainingCount == 0) {
            delete pendingReleasesByRecipient[recipient];
            hasPendingReleases[recipient] = false;
            
            uint256 pendingLen = pendingRecipients.length;
            for (uint256 i; i < pendingLen; i++) {
                if (pendingRecipients[i] == recipient) {
                    pendingRecipients[i] = pendingRecipients[pendingLen - 1];
                    pendingRecipients.pop();
                    break;
                }
            }
        } else if (remainingCount < len) {
            PendingRelease[] memory newReleases = new PendingRelease[](remainingCount);
            uint256 index;
            
            for (uint256 i; i < len; i++) {
                if (releases[i].exists) {
                    newReleases[index] = releases[i];
                    index++;
                }
            }
            
            delete pendingReleasesByRecipient[recipient];
            for (uint256 i; i < remainingCount; i++) {
                pendingReleasesByRecipient[recipient].push(newReleases[i]);
            }
        }
    }
    
    /// @notice Returns the number of pending releases for a given recipient
    /// @param recipient The address to query
    /// @return The number of pending releases
    function getPendingReleaseCount(address recipient) external view returns (uint256) {
        return pendingReleasesByRecipient[recipient].length;
    }
    
    /// @notice Returns details of a specific pending release
    /// @param recipient The address to query
    /// @param index The index in the recipient's pending releases array
    /// @return _recipient The recipient address
    /// @return amount The pending release amount
    /// @return sourceChainTxHash The source chain transaction hash
    /// @return exists Whether the pending release is still active
    function getPendingRelease(address recipient, uint256 index) external view returns (
        address _recipient,
        uint256 amount,
        bytes32 sourceChainTxHash,
        bool exists
    ) {
        require(index < pendingReleasesByRecipient[recipient].length, "Index out of bounds");
        PendingRelease storage release = pendingReleasesByRecipient[recipient][index];
        return (
            release.recipient,
            release.amount,
            release.sourceChainTxHash,
            release.exists
        );
    }

    /// @notice Checks whether a recipient's pending releases can be processed
    /// @dev Returns true if the recipient has eligible releases, pending releases,
    ///      and the vault has sufficient balance (or bridge can mint) for the first
    ///      pending release. This is a gas-free view function intended for off-chain
    ///      use by relayers to avoid wasting gas on calls that would revert.
    /// @param recipient The address to check
    /// @return True if at least one pending release can be processed
    function canProcessPendingRelease(address recipient) external view returns (bool) {
        if (eligibleBridgeReleases[recipient] == 0) return false;
        
        PendingRelease[] storage releases = pendingReleasesByRecipient[recipient];
        if (releases.length == 0) return false;
        
        for (uint256 i; i < releases.length; i++) {
            if (releases[i].exists) {
                // PublicBridge can mint if vault is short, so just return true
                // if there's a valid pending release with eligible credits
                return true;
            }
        }
        return false;
    }

    /// @notice Processes pending releases for a given recipient
    /// @dev Callable by anyone. Only processes releases for recipients who have
    ///      already paid the release fee (have eligible releases). This allows
    ///      relayers to trigger processing when vault liquidity becomes available
    ///      without requiring the recipient to take action.
    /// @param recipient The address whose pending releases should be processed
    function processPendingReleasesFor(address recipient) external nonReentrant whenNotPaused {
        require(eligibleBridgeReleases[recipient] > 0, "No eligible releases");
        require(pendingReleasesByRecipient[recipient].length > 0, "No pending releases");
        _processPendingReleases(recipient);
    }
    
    /// @notice Emergency function to force-process a pending release without fee payment
    /// @dev Only callable by the owner. Bypasses the release fee requirement.
    /// @param recipient The address with the pending release
    /// @param index The index of the pending release to process
    function forceProcessPendingRelease(
        address recipient,
        uint256 index
    ) external onlyOwner nonReentrant {
        require(index < pendingReleasesByRecipient[recipient].length, "Index out of bounds");
        PendingRelease storage release = pendingReleasesByRecipient[recipient][index];
        require(release.exists, "Release already processed");
        
        address cachedRecipient = release.recipient;
        uint256 cachedAmount = release.amount;
        
        require(
            _releaseTokens(
                cachedRecipient,
                cachedAmount,
                release.destinationChain
            ),
            "Release failed - mint may have hit maxSupply"
        );

        emit ForcedRelease(cachedRecipient, cachedAmount, release.sourceChainTxHash);
        
        release.exists = false;
        
        _cleanPendingReleases(recipient);
    }
    
    /// @notice Returns the current signature count for a specific release
    /// @param to The recipient address
    /// @param amount The release amount
    /// @param sourceChainTxHash The source chain transaction hash
    /// @param destinationChain The destination chain enum
    /// @return The number of signatures collected so far
    function getSignatureCount(
        address to, 
        uint256 amount, 
        bytes32 sourceChainTxHash,
        DestinationChain destinationChain
    ) external view returns (uint256) {
        bytes32 txHash = keccak256(abi.encodePacked(to, amount, sourceChainTxHash, destinationChain));
        return signatureCount[txHash];
    }
    
    /// @notice Checks if a specific releaser has signed a given release
    /// @param releaser The releaser address to check
    /// @param to The recipient address
    /// @param amount The release amount
    /// @param sourceChainTxHash The source chain transaction hash
    /// @param destinationChain The destination chain enum
    /// @return True if the releaser has signed this release
    function hasSignedRelease(
        address releaser,
        address to, 
        uint256 amount, 
        bytes32 sourceChainTxHash,
        DestinationChain destinationChain
    ) external view returns (bool) {
        bytes32 txHash = keccak256(abi.encodePacked(to, amount, sourceChainTxHash, destinationChain));
        return signatures[txHash][releaser];
    }
    
    /// @notice Returns the full list of authorized releasers
    /// @return Array of releaser addresses
    function getReleasers() external view returns (address[] memory) {
        return releasers;
    }

    /// @notice Updates the bridge fee deducted during token locking
    /// @param _newBridgeFee The new bridge fee amount (in ERC20 token units)
    function setBridgeFee(uint256 _newBridgeFee) external onlyOwner {
        bridgeFee = _newBridgeFee;
        emit BridgeFeeUpdated(_newBridgeFee);
    }
    
    /// @notice Updates the address that receives bridge fees
    /// @param _newReceiver The new fee receiver address (must not be zero)
    function setBridgeFeeReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid address");
        bridgeFeeReceiver = _newReceiver;
        emit BridgeFeeReceiverUpdated(_newReceiver);
    }

    /// @notice Pauses the bridge, preventing all lock and release operations
    /// @dev Only callable by the owner when the bridge is not already paused
    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit BridgePaused(msg.sender);
    }

    /// @notice Unpauses the bridge, resuming normal operations
    /// @dev Only callable by the owner
    function unpause() external onlyOwner {
        paused = false;
        emit BridgeUnpaused(msg.sender);
    }

    /// @notice Initiates a two-step ownership transfer
    /// @dev Only callable by the current owner. The new owner must call acceptOwnership()
    ///      to complete the transfer. This two-step process prevents accidental transfers
    ///      to incorrect addresses. Setting pendingOwner to address(0) cancels a pending transfer.
    /// @param _newOwner The address proposed as the new owner
    function transferOwnership(address _newOwner) external onlyOwner {
        pendingOwner = _newOwner;
        emit OwnershipTransferred(msg.sender, _newOwner, false);
    }

    /// @notice Completes the ownership transfer
    /// @dev Only callable by the pending owner set via transferOwnership().
    ///      After completion, the pending owner is cleared.
    function acceptOwnership() external {
        address _pendingOwner = pendingOwner;
        require(msg.sender == _pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, _pendingOwner, true);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }
}

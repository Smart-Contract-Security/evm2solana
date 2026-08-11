// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract MintBundler is Ownable {
    // Array of deployed proxy addresses
    address[] public proxies;
    // Mapping to track proxy indices
    mapping(address => uint256) public proxyIndices;
    // Mapping to track minting progress for each user
    mapping(address => uint256) public mintIndices;
    // Template contract address for proxies
    address public template;
    // Transfer event topic for ERC721
    bytes32 constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");

    // Events
    event ProxyCreated(address indexed proxy);
    event Minted(address indexed user, uint256 quantity, address indexed proxy, bool isERC721, uint256 tokenId);

    // Constructor sets the initial owner
    constructor() Ownable(msg.sender) {}

    // Deploy the template contract (minimal proxy template)
    function deployTemplate() external onlyOwner {
        require(template == address(0), "Template already set");
        bytes memory bytecode = type(MintProxy).creationCode;
        address templateAddr = Create2.deploy(0, bytes32(uint256(0)), bytecode);
        template = templateAddr;
    }

    // Deploy a batch of proxies using CREATE2
    function deployProxies(uint256 quantity) external onlyOwner {
        for (uint256 i = 0; i < quantity; i++) {
            bytes32 salt = keccak256(abi.encodePacked(proxies.length));
            bytes memory bytecode = abi.encodePacked(
                // Minimal proxy bytecode (EIP-1167)
                hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
                template,
                hex"5af43d82803e903d91602b57fd5bf3"
            );
            address proxy = Create2.deploy(0, salt, bytecode);
            require(proxy != address(0), "Proxy deployment failed");
            proxies.push(proxy);
            proxyIndices[proxy] = proxies.length - 1;
            emit ProxyCreated(proxy);
        }
    }

    // Batch mint ERC721 tokens using proxies and transfer to caller
    function batchMint(
        address recipient,
        uint256 quantity,
        bytes calldata mintCallData, // Raw hex data for the mint function call
        bool returnsTokenId // True if mint function returns uint256 tokenId
    ) external payable {
        require(proxies.length > 0, "No proxies deployed");
        require(mintCallData.length >= 4, "Invalid call data");
        uint256 startIndex = mintIndices[recipient];
        require(startIndex + quantity <= proxies.length, "Exceeds proxy count");

        for (uint256 i = 0; i < quantity; i++) {
            uint256 index = startIndex + i;
            address proxy = proxies[index];

            // Call mint function on proxy
            (bool success, bytes memory returnData) = proxy.call{value: msg.value / quantity}(mintCallData);
            require(success, "Mint failed");

            // Validate return data if expected
            if (returnData.length >= 32) {
                bool mintSuccess = abi.decode(returnData, (bool));
                require(mintSuccess, "Mint call returned false");
            }

            // Get token ID for ERC721
            uint256 tokenId;
            if (returnsTokenId && returnData.length >= 32) {
                // Decode token ID from return data
                tokenId = abi.decode(returnData, (uint256));
            } else {
                // Parse Transfer event from logs
                tokenId = _parseTransferEvent(returnData, proxy);
                require(tokenId != 0, "Failed to parse token ID");
            }

            // Transfer ERC721 token
            IERC721(proxy).safeTransferFrom(address(this), recipient, tokenId);
            emit Minted(recipient, 1, proxy, true, tokenId);
        }

        // Update mint index
        mintIndices[recipient] = startIndex + quantity;
    }

    // Batch mint ERC1155 tokens using proxies and transfer to caller
    function batchMintERC1155(
        address recipient,
        uint256 quantity,
        bytes calldata mintCallData,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external payable {
        require(proxies.length > 0, "No proxies deployed");
        require(mintCallData.length >= 4, "Invalid call data");
        require(tokenIds.length == quantity && amounts.length == quantity, "Mismatched arrays");
        uint256 startIndex = mintIndices[recipient];
        require(startIndex + quantity <= proxies.length, "Exceeds proxy count");

        for (uint256 i = 0; i < quantity; i++) {
            uint256 index = startIndex + i;
            address proxy = proxies[index];

            // Call mint function on proxy
            (bool success, bytes memory returnData) = proxy.call{value: msg.value / quantity}(mintCallData);
            require(success, "Mint failed");
            if (returnData.length >= 32) {
                bool mintSuccess = abi.decode(returnData, (bool));
                require(mintSuccess, "Mint call returned false");
            }

            // Transfer ERC1155 token
            IERC1155(proxy).safeTransferFrom(
                address(this),
                recipient,
                tokenIds[i],
                amounts[i],
                ""
            );
            emit Minted(recipient, 1, proxy, false, tokenIds[i]);
        }

        // Update mint index
        mintIndices[recipient] = startIndex + quantity;
    }

    // Parse Transfer event from call return data to extract token ID
    function _parseTransferEvent(bytes memory returnData, address proxy) private view returns (uint256) {
        uint256 tokenId;
        bytes32 transferTopic = TRANSFER_TOPIC; // Assign to a local variable
        assembly {
            // Check if returnData contains logs (non-zero length)
            if gt(mload(returnData), 0) {
                // Iterate over log entries
                let offset := add(returnData, 32) // Skip length prefix
                let end := add(offset, mload(returnData))
                let localTransferTopic := transferTopic // Load into assembly variable
                for {} lt(offset, end) {} {
                    // Read log topics
                    let topic0 := mload(offset) // First topic (event signature)
                    if eq(topic0, localTransferTopic) { // Use local assembly variable
                        // Check if from address is 0x0 (mint event)
                        let fromAddr := mload(add(offset, 32)) // Second topic (from)
                        if eq(fromAddr, 0) {
                            // Extract tokenId from third topic (uint256)
                            tokenId := mload(add(offset, 64))
                            break
                        }
                    }
                    // Move to next log (size of a log entry: topic0 + topic1 + topic2 + topic3 + data_length + data_content)
                    // A log entry with N topics has N+1 words for topics (including topic0)
                    // and then a word for data length, then the data itself.
                    // Assuming max 4 topics for simplicity here, and no data or data length considered for now.
                    // A more robust way would be to parse the log structure fully.
                    // For Transfer(address,address,uint256), there are 3 indexed topics + 1 non-indexed (data).
                    // So, 4 topics (including signature). topic0, topic1 (from), topic2 (to), topic3 (tokenId).
                    // Log structure: topic0, topic1, topic2, topic3, data_offset, data_length, data...
                    // However, the Transfer event as defined usually has:
                    // topics[0] = event signature
                    // topics[1] = from (indexed)
                    // topics[2] = to (indexed)
                    // topics[3] = tokenId (indexed)
                    // So, we expect 4 topics. Each topic is 32 bytes.
                    // The line below assumes no data in the log entry, which is true for Transfer event's indexed parameters.
                    // It moves by 4 * 32 bytes = 128 bytes (for 4 topics).
                    // THIS LOG PARSING IS LIKELY THE SOURCE OF THE "failed to parse token ID" if not careful.
                    // The original `offset := add(offset, add(128, mload(add(offset, 128))))` was for a different log structure or was incorrect.
                    // For a simple log with N topics and D bytes of data, the size is (N+1)*32 + D + (length_of_D_itself_if_dynamic)
                    // For Transfer(address,address,uint256) with 3 indexed topics:
                    // topic0 (signature), topic1 (from), topic2 (to), topic3 (tokenId)
                    // Size = 4 * 32 bytes (for topics) + 0 bytes for data
                    // So, move by 128.
                    offset := add(offset, 128) // Move to the next log entry (assuming 4 topics, no data)
                }
            }
        }
        return tokenId;
    }

    // Withdraw Ether from the contract
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // Receive Ether
    receive() external payable {}

    // ERC721 receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ERC1155 receiver
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // ERC1155 batch receiver
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

// Example minimal proxy contract
contract MintProxy {
    address public immutable implementation;

    constructor() {
        implementation = msg.sender;
    }

    // Generic mint function forwarding to implementation
    function mint(bytes calldata callData) external payable {
        (bool success, bytes memory returnData) = implementation.call{value: msg.value}(callData);
        require(success, "Mint failed");
        // Return data as-is to allow caller to parse
        assembly {
            return(add(returnData, 32), mload(returnData))
        }
    }
}
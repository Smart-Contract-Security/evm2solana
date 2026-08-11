import 'solana';

interface ITransferValidator721 {
    /// @notice Ensure that a transfer has been authorized for a specific tokenId
    function validateTransfer(
        address caller,
        address from,
        address to,
        uint64 tokenId
    ) external view;
}

interface ITransferValidator1155 {
    /// @notice Ensure that a transfer has been authorized for a specific amount of a specific tokenId, and reduce the transferable amount remaining
    function validateTransfer(
        address caller,
        address from,
        address to,
        uint64 tokenId,
        uint64 amount
    ) external;
}
import {AccountInfo} from 'solana';

abstract contract TransferValidation {
    
    function _validateBeforeTransfer(address from, address to, uint64 tokenId) internal {
        bool fromZeroAddress = from == address(0);
        bool toZeroAddress = to == address(0);

        if(fromZeroAddress && toZeroAddress) {
            revert();
        } else if(fromZeroAddress) {
            _preValidateMint(tx.accounts.dataAccount.key, to, tokenId, 0);
        } else if(toZeroAddress) {
            _preValidateBurn(tx.accounts.dataAccount.key, from, tokenId, 0);
        } else {
            _preValidateTransfer(tx.accounts.dataAccount.key, from, to, tokenId, 0);
        }
    }

    function _validateAfterTransfer(address from, address to, uint64 tokenId) internal {
        bool fromZeroAddress = from == address(0);
        bool toZeroAddress = to == address(0);

        if(fromZeroAddress && toZeroAddress) {
            revert();
        } else if(fromZeroAddress) {
            _postValidateMint(tx.accounts.dataAccount.key, to, tokenId, 0);
        } else if(toZeroAddress) {
            _postValidateBurn(tx.accounts.dataAccount.key, from, tokenId, 0);
        } else {
            _postValidateTransfer(tx.accounts.dataAccount.key, from, to, tokenId, 0);
        }
    }

    function _preValidateMint(address caller, address to, uint64 tokenId, uint64 value) internal virtual {}

    function _postValidateMint(address caller, address to, uint64 tokenId, uint64 value) internal virtual {}

    function _preValidateBurn(address caller, address from, uint64 tokenId, uint64 value) internal virtual {}

    function _postValidateBurn(address caller, address from, uint64 tokenId, uint64 value) internal virtual {}

    function _preValidateTransfer(address caller, address from, address to, uint64 tokenId, uint64 value) internal virtual {}

    function _postValidateTransfer(address caller, address from, address to, uint64 tokenId, uint64 value) internal virtual {}
}
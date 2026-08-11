import 'solana';

abstract contract Proxy {
    function _delegate(address implementation) internal virtual {
        AccountMeta[3] metas = [
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: implementation, is_signer: false, is_writable: true}),
            AccountMeta({pubkey: tx.accounts.dataAccount.key, is_signer: false, is_writable: true})
        ];
        bytes memory data = tx.accounts.dataAccount.data;
        implementation.call{accounts: metas}(data);
    }

    function _implementation() internal view virtual returns (address);

    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    fallback() external {
        _fallback();
    }
}
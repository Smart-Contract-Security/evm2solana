import {AccountMeta} from 'solana';

abstract contract MembershipDiscount {
    uint64 internal constant MAX_DISCOUNT_BPS = 10_000;

    bytes8 public constant ACTION_SET_NFT_COLLECTION = bytes8(keccak256("SET_NFT_COLLECTION"));

    address public nftCollection;

    event NftCollectionChanged(address oldCollection, address newCollection);

    function _isMember(
        address account
    ) internal returns (bool) {
        address nft = nftCollection;
        if (nft == address(0)) return false;
        AccountMeta[1] metas = [
            AccountMeta({pubkey: account, is_signer: false, is_writable: false})
        ];
        (bool success, bytes memory result) = nft.call{accounts: metas}(abi.encodeWithSignature("balanceOf(address)", account));
        if (!success) return false;
        uint64 balance = abi.decode(result, (uint64));
        return balance > 0;
    }

    function _effectiveCost(
        uint64 baseCost,
        uint64 discountBps,
        address account
    ) internal returns (uint64) {
        if (baseCost == 0 || discountBps == 0 || !_isMember(account)) return baseCost;
        return baseCost - (baseCost * discountBps / MAX_DISCOUNT_BPS);
    }

    function _setNftCollection(
        address _nft
    ) internal {
        emit NftCollectionChanged(nftCollection, _nft);
        nftCollection = _nft;
    }
}
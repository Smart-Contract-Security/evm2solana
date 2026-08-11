// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

abstract contract MembershipDiscount {
    uint256 internal constant MAX_DISCOUNT_BPS = 10_000;

    bytes32 public constant ACTION_SET_NFT_COLLECTION = keccak256("SET_NFT_COLLECTION");

    address public nftCollection;

    event NftCollectionChanged(address oldCollection, address newCollection);

    function _isMember(
        address account
    ) internal view returns (bool) {
        address nft = nftCollection;
        if (nft == address(0)) return false;
        return IERC721(nft).balanceOf(account) > 0;
    }

    function _effectiveCost(
        uint256 baseCost,
        uint256 discountBps,
        address account
    ) internal view returns (uint256) {
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
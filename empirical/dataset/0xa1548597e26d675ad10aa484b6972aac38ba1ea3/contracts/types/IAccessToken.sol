// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import "./IMerkle.sol";

struct SignatureData {
    uint8 v;
    bytes32 r;
    bytes32 s;
    uint256 accessKey;
    uint256 nonce;
    address ethereumAddress;
}

struct AccessTokenWithAddress {
    uint256 accessToken;
    address ethAddress;
}

interface IAccessToken {
    event NewAccessKeyAdded(
        uint256 accessKey,
        uint256 index,
        address senderAddress
    );
    event MintingFeeChanged(uint256 newMintingFee);
    event AccessKeyBlacklisted(uint256 blacklistedAccessKey);
    event AddressBlacklisted(address blacklistedAddress);
    event AddressRemovedFromBlacklist(address addressToRestore);

    function addToken(SignatureData calldata signatureData) external;

    function hasToken(uint256 accessKey) external view returns (bool);

    function blacklistAccessKey(uint256 accessKey, uint256 index) external;

    function blacklistAddress(address _address) external;

    function removeAddressFromBlacklist(address addressToRestore) external;

    function registerCheck(address sender) external view;

    function checkForRootHash(
        uint256 rootHashAccessToken,
        address sender
    ) external view returns (bool);
}

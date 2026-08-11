// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice GOME — LayerZero OFT V2. ETH canonical + Base/Arb peer.
///         ETH 에서만 1B mint. Base/Arb 는 supply=0 으로 배포 후
///         LZ messaging 으로 send 받을 때 mint, 다른 chain 보낼 때 burn.
///
/// @dev OAppCore (LZ oapp-evm 0.4.1) 는 `Ownable(_delegate)` 명시 호출이 없어
///      OZ v5 abstract Ownable 의 `constructor(address)` 와 충돌. 최하위 concrete
///      contract 인 GomeOFT 가 직접 `Ownable(_owner)` 를 호출해 v5 호환.
contract GomeOFT is OFT {
    constructor(
        address _lzEndpoint,
        address _owner,
        uint256 _initialMint
    ) OFT("Gome", "GOME", _lzEndpoint, _owner) Ownable(_owner) {
        if (_initialMint > 0) {
            _mint(_owner, _initialMint);
        }
    }
}

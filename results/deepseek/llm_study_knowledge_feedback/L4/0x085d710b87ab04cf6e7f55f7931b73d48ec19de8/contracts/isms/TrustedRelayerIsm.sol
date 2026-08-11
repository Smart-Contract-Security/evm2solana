// SPDX-License-Identifier: MIT OR Apache-2.0

import {IInterchainSecurityModule} from "../interfaces/IInterchainSecurityModule.sol";
import {PackageVersioned} from "contracts/PackageVersioned.sol";

contract TrustedRelayerIsm is IInterchainSecurityModule, PackageVersioned {
    uint8 public immutable moduleType = uint8(Types.NULL);
    address public immutable mailbox;
    address public immutable trustedRelayer;

    constructor(address _mailbox, address _trustedRelayer) {
        require(
            _trustedRelayer != address(0),
            "TrustedRelayerIsm: invalid relayer"
        );
        require(
            _mailbox != address(0),
            "TrustedRelayerIsm: invalid mailbox"
        );
        mailbox = _mailbox;
        trustedRelayer = _trustedRelayer;
    }

    function verify(
        bytes calldata,
        bytes calldata message
    ) external view returns (bool) {
        bytes32 id = keccak256(message);
        (bool success, bytes memory result) = mailbox.call(
            abi.encodeWithSignature("processor(bytes32)", id)
        );
        require(success, "TrustedRelayerIsm: call failed");
        return abi.decode(result, (address)) == trustedRelayer;
    }
}
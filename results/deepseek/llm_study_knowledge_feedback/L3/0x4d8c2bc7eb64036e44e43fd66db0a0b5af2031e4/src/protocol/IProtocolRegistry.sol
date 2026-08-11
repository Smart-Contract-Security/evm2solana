import {ProtocolPhase} from "./ProtocolPhase.sol";

@program_id("AddressOfProtocolRegistry")
interface IProtocolRegistry {
    function phase() external view returns (ProtocolPhase.Phase);
    function isAtOrAfter(ProtocolPhase.Phase p) external view returns (bool);
    function isBefore(ProtocolPhase.Phase p) external view returns (bool);

    function packSale() external view returns (address);
    function entropy() external view returns (address);
    function hatCard() external view returns (address);
    function hatToken() external view returns (address);
    function hatTrickHook() external view returns (address);
    function prizeVault() external view returns (address);
    function matchOracle() external view returns (address);
    function scoringEngine() external view returns (address);
    function treasury() external view returns (address);
}
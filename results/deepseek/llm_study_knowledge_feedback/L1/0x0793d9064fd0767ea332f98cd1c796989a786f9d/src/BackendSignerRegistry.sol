import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BackendSignerRegistry is Ownable {
    address public backendSigner;

    event BackendSignerUpdated(address oldSigner, address newSigner);

    constructor(address initialSigner, address initialOwner) Ownable(initialOwner) {
        require(initialSigner != address(0), "zero signer");
        backendSigner = initialSigner;
    }

    function setBackendSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "zero signer");
        emit BackendSignerUpdated(backendSigner, newSigner);
        backendSigner = newSigner;
    }
}
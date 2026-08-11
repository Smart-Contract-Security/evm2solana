import {Errors} from "../utils/Errors.sol";

library Clones {
    function clone(address implementation) internal returns (address) {
        return clone(implementation, 0);
    }

    function clone(address implementation, uint64 value) internal returns (address) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        address instance = new Contract{salt: 0}(bytecode);
        if (instance == address(0)) {
            revert Errors.FailedDeployment();
        }
        return instance;
    }

    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address) {
        return cloneDeterministic(implementation, salt, 0);
    }

    function cloneDeterministic(
        address implementation,
        bytes32 salt,
        uint64 value
    ) internal returns (address) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        address instance = new Contract{salt: salt}(bytecode);
        if (instance == address(0)) {
            revert Errors.FailedDeployment();
        }
        return instance;
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address) {
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(
            hex"ff",
            deployer,
            salt,
            keccak256(bytecode)
        )))));
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt
    ) internal view returns (address) {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}
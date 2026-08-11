import {AccountMeta, AccountInfo} from 'solana';

struct Quote {
    address token;
    uint64 amount;
}

interface ITokenFee {
    function quoteTransferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) external view returns (Quote[] memory quotes);
}

interface ITokenBridge is ITokenFee {
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint64 _amount
    ) external returns (bytes32);
}
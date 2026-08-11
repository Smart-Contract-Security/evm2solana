import 'solana';

interface ILSDAdapter {
    struct ExchangeRateInfo {
        address lsdToken;
        string lsdSymbol;
        uint8 lsdDecimals;
        address underlyingAsset;
        string underlyingSymbol;
        uint8 underlyingDecimals;
        bool isNative;
        uint64 rate;
        uint64 timestamp;
    }

    function getExchangeRate(address lsdTokenAddress) external view returns (ExchangeRateInfo memory info);

    function convertToUnderlying(address lsdTokenAddress, uint64 lsdAmount)
        external
        view
        returns (uint64 underlyingAmount, ExchangeRateInfo memory info);
}
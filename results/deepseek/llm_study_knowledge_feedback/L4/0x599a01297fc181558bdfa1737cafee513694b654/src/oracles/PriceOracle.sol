import 'solana';

abstract contract PriceOracle {
    bool public constant isPriceOracle = true;

    function getUnderlyingPrice(
        address mToken
    ) external view virtual returns (uint64);
}
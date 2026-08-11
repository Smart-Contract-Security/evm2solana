import 'solana';

interface AggregatorV3Interface {
    function decimals() external view returns (uint64);
    function latestRoundData() external view returns (uint80 roundId, int64 answer, uint64 startedAt, uint64 updatedAt, uint80 answeredInRound);
}

contract TwoBaseFeeds {
    address immutable feed1;
    address immutable feed2;
    uint64 public targetDecimals = 18;
    uint64 public feedsTotalDecimals;

    constructor(address _feed1, address _feed2) {
        feed1 = _feed1;
        feed2 = _feed2;

        feedsTotalDecimals = AggregatorV3Interface(feed1).decimals() + AggregatorV3Interface(feed2).decimals();
    }

    function getPrice() public view returns (uint64) {
        uint64 _price = price(feed1) * price(feed2);

        if (feedsTotalDecimals > targetDecimals) {
            _price = _price / (10 ** (feedsTotalDecimals - targetDecimals));
        } else if (targetDecimals > feedsTotalDecimals) {
            _price = _price * (10 ** (targetDecimals - feedsTotalDecimals));
        }

        return _price;
    }

    function price(address feed) public view returns (uint64) {
        (, int64 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
        require(answer >= 0, "amount should be positive");

        return uint64(answer);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(
        address owner
    ) external view returns (uint256);
}

contract PartialNonCustodialERC20OrderBook {
    uint256 public constant MAX_UINT256 = type(uint256).max;

    struct Order {
        address maker;
        address sellToken;
        address buyToken;

        uint256 sellAmount;
        uint256 buyAmount;

        uint256 remainingSellAmount;
        uint256 remainingBuyAmount;

        uint256 expiry;
        bool active;
    }

    uint256 public nextOrderId = 1;
    mapping(uint256 => Order) public orders;

    uint256 private unlocked = 1;

    event OrderCreated(
        uint256 indexed id,
        address indexed maker,
        address indexed sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 expiry
    );

    event OrderFilled(
        uint256 indexed id,
        address indexed taker,
        uint256 sellAmountFilled,
        uint256 buyAmountFilled,
        uint256 remainingSellAmount,
        uint256 remainingBuyAmount,
        bool fullyFilled
    );

    event OrderCancelled(
        uint256 indexed id,
        uint256 remainingSellAmount,
        uint256 remainingBuyAmount
    );

    modifier nonReentrant() {
        require(unlocked == 1, "REENTRANCY");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    receive() external payable {
        revert("ETH_NOT_ACCEPTED");
    }

    fallback() external payable {
        revert("ETH_NOT_ACCEPTED");
    }

    function createOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 expiry
    ) external nonReentrant returns (uint256 id) {
        require(sellToken != address(0), "BAD_SELL_TOKEN");
        require(buyToken != address(0), "BAD_BUY_TOKEN");
        require(sellToken != buyToken, "SAME_TOKEN");
        require(sellAmount > 0, "BAD_SELL_AMOUNT");
        require(buyAmount > 0, "BAD_BUY_AMOUNT");
        require(expiry == 0 || expiry > block.timestamp, "BAD_EXPIRY");

        require(sellToken.code.length > 0, "SELL_TOKEN_NOT_CONTRACT");
        require(buyToken.code.length > 0, "BUY_TOKEN_NOT_CONTRACT");

        require(
            IERC20Minimal(sellToken).balanceOf(msg.sender) >= sellAmount,
            "INSUFFICIENT_MAKER_BALANCE"
        );

        require(
            IERC20Minimal(sellToken).allowance(msg.sender, address(this)) >= sellAmount,
            "INSUFFICIENT_MAKER_ALLOWANCE"
        );

        id = nextOrderId;

        unchecked {
            nextOrderId = id + 1;
        }

        orders[id] = Order({
            maker: msg.sender,
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            remainingSellAmount: sellAmount,
            remainingBuyAmount: buyAmount,
            expiry: expiry,
            active: true
        });

        emit OrderCreated(
            id,
            msg.sender,
            sellToken,
            buyToken,
            sellAmount,
            buyAmount,
            expiry
        );
    }

    function fillOrder(
        uint256 id,
        uint256 buyAmountIn
    ) external nonReentrant {
        require(buyAmountIn > 0, "BAD_FILL_AMOUNT");

        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");
        require(order.maker != address(0), "ORDER_NOT_FOUND");
        require(order.maker != msg.sender, "MAKER_CANNOT_FILL");
        require(order.expiry == 0 || order.expiry >= block.timestamp, "ORDER_EXPIRED");
        require(order.remainingSellAmount > 0, "NO_REMAINING_SELL");
        require(order.remainingBuyAmount > 0, "NO_REMAINING_BUY");

        uint256 fillBuyAmount;
        uint256 fillSellAmount;
        bool fullyFilled;

        if (buyAmountIn >= order.remainingBuyAmount) {
            fillBuyAmount = order.remainingBuyAmount;
            fillSellAmount = order.remainingSellAmount;
            fullyFilled = true;
        } else {
            fillBuyAmount = buyAmountIn;

            fillSellAmount = _mulDiv(
                order.remainingSellAmount,
                fillBuyAmount,
                order.remainingBuyAmount
            );

            require(fillSellAmount > 0, "FILL_TOO_SMALL");

            fullyFilled = false;
        }

        require(
            IERC20Minimal(order.sellToken).balanceOf(order.maker) >= fillSellAmount,
            "INSUFFICIENT_MAKER_BALANCE"
        );

        require(
            IERC20Minimal(order.sellToken).allowance(order.maker, address(this)) >= fillSellAmount,
            "INSUFFICIENT_MAKER_ALLOWANCE"
        );

        require(
            IERC20Minimal(order.buyToken).balanceOf(msg.sender) >= fillBuyAmount,
            "INSUFFICIENT_TAKER_BALANCE"
        );

        require(
            IERC20Minimal(order.buyToken).allowance(msg.sender, address(this)) >= fillBuyAmount,
            "INSUFFICIENT_TAKER_ALLOWANCE"
        );

        if (fullyFilled) {
            order.remainingSellAmount = 0;
            order.remainingBuyAmount = 0;
            order.active = false;
        } else {
            order.remainingSellAmount -= fillSellAmount;
            order.remainingBuyAmount -= fillBuyAmount;

            if (
                order.remainingSellAmount == 0 ||
                order.remainingBuyAmount == 0
            ) {
                order.active = false;
                fullyFilled = true;
            }
        }

        uint256 makerBuyBalanceBefore =
            IERC20Minimal(order.buyToken).balanceOf(order.maker);

        uint256 takerSellBalanceBefore =
            IERC20Minimal(order.sellToken).balanceOf(msg.sender);

        _safeTransferFrom(
            order.buyToken,
            msg.sender,
            order.maker,
            fillBuyAmount
        );

        _safeTransferFrom(
            order.sellToken,
            order.maker,
            msg.sender,
            fillSellAmount
        );

        uint256 makerBuyBalanceAfter =
            IERC20Minimal(order.buyToken).balanceOf(order.maker);

        uint256 takerSellBalanceAfter =
            IERC20Minimal(order.sellToken).balanceOf(msg.sender);

        require(
            makerBuyBalanceAfter >= makerBuyBalanceBefore &&
            makerBuyBalanceAfter - makerBuyBalanceBefore >= fillBuyAmount,
            "MAKER_DID_NOT_RECEIVE_EXACT_BUY_AMOUNT"
        );

        require(
            takerSellBalanceAfter >= takerSellBalanceBefore &&
            takerSellBalanceAfter - takerSellBalanceBefore >= fillSellAmount,
            "TAKER_DID_NOT_RECEIVE_EXACT_SELL_AMOUNT"
        );

        emit OrderFilled(
            id,
            msg.sender,
            fillSellAmount,
            fillBuyAmount,
            order.remainingSellAmount,
            order.remainingBuyAmount,
            fullyFilled
        );
    }

    function cancelOrder(uint256 id) external nonReentrant {
        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");
        require(order.maker == msg.sender, "NOT_MAKER");

        uint256 remainingSellAmount = order.remainingSellAmount;
        uint256 remainingBuyAmount = order.remainingBuyAmount;

        order.active = false;

        emit OrderCancelled(
            id,
            remainingSellAmount,
            remainingBuyAmount
        );
    }

    function getOrder(
        uint256 id
    )
        external
        view
        returns (
            address maker,
            address sellToken,
            address buyToken,
            uint256 sellAmount,
            uint256 buyAmount,
            uint256 remainingSellAmount,
            uint256 remainingBuyAmount,
            uint256 expiry,
            bool active
        )
    {
        Order storage order = orders[id];

        return (
            order.maker,
            order.sellToken,
            order.buyToken,
            order.sellAmount,
            order.buyAmount,
            order.remainingSellAmount,
            order.remainingBuyAmount,
            order.expiry,
            order.active
        );
    }

    function isOrderFillable(uint256 id) external view returns (bool) {
        Order storage order = orders[id];

        if (!order.active) return false;
        if (order.maker == address(0)) return false;
        if (order.expiry != 0 && order.expiry < block.timestamp) return false;
        if (order.remainingSellAmount == 0) return false;
        if (order.remainingBuyAmount == 0) return false;

        if (
            IERC20Minimal(order.sellToken).balanceOf(order.maker) <
            order.remainingSellAmount
        ) return false;

        if (
            IERC20Minimal(order.sellToken).allowance(order.maker, address(this)) <
            order.remainingSellAmount
        ) return false;

        return true;
    }

    function orderBookVersion() external pure returns (string memory) {
        return "NON_CUSTODIAL_PARTIAL_V1";
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        require(token.code.length > 0, "TOKEN_NOT_CONTRACT");

        bytes memory data = abi.encodeWithSelector(
            IERC20Minimal.transferFrom.selector,
            from,
            to,
            amount
        );

        bool ok;
        bytes memory result;

        (ok, result) = token.call(data);

        require(ok, "TOKEN_CALL_FAILED");

        if (result.length > 0) {
            require(
                abi.decode(result, (bool)),
                "TOKEN_TRANSFER_FROM_FAILED"
            );
        }
    }

    function _mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            require(denominator > 0, "DIV_BY_ZERO");

            uint256 prod0;
            uint256 prod1;

            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            require(denominator > prod1, "MULDIV_OVERFLOW");

            uint256 remainder;

            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);

            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;

            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }
}
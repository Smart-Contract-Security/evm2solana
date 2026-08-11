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

contract NonCustodialERC20OrderBook {
    uint256 public constant MAX_UINT256 = type(uint256).max;

    struct Order {
        address maker;
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
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
        address indexed taker
    );

    event OrderCancelled(
        uint256 indexed id
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

    function fillOrder(uint256 id) external nonReentrant {
        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");
        require(order.maker != address(0), "ORDER_NOT_FOUND");
        require(order.maker != msg.sender, "MAKER_CANNOT_FILL");
        require(order.expiry == 0 || order.expiry >= block.timestamp, "ORDER_EXPIRED");

        order.active = false;

        require(
            IERC20Minimal(order.sellToken).balanceOf(order.maker) >= order.sellAmount,
            "INSUFFICIENT_MAKER_BALANCE"
        );

        require(
            IERC20Minimal(order.sellToken).allowance(order.maker, address(this)) >= order.sellAmount,
            "INSUFFICIENT_MAKER_ALLOWANCE"
        );

        require(
            IERC20Minimal(order.buyToken).balanceOf(msg.sender) >= order.buyAmount,
            "INSUFFICIENT_TAKER_BALANCE"
        );

        require(
            IERC20Minimal(order.buyToken).allowance(msg.sender, address(this)) >= order.buyAmount,
            "INSUFFICIENT_TAKER_ALLOWANCE"
        );

        uint256 makerBuyBalanceBefore =
            IERC20Minimal(order.buyToken).balanceOf(order.maker);

        uint256 takerSellBalanceBefore =
            IERC20Minimal(order.sellToken).balanceOf(msg.sender);

        _safeTransferFrom(
            order.buyToken,
            msg.sender,
            order.maker,
            order.buyAmount
        );

        _safeTransferFrom(
            order.sellToken,
            order.maker,
            msg.sender,
            order.sellAmount
        );

        uint256 makerBuyBalanceAfter =
            IERC20Minimal(order.buyToken).balanceOf(order.maker);

        uint256 takerSellBalanceAfter =
            IERC20Minimal(order.sellToken).balanceOf(msg.sender);

        require(
            makerBuyBalanceAfter >= makerBuyBalanceBefore + order.buyAmount,
            "MAKER_DID_NOT_RECEIVE_EXACT_BUY_AMOUNT"
        );

        require(
            takerSellBalanceAfter >= takerSellBalanceBefore + order.sellAmount,
            "TAKER_DID_NOT_RECEIVE_EXACT_SELL_AMOUNT"
        );

        emit OrderFilled(id, msg.sender);
    }

    function cancelOrder(uint256 id) external nonReentrant {
        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");
        require(order.maker == msg.sender, "NOT_MAKER");

        order.active = false;

        emit OrderCancelled(id);
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
            order.expiry,
            order.active
        );
    }

    function isOrderFillable(uint256 id) external view returns (bool) {
        Order storage order = orders[id];

        if (!order.active) return false;
        if (order.maker == address(0)) return false;
        if (order.expiry != 0 && order.expiry < block.timestamp) return false;

        if (
            IERC20Minimal(order.sellToken).balanceOf(order.maker) <
            order.sellAmount
        ) return false;

        if (
            IERC20Minimal(order.sellToken).allowance(order.maker, address(this)) <
            order.sellAmount
        ) return false;

        return true;
    }

    function orderBookVersion() external pure returns (string memory) {
        return "NON_CUSTODIAL_EXPIRY_V1";
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
}
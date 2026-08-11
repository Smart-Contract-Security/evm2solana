// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
}

contract NonCustodialERC20OrderBook {
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

    event OrderFilled(uint256 indexed id, address indexed taker);
    event OrderCancelled(uint256 indexed id);

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

        require(
            IERC20Minimal(sellToken).balanceOf(msg.sender) >= sellAmount,
            "INSUFFICIENT_MAKER_BALANCE"
        );

        require(
            IERC20Minimal(sellToken).allowance(msg.sender, address(this)) >= sellAmount,
            "INSUFFICIENT_MAKER_ALLOWANCE"
        );

        id = nextOrderId++;

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
        require(order.expiry == 0 || order.expiry >= block.timestamp, "ORDER_EXPIRED");

        order.active = false;

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

        emit OrderFilled(id, msg.sender);
    }

    function cancelOrder(uint256 id) external nonReentrant {
        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");
        require(order.maker == msg.sender, "NOT_MAKER");

        order.active = false;

        emit OrderCancelled(id);
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

        // solhint-disable-next-line avoid-low-level-calls
        (ok, result) = token.call(data);

        require(ok, "TOKEN_CALL_FAILED");

        if (result.length > 0) {
            require(abi.decode(result, (bool)), "TOKEN_TRANSFER_FROM_FAILED");
        }
    }
}
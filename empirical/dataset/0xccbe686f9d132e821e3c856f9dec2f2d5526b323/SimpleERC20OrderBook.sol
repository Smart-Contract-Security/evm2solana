// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract SimpleERC20OrderBook {
    struct Order {
        address maker;
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
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
        uint256 buyAmount
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

    function createOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    ) external nonReentrant returns (uint256 id) {
        require(sellToken != address(0), "BAD_SELL_TOKEN");
        require(buyToken != address(0), "BAD_BUY_TOKEN");
        require(sellToken != buyToken, "SAME_TOKEN");
        require(sellAmount > 0, "BAD_SELL_AMOUNT");
        require(buyAmount > 0, "BAD_BUY_AMOUNT");

        id = nextOrderId++;

        orders[id] = Order({
            maker: msg.sender,
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            active: true
        });

        _safeTransferFrom(sellToken, msg.sender, address(this), sellAmount);

        emit OrderCreated(
            id,
            msg.sender,
            sellToken,
            buyToken,
            sellAmount,
            buyAmount
        );
    }

    function fillOrder(uint256 id) external nonReentrant {
        Order storage order = orders[id];

        require(order.active, "INACTIVE_ORDER");

        order.active = false;

        _safeTransferFrom(
            order.buyToken,
            msg.sender,
            order.maker,
            order.buyAmount
        );

        _safeTransfer(
            order.sellToken,
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

        _safeTransfer(
            order.sellToken,
            order.maker,
            order.sellAmount
        );

        emit OrderCancelled(id);
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        bytes memory data = abi.encodeWithSelector(
            IERC20Minimal.transfer.selector,
            to,
            value
        );

        bytes memory result = _callToken(token, data);
        if (result.length > 0) {
            require(abi.decode(result, (bool)), "TRANSFER_FAILED");
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        bytes memory data = abi.encodeWithSelector(
            IERC20Minimal.transferFrom.selector,
            from,
            to,
            value
        );

        bytes memory result = _callToken(token, data);
        if (result.length > 0) {
            require(abi.decode(result, (bool)), "TRANSFER_FROM_FAILED");
        }
    }

    function _callToken(
        address token,
        bytes memory data
    ) internal returns (bytes memory) {
        require(token.code.length > 0, "TOKEN_NOT_CONTRACT");

        bool ok;
        bytes memory result;

        // solhint-disable-next-line avoid-low-level-calls
        (ok, result) = token.call(data);

        require(ok, "TOKEN_CALL_FAILED");

        return result;
    }
}
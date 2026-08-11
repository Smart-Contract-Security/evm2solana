// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokinsoCore.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokinsoOrdersModule is TokinsoCore {
    using SafeERC20 for IERC20;
    // ========= Investor functions =========
    function buy(uint256 usdcAmount) external {
        _queueSubscription(msg.sender, usdcAmount);
    }

    function queueSubscription(uint256 usdcAmount) external returns (uint256) {
        return _queueSubscription(msg.sender, usdcAmount);
    }

    function sell(uint256 amount) external {
        _queueRedemption(msg.sender, amount, false, 0);
    }

    function queueRedemption(uint256 amount) external returns (uint256) {
        return _queueRedemption(msg.sender, amount, false, 0);
    }

    // ========= Views =========
    function getOrder(uint256 orderId) external view returns (Order memory) {
        require(orderId < orders.length, "Order inexistant");
        return orders[orderId];
    }

    function getOrdersForNavDay(uint256 dayId) external view returns (uint256[] memory) {
        uint256[] storage refs = ordersByNavDay[dayId];
        uint256[] memory ids = new uint256[](refs.length);
        for (uint256 i = 0; i < refs.length; i++) {
            ids[i] = refs[i];
        }
        return ids;
    }

    function ordersLength() external view returns (uint256) {
        return orders.length;
    }

    // ========= Internal order helpers =========
    function _queueSubscription(address user, uint256 usdcAmount) internal returns (uint256 orderId) {
        require(usdcAmount > 0, "Montant nul");
        require(usdcToken != address(0), "USDC non configure");
        uint256 navDayId = _navDayForOrder(block.timestamp);
        bool beforeCutoff = _isBeforeCutoff(block.timestamp);

        IERC20(usdcToken).safeTransferFrom(user, address(this), usdcAmount);

        orderId = orders.length;
        orders.push(Order({
            user: user,
            orderType: OrderType.Subscription,
            amount: usdcAmount,
            submittedAt: block.timestamp,
            navDayId: navDayId,
            beforeCutoff: beforeCutoff,
            processed: false
        }));
        ordersByNavDay[navDayId].push(orderId);

        emit OrderQueued(orderId, user, OrderType.Subscription, usdcAmount, navDayId, beforeCutoff);
    }

    function _queueRedemption(
        address user,
        uint256 amount,
        bool carryOver,
        uint256 forcedNavDay
    ) internal returns (uint256 orderId) {
        require(amount > 0, "Montant nul");

        uint256 navDayId = carryOver ? forcedNavDay : _navDayForOrder(block.timestamp);
        bool beforeCutoff = carryOver ? true : _isBeforeCutoff(block.timestamp);

        if (!carryOver) {
            require(balanceOf(user) >= amount, "Solde insuffisant");
            _spendAllowance(user, address(this), amount);
            _transfer(user, address(this), amount);
            lockedRedemptionTokens[user] += amount;
        }

        orderId = orders.length;
        orders.push(Order({
            user: user,
            orderType: OrderType.Redemption,
            amount: amount,
            submittedAt: block.timestamp,
            navDayId: navDayId,
            beforeCutoff: beforeCutoff,
            processed: false
        }));
        ordersByNavDay[navDayId].push(orderId);

        emit OrderQueued(orderId, user, OrderType.Redemption, amount, navDayId, beforeCutoff);
    }

    function _processOrdersForNavDay(
        uint256 navDayId,
        uint256 navPerTokenUSD,
        uint256 totalValueUSD
    ) internal {
        uint256[] storage ids = ordersByNavDay[navDayId];
        if (ids.length == 0) {
            return;
        }
        uint256[] memory sortedIds = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            sortedIds[i] = ids[i];
        }
        _sortOrdersBySubmission(sortedIds);

        uint256 totalRedemptionUsd18 = 0;
        for (uint256 i = 0; i < sortedIds.length; i++) {
            Order storage o = orders[sortedIds[i]];
            if (o.processed || o.orderType != OrderType.Redemption) continue;
            totalRedemptionUsd18 += _tokenAmountToUsd18(o.amount, navPerTokenUSD);
        }

        uint256 redemptionLimitUsd18 = (totalValueUSD * USD_TO_18 * DAILY_REDEMPTION_LIMIT_BPS) / 10000;
        uint256 payoutRatio = 1e18;
        if (totalRedemptionUsd18 > 0 && redemptionLimitUsd18 < totalRedemptionUsd18) {
            payoutRatio = redemptionLimitUsd18 == 0
                ? 0
                : (redemptionLimitUsd18 * 1e18) / totalRedemptionUsd18;
        }

        for (uint256 i = 0; i < sortedIds.length; i++) {
            uint256 orderId = sortedIds[i];
            Order storage orderRef = orders[orderId];
            if (orderRef.processed) continue;

            if (orderRef.orderType == OrderType.Subscription) {
                _executeSubscription(orderRef, orderId, navPerTokenUSD);
            } else {
                _executeRedemption(orderRef, orderId, navDayId, navPerTokenUSD, payoutRatio, totalValueUSD);
            }
        }

        delete ordersByNavDay[navDayId];
    }

    function _sortOrdersBySubmission(uint256[] memory arr) internal view {
        uint256 len = arr.length;
        if (len < 2) return;
        for (uint256 i = 1; i < len; i++) {
            uint256 key = arr[i];
            uint256 j = i;
            while (
                j > 0 &&
                (
                    orders[arr[j - 1]].submittedAt > orders[key].submittedAt ||
                    (
                        orders[arr[j - 1]].submittedAt == orders[key].submittedAt &&
                        arr[j - 1] > key
                    )
                )
            ) {
                arr[j] = arr[j - 1];
                j--;
            }
            arr[j] = key;
        }
    }

    // If a NAV day is skipped, carry stale unprocessed orders to the day being published
    // so execution stays monotonic and older orders cannot get stranded.
    function _rollForwardUnprocessedOrders(uint256 targetNavDayId) internal {
        for (uint256 orderId = 0; orderId < orders.length; orderId++) {
            Order storage orderRef = orders[orderId];
            if (orderRef.processed) continue;
            if (orderRef.navDayId >= targetNavDayId) continue;

            uint256 fromNavDayId = orderRef.navDayId;
            orderRef.navDayId = targetNavDayId;
            orderRef.beforeCutoff = true;
            ordersByNavDay[targetNavDayId].push(orderId);

            emit OrderDeferred(fromNavDayId, targetNavDayId, orderRef.user, orderRef.amount);
        }
    }

    function _executeSubscription(
        Order storage orderRef,
        uint256 orderId,
        uint256 navPerTokenUSD
    ) internal {
        uint256 tokensToMint = (orderRef.amount * 1e18) / navPerTokenUSD;
        require(tokensToMint > 0, "Souscription trop faible");

        _mint(orderRef.user, tokensToMint);
        orderRef.processed = true;

        emit OrderProcessed(orderRef.navDayId, orderId, orderRef.orderType, tokensToMint);
    }

    function _executeRedemption(
        Order storage orderRef,
        uint256 orderId,
        uint256 navDayId,
        uint256 navPerTokenUSD,
        uint256 payoutRatio,
        uint256 totalValueUSD
    ) internal {
        if (payoutRatio == 0) {
            _carryOver(orderRef, navDayId + 1, orderRef.amount);
            orderRef.processed = true;
            emit OrderProcessed(navDayId, orderId, orderRef.orderType, 0);
            return;
        }

        uint256 tokensToBurn = orderRef.amount;
        uint256 usdAmount18 = _tokenAmountToUsd18(orderRef.amount, navPerTokenUSD);
        if (payoutRatio < 1e18) {
            tokensToBurn = (orderRef.amount * payoutRatio) / 1e18;
            uint256 remaining = orderRef.amount - tokensToBurn;
            if (remaining > 0) {
                _carryOver(orderRef, navDayId + 1, remaining);
            }
            usdAmount18 = (usdAmount18 * payoutRatio) / 1e18;
        }

        _onRedemptionCrystallizePerfFee(usdAmount18, totalValueUSD);
        lockedRedemptionTokens[orderRef.user] -= tokensToBurn;
        _burn(address(this), tokensToBurn);

        require(usdcToken != address(0), "USDC non configure");
        uint256 usdcAmount = usdAmount18 / USD_TO_18;
        IERC20(usdcToken).safeTransfer(orderRef.user, usdcAmount);

        orderRef.processed = true;
        emit OrderProcessed(navDayId, orderId, orderRef.orderType, tokensToBurn);
    }

    function _carryOver(Order storage orderRef, uint256 nextNavDayId, uint256 amount) internal {
        _queueRedemption(orderRef.user, amount, true, nextNavDayId);
        emit OrderDeferred(orderRef.navDayId, nextNavDayId, orderRef.user, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./libraries/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IProfile.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";

contract Bazaar is Ownable {
    using SafeMath for uint256;

    event OrderPlaced(uint256 indexed orderIdx, address indexed seller);
    event OrderClosed(uint256 indexed orderIdx, address indexed seller);
    event OrderCancelledBuySeller(
        uint256 indexed orderIdx,
        address indexed seller
    );
    event OrderCancelledBuyBuyer(
        uint256 indexed orderIdx,
        address indexed buyer
    );
    event OrderWithdrew(uint256 indexed orderIdx, address indexed seller);
    event OrderSold(uint256 indexed orderIdx, address indexed buyer);
    event DeliveryApproved(uint256 indexed orderIdx, address indexed buyer);

    enum OrderState {
        Placed,
        Sold,
        Finished,
        Closed,
        Withdrew,
        CancelledBySeller,
        CancelledByBuyer
    }

    struct SourceAsset {
        string symbol;
        bool deleted;
    }

    struct Order {
        uint256 id;
        address seller;
        address buyer;
        uint256 createdAt;
        uint256 deadline; // timestamp of order deadline
        OrderState state;
        uint256 sourceAsset; // index of source asset
        address targetAsset;
        uint256 sourceAmount;
        uint256 targetAmount;
    }

    Order[] public orders;
    SourceAsset[] public allowedSourceAssets;

    address public feeTo;
    address public feeToSetter;
    address public profileContract;

    uint256 public maxDeliveryTime; // maximum delivery time in seconds
    uint256 public guaranteePercent; // seller guarantee amount by fraction of 1000
    uint256 public closeFee; // close fee by fraction of 1000
    uint256 public sellFee; // sell fee by fraction of 1000
    uint256 public buyFee; // buy fee by fraction of 1000
    uint256 public cancellationFee; // cancellation fee by fraction of 1000

    modifier onlyProfileHolders() {
        require(
            IProfile(profileContract).registered(msg.sender),
            "BAZAAR: NOT_REGISTERED"
        );
        _;
    }

    modifier onlySeller(uint256 _orderIdx) {
        require(msg.sender == orders[_orderIdx].seller, "BAZAAR: ONLY_SELLER");
        _;
    }

    modifier onlyBuyer(uint256 _orderIdx) {
        require(msg.sender == orders[_orderIdx].buyer, "BAZAAR: ONLY_BUYER");
        _;
    }

    modifier validSourceAsset(uint256 _idx) {
        require(
            (_idx < allowedSourceAssets.length) &&
                !allowedSourceAssets[_idx].deleted,
            "BAZAAR: INVALID_SOURCE_ASSET"
        );
        _;
    }

    modifier validOrder(uint256 _idx) {
        require(_idx < orders.length, "BAZAAR: INVALID_ORDER");
        _;
    }

    modifier inState(uint256 _orderIdx, OrderState state) {
        require(
            orders[_orderIdx].state == state,
            "BAZAAR: INVALID_ORDER_STATE"
        );
        _;
    }

    modifier notExpired(uint256 _orderIdx) {
        require(
            block.timestamp < orders[_orderIdx].deadline,
            "BAZAAR: ORDER_DEADLINE_EXCEEDED"
        );
        _;
    }

    modifier expired(uint256 _orderIdx) {
        require(
            block.timestamp >= orders[_orderIdx].deadline,
            "BAZAAR: ORDER_DEADLINE_NOT_EXCEEDED"
        );
        _;
    }

    modifier cancellable(uint256 _orderIdx) {
        require(
            (orders[_orderIdx].createdAt.add(maxDeliveryTime)) <=
                block.timestamp,
            "BAZAAR: ORDER_MAX_DELIVERY_NOT_EXCEEDED"
        );
        _;
    }

    constructor(address _profileContract) {
        profileContract = _profileContract;
        allowedSourceAssets.push(SourceAsset("GOLD_OUNCE", false));
        allowedSourceAssets.push(SourceAsset("SILVER_OUNCE", false));
        allowedSourceAssets.push(SourceAsset("CARAT_GOLD_18", false));
        allowedSourceAssets.push(SourceAsset("CARAT_GOLD_24", false));
        allowedSourceAssets.push(SourceAsset("GOLD_MESGHAL", false));
        allowedSourceAssets.push(SourceAsset("GOLD_MELTED_CASH", false));
        allowedSourceAssets.push(SourceAsset("MELTED_BANKING_GOLD", false));
        allowedSourceAssets.push(SourceAsset("MELTED_GOLD", false));
        allowedSourceAssets.push(SourceAsset("GOLD_COIN_CASH", false));
        allowedSourceAssets.push(SourceAsset("GOLD_COIN", false));
        allowedSourceAssets.push(SourceAsset("USD", false));
        allowedSourceAssets.push(SourceAsset("MANAT", false));
        allowedSourceAssets.push(SourceAsset("DIRHAM", false));
        allowedSourceAssets.push(SourceAsset("DINAR_IRAQI", false));
        allowedSourceAssets.push(SourceAsset("TURKISH_LIRA", false));
        allowedSourceAssets.push(SourceAsset("POLYSTYRENE", false));
        allowedSourceAssets.push(SourceAsset("BITUMEN", false));
        allowedSourceAssets.push(SourceAsset("BASE_OIL", false));
        allowedSourceAssets.push(SourceAsset("POLYPROPYLENE", false));
        allowedSourceAssets.push(SourceAsset("HDPE", false));
        allowedSourceAssets.push(SourceAsset("LDPE", false));
        allowedSourceAssets.push(SourceAsset("NITRIC_ACID", false));
        allowedSourceAssets.push(SourceAsset("SODIUM_HYDROXIDE", false));
        allowedSourceAssets.push(SourceAsset("UREA", false));
        allowedSourceAssets.push(SourceAsset("SODIUM_CARBONATE", false));
        allowedSourceAssets.push(SourceAsset("SODIUM_SULFATE", false));
        allowedSourceAssets.push(SourceAsset("PARAFFIN_WAX", false));
        allowedSourceAssets.push(SourceAsset("EPOXY_RESIN", false));
        allowedSourceAssets.push(SourceAsset("STYRENE", false));
        allowedSourceAssets.push(SourceAsset("STEEL", false));
        allowedSourceAssets.push(SourceAsset("IRON_ORE", false));
        allowedSourceAssets.push(SourceAsset("CONCENTRATE", false));
        allowedSourceAssets.push(SourceAsset("IRON_PELLET", false));
        allowedSourceAssets.push(SourceAsset("COPPER", false));
        allowedSourceAssets.push(SourceAsset("ZINC", false));
        allowedSourceAssets.push(SourceAsset("ALUMINIUM", false));

        guaranteePercent = 3_500; // 3.5% of sale price
        closeFee = 10; // 0.01% of sale price
        sellFee = 250; // 0.25% of sale price
        buyFee = 250; // 0.25% of sale price
        cancellationFee = 2_000; // 2% of sale price
        feeToSetter = msg.sender;
        feeTo = msg.sender;
        maxDeliveryTime = 8 hours;
    }

    /**
     * @dev calculate guarantee amount
     */
    function calcGuarantee(uint256 _orderIdx) internal view returns (uint256) {
        Order storage order = orders[_orderIdx];

        return order.targetAmount.mul(guaranteePercent).div(100_000);
    }

    /**
     * @dev calculate sell fee
     */
    function calcSellFee(uint256 _orderIdx) internal view returns (uint256) {
        Order storage order = orders[_orderIdx];

        return order.targetAmount.mul(sellFee).div(100_000);
    }

    /**
     * @dev calculate buy fee
     */
    function calcBuyFee(uint256 _orderIdx) internal view returns (uint256) {
        Order storage order = orders[_orderIdx];

        return order.targetAmount.mul(buyFee).div(100_000);
    }

    /**
     * @dev calculate close fee
     */
    function calcCloseFee(uint256 _orderIdx) internal view returns (uint256) {
        Order storage order = orders[_orderIdx];

        return order.targetAmount.mul(closeFee).div(100_000);
    }

    /**
     * @dev calculate cancellation fee
     */
    function calcCancellationFee(uint256 _orderIdx)
        internal
        view
        returns (uint256)
    {
        Order storage order = orders[_orderIdx];

        return order.targetAmount.mul(cancellationFee).div(100_000);
    }

    /**
     * @dev set fee to account
     */
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "BAZAAR: FORBIDDEN");
        feeTo = _feeTo;
    }

    /**
     * @dev set fee to setter account
     */
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "BAZAAR: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    /**
     * @dev set guarantee percent
     */
    function setGuaranteePercent(uint256 _value) public onlyOwner {
        guaranteePercent = _value;
    }

    /**
     * @dev set close fee
     */
    function setCloseFee(uint256 _value) public onlyOwner {
        closeFee = _value;
    }

    /**
     * @dev set sell fee
     */
    function setSellFee(uint256 _value) public onlyOwner {
        sellFee = _value;
    }

    /**
     * @dev set buy fee
     */
    function setBuyFee(uint256 _value) public onlyOwner {
        buyFee = _value;
    }

    /**
     * @dev set cancellation fee
     */
    function setCancellationFee(uint256 _value) public onlyOwner {
        cancellationFee = _value;
    }

    /**
     * @dev change profile contract address
     */
    function setProfile(address addr) public onlyOwner {
        profileContract = addr;
    }

    /**
     * @dev add new allowed source asset
     */
    function addAllowedSourceAsset(string memory _symbol) public onlyOwner {
        allowedSourceAssets.push(SourceAsset(_symbol, false));
    }

    /**
     * @dev disable allowed source asset
     */
    function disableAllowedSourceAsset(uint256 _idx) public onlyOwner {
        allowedSourceAssets[_idx].deleted = true;
    }

    /**
     * @dev enable allowed source asset
     */
    function enableAllowedSourceAsset(uint256 _idx) public onlyOwner {
        allowedSourceAssets[_idx].deleted = false;
    }

    /**
     * @dev create a new order
     */
    function placeOrder(
        uint256 sourceAsset,
        uint256 sourceAmount,
        address targetAsset,
        uint256 targetAmount,
        uint256 timeout
    )
        public
        onlyProfileHolders
        validSourceAsset(sourceAsset)
        returns (uint256)
    {
        require(sourceAmount > 0, "BAZAAR: INVALID_SOURCE_AMOUNT");
        require(targetAmount > 0, "BAZAAR: INVALID_TARGET_AMOUNT");

        Order memory order;
        order.id = orders.length;
        order.seller = msg.sender;
        order.deadline = block.timestamp + timeout;
        order.createdAt = block.timestamp;
        order.sourceAsset = sourceAsset;
        order.sourceAmount = sourceAmount;
        order.targetAsset = targetAsset;
        order.targetAmount = targetAmount;
        order.state = OrderState.Placed;

        orders.push(order);

        // ((targetAmount * guaranteePercent) / 1000) / 100
        uint256 _guaranteeAmount = targetAmount.mul(guaranteePercent).div(
            100_000
        );

        TransferHelper.safeTransferFrom(
            order.targetAsset,
            msg.sender,
            address(this),
            _guaranteeAmount
        );

        emit OrderPlaced(order.id, order.seller);

        return order.id;
    }

    /**
     * @dev seller closes an order before its get expired
     */
    function close(uint256 _orderIdx)
        public
        validOrder(_orderIdx)
        onlySeller(_orderIdx)
        inState(_orderIdx, OrderState.Placed)
        notExpired(_orderIdx)
    {
        Order storage order = orders[_orderIdx];

        order.state = OrderState.Closed;

        uint256 _guaranteeAmount = calcGuarantee(_orderIdx);
        uint256 _closeFee = calcCloseFee(_orderIdx);

        uint256 _toReturn = _guaranteeAmount.sub(_closeFee);

        // transfer close fee
        TransferHelper.safeTransfer(order.targetAsset, feeTo, _closeFee);

        // return rest of guarantee deposit
        TransferHelper.safeTransfer(order.targetAsset, order.seller, _toReturn);

        emit OrderClosed(_orderIdx, msg.sender);
    }

    /**
     * @dev withdraw guarantee amount for expired orders
     */
    function withdraw(uint256 _orderIdx)
        public
        validOrder(_orderIdx)
        onlySeller(_orderIdx)
        inState(_orderIdx, OrderState.Placed)
        expired(_orderIdx)
    {
        Order storage order = orders[_orderIdx];

        order.state = OrderState.Withdrew;

        uint256 _guaranteeAmount = calcGuarantee(_orderIdx);

        TransferHelper.safeTransfer(
            order.targetAsset,
            order.seller,
            _guaranteeAmount
        );

        emit OrderWithdrew(_orderIdx, msg.sender);
    }

    /**
     * @dev buy an asset
     */
    function buy(uint256 _orderIdx)
        public
        onlyProfileHolders
        validOrder(_orderIdx)
        inState(_orderIdx, OrderState.Placed)
        notExpired(_orderIdx)
    {
        Order storage order = orders[_orderIdx];
        order.buyer = msg.sender;
        order.state = OrderState.Sold;

        uint256 _buyFee = calcBuyFee(_orderIdx);

        uint256 _totalDepo = order.targetAmount.add(_buyFee);

        TransferHelper.safeTransferFrom(
            order.targetAsset,
            msg.sender,
            address(this),
            _totalDepo
        );

        emit OrderSold(_orderIdx, msg.sender);
    }

    /**
     * @dev buyer approves that recieved asset
     */
    function approveDelivery(uint256 _orderIdx)
        public
        validOrder(_orderIdx)
        onlyBuyer(_orderIdx)
        inState(_orderIdx, OrderState.Sold)
    {
        Order storage order = orders[_orderIdx];
        order.state = OrderState.Finished;

        uint256 _guaranteeAmount = calcGuarantee(_orderIdx);
        uint256 _buyFee = calcBuyFee(_orderIdx);
        uint256 _sellFee = calcSellFee(_orderIdx);

        uint256 _totalFee = _buyFee.add(_sellFee);

        uint256 _transferAmount = order.targetAmount.add(_guaranteeAmount).sub(
            _sellFee
        );

        TransferHelper.safeTransfer(
            order.targetAsset,
            order.seller,
            _transferAmount
        );

        if (feeTo != address(0)) {
            TransferHelper.safeTransfer(order.targetAsset, feeTo, _totalFee);
        }

        emit DeliveryApproved(_orderIdx, msg.sender);
    }

    /**
     * @dev cancel an order and return funds
     */
    function _cancelOrder(uint256 _orderIdx) internal {
        Order storage order = orders[_orderIdx];

        uint256 _guaranteeAmount = calcGuarantee(_orderIdx);
        uint256 _buyFee = calcBuyFee(_orderIdx);
        uint256 _cancellationFee = calcCancellationFee(_orderIdx);

        uint256 _toReturnSeller = _guaranteeAmount.sub(_cancellationFee);
        uint256 _toReturnBuyer = _buyFee.add(order.targetAmount).sub(
            _cancellationFee
        );

        // transfer cancellation fee(2 * cancelaltion fee, for seller and buyer)
        TransferHelper.safeTransfer(
            order.targetAsset,
            feeTo,
            _cancellationFee.mul(2)
        );

        // return rest of guarantee deposit
        TransferHelper.safeTransfer(
            order.targetAsset,
            order.seller,
            _toReturnSeller
        );

        // return rest of buyer deposit
        TransferHelper.safeTransfer(
            order.targetAsset,
            order.buyer,
            _toReturnBuyer
        );
    }

    /**
     * @dev seller cancels an order after sold
     */
    function cancelForSeller(uint256 _orderIdx)
        public
        validOrder(_orderIdx)
        onlySeller(_orderIdx)
        inState(_orderIdx, OrderState.Sold)
        cancellable(_orderIdx)
    {
        Order storage order = orders[_orderIdx];

        order.state = OrderState.CancelledBySeller;

        _cancelOrder(_orderIdx);

        emit OrderCancelledBuySeller(_orderIdx, msg.sender);
    }

    /**
     * @dev buyer cancels an order after bought
     */
    function cancelForBuyer(uint256 _orderIdx)
        public
        validOrder(_orderIdx)
        onlyBuyer(_orderIdx)
        inState(_orderIdx, OrderState.Sold)
        cancellable(_orderIdx)
    {
        Order storage order = orders[_orderIdx];

        order.state = OrderState.CancelledByBuyer;

        _cancelOrder(_orderIdx);

        emit OrderCancelledBuyBuyer(_orderIdx, msg.sender);
    }

    /**
     * @dev filters orders by give filters
     */
    function fetchOrders(
        int256 fromID,
        uint256 maxLength,
        address buyer,
        address seller,
        OrderState[] memory states,
        uint256[] memory sourceAssets,
        uint256 fromDate,
        uint256 toDate,
        bool withExpireds
    ) public view returns (Order[] memory) {
        uint256 count = 0;
        Order[] memory _upfrontOrders = new Order[](orders.length);

        if (fromID < 0) {
            fromID = int256(orders.length);
        }

        for (int256 i = fromID - 1; i >= 0; i--) {
            if (count >= maxLength) break;

            Order storage _order = orders[uint256(i)];

            if (!withExpireds && (_order.deadline <= block.timestamp)) {
                continue;
            }

            if (buyer != address(0)) {
                if (_order.buyer != buyer) {
                    continue;
                }
            }

            if (seller != address(0)) {
                if (_order.seller != seller) {
                    continue;
                }
            }

            if (fromDate > 0) {
                if (_order.createdAt < fromDate) {
                    continue;
                }
            }

            if (toDate > 0) {
                if (_order.createdAt > toDate) {
                    continue;
                }
            }

            if (sourceAssets.length > 0) {
                bool found = false;

                for (uint256 l = 0; l < sourceAssets.length; l++) {
                    if (_order.sourceAsset == sourceAssets[l]) {
                        found = true;
                        break;
                    }
                }

                if (!found) continue;
            }

            if (states.length > 0) {
                bool found = false;

                for (uint256 l = 0; l < states.length; l++) {
                    if (_order.state == states[l]) {
                        found = true;
                        break;
                    }
                }

                if (!found) continue;
            }

            _upfrontOrders[count] = _order;
            count++;
        }

        Order[] memory _orders = new Order[](count);

        for (uint256 i = 0; i < count; i++) {
            _orders[i] = _upfrontOrders[i];
        }

        return _orders;
    }

    function sellerMetrics(address seller)
        public
        view
        returns (
            uint256 totalSaleOrders,
            uint256 soldOrders,
            uint256 deliveredOrders,
            uint256 cancelledSeller,
            uint256 cancelledBuyer
        )
    {
        for (uint256 i = 0; i < orders.length; i++) {
            Order storage _order = orders[uint256(i)];

            if (_order.seller != seller) {
                continue;
            }

            totalSaleOrders++;

            if (_order.state == OrderState.Sold) {
                soldOrders++;
            }

            if (_order.state == OrderState.Finished) {
                deliveredOrders++;
            }

            if (_order.state == OrderState.CancelledBySeller) {
                cancelledSeller++;
            }

            if (_order.state == OrderState.CancelledByBuyer) {
                cancelledBuyer++;
            }
        }

        soldOrders += cancelledBuyer + cancelledSeller + deliveredOrders;
    }

    function buyerMetrics(address buyer)
        public
        view
        returns (
            uint256 boughtOrders,
            uint256 deliveredOrders,
            uint256 cancelledSeller,
            uint256 cancelledBuyer
        )
    {
        for (uint256 i = 0; i < orders.length; i++) {
            Order storage _order = orders[uint256(i)];

            if (_order.buyer != buyer) {
                continue;
            }

            if (_order.state == OrderState.Sold) {
                boughtOrders++;
            }

            if (_order.state == OrderState.Finished) {
                deliveredOrders++;
            }

            if (_order.state == OrderState.CancelledBySeller) {
                cancelledSeller++;
            }

            if (_order.state == OrderState.CancelledByBuyer) {
                cancelledBuyer++;
            }
        }

        boughtOrders += cancelledSeller + cancelledBuyer + deliveredOrders;
    }
}

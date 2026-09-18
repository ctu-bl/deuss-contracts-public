// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Bond, BondStatus, CouponFrequency, CouponRateType} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {AssetType, InterestStatus, Offer, SaleMode} from "src/marketplace/MarketStructs.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {IMarketFilter} from "src/marketplace/interfaces/IMarketFilter.sol";
import {IBondMetadataAdapter} from "src/marketplace/filters/interfaces/IBondMetadataAdapter.sol";

/// @notice Fuzz-only metadata adapter for deterministic BondMarketFilter coverage.
contract FuzzBondMetadataAdapter is IBondMetadataAdapter {
    error FuzzBondMetadataAdapter__BondNotConfigured();

    mapping(address token => mapping(uint256 tokenId => Bond bond)) internal _bonds;
    mapping(address token => mapping(uint256 tokenId => bool configured)) internal _configured;
    mapping(address token => mapping(uint256 tokenId => uint256 rate)) internal _rates;

    function configureBond(
        address token,
        uint256 tokenId,
        bytes3 currency,
        address issuer,
        BondStatus status,
        CouponRateType couponRateType,
        uint256 bondNominalValue,
        uint256 maturityDate,
        uint256 rate
    ) external {
        Bond storage bond = _bonds[token][tokenId];
        bond.isin = bytes12(keccak256(abi.encode(token, tokenId)));
        bond.issuer = issuer;
        bond.tokenAddress = token;
        bond.status = status;
        bond.couponFrequency = CouponFrequency.Annual;
        bond.trancheCount = 1;
        bond.currency = currency;
        bond.couponRateType = couponRateType;
        bond.bondNominalValue = bondNominalValue;
        bond.maxSupply = 1_000_000;
        bond.mintedSupply = 1_000_000;
        bond.maturityDate = maturityDate;
        bond.tokenId = tokenId;
        bond.remainingIssuableSupply = 0;
        bond.issuanceClosed = true;
        bond.isGuaranteed = false;
        bond.issuanceCountry = 703;

        delete bond.couponRates.paymentTimestamps;
        delete bond.couponRates.rates;
        bond.couponRates.paymentTimestamps.push(block.timestamp);
        bond.couponRates.rates.push(rate);

        _rates[token][tokenId] = rate;
        _configured[token][tokenId] = true;
    }

    function clearBond(address token, uint256 tokenId) external {
        delete _bonds[token][tokenId];
        delete _configured[token][tokenId];
        delete _rates[token][tokenId];
    }

    function getBond(address token, uint256 tokenId) external view returns (Bond memory bond) {
        if (!_configured[token][tokenId]) {
            revert FuzzBondMetadataAdapter__BondNotConfigured();
        }
        return _bonds[token][tokenId];
    }

    function getCurrentCouponRate(Bond calldata bond) external view returns (uint256 rate) {
        if (bond.couponRateType == CouponRateType.ZERO_COUPON) {
            return 0;
        }
        return _rates[bond.tokenAddress][bond.tokenId];
    }
}

/// @notice Minimal IMarketFilter implementation used by the orderbook internal coverage harness.
contract FuzzMarketFilter is IMarketFilter {
    function matchesFilter(address, uint256, bytes calldata filterData) external pure returns (bool) {
        return filterData.length == 0 || filterData[0] != 0xff;
    }
}

/// @notice Direct BondMarketFilter probe that avoids proxy/staticcall coverage blind spots.
contract FuzzBondMarketFilterCoverageHarness is BondMarketFilter {
    error FuzzBondMarketFilterCoverageHarness__UnexpectedCallFailure(bytes4 selector);
    error FuzzBondMarketFilterCoverageHarness__UnexpectedCallSuccess();
    error FuzzBondMarketFilterCoverageHarness__UnexpectedMatch(bool actual, bool expected);

    // solhint-disable-next-line function-max-lines
    function exerciseSurface(
        FuzzBondMetadataAdapter adapter_,
        address token,
        uint256 baseTokenId,
        bytes3 currency,
        address issuer,
        address otherIssuer
    ) external {
        _adapters[token] = IBondMetadataAdapter(address(adapter_));

        BondFilter memory filter;
        this.encodeFilter(filter);
        _expectMatch(token, baseTokenId, filter, false);

        uint256 issuedTokenId = baseTokenId + 1;
        adapter_.configureBond(
            token,
            issuedTokenId,
            currency,
            issuer,
            BondStatus.Issued,
            CouponRateType.FIXED,
            1_000,
            block.timestamp + 365 days,
            500
        );
        _expectMatch(token, issuedTokenId, filter, true);

        uint256 suspendedTokenId = baseTokenId + 2;
        adapter_.configureBond(
            token,
            suspendedTokenId,
            currency,
            issuer,
            BondStatus.Suspended,
            CouponRateType.FIXED,
            1_000,
            block.timestamp + 365 days,
            500
        );
        _expectMatch(token, suspendedTokenId, filter, false);

        filter.maturityFrom = block.timestamp + 400 days;
        _expectMatch(token, issuedTokenId, filter, false);
        filter = _emptyFilter();
        filter.maturityTo = block.timestamp + 1 days;
        _expectMatch(token, issuedTokenId, filter, false);
        filter = _emptyFilter();
        filter.bondNominalValueFrom = 2_000;
        _expectMatch(token, issuedTokenId, filter, false);
        filter = _emptyFilter();
        filter.bondNominalValueTo = 500;
        _expectMatch(token, issuedTokenId, filter, false);

        filter = _emptyFilter();
        filter.currencyWhitelist = new bytes3[](1);
        filter.currencyWhitelist[0] = bytes3("USD");
        _expectMatch(token, issuedTokenId, filter, false);
        filter.currencyWhitelist[0] = currency;
        _expectMatch(token, issuedTokenId, filter, true);
        filter = _emptyFilter();
        filter.currencyBlacklist = new bytes3[](1);
        filter.currencyBlacklist[0] = currency;
        _expectMatch(token, issuedTokenId, filter, false);
        filter.currencyBlacklist[0] = bytes3("USD");
        _expectMatch(token, issuedTokenId, filter, true);

        filter = _emptyFilter();
        filter.issuerWhitelist = new address[](1);
        filter.issuerWhitelist[0] = otherIssuer;
        _expectMatch(token, issuedTokenId, filter, false);
        filter.issuerWhitelist[0] = issuer;
        _expectMatch(token, issuedTokenId, filter, true);
        filter = _emptyFilter();
        filter.issuerBlacklist = new address[](1);
        filter.issuerBlacklist[0] = issuer;
        _expectMatch(token, issuedTokenId, filter, false);
        filter.issuerBlacklist[0] = otherIssuer;
        _expectMatch(token, issuedTokenId, filter, true);

        filter = _emptyFilter();
        filter.couponRateTypes = new CouponRateType[](1);
        filter.couponRateTypes[0] = CouponRateType.ZERO_COUPON;
        _expectMatch(token, issuedTokenId, filter, false);
        filter.couponRateTypes[0] = CouponRateType.FIXED;
        _expectMatch(token, issuedTokenId, filter, true);
        filter = _emptyFilter();
        filter.couponRateFrom = 600;
        _expectMatch(token, issuedTokenId, filter, false);
        filter = _emptyFilter();
        filter.couponRateTo = 400;
        _expectMatch(token, issuedTokenId, filter, false);
        filter = _emptyFilter();
        filter.couponRateFrom = 400;
        filter.couponRateTo = 600;
        _expectMatch(token, issuedTokenId, filter, true);

        filter = _emptyFilter();
        filter.maturityFrom = 2;
        filter.maturityTo = 1;
        _expectRevert(token, issuedTokenId, filter, Errors.BondMarketFilter__InvalidFilterRange.selector);
        filter = _emptyFilter();
        filter.couponRateFrom = 2;
        filter.couponRateTo = 1;
        _expectRevert(token, issuedTokenId, filter, Errors.BondMarketFilter__InvalidFilterRange.selector);
        filter = _emptyFilter();
        filter.bondNominalValueFrom = 2;
        filter.bondNominalValueTo = 1;
        _expectRevert(token, issuedTokenId, filter, Errors.BondMarketFilter__InvalidFilterRange.selector);
    }

    // solhint-disable avoid-low-level-calls
    function _expectMatch(address token, uint256 tokenId, BondFilter memory filter, bool expected) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) =
            address(this).call(abi.encodeWithSelector(this.matchesFilter.selector, token, tokenId, abi.encode(filter)));
        if (!success) {
            revert FuzzBondMarketFilterCoverageHarness__UnexpectedCallFailure(_returnSelector(returnData));
        }
        bool actual = abi.decode(returnData, (bool));
        if (actual != expected) {
            revert FuzzBondMarketFilterCoverageHarness__UnexpectedMatch(actual, expected);
        }
    }

    function _expectRevert(address token, uint256 tokenId, BondFilter memory filter, bytes4 expectedSelector) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) =
            address(this).call(abi.encodeWithSelector(this.matchesFilter.selector, token, tokenId, abi.encode(filter)));
        if (success) {
            revert FuzzBondMarketFilterCoverageHarness__UnexpectedCallSuccess();
        }
        bytes4 actualSelector = _returnSelector(returnData);
        if (actualSelector != expectedSelector) {
            revert FuzzBondMarketFilterCoverageHarness__UnexpectedCallFailure(actualSelector);
        }
    }
    // solhint-enable avoid-low-level-calls

    function _emptyFilter() internal pure returns (BondFilter memory filter) {
        return filter;
    }

    function _returnSelector(bytes memory returnData) internal pure returns (bytes4 selector) {
        if (returnData.length > 3) {
            // forge-lint: disable-next-line(unsafe-typecast)
            selector = bytes4(returnData);
        }
    }
}

/// @notice Exposes Marketplace defensive internal branches that cannot be reached through valid public storage.
contract FuzzMarketplaceCoverageHarness is Marketplace {
    uint256 private constant _INVALID_SALE_MODE = 99;

    function initializeCoverage(address owner_, address assetManager_, address escrowManager_, address entityRegistry_)
        external
        initializer
    {
        __Marketplace_init(
            owner_, 1 days, 1 days, 1 days, 1 days, 1 days, 1 days, assetManager_, escrowManager_, entityRegistry_, 1
        );
    }

    function exposedInvalidCancellationSaleMode() external {
        Offer storage offer = _marketplaceStorage().offers[1];
        _storeInvalidSaleMode(offer);
        _prepareOfferCancellation(1, offer);
    }

    function exposedInvalidPaymentExpirySaleMode() external view returns (uint256) {
        return _getPaymentExpiryThreshold(SaleMode.INTEREST_DISCOVERY);
    }

    function exposedInvalidInterestStatus() external pure {
        _validateInterestStatus(1, InterestStatus.CLOSED, InterestStatus.EXPRESSED);
    }

    function exposedValidateMarketplaceSaleMode() external {
        Offer storage offer = _marketplaceStorage().offers[2];
        offer.saleMode = SaleMode.REDEMPTION;
        _validateMarketplaceSaleMode(offer, 2);
    }

    function _storeInvalidSaleMode(Offer storage offer) internal {
        offer.saleMode = SaleMode.MARKETPLACE;
        bytes32 offerSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            offerSlot := offer.slot
            let word := sload(offerSlot)
            word := and(word, not(shl(32, 0xff)))
            word := or(word, shl(32, _INVALID_SALE_MODE))
            sstore(offerSlot, word)
        }
    }
}

/// @notice Exposes EscrowManager invalid asset-type branches that valid AssetManager configs prevent.
contract FuzzEscrowManagerCoverageHarness is EscrowManager {
    function exposedTransferERC721(address token, uint256 tokenId, address beneficiary) external {
        _transferAsset(AssetType.ERC721, token, address(this), beneficiary, tokenId, 1);
    }

    function exposedBalanceHeldERC721(address token, uint256 tokenId) external view returns (uint256) {
        return _balanceHeld(AssetType.ERC721, token, tokenId);
    }

    function exposedInvalidTransferAsset(address token) external {
        _transferAsset(AssetType.NONE, token, address(this), address(0xBEEF), 0, 1);
    }

    function exposedInvalidBalanceHeld(address token) external view returns (uint256) {
        return _balanceHeld(AssetType.NONE, token, 0);
    }
}

/// @notice Exposes OrderbookMarketplace internal matching and validation branches for line coverage.
contract FuzzOrderbookCoverageHarness is OrderbookMarketplace {
    /// @notice Full internal-surface coverage in one call. Used on the harness SETUP path only, where the
    ///         constructor's gas budget comfortably covers the whole body. The campaign exercises the same
    ///         branches through the smaller exerciseInternal*Surface entrypoints below, each of which fits
    ///         inside Echidna's per-call gas limit.
    function exerciseInternalSurface(
        address entityRegistry_,
        address marketFilter_,
        address actorA,
        address actorB,
        address[] calldata emptyFilterAddresses,
        address[] calldata filterAddresses,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) external {
        _resetCoverageOrderbookState();
        _setupCoverageConfig(marketFilter_);
        _exerciseValidationBranches(entityRegistry_, actorA, actorB, emptyFilterAddresses, filterAddresses);
        _exerciseOrderCreation(actorA, actorB);
        _exerciseMatchingBranches(actorA, actorB, batch);
        _exerciseObservationBranches();
    }

    /// @notice Validation, trader-filter, expiry, and delegate coverage plus light order creation and TWAP
    ///         observation branches. Creates no matched order books, so it is the cheapest split.
    function exerciseInternalValidationSurface(
        address entityRegistry_,
        address marketFilter_,
        address actorA,
        address actorB,
        address[] calldata emptyFilterAddresses,
        address[] calldata filterAddresses
    ) external {
        _resetCoverageOrderbookState();
        _setupCoverageConfig(marketFilter_);
        _exerciseValidationBranches(entityRegistry_, actorA, actorB, emptyFilterAddresses, filterAddresses);
        _exerciseOrderCreation(actorA, actorB);
        _exerciseObservationBranches();
    }

    /// @notice Buy-order matching branches (break + skip legs).
    function exerciseInternalMatchBuySurface(address marketFilter_, address actorA, address actorB) external {
        _resetCoverageOrderbookState();
        _setupCoverageConfig(marketFilter_);
        _exerciseMatchBuyBranches(actorA, actorB);
    }

    /// @notice Sell-order matching branches (break + skip legs).
    function exerciseInternalMatchSellSurface(address marketFilter_, address actorA, address actorB) external {
        _resetCoverageOrderbookState();
        _setupCoverageConfig(marketFilter_);
        _exerciseMatchSellBranches(actorA, actorB);
    }

    /// @notice Residual buy/sell matching branches plus the peek-and-batch market branches.
    function exerciseInternalResidualAndBatchSurface(
        address marketFilter_,
        address actorA,
        address actorB,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) external {
        _resetCoverageOrderbookState();
        _setupCoverageConfig(marketFilter_);
        _exerciseResidualMatchBuyBranches(actorA, actorB);
        _exerciseResidualMatchSellBranches(actorA, actorB);
        _exercisePeekAndBatchBranches(actorA, actorB, batch);
    }

    /// @dev Storage config the matching branches depend on (asset manager, escrow, thresholds, market filter).
    function _setupCoverageConfig(address marketFilter_) internal {
        _orderbookMarketplaceStorage().assetManager = address(0xA551A551);
        _orderbookMarketplaceStorage().escrowManager = address(0xE5C0);
        _orderbookMarketplaceStorage().paymentExpiryThreshold = 1 days;
        _orderbookMarketplaceStorage().minExpiryThreshold = 1 days;
        _orderbookMarketplaceStorage().disputeBufferPeriod = 1 days;
        _orderbookMarketplaceStorage().marketFilter = marketFilter_;
    }

    /// @dev Validation, trader-filter, expiry, delegate and msg.sender resolution coverage. Creates no orders.
    function _exerciseValidationBranches(
        address entityRegistry_,
        address actorA,
        address actorB,
        address[] calldata emptyFilterAddresses,
        address[] calldata filterAddresses
    ) internal {
        _validatePlaceOrderInputs(1, 1, 1, 0);
        _validateTraderFilter(IOrderbookMarketplace.TraderFilterMode.NONE, emptyFilterAddresses);
        _validateTraderFilter(IOrderbookMarketplace.TraderFilterMode.WHITELIST, filterAddresses);
        _storeTraderFilter(1, filterAddresses);
        _orderbookMarketplaceStorage().orderTraderFilter[2][actorA] = true;
        _isTraderAllowed(1, IOrderbookMarketplace.TraderFilterMode.NONE, actorA);
        _isTraderAllowed(2, IOrderbookMarketplace.TraderFilterMode.WHITELIST, actorA);
        _isTraderAllowed(2, IOrderbookMarketplace.TraderFilterMode.BLACKLIST, actorB);

        _validateOrderExpiryThreshold(0);
        _validateOrderExpiryThreshold(block.timestamp + 2 days);
        _isOrderExpired(0);
        if (block.timestamp > 1) {
            _isOrderExpired(block.timestamp - 1);
        }

        _orderbookMarketplaceStorage().entityRegistry = address(0);
        _validateMsgSender(actorA);
        _resolveEffectiveTrader(address(0));
        _orderbookMarketplaceStorage().delegations[actorA][msg.sender] = true;
        _validateDelegate(actorA, msg.sender);
        _resolveEffectiveTrader(actorA);
        _orderbookMarketplaceStorage().entityRegistry = entityRegistry_;
        _validateMsgSender(actorA);
        _orderbookMarketplaceStorage().entityRegistry = address(0);
    }

    /// @dev Resets the fixed markets used by the directed branch probes so corpus replay order cannot leak scratch
    ///      orderbook/TWAP state between otherwise independent coverage surfaces.
    function _resetCoverageOrderbookState() internal {
        OrderbookMarketplaceState storage store = _orderbookMarketplaceStorage();
        uint256 activeCount = store.activeSellMarkets.length;
        for (uint256 i; i < activeCount; ++i) {
            IOrderbookMarketplace.Market memory market = store.activeSellMarkets[i];
            store.activeSellMarketIndex[market.tokenAddress][market.tokenId] = 0;
        }
        delete store.activeSellMarkets;
        delete store.twapStates[address(0xB003)][2];
        delete store.twapStates[address(0xB005)][4];
        delete store.twapStates[address(0xBA01)][101];
        delete store.twapStates[address(0xBA12)][110];
        delete store.twapStates[address(0xB007)][6];
        delete store.twapStates[address(0xB007)][7];
        delete store.twapStates[address(0xBA20)][120];
    }

    /// @dev Empties both order-id arrays and active-market indexing for a single (token, tokenId) market. Called at
    ///      the start of each branch helper so the persistent harness's order books cannot accumulate across campaign
    ///      calls (which would make _createOrder's O(n) insertion sort run out of gas after enough invocations).
    function _clearMarket(address token, uint256 tokenId) internal {
        OrderbookMarketplaceState storage store = _orderbookMarketplaceStorage();
        uint256 indexPlusOne = store.activeSellMarketIndex[token][tokenId];
        uint256 activeCount = store.activeSellMarkets.length;
        if (indexPlusOne != 0) {
            uint256 index = indexPlusOne - 1;
            if (index < activeCount) {
                IOrderbookMarketplace.Market memory indexedMarket = store.activeSellMarkets[index];
                if (indexedMarket.tokenAddress == token && indexedMarket.tokenId == tokenId) {
                    _removeActiveSellMarket(token, tokenId);
                }
            }
        }

        store.activeSellMarketIndex[token][tokenId] = 0;
        delete store.buyOrderIdsByTokenId[token][tokenId];
        delete store.sellOrderIdsByTokenId[token][tokenId];
    }

    function exposedValidateZeroAmount() external pure {
        _validatePlaceOrderInputs(0, 1, 1, 0);
    }

    function exposedValidateZeroPrice() external pure {
        _validatePlaceOrderInputs(1, 0, 1, 0);
    }

    function exposedValidateInvalidPriceRange() external pure {
        _validatePlaceOrderInputs(1, 2, 1, 0);
    }

    function exposedValidateMinMatchExceedsTotal() external pure {
        _validatePlaceOrderInputs(1, 1, 1, 2);
    }

    function exposedValidateTraderFilterNotEmpty(address[] calldata traderFilterAddresses) external pure {
        _validateTraderFilter(IOrderbookMarketplace.TraderFilterMode.NONE, traderFilterAddresses);
    }

    function exposedValidateTraderFilterEmpty(address[] calldata traderFilterAddresses) external pure {
        _validateTraderFilter(IOrderbookMarketplace.TraderFilterMode.WHITELIST, traderFilterAddresses);
    }

    function exposedValidateTraderFilterTooLarge(address[] calldata traderFilterAddresses) external pure {
        _validateTraderFilter(IOrderbookMarketplace.TraderFilterMode.WHITELIST, traderFilterAddresses);
    }

    function exposedStoreZeroTraderFilter(address[] calldata traderFilterAddresses) external {
        _storeTraderFilter(99, traderFilterAddresses);
    }

    function exposedBlacklistTraderAllowed(address trader) external view returns (bool) {
        return _isTraderAllowed(2, IOrderbookMarketplace.TraderFilterMode.BLACKLIST, trader);
    }

    function exposedMatchSellZeroBreak(address buyer, address seller) external returns (uint256) {
        address token = address(0xBA20);
        uint256 tokenId = 120;

        _clearMarket(token, tokenId);
        _createOrder(
            token,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            0,
            buyer
        );
        uint256 sellOrderId = _createOrder(
            token,
            tokenId,
            1,
            1,
            3,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.SELL,
            0,
            seller
        );

        return
            _matchSellOrder(
                token, tokenId, sellOrderId, 0, 1, 3, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller
            );
    }

    function _exerciseOrderCreation(address actorA, address actorB) internal {
        address token = address(0xB001);
        uint256 tokenId = 1;

        _clearMarket(token, tokenId);
        _createOrder(
            token,
            tokenId,
            1,
            1,
            5,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            0,
            actorA
        );
        _createOrder(
            token,
            tokenId,
            1,
            1,
            7,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            0,
            actorB
        );
        uint256 sellA = _createOrder(
            token,
            tokenId,
            1,
            9,
            10,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.SELL,
            0,
            actorA
        );
        _createOrder(
            token,
            tokenId,
            1,
            8,
            10,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.SELL,
            0,
            actorB
        );
        _addActiveSellMarket(token, tokenId);

        _removeFromArray(_orderbookMarketplaceStorage().buyOrderIdsByTokenId[token][tokenId], type(uint256).max);
        _deleteOrder(sellA, _orderbookMarketplaceStorage().orders[sellA]);
    }

    function _createBuyOrder(
        address token,
        uint256 tokenId,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        uint256 expiry,
        address trader
    ) internal returns (uint256 orderId) {
        return _createOrder(
            token,
            tokenId,
            1,
            minPrice,
            maxPrice,
            minMatchAmount,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            expiry,
            trader
        );
    }

    function _createSellOrder(
        address token,
        uint256 tokenId,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 minMatchAmount,
        uint256 expiry,
        address trader
    ) internal returns (uint256 orderId) {
        return _createOrder(
            token,
            tokenId,
            1,
            minPrice,
            maxPrice,
            minMatchAmount,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.SELL,
            expiry,
            trader
        );
    }

    function _exerciseMatchingBranches(
        address actorA,
        address actorB,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) internal {
        _exerciseMatchBuyBranches(actorA, actorB);
        _exerciseMatchSellBranches(actorA, actorB);
        _exerciseResidualMatchBuyBranches(actorA, actorB);
        _exerciseResidualMatchSellBranches(actorA, actorB);
        _exercisePeekAndBatchBranches(actorA, actorB, batch);
    }

    function _exerciseMatchBuyBranches(address buyer, address seller) internal {
        _exerciseMatchBuyBreakBranch(buyer, seller);
        _exerciseMatchBuySkipBranches(buyer, seller);
    }

    function _exerciseMatchBuyBreakBranch(address buyer, address seller) internal {
        address token = address(0xB002);
        uint256 tokenId = 2;

        _clearMarket(token, tokenId);
        _createSellOrder(token, tokenId, 200, 200, 0, 0, seller);
        uint256 buyBreak = _createBuyOrder(token, tokenId, 1, 100, 0, 0, buyer);
        _matchBuyOrder(token, tokenId, buyBreak, 1, 1, 100, 0, IOrderbookMarketplace.TraderFilterMode.NONE, buyer);
    }

    function _exerciseMatchBuySkipBranches(address buyer, address seller) internal {
        address token = address(0xB003);
        uint256 tokenId = 2;

        _clearMarket(token, tokenId);
        _createSellOrder(token, tokenId, 1, 1, 0, 0, seller);
        if (block.timestamp > 1) {
            _createSellOrder(token, tokenId, 2, 10, 0, block.timestamp - 1, seller);
        }
        uint256 empty = _createSellOrder(token, tokenId, 3, 10, 0, 0, seller);
        _orderbookMarketplaceStorage().orders[empty].amounts.available = 0;
        _orderbookMarketplaceStorage().orders[empty].amounts.inDeals = 1;
        uint256 frozen = _createSellOrder(token, tokenId, 4, 10, 0, 0, seller);
        _orderbookMarketplaceStorage().orderFrozen[frozen] = true;
        _createSellOrder(token, tokenId, 5, 10, 0, 0, buyer);
        _createOrder(
            token,
            tokenId,
            1,
            5,
            10,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.SELL,
            0,
            buyer
        );
        _createOrder(
            token,
            tokenId,
            1,
            6,
            10,
            0,
            IOrderbookMarketplace.TraderFilterMode.WHITELIST,
            IOrderbookMarketplace.OrderSide.SELL,
            0,
            seller
        );
        _createSellOrder(token, tokenId, 7, 10, 2, 0, seller);
        uint256 buyOrder = _createBuyOrder(token, tokenId, 1, 10, 0, 0, buyer);
        _matchBuyOrder(token, tokenId, buyOrder, 1, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE, buyer);
    }

    function _exerciseMatchSellBranches(address buyer, address seller) internal {
        _exerciseMatchSellBreakBranch(buyer, seller);
        _exerciseMatchSellSkipBranches(buyer, seller);
    }

    function _exerciseMatchSellBreakBranch(address buyer, address seller) internal {
        address token = address(0xB004);
        uint256 tokenId = 4;

        _clearMarket(token, tokenId);
        _createBuyOrder(token, tokenId, 1, 1, 0, 0, buyer);
        uint256 sellBreak = _createSellOrder(token, tokenId, 10, 20, 0, 0, seller);
        _matchSellOrder(token, tokenId, sellBreak, 1, 10, 20, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller);
    }

    function _exerciseMatchSellSkipBranches(address buyer, address seller) internal {
        address token = address(0xB005);
        uint256 tokenId = 4;

        _clearMarket(token, tokenId);
        _createBuyOrder(token, tokenId, 50, 100, 0, 0, buyer);
        if (block.timestamp > 1) {
            _createBuyOrder(token, tokenId, 1, 9, 0, block.timestamp - 1, buyer);
        }
        uint256 empty = _createBuyOrder(token, tokenId, 1, 8, 0, 0, buyer);
        _orderbookMarketplaceStorage().orders[empty].amounts.available = 0;
        _orderbookMarketplaceStorage().orders[empty].amounts.inDeals = 1;
        uint256 frozen = _createBuyOrder(token, tokenId, 1, 7, 0, 0, buyer);
        _orderbookMarketplaceStorage().orderFrozen[frozen] = true;
        _createBuyOrder(token, tokenId, 1, 6, 0, 0, seller);
        _createOrder(
            token,
            tokenId,
            1,
            1,
            6,
            0,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            0,
            seller
        );
        _createOrder(
            token,
            tokenId,
            1,
            1,
            5,
            0,
            IOrderbookMarketplace.TraderFilterMode.WHITELIST,
            IOrderbookMarketplace.OrderSide.BUY,
            0,
            buyer
        );
        _createBuyOrder(token, tokenId, 1, 4, 2, 0, buyer);
        uint256 sellOrder = _createSellOrder(token, tokenId, 1, 10, 0, 0, seller);
        _matchSellOrder(token, tokenId, sellOrder, 1, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller);
    }

    function _exerciseResidualMatchBuyBranches(address buyer, address seller) internal {
        _exerciseResidualMatchBuyExpiredBranch(buyer, seller);
        _exerciseResidualMatchBuySelfTradeBranch(buyer);
        _exerciseResidualMatchBuyMinMatchBranch(buyer, seller);
    }

    function _exerciseResidualMatchBuyExpiredBranch(address buyer, address seller) internal {
        address token = address(0xBA01);
        uint256 tokenId = 101;

        if (block.timestamp < 2) {
            return;
        }

        _clearMarket(token, tokenId);
        _createSellOrder(token, tokenId, 1, 10, 0, block.timestamp - 1, seller);
        uint256 buyExpired = _createBuyOrder(token, tokenId, 1, 10, 0, 0, buyer);
        _matchBuyOrder(token, tokenId, buyExpired, 1, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE, buyer);
    }

    function _exerciseResidualMatchBuySelfTradeBranch(address buyer) internal {
        address token = address(0xBA02);
        uint256 tokenId = 101;

        _clearMarket(token, tokenId);
        _createSellOrder(token, tokenId, 1, 10, 0, 0, buyer);
        uint256 buySelfTrade = _createBuyOrder(token, tokenId, 1, 10, 0, 0, buyer);
        _matchBuyOrder(token, tokenId, buySelfTrade, 1, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE, buyer);
    }

    function _exerciseResidualMatchBuyMinMatchBranch(address buyer, address seller) internal {
        address token = address(0xBA03);
        uint256 tokenId = 101;

        _clearMarket(token, tokenId);
        _createSellOrder(token, tokenId, 1, 10, 2, 0, seller);
        uint256 buyMinMatch = _createBuyOrder(token, tokenId, 1, 10, 0, 0, buyer);
        _matchBuyOrder(token, tokenId, buyMinMatch, 1, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE, buyer);
    }

    function _exerciseResidualMatchSellBranches(address buyer, address seller) internal {
        _exerciseResidualMatchSellZeroRemainingBranch(buyer, seller);
        _exerciseResidualMatchSellBreakBranch(buyer, seller);
        _exerciseResidualMatchSellMatchBranch(buyer, seller);
    }

    function _exerciseResidualMatchSellZeroRemainingBranch(address buyer, address seller) internal {
        address token = address(0xBA10);
        uint256 tokenId = 110;

        _clearMarket(token, tokenId);
        _createBuyOrder(token, tokenId, 1, 3, 0, 0, buyer);
        uint256 sellZeroRemaining = _createSellOrder(token, tokenId, 1, 3, 0, 0, seller);
        _matchSellOrder(
            token, tokenId, sellZeroRemaining, 0, 1, 3, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller
        );
    }

    function _exerciseResidualMatchSellBreakBranch(address buyer, address seller) internal {
        address token = address(0xBA11);
        uint256 tokenId = 110;

        _clearMarket(token, tokenId);
        _createBuyOrder(token, tokenId, 1, 1, 0, 0, buyer);
        uint256 sellBreak = _createSellOrder(token, tokenId, 2, 3, 0, 0, seller);
        _matchSellOrder(token, tokenId, sellBreak, 1, 2, 3, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller);
    }

    function _exerciseResidualMatchSellMatchBranch(address buyer, address seller) internal {
        address token = address(0xBA12);
        uint256 tokenId = 110;

        _clearMarket(token, tokenId);
        _createBuyOrder(token, tokenId, 1, 3, 0, 0, buyer);
        uint256 sellMatch = _createSellOrder(token, tokenId, 1, 3, 0, 0, seller);
        _matchSellOrder(token, tokenId, sellMatch, 1, 1, 3, 0, IOrderbookMarketplace.TraderFilterMode.NONE, seller);
    }

    function _exercisePeekAndBatchBranches(
        address actorA,
        address actorB,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) internal {
        uint256 batchOrderId = _createSyntheticBatchOrder(batch);

        _exerciseExpensiveAskPeek(batchOrderId, actorA, batch);
        _exerciseBatchMarketBranches(batchOrderId, actorA, actorB, batch);
    }

    function _createSyntheticBatchOrder(IOrderbookMarketplace.BatchOrderInput calldata batch)
        internal
        returns (uint256 batchOrderId)
    {
        batchOrderId = ++_orderbookMarketplaceStorage().ordersCount;
        _orderbookMarketplaceStorage().orders[batchOrderId] = IOrderbookMarketplace.Order({
            tokenAddress: address(0),
            tokenId: 0,
            trader: msg.sender,
            minPrice: batch.minPrice,
            maxPrice: batch.maxPrice,
            minMatchAmount: batch.minMatchAmount,
            traderFilterMode: batch.traderFilterMode,
            side: IOrderbookMarketplace.OrderSide.BUY,
            timestamp: block.timestamp,
            expiry: 0,
            amounts: IOrderbookMarketplace.OrderAmounts({total: batch.totalAmount, available: 0, inDeals: 0, sold: 0})
        });
    }

    function _exerciseExpensiveAskPeek(
        uint256 batchOrderId,
        address actorA,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) internal {
        address expensiveToken = address(0xB006);
        uint256 tokenId = 6;

        _clearMarket(expensiveToken, tokenId);
        _createSellOrder(expensiveToken, tokenId, batch.maxPrice + 1, batch.maxPrice + 1, 0, 0, actorA);
        _peekEligibleAskPrice(expensiveToken, tokenId, batchOrderId, batch.totalAmount, batch, msg.sender);
    }

    function _exerciseBatchMarketBranches(
        uint256 batchOrderId,
        address actorA,
        address actorB,
        IOrderbookMarketplace.BatchOrderInput calldata batch
    ) internal {
        uint256 tokenId = 6;

        address token = address(0xB007);
        _clearMarket(token, tokenId);
        uint256 validSell = _createSellOrder(token, tokenId, 1, batch.maxPrice, 0, 0, actorA);
        _createSellOrder(token, tokenId, 2, batch.maxPrice, 0, 0, actorB);
        _peekEligibleAskPrice(token, tokenId, batchOrderId, batch.totalAmount, batch, msg.sender);
        _evaluateMarketForBatch(
            IOrderbookMarketplace.Market({tokenAddress: token, tokenId: tokenId}), batch.filterData, batch.maxPrice
        );
        _buildSortedMarketList(batch.filterData, batch.maxPrice);

        IOrderbookMarketplace.Market[] memory sorted = new IOrderbookMarketplace.Market[](1);
        sorted[0] = IOrderbookMarketplace.Market({tokenAddress: token, tokenId: tokenId});
        _matchBatchBuyOrder(sorted, batchOrderId, batch);

        _orderbookMarketplaceStorage().orders[validSell].amounts.available;
    }

    function _exerciseObservationBranches() internal {
        address token = address(0xB007);
        uint256 tokenId = 7;
        TWAPState storage state = _orderbookMarketplaceStorage().twapStates[token][tokenId];
        _recordObservation(state, token, tokenId, 10, block.timestamp);
        _recordObservation(state, token, tokenId, 20, block.timestamp + 1);

        state.observationCount = MAX_RECENT_OBSERVATIONS;
        state.currentIndex = 255;
        state.observations[0] =
            IOrderbookMarketplace.Observation({timestamp: uint32(block.timestamp + 2), cumulativePrice: 0});
        _findClosestObservation(state, 0, MAX_RECENT_OBSERVATIONS, uint32(block.timestamp + 1));
    }
}

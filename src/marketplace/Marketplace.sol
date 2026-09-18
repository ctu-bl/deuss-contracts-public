// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {Errors} from "../libs/Errors.sol";
import {IEntityRegistry} from "../registry/interfaces/IEntityRegistry.sol";
import {MarketplaceBase} from "./MarketplaceBase.sol";
import {IAssetManager} from "./interfaces/IAssetManager.sol";
import {IEscrowManager} from "./interfaces/IEscrowManager.sol";
import {IMarketplace} from "./interfaces/IMarketplace.sol";
import {IMarketplaceLensSource} from "./interfaces/IMarketplaceLensSource.sol";
import {
    Amounts,
    AssetType,
    CounterOfferInput,
    Deal,
    DealCreationInput,
    DealStatus,
    DealType,
    Interest,
    InterestDiscoveryState,
    InterestStatus,
    Offer,
    OfferInput,
    PaymentResolutionInput,
    SaleMode
} from "./MarketStructs.sol";

/* solhint-disable ordering */

/**
 * @title Marketplace
 * @notice Marketplace module supporting both direct marketplace offers and threshold-gated interest discovery offers
 * @author DEUSS Team
 * @dev Coordinates offers/deals with `EscrowManager` for custody and settlement; role-gated payment, freeze, seizure,
 *      and dispute flows. Ordering of functions is grouped by domain (`solhint-disable ordering`).
 */
contract Marketplace is IMarketplace, IMarketplaceLensSource, MarketplaceBase, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Role for handling payments
    uint256 public constant PAYMENT_HANDLER = _ROLE_1;
    /// @notice Role for arbitrating disputes
    uint256 public constant ARBITRATOR = _ROLE_2;
    /// @notice Role for seizure operations on frozen offers/deals
    uint256 public constant SEIZURE_ROLE = _ROLE_3;
    /// @notice Role for freezing and unfreezing offers/deals
    uint256 public constant FREEZE_ROLE = _ROLE_4;
    /// @notice Role for operational maintenance of interest-discovery offers (e.g. closing expired interests)
    uint256 public constant INTEREST_DISCOVERY_OPERATOR = _ROLE_5;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param owner_ Address of the contract owner
     * @param offerExpiryThreshold Minimum offer lifetime in seconds
     * @param maxOfferLifetime Maximum offer lifetime in seconds
     * @param marketplacePaymentExpiryThreshold Payment expiry threshold for marketplace deals in seconds
     * @param redemptionPaymentExpiryThreshold Payment expiry threshold for redemption deals in seconds
     * @param interestDiscoveryPaymentExpiryThreshold Threshold snapshotted into new interest-discovery offers
     * @param disputeBufferPeriod Dispute buffer period in seconds
     * @param assetManager_ Address of the asset manager
     * @param escrowManager Address of the escrow manager
     * @param entityRegistry_ Address of the entity registry
     * @param maxCounterOffers Maximum number of counter offers per user per offer
     */
    function initialize(
        address owner_,
        uint256 offerExpiryThreshold,
        uint256 maxOfferLifetime,
        uint256 marketplacePaymentExpiryThreshold,
        uint256 redemptionPaymentExpiryThreshold,
        uint256 interestDiscoveryPaymentExpiryThreshold,
        uint256 disputeBufferPeriod,
        address assetManager_,
        address escrowManager,
        address entityRegistry_,
        uint256 maxCounterOffers
    ) external initializer {
        __Marketplace_init(
            owner_,
            offerExpiryThreshold,
            maxOfferLifetime,
            marketplacePaymentExpiryThreshold,
            redemptionPaymentExpiryThreshold,
            interestDiscoveryPaymentExpiryThreshold,
            disputeBufferPeriod,
            assetManager_,
            escrowManager,
            entityRegistry_,
            maxCounterOffers
        );
    }

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMarketplace
     * @dev Seller wallet/entity enabled state and entity type are validated before escrow creation.
     */
    function registerOffer(OfferInput calldata offer) external nonReentrant returns (uint256 offerId) {
        Offer memory validatedOffer = _validateOffer(offer, msg.sender);
        MarketplaceState storage $ = _marketplaceStorage();
        Counters storage counters = $.counters;
        Config storage config = $.config;

        offerId = ++counters.offerCounter;
        address escrowManager = _dependenciesStorage().escrowManager;
        uint256 expectedEscrowId = IEscrowManager(escrowManager).previewNextEscrowId();

        $.offers[offerId] = validatedOffer;

        if (validatedOffer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            $.interestDiscoveryStateByOfferId[offerId] = InterestDiscoveryState({
                minSaleUnits: offer.minSaleUnits,
                interestedUnits: 0,
                reservedInterestUnits: 0,
                paymentExpiryThreshold: config.interestDiscoveryPaymentExpiryThreshold
            });
        } else {
            _storeAllowedBuyers(offerId, offer.allowedBuyers);
        }

        $.escrowIdByOfferId[offerId] = expectedEscrowId;
        uint256 actualEscrowId = IEscrowManager(escrowManager)
            .createEscrow(
                validatedOffer.amounts.total, validatedOffer.owner, validatedOffer.tokenAddress, validatedOffer.tokenId
            );
        require(
            actualEscrowId == expectedEscrowId, Errors.Marketplace__EscrowIdMismatch(actualEscrowId, expectedEscrowId)
        );

        _emitOfferRegistered(offerId, validatedOffer, offer.minSaleUnits);
        _emitAmountsUpdated(offerId, validatedOffer.amounts);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function acceptOffer(uint256 offerId, uint256 amount) external nonReentrant returns (uint256 dealId) {
        _validateOfferNotCancelled(offerId);
        _validateOfferNotFrozen(offerId);
        Offer storage currentOffer = _marketplaceStorage().offers[offerId];
        _validateDirectSaleMode(currentOffer, offerId);
        _validateBuyerAllowed(currentOffer, offerId, msg.sender);
        _validateNotOwner(msg.sender, currentOffer.owner);
        _validateOfferNotExpired(currentOffer.expiry);
        _validateAmounts(currentOffer, amount);
        _validateEntityWalletAndTypeAllowed(msg.sender);
        _validateEntityWalletEnabled(currentOffer.owner);

        currentOffer.amounts.available -= amount;
        currentOffer.amounts.inDeals += amount;

        dealId = _createOfferDeal(currentOffer, offerId, amount);
        _emitAmountsUpdated(offerId, currentOffer.amounts);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function expressInterest(uint256 offerId, uint256 amount) external nonReentrant returns (uint256 interestId) {
        _validateOfferNotCancelled(offerId);
        _validateOfferNotFrozen(offerId);
        MarketplaceState storage $ = _marketplaceStorage();
        Offer storage currentOffer = $.offers[offerId];
        _validateInterestDiscoverySaleMode(currentOffer, offerId);
        _validateNotOwner(msg.sender, currentOffer.owner);
        _validateOfferNotExpired(currentOffer.expiry);
        _validateAmounts(currentOffer, amount);
        _validateEntityWalletAndTypeAllowed(msg.sender);
        _validateEntityWalletEnabled(currentOffer.owner);

        currentOffer.amounts.available -= amount;

        InterestDiscoveryState storage state = $.interestDiscoveryStateByOfferId[offerId];
        state.interestedUnits += amount;
        state.reservedInterestUnits += amount;

        Counters storage counters = $.counters;
        interestId = ++counters.interestCounter;
        $.interests[interestId] = Interest({
            offerId: offerId,
            amount: amount,
            investor: msg.sender,
            price: currentOffer.unitPrice * amount,
            status: InterestStatus.EXPRESSED
        });
        $.interestIdsByOfferId[offerId].push(interestId);

        emit InterestExpressed(offerId, interestId, msg.sender, amount, currentOffer.unitPrice * amount);
        _emitAmountsUpdated(offerId, currentOffer.amounts);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function activateInterest(uint256 interestId) external nonReentrant returns (uint256 dealId) {
        Interest storage interest = _getInterest(interestId);
        _validateOfferNotCancelled(interest.offerId);
        _validateOfferNotFrozen(interest.offerId);
        MarketplaceState storage $ = _marketplaceStorage();
        Offer storage currentOffer = $.offers[interest.offerId];
        _validateInterestDiscoverySaleMode(currentOffer, interest.offerId);

        InterestDiscoveryState storage state = $.interestDiscoveryStateByOfferId[interest.offerId];
        _validateThresholdReached(interest.offerId, state.interestedUnits, state.minSaleUnits);
        _validateInterestStatus(interestId, interest.status, InterestStatus.EXPRESSED);
        _validateInterestActivationWindow(interest.offerId, currentOffer.expiry);
        _validateNotOwner(interest.investor, currentOffer.owner);
        _validateEntityWalletEnabled(interest.investor);
        _validateEntityWalletEnabled(currentOffer.owner);

        currentOffer.amounts.inDeals += interest.amount;
        state.reservedInterestUnits -= interest.amount;

        dealId = _createActivatedInterestDeal(interest, interestId, currentOffer.expiry);
        _emitAmountsUpdated(interest.offerId, currentOffer.amounts);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function closeExpiredInterests(uint256 offerId, uint256[] calldata interestIds) external nonReentrant {
        _validateOfferNotCancelled(offerId);
        MarketplaceState storage $ = _marketplaceStorage();
        Offer storage currentOffer = $.offers[offerId];
        _validateInterestDiscoverySaleMode(currentOffer, offerId);
        _validateOwnerOrOperator(msg.sender, currentOffer.owner);

        InterestDiscoveryState storage state = $.interestDiscoveryStateByOfferId[offerId];
        uint256 activationDeadline = _getInterestActivationDeadline(offerId, currentOffer.expiry);
        // slither-disable-next-line timestamp
        require(
            block.timestamp > activationDeadline,
            Errors.Marketplace__InterestActivationWindowOpen(offerId, activationDeadline, block.timestamp)
        );
        _validateThresholdReached(offerId, state.interestedUnits, state.minSaleUnits);

        uint256 releasedAmount;
        for (uint256 i; i < interestIds.length; ++i) {
            uint256 interestId = interestIds[i];
            Interest storage interest = _getInterest(interestId);
            require(interest.offerId == offerId, Errors.Marketplace__InterestOfferMismatch(interestId, offerId));
            _validateInterestStatus(interestId, interest.status, InterestStatus.EXPRESSED);

            InterestStatus oldStatus = interest.status;
            interest.status = InterestStatus.CLOSED;
            releasedAmount += interest.amount;

            _emitInterestStatusUpdated(interestId, interest, oldStatus, InterestStatus.CLOSED);
        }

        if (releasedAmount != 0) {
            state.reservedInterestUnits -= releasedAmount;
            currentOffer.amounts.available += releasedAmount;
        }

        _emitAmountsUpdated(offerId, currentOffer.amounts);
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IMarketplace
     * @param offerId The ID of the offer to cancel
     * @dev Seller wallet/entity enabled state and entity type are validated during offer registration.
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        _validateOfferNotCancelled(offerId);
        _validateOfferNotFrozen(offerId);
        Offer storage currentOffer = _marketplaceStorage().offers[offerId];
        if (currentOffer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            _validateOwnerOrOperatorWithEnabledOwner(msg.sender, currentOffer.owner);
        } else {
            _requireEnabledActor(msg.sender, currentOffer.owner);
        }

        uint256 withdrawAmount = _prepareOfferCancellation(offerId, currentOffer);
        _cancelOfferAndWithdraw(offerId, currentOffer, withdrawAmount);
    }

    // slither-disable-end timestamp

    /**
     * @inheritdoc IMarketplace
     * @dev For interest discovery, expiry is the closeout gate. Failed books must use `cancelOffer`,
     *      while successful books withdraw only the currently unreserved available amount.
     */
    function withdrawAvailable(uint256 offerId) external nonReentrant {
        MarketplaceState storage $ = _marketplaceStorage();
        Offer storage currentOffer = $.offers[offerId];
        _requireEnabledActor(msg.sender, currentOffer.owner);
        _validateOfferNotFrozen(offerId);

        uint256 withdrawAmount;
        if (_isDirectSaleMode(currentOffer.saleMode)) {
            _validateOfferCancelled(offerId);
            withdrawAmount = currentOffer.amounts.available;
        } else {
            _validateOfferNotCancelled(offerId);
            // slither-disable-next-line timestamp
            require(
                block.timestamp > currentOffer.expiry,
                Errors.Marketplace__OfferNotExpired(currentOffer.expiry, block.timestamp)
            );
            InterestDiscoveryState storage state = $.interestDiscoveryStateByOfferId[offerId];
            _validateThresholdReached(offerId, state.interestedUnits, state.minSaleUnits);
            withdrawAmount = currentOffer.amounts.available;
        }
        require(withdrawAmount != 0, Errors.Marketplace__NoAvailableAmount(offerId));
        currentOffer.amounts.available = 0;
        IEscrowManager(_dependenciesStorage().escrowManager).withdraw($.escrowIdByOfferId[offerId], withdrawAmount);

        _emitAmountsUpdated(offerId, currentOffer.amounts);
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IMarketplace
     * @param counterOffer Counter-offer payload supplied by the buyer
     * @return dealId The unique identifier for the counter offer deal
     */
    function createCounterOffer(CounterOfferInput calldata counterOffer)
        external
        nonReentrant
        returns (uint256 dealId)
    {
        _validateOfferNotCancelled(counterOffer.offerId);
        _validateOfferNotFrozen(counterOffer.offerId);
        MarketplaceState storage $ = _marketplaceStorage();
        Offer storage originalOffer = $.offers[counterOffer.offerId];
        require(originalOffer.allowCounterOffers, Errors.Marketplace__CounterOffersNotAllowed());

        uint256 currentCount = $.counterOfferCounts[msg.sender][counterOffer.offerId];
        Config storage config = $.config;
        require(currentCount < config.maxCounterOffersPerUser, Errors.Marketplace__CounterOfferLimitReached());

        _validateMarketplaceSaleMode(originalOffer, counterOffer.offerId);
        _validateBuyerAllowed(originalOffer, counterOffer.offerId, msg.sender);
        _validateNotOwner(msg.sender, originalOffer.owner);
        _validateOfferNotExpired(originalOffer.expiry);
        _validateOfferExpiryThreshold(counterOffer.expiry);
        _validateNonZeroPrice(counterOffer.unitPrice);
        _validateAmounts(originalOffer, counterOffer.amount);
        _validateEntityWalletAndTypeAllowed(msg.sender);
        _validateEntityWalletEnabled(originalOffer.owner);

        ++$.counterOfferCounts[msg.sender][counterOffer.offerId];
        dealId = _createCounterOfferDeal(
            counterOffer.offerId, counterOffer.amount, counterOffer.unitPrice, counterOffer.expiry
        );

        emit CounterOfferCreated(counterOffer.offerId, dealId, msg.sender);
    }

    // slither-disable-end timestamp

    /**
     * @inheritdoc IMarketplace
     */
    function cancelCounterOffer(uint256 dealId) external nonReentrant {
        MarketplaceState storage $ = _marketplaceStorage();
        Deal storage currentDeal = $.deals[dealId];
        Offer storage originalOffer = $.offers[currentDeal.offerId];
        _validateDealOrOfferNotFrozen(dealId, currentDeal.offerId);

        _validateMarketplaceSaleMode(originalOffer, currentDeal.offerId);
        _validateDealStatus(currentDeal.status, DealStatus.PROPOSED);
        _validateCounterOfferNotExpired(currentDeal.counterOfferExpiry);
        _requireEnabledActor(msg.sender, currentDeal.buyer);

        DealStatus oldStatus = currentDeal.status;
        currentDeal.status = DealStatus.CANCELLED;

        _emitDealStatusUpdated(dealId, currentDeal, oldStatus, DealStatus.CANCELLED);
        emit CounterOfferCancelled(dealId, msg.sender);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function resolveCounterOffer(uint256 dealId, bool accepted) external nonReentrant {
        MarketplaceState storage $ = _marketplaceStorage();
        Deal storage currentDeal = $.deals[dealId];
        _validateOfferNotCancelled(currentDeal.offerId);
        _validateDealOrOfferNotFrozen(dealId, currentDeal.offerId);
        Offer storage originalOffer = $.offers[currentDeal.offerId];
        _validateMarketplaceSaleMode(originalOffer, currentDeal.offerId);

        _validateDealStatus(currentDeal.status, DealStatus.PROPOSED);
        _requireEnabledActor(msg.sender, originalOffer.owner);
        _validateCounterOfferNotExpired(currentDeal.counterOfferExpiry);

        if (accepted) {
            _validateOfferNotExpired(originalOffer.expiry);
            _validateEntityWalletEnabled(msg.sender);
            _validateEntityWalletAndTypeAllowed(currentDeal.buyer);
            _validateAmounts(originalOffer, currentDeal.amount);

            DealStatus oldStatus = currentDeal.status;
            currentDeal.status = DealStatus.PENDING;
            currentDeal.dealType = DealType.OFFER;
            Config storage config = $.config;
            uint256 newPaymentDeadline = config.marketplacePaymentExpiryThreshold + block.timestamp;
            currentDeal.paymentDeadline = newPaymentDeadline;
            currentDeal.disputeBuffer = newPaymentDeadline + config.disputeBufferPeriod;
            currentDeal.counterOfferExpiry = 0;

            originalOffer.amounts.available -= currentDeal.amount;
            originalOffer.amounts.inDeals += currentDeal.amount;

            _emitAmountsUpdated(currentDeal.offerId, originalOffer.amounts);
            _emitDealStatusUpdated(dealId, currentDeal, oldStatus, DealStatus.PENDING);
        } else {
            DealStatus oldStatus = currentDeal.status;
            currentDeal.status = DealStatus.DECLINED;
            currentDeal.counterOfferExpiry = 0;

            _emitDealStatusUpdated(dealId, currentDeal, oldStatus, DealStatus.DECLINED);
        }

        emit CounterOfferResolved(
            dealId,
            accepted,
            originalOffer.tokenId,
            currentDeal.amount,
            originalOffer.currency,
            currentDeal.buyer,
            originalOffer.owner
        );
    }

    /**
     * @inheritdoc IMarketplace
     */
    function resolvePayment(uint256 dealId, bool paid) external nonReentrant {
        _resolvePayment(dealId, paid, msg.sender, false);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function resolvePayments(PaymentResolutionInput[] calldata resolutions) external nonReentrant {
        uint256 length = resolutions.length;
        for (uint256 i; i < length; ++i) {
            if (resolutions[i].paid) {
                _checkRoles(PAYMENT_HANDLER);
                break;
            }
        }

        address resolver = msg.sender;
        uint256 succeeded;
        uint256 skipped;

        for (uint256 i; i < length; ++i) {
            PaymentResolutionInput calldata resolution = resolutions[i];

            // External self-call is intentional to isolate per-item failures with try/catch.
            // slither-disable-next-line calls-loop
            try this.resolvePaymentBatchItem(resolution.dealId, resolution.paid, resolver) {
                ++succeeded;
            } catch (bytes memory failureData) {
                ++skipped;

                emit PaymentResolutionSkipped(resolution.dealId, resolution.paid, resolver, failureData);
            }
        }

        emit PaymentResolutionsBatchProcessed(resolver, length, succeeded, skipped);
    }

    /**
     * @notice Resolve one item for `resolvePayments`; callable only by this contract for try/catch isolation
     * @param dealId The ID of the deal to resolve payment for
     * @param paid Whether to resolve as paid or unpaid
     * @param resolver The original batch caller to include in emitted events
     */
    function resolvePaymentBatchItem(uint256 dealId, bool paid, address resolver) external {
        _doAddressesMatch(msg.sender, address(this));
        _resolvePayment(dealId, paid, resolver, true);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function initiateDispute(uint256 dealId) external nonReentrant {
        Deal storage currentDeal = _marketplaceStorage().deals[dealId];

        _requireEnabledActor(msg.sender, currentDeal.buyer);
        _validateDealStatus(currentDeal.status, DealStatus.UNPAID);
        // slither-disable-next-line timestamp
        require(!(block.timestamp > currentDeal.disputeBuffer), Errors.Marketplace__DisputePeriodExpired());

        DealStatus oldStatus = currentDeal.status;
        currentDeal.status = DealStatus.IN_DISPUTE;

        _emitDealStatusUpdated(dealId, currentDeal, oldStatus, DealStatus.IN_DISPUTE);
    }

    // slither-disable-start timestamp
    /**
     * @inheritdoc IMarketplace
     * @param dealId The ID of the deal to resolve
     * @param status The new status for the deal (PAID or UNPAID)
     */
    function resolveDispute(uint256 dealId, DealStatus status) external onlyRoles(ARBITRATOR) nonReentrant {
        Deal storage currentDeal = _marketplaceStorage().deals[dealId];

        require(currentDeal.status == DealStatus.IN_DISPUTE, Errors.Marketplace__DealNotInDispute());
        require(
            status == DealStatus.PAID || status == DealStatus.UNPAID, Errors.Marketplace__InvalidStatus(uint8(status))
        );

        DealStatus oldStatus = currentDeal.status;
        currentDeal.disputeBuffer = 0;
        currentDeal.status = status;

        _emitDealStatusUpdated(dealId, currentDeal, oldStatus, status);
    }

    // slither-disable-end timestamp

    /**
     * @inheritdoc IMarketplace
     */
    function settleDeal(uint256 dealId) external nonReentrant {
        _settleDeal(dealId);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function settleDeals(uint256[] calldata dealIds) external nonReentrant {
        uint256 length = dealIds.length;
        uint256 succeeded;
        uint256 skipped;

        for (uint256 i; i < length; ++i) {
            uint256 dealId = dealIds[i];

            // External self-call is intentional to isolate per-item failures with try/catch.
            // slither-disable-next-line calls-loop
            try this.settleDealBatchItem(dealId) {
                ++succeeded;
            } catch (bytes memory failureData) {
                ++skipped;

                emit DealSettlementSkipped(dealId, msg.sender, failureData);
            }
        }

        emit DealSettlementsBatchProcessed(msg.sender, length, succeeded, skipped);
    }

    /**
     * @notice Settle one item for `settleDeals`; callable only by this contract for try/catch isolation
     * @param dealId The ID of the deal to settle
     */
    function settleDealBatchItem(uint256 dealId) external {
        _doAddressesMatch(msg.sender, address(this));
        _settleDeal(dealId);
    }

    /**
     * @notice Settle one paid or timed-out unpaid deal
     * @param dealId The ID of the deal to settle
     */
    function _settleDeal(uint256 dealId) internal {
        MarketplaceState storage $ = _marketplaceStorage();
        Deal storage currentDeal = $.deals[dealId];
        _validateDealOrOfferNotFrozen(dealId, currentDeal.offerId);

        require(
            currentDeal.status == DealStatus.PAID || currentDeal.status == DealStatus.UNPAID,
            Errors.Marketplace__InvalidStatus(uint8(currentDeal.status))
        );
        if (currentDeal.status == DealStatus.UNPAID) {
            // slither-disable-next-line timestamp
            require(block.timestamp > currentDeal.disputeBuffer, Errors.Marketplace__DisputePeriodNotExpired());
        }

        uint256 amount = currentDeal.amount;
        uint256 offerId = currentDeal.offerId;
        Offer storage currentOffer = $.offers[offerId];
        DealStatus originalStatus = currentDeal.status;
        bool wasPaid = originalStatus == DealStatus.PAID;
        DealStatus terminalStatus = wasPaid ? DealStatus.SUCCESSFUL : DealStatus.UNSUCCESSFUL;
        address buyer = currentDeal.buyer;

        if (wasPaid) {
            require(_isAccountEnabled(buyer), Errors.Marketplace__NotAuthorized(buyer));
        }

        currentDeal.status = terminalStatus;
        currentOffer.amounts.inDeals -= amount;
        if (!wasPaid) {
            currentOffer.amounts.available += amount;
        } else {
            currentOffer.amounts.sold += amount;
            // State is finalized before claiming escrow; reentry is blocked by nonReentrant entrypoints and self-call guards.
            // slither-disable-next-line reentrancy-no-eth,reentrancy-events
            IEscrowManager(_dependenciesStorage().escrowManager).claim($.escrowIdByOfferId[offerId], amount, buyer);
        }

        _emitDealStatusUpdated(dealId, currentDeal, originalStatus, terminalStatus);
        _emitAmountsUpdated(offerId, currentOffer.amounts);
    }

    /*//////////////////////////////////////////////////////////////
                              SEIZURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMarketplace
     */
    function seizeOfferEscrow(uint256 offerId, address beneficiary, bytes32 reason)
        external
        onlyRoles(SEIZURE_ROLE)
        nonReentrant
    {
        _validateOfferExists(offerId);
        MarketplaceState storage $ = _marketplaceStorage();
        require($.offerFrozen[offerId], Errors.Marketplace__OfferNotFrozen(offerId));
        require(beneficiary != address(0), Errors.ZeroAddress());
        require(reason != bytes32(0), Errors.Marketplace__ZeroReason());
        _validateEntityWalletEnabled(beneficiary);

        Offer storage offer = $.offers[offerId];
        uint256 seizeAmount = offer.amounts.available;

        // For INTEREST_DISCOVERY offers, also seize the reserved interest bucket in O(1)
        if (offer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            InterestDiscoveryState storage state = $.interestDiscoveryStateByOfferId[offerId];
            uint256 reserved = state.reservedInterestUnits;
            if (reserved != 0) {
                state.reservedInterestUnits = 0;
                $.reservedInterestSeized[offerId] = true;
                seizeAmount += reserved;
            }
        }

        require(seizeAmount != 0, Errors.Marketplace__NoAvailableAmount(offerId));

        offer.amounts.available = 0;
        $.offerCancelled[offerId] = true;
        offer.expiry = block.timestamp;

        IEscrowManager(_dependenciesStorage().escrowManager)
            .claim($.escrowIdByOfferId[offerId], seizeAmount, beneficiary);

        emit OfferCancelled(offerId, msg.sender);
        emit AmountsUpdated(offerId, 0, offer.amounts.inDeals, offer.amounts.sold);
        emit OfferEscrowSeized(offerId, beneficiary, seizeAmount, reason, msg.sender);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function seizeDeal(uint256 dealId, address beneficiary, bytes32 reason)
        external
        onlyRoles(SEIZURE_ROLE)
        nonReentrant
    {
        _validateDealExists(dealId);
        MarketplaceState storage $ = _marketplaceStorage();
        require($.dealFrozen[dealId], Errors.Marketplace__DealNotFrozen(dealId));

        Deal storage deal = $.deals[dealId];
        uint256 offerId = deal.offerId;
        require($.offerFrozen[offerId], Errors.Marketplace__OfferNotFrozen(offerId));
        require(beneficiary != address(0), Errors.ZeroAddress());
        require(reason != bytes32(0), Errors.Marketplace__ZeroReason());
        _validateEntityWalletEnabled(beneficiary);

        DealStatus status = deal.status;
        require(
            status == DealStatus.PENDING || status == DealStatus.UNPAID || status == DealStatus.IN_DISPUTE
                || status == DealStatus.PAID,
            Errors.Marketplace__InvalidStatus(uint8(status))
        );

        uint256 amount = deal.amount;
        Offer storage offer = $.offers[offerId];

        // Effects before external call (checks-effects-interactions)
        deal.status = DealStatus.SEIZED;
        offer.amounts.inDeals -= amount;

        IEscrowManager(_dependenciesStorage().escrowManager).claim($.escrowIdByOfferId[offerId], amount, beneficiary);

        _emitDealStatusUpdated(dealId, deal, status, DealStatus.SEIZED);
        emit AmountsUpdated(offerId, offer.amounts.available, offer.amounts.inDeals, offer.amounts.sold);
        emit DealSeized(dealId, offerId, beneficiary, amount, reason, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            FREEZE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMarketplace
     */
    function setOfferFrozen(uint256 offerId, bool frozen) external onlyRoles(FREEZE_ROLE) {
        _validateOfferExists(offerId);
        _marketplaceStorage().offerFrozen[offerId] = frozen;
        emit OfferFrozenSet(offerId, frozen);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function setDealFrozen(uint256 dealId, bool frozen) external onlyRoles(FREEZE_ROLE) {
        _validateDealExists(dealId);
        _marketplaceStorage().dealFrozen[dealId] = frozen;
        emit DealFrozenSet(dealId, frozen);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IMarketplaceLensSource
     */
    function getOfferData(uint256 offerId)
        external
        view
        returns (
            Offer memory offer,
            InterestDiscoveryState memory state,
            uint256[] memory interestIds,
            address[] memory allowedBuyers,
            uint256 escrowId
        )
    {
        MarketplaceState storage $ = _marketplaceStorage();
        return (
            $.offers[offerId],
            $.interestDiscoveryStateByOfferId[offerId],
            $.interestIdsByOfferId[offerId],
            $.allowedBuyersByOfferId[offerId],
            $.escrowIdByOfferId[offerId]
        );
    }

    /**
     * @inheritdoc IMarketplaceLensSource
     */
    function getOfferFlags(uint256 offerId)
        external
        view
        returns (bool cancelled, bool frozen, bool reservedInterestSeized)
    {
        MarketplaceState storage $ = _marketplaceStorage();
        return ($.offerCancelled[offerId], $.offerFrozen[offerId], $.reservedInterestSeized[offerId]);
    }

    /**
     * @inheritdoc IMarketplaceLensSource
     */
    function getDealData(uint256 dealId) external view returns (Deal memory deal, bool frozen) {
        MarketplaceState storage $ = _marketplaceStorage();
        return ($.deals[dealId], $.dealFrozen[dealId]);
    }

    /**
     * @inheritdoc IMarketplaceLensSource
     */
    function getInterestData(uint256 interestId) external view returns (Interest memory interest) {
        return _getInterest(interestId);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param owner_ Owner of the contract
     * @param offerExpiryThreshold Minimum offer lifetime in seconds
     * @param maxOfferLifetime Maximum offer lifetime in seconds
     * @param marketplacePaymentExpiryThreshold Payment expiry threshold for marketplace deals in seconds
     * @param redemptionPaymentExpiryThreshold Payment expiry threshold for redemption deals in seconds
     * @param interestDiscoveryPaymentExpiryThreshold Threshold snapshotted into new interest-discovery offers
     * @param disputeBufferPeriod Dispute buffer period in seconds
     * @param assetManager_ Address of valid asset manager
     * @param escrowManager Address of valid Escrow Manager
     * @param entityRegistry_ Address of valid Entity Registry
     * @param maxCounterOffers Maximum number of counter offers per user per offer
     */
    function __Marketplace_init( // solhint-disable-line func-name-mixedcase
        address owner_,
        uint256 offerExpiryThreshold,
        uint256 maxOfferLifetime,
        uint256 marketplacePaymentExpiryThreshold,
        uint256 redemptionPaymentExpiryThreshold,
        uint256 interestDiscoveryPaymentExpiryThreshold,
        uint256 disputeBufferPeriod,
        address assetManager_,
        address escrowManager,
        address entityRegistry_,
        uint256 maxCounterOffers
    ) internal {
        __MarketplaceBase_init(
            owner_,
            offerExpiryThreshold,
            maxOfferLifetime,
            marketplacePaymentExpiryThreshold,
            redemptionPaymentExpiryThreshold,
            interestDiscoveryPaymentExpiryThreshold,
            disputeBufferPeriod,
            assetManager_,
            escrowManager,
            entityRegistry_,
            maxCounterOffers
        );
    }

    /**
     * @notice Resolve one deal payment status and emit the canonical payment events
     * @param dealId The ID of the deal to resolve payment for
     * @param paid Whether to resolve as paid or unpaid
     * @param resolver Account to report as resolver in emitted events
     * @param paymentHandlerChecked Whether the caller already checked PAYMENT_HANDLER for paid resolutions
     */
    function _resolvePayment(uint256 dealId, bool paid, address resolver, bool paymentHandlerChecked) internal {
        Deal storage currentDeal = _marketplaceStorage().deals[dealId];

        DealStatus newStatus;
        if (paid) {
            if (!paymentHandlerChecked) {
                _checkRoles(PAYMENT_HANDLER);
            }
            require(
                currentDeal.status == DealStatus.PENDING || currentDeal.status == DealStatus.UNPAID,
                Errors.Marketplace__InvalidStatus(uint8(currentDeal.status))
            );
            if (currentDeal.status == DealStatus.UNPAID) {
                require(currentDeal.disputeBuffer != 0, Errors.Marketplace__DealAlreadyArbitrated());
            }
            // slither-disable-next-line timestamp
            if (block.timestamp > currentDeal.paymentDeadline && currentDeal.status == DealStatus.PENDING) {
                revert Errors.Marketplace__PaymentDeadlineExpired();
            }
            newStatus = DealStatus.PAID;
        } else {
            _validateDealStatus(currentDeal.status, DealStatus.PENDING);
            // slither-disable-next-line timestamp
            require(block.timestamp > currentDeal.paymentDeadline, Errors.Marketplace__DealNotExpired());
            newStatus = DealStatus.UNPAID;
        }

        DealStatus oldStatus = currentDeal.status;
        currentDeal.status = newStatus;

        _emitDealStatusUpdated(dealId, currentDeal, oldStatus, newStatus);
        emit PaymentResolved(dealId, paid, resolver);
    }

    // Offer cancellation intentionally relies on expiry windows; timestamp drift is not meaningful at this granularity.
    // slither-disable-start timestamp
    /**
     * @notice Validate cancellation rules and return the amount to withdraw during cancellation
     * @param offerId Offer identifier
     * @param offer Offer storage pointer
     * @return withdrawAmount Amount to withdraw from escrow while cancelling
     */
    function _prepareOfferCancellation(uint256 offerId, Offer storage offer) internal returns (uint256 withdrawAmount) {
        uint8 saleModeRaw = uint8(offer.saleMode);
        _validateSaleMode(saleModeRaw);

        if (offer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            return _prepareFailedInterestDiscoveryCancellation(offerId, offer);
        }

        return _prepareDirectOfferCancellation(offerId, offer);
    }

    /**
     * @notice Validate direct-offer cancellation rules and return the amount to withdraw
     * @param offerId Offer identifier
     * @param offer Offer storage pointer
     * @return withdrawAmount Amount to withdraw from escrow while cancelling
     */
    function _prepareDirectOfferCancellation(uint256 offerId, Offer storage offer)
        internal
        view
        returns (uint256 withdrawAmount)
    {
        withdrawAmount = offer.amounts.available;
        require(withdrawAmount != 0 || offer.amounts.inDeals != 0, Errors.Marketplace__NoAvailableAmount(offerId));
    }

    /**
     * @notice Validate failed interest-discovery cancellation rules and release reserved interest inventory
     * @param offerId Offer identifier
     * @param offer Offer storage pointer
     * @return withdrawAmount Amount to withdraw from escrow while cancelling
     */
    function _prepareFailedInterestDiscoveryCancellation(uint256 offerId, Offer storage offer)
        internal
        returns (uint256 withdrawAmount)
    {
        // slither-disable-next-line timestamp
        require(block.timestamp > offer.expiry, Errors.Marketplace__OfferNotExpired(offer.expiry, block.timestamp));

        InterestDiscoveryState storage state = _marketplaceStorage().interestDiscoveryStateByOfferId[offerId];
        require(
            !_hasReachedThreshold(state.interestedUnits, state.minSaleUnits),
            Errors.Marketplace__ThresholdAlreadyReached(offerId, state.interestedUnits, state.minSaleUnits)
        );

        withdrawAmount = offer.amounts.available + state.reservedInterestUnits;
        state.reservedInterestUnits = 0;
    }

    // slither-disable-end timestamp

    /**
     * @notice Cancel an offer, withdraw escrowed inventory if any, and emit canonical cancellation events
     * @param offerId Offer identifier
     * @param offer Offer storage pointer
     * @param withdrawAmount Amount to withdraw from escrow
     */
    function _cancelOfferAndWithdraw(uint256 offerId, Offer storage offer, uint256 withdrawAmount) internal {
        MarketplaceState storage $ = _marketplaceStorage();
        $.offerCancelled[offerId] = true;
        offer.expiry = block.timestamp;
        offer.amounts.available = 0;

        if (withdrawAmount != 0) {
            IEscrowManager(_dependenciesStorage().escrowManager).withdraw($.escrowIdByOfferId[offerId], withdrawAmount);
        }

        emit OfferCancelled(offerId, msg.sender);
        _emitAmountsUpdated(offerId, offer.amounts);
    }

    /**
     * @notice Create and store a deal for a direct marketplace offer acceptance
     * @param offer Offer this deal is bound to
     * @param offerId ID of the accepted offer
     * @param amount Amount of units
     * @return dealId ID of the created deal
     */
    function _createOfferDeal(Offer storage offer, uint256 offerId, uint256 amount) internal returns (uint256 dealId) {
        uint256 paymentDeadline = _getPaymentExpiryThreshold(offer.saleMode) + block.timestamp;
        DealCreationInput memory input = DealCreationInput({
            offerId: offerId,
            amount: amount,
            buyer: msg.sender,
            price: offer.unitPrice * amount,
            counterOfferExpiry: 0,
            paymentDeadline: paymentDeadline,
            status: DealStatus.PENDING,
            dealType: DealType.OFFER
        });
        return _createDeal(input);
    }

    /**
     * @notice Create and store a deal from an activated expressed interest
     * @param interest Interest being activated
     * @param interestId Interest identifier
     * @param saleEnd End of the interest-collection period
     * @return dealId ID of the created deal
     */
    function _createActivatedInterestDeal(Interest storage interest, uint256 interestId, uint256 saleEnd)
        internal
        returns (uint256 dealId)
    {
        uint256 paymentDeadline = _getActivatedInterestPaymentDeadline(interest.offerId, saleEnd);
        DealCreationInput memory input = DealCreationInput({
            offerId: interest.offerId,
            amount: interest.amount,
            buyer: interest.investor,
            price: interest.price,
            counterOfferExpiry: 0,
            paymentDeadline: paymentDeadline,
            status: DealStatus.PENDING,
            dealType: DealType.OFFER
        });
        dealId = _createDeal(input);
        InterestStatus oldStatus = interest.status;
        interest.status = InterestStatus.ACTIVATED;

        _emitInterestStatusUpdated(interestId, interest, oldStatus, InterestStatus.ACTIVATED);
    }

    /**
     * @notice Create and store a deal for a counter-offer proposal
     * @param offerId ID of the original offer being countered
     * @param amount Amount of units
     * @param unitPrice Unit price proposed in the counter offer
     * @param counterOfferExpiry Expiry timestamp for the counter offer
     * @return dealId ID of the created deal
     */
    function _createCounterOfferDeal(uint256 offerId, uint256 amount, uint256 unitPrice, uint256 counterOfferExpiry)
        internal
        returns (uint256 dealId)
    {
        DealCreationInput memory input = DealCreationInput({
            offerId: offerId,
            amount: amount,
            buyer: msg.sender,
            price: unitPrice * amount,
            counterOfferExpiry: counterOfferExpiry,
            paymentDeadline: 0,
            status: DealStatus.PROPOSED,
            dealType: DealType.COUNTER_OFFER
        });
        return _createDeal(input);
    }

    /**
     * @notice Create and store a generic deal and emit the shared creation event
     * @param input Generic deal creation payload
     * @return dealId ID of the created deal
     */
    // slither-disable-start timestamp
    function _createDeal(DealCreationInput memory input) internal returns (uint256 dealId) {
        MarketplaceState storage $ = _marketplaceStorage();
        Counters storage counters = $.counters;
        Config storage config = $.config;
        dealId = ++counters.dealCounter;
        uint256 hasPaymentDeadline = input.paymentDeadline > 0 ? 1 : 0;
        uint256 disputeDeadline = hasPaymentDeadline * (input.paymentDeadline + config.disputeBufferPeriod);

        $.deals[dealId] = Deal({
            offerId: input.offerId,
            amount: input.amount,
            buyer: input.buyer,
            price: input.price,
            counterOfferExpiry: input.counterOfferExpiry,
            paymentDeadline: input.paymentDeadline,
            disputeBuffer: disputeDeadline,
            status: input.status,
            dealType: input.dealType
        });

        _emitDealCreated(input, dealId, disputeDeadline);
    }

    // slither-disable-end timestamp

    /**
     * @notice Emit compact deal creation events.
     * @param input Deal creation payload
     * @param dealId Assigned deal identifier
     * @param disputeDeadline Deadline after which a paid deal leaves the dispute buffer
     */
    function _emitDealCreated(DealCreationInput memory input, uint256 dealId, uint256 disputeDeadline) internal {
        emit DealCreated(input.offerId, dealId, input.buyer, input.dealType, input.amount, input.price);
        emit DealTermsRegistered(dealId, input.paymentDeadline, input.counterOfferExpiry, disputeDeadline);
    }

    /**
     * @notice Return the payment expiry threshold for an offer sale mode
     * @param saleMode Offer sale mode
     * @return paymentExpiryThreshold The threshold to add to the current timestamp
     */
    function _getPaymentExpiryThreshold(SaleMode saleMode) internal view returns (uint256 paymentExpiryThreshold) {
        Config storage config = _marketplaceStorage().config;
        if (saleMode == SaleMode.REDEMPTION) {
            return config.redemptionPaymentExpiryThreshold;
        }
        if (saleMode == SaleMode.MARKETPLACE) {
            return config.marketplacePaymentExpiryThreshold;
        }
        revert Errors.Marketplace__InvalidSaleMode(uint8(saleMode));
    }

    /**
     * @notice Emit the canonical offer registration snapshot.
     * @param offerId Offer identifier
     * @param offer Validated offer data
     * @param minSaleUnits Minimum sale units for interest-discovery offers; zero for direct-sale offers
     */
    function _emitOfferRegistered(uint256 offerId, Offer memory offer, uint256 minSaleUnits) private {
        emit OfferRegistered(offerId, offer.owner, offer.tokenAddress, offer.tokenId, offer.assetType, offer.saleMode);
        emit OfferTermsRegistered(
            offerId,
            offer.amounts.total,
            offer.lot,
            offer.unitPrice,
            offer.currency,
            offer.expiry,
            offer.allowCounterOffers
        );
        if (offer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            emit InterestDiscoveryConfigured(offerId, minSaleUnits);
        }
    }

    /**
     * @notice Emit the canonical offer amount snapshot
     * @param offerId Offer identifier
     * @param amounts Offer amount snapshot
     */
    function _emitAmountsUpdated(uint256 offerId, Amounts memory amounts) internal {
        emit AmountsUpdated(offerId, amounts.available, amounts.inDeals, amounts.sold);
    }

    /**
     * @notice Emit the canonical deal status transition snapshot.
     * @param dealId Deal identifier
     * @param deal Deal snapshot after the status update
     * @param oldStatus Previous status
     * @param newStatus New status
     */
    function _emitDealStatusUpdated(uint256 dealId, Deal storage deal, DealStatus oldStatus, DealStatus newStatus)
        internal
    {
        emit DealStatusUpdated(dealId, deal.offerId, uint8(newStatus), uint8(oldStatus));
    }

    /**
     * @notice Emit the canonical expressed-interest status transition snapshot.
     * @param interestId Interest identifier
     * @param interest Interest snapshot after the status update
     * @param oldStatus Previous status
     * @param newStatus New status
     */
    function _emitInterestStatusUpdated(
        uint256 interestId,
        Interest storage interest,
        InterestStatus oldStatus,
        InterestStatus newStatus
    ) internal {
        emit InterestStatusUpdated(interestId, interest.offerId, uint8(newStatus), uint8(oldStatus));
    }

    /**
     * @notice Return the last timestamp when an expressed interest may still be activated into a deal
     * @param offerId Offer identifier
     * @param saleEnd End of the interest-collection period
     * @return activationDeadline End of the activation period
     * @dev Reverts if saleEnd + the offer's snapshotted payment expiry threshold cannot be computed safely.
     */
    function _getInterestActivationDeadline(uint256 offerId, uint256 saleEnd)
        internal
        view
        returns (uint256 activationDeadline)
    {
        uint256 paymentExpiryThreshold = _getInterestDiscoveryPaymentExpiryThreshold(offerId);
        require(
            !(saleEnd > type(uint256).max - paymentExpiryThreshold),
            Errors.Marketplace__InterestActivationDeadlineOverflow(offerId, saleEnd, paymentExpiryThreshold)
        );

        return saleEnd + paymentExpiryThreshold;
    }

    /**
     * @notice Return the payment deadline for a deal created from an activated expressed interest
     * @param offerId Offer identifier
     * @param saleEnd End of the interest-collection period
     * @return paymentDeadline Payment deadline for the activated interest deal
     */
    function _getActivatedInterestPaymentDeadline(uint256 offerId, uint256 saleEnd)
        internal
        view
        returns (uint256 paymentDeadline)
    {
        uint256 paymentExpiryThreshold = _getInterestDiscoveryPaymentExpiryThreshold(offerId);
        // slither-disable-next-line timestamp
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp > saleEnd) {
            return currentTimestamp + paymentExpiryThreshold;
        }
        return saleEnd + paymentExpiryThreshold;
    }

    /**
     * @notice Return the payment expiry threshold snapshotted for an interest-discovery offer
     * @param offerId Offer identifier
     * @return paymentExpiryThreshold Per-offer activation and payment deadline offset
     */
    function _getInterestDiscoveryPaymentExpiryThreshold(uint256 offerId)
        internal
        view
        returns (uint256 paymentExpiryThreshold)
    {
        return _marketplaceStorage().interestDiscoveryStateByOfferId[offerId].paymentExpiryThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                          VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate that an offer exists (has a non-zero escrow link)
     * @param offerId Offer identifier
     * @dev Reverts if the offer was never registered
     */
    function _validateOfferExists(uint256 offerId) internal view {
        require(_marketplaceStorage().escrowIdByOfferId[offerId] != 0, Errors.Marketplace__OfferDoesNotExist(offerId));
    }

    /**
     * @notice Validate that a deal exists (status is not NON_EXISTING)
     * @param dealId Deal identifier
     * @dev Reverts if the deal was never created
     */
    // slither-disable-start timestamp
    function _validateDealExists(uint256 dealId) internal view {
        require(
            _marketplaceStorage().deals[dealId].status != DealStatus.NON_EXISTING,
            Errors.Marketplace__DealDoesNotExist(dealId)
        );
    }

    // slither-disable-end timestamp

    /**
     * @notice Validate that an offer is not frozen
     * @param offerId Offer identifier
     * @dev Reverts if the offer is frozen
     */
    function _validateOfferNotFrozen(uint256 offerId) internal view {
        require(!_marketplaceStorage().offerFrozen[offerId], Errors.Marketplace__OfferFrozen(offerId));
    }

    /**
     * @notice Validate that neither the deal nor its parent offer is frozen
     * @param dealId Deal identifier
     * @param offerId Parent offer identifier
     * @dev Reverts if the deal or parent offer is frozen
     */
    function _validateDealOrOfferNotFrozen(uint256 dealId, uint256 offerId) internal view {
        MarketplaceState storage $ = _marketplaceStorage();
        require(!$.dealFrozen[dealId], Errors.Marketplace__DealFrozen(dealId));
        require(!$.offerFrozen[offerId], Errors.Marketplace__OfferFrozen(offerId));
    }

    /**
     * @notice Validate that an offer has not been cancelled
     * @param offerId Offer identifier
     * @dev Reverts if the offer has already been cancelled
     */
    function _validateOfferNotCancelled(uint256 offerId) internal view {
        require(!_marketplaceStorage().offerCancelled[offerId], Errors.Marketplace__OfferAlreadyCancelled(offerId));
    }

    /**
     * @notice Validate that an offer has already been cancelled
     * @param offerId Offer identifier
     * @dev Reverts if the offer is not cancelled
     */
    function _validateOfferCancelled(uint256 offerId) internal view {
        require(_marketplaceStorage().offerCancelled[offerId], Errors.Marketplace__OfferNotCancelled(offerId));
    }

    /**
     * @notice Validate offer input and build the persisted offer struct
     * @param offer Offer input to validate
     * @param owner_ Owner of the offer to be validated
     * @return validatedOffer The validated offer
     */
    function _validateOffer(OfferInput calldata offer, address owner_)
        internal
        view
        returns (Offer memory validatedOffer)
    {
        _validateEntityWalletAndTypeAllowed(owner_);
        _validateSaleMode(uint8(offer.saleMode));

        AssetType assetType = _validateAsset(offer);
        _validateDepositAmounts(offer.totalAmount, offer.lot);

        if (offer.saleMode != SaleMode.MARKETPLACE) {
            require(!offer.allowCounterOffers, Errors.Marketplace__CounterOffersMustBeDisabled());
        }

        if (offer.saleMode == SaleMode.INTEREST_DISCOVERY) {
            require(offer.allowedBuyers.length == 0, Errors.Marketplace__AllowedBuyersNotAllowed());
            _validateMinSaleUnits(offer.minSaleUnits, offer.totalAmount, offer.lot);
        } else {
            require(offer.minSaleUnits == 0, Errors.Marketplace__MinSaleUnitsNotAllowed(offer.minSaleUnits));
            if (offer.saleMode == SaleMode.REDEMPTION) {
                require(offer.allowedBuyers.length != 0, Errors.Marketplace__AllowedBuyersRequired());
            }
        }

        _validatePrice(offer.unitPrice, offer.currency);
        _validateOfferExpiryThreshold(offer.expiry);

        validatedOffer = Offer({
            currency: offer.currency,
            allowCounterOffers: offer.allowCounterOffers,
            saleMode: offer.saleMode,
            assetType: assetType,
            owner: owner_,
            tokenAddress: offer.tokenAddress,
            tokenId: offer.tokenId,
            lot: offer.lot,
            unitPrice: offer.unitPrice,
            expiry: offer.expiry,
            amounts: Amounts({total: offer.totalAmount, available: offer.totalAmount, inDeals: 0, sold: 0})
        });
    }

    /**
     * @notice Validate that an offer is not expired
     * @param offerExpiry Expiry timestamp of the offer
     * @dev Reverts if the offer has expired
     */
    function _validateOfferNotExpired(uint256 offerExpiry) internal view {
        // slither-disable-next-line timestamp
        require(!(block.timestamp > offerExpiry), Errors.Marketplace__OfferExpired(offerExpiry, block.timestamp));
    }

    /**
     * @notice Validate that a counter offer is not expired
     * @param counterOfferExpiry Expiry timestamp of the counter offer
     * @dev Reverts if the counter offer has expired
     */
    function _validateCounterOfferNotExpired(uint256 counterOfferExpiry) internal view {
        // slither-disable-next-line timestamp
        require(
            !(block.timestamp > counterOfferExpiry),
            Errors.Marketplace__CounterOfferExpired(counterOfferExpiry, block.timestamp)
        );
    }

    /**
     * @notice Validate that offer expiry falls within the configured lifetime bounds
     * @param offerExpiry Expiry timestamp of the offer
     */
    function _validateOfferExpiryThreshold(uint256 offerExpiry) internal view {
        Config storage config = _marketplaceStorage().config;
        // slither-disable-next-line timestamp
        require(!(offerExpiry < block.timestamp), Errors.Marketplace__InvalidExpiry(offerExpiry, block.timestamp));
        uint256 offerLifetime = offerExpiry - block.timestamp;
        require(
            !(offerLifetime < config.offerExpiryThreshold),
            Errors.Marketplace__InvalidExpiry(offerExpiry, block.timestamp)
        );
        require(
            !(offerLifetime > config.maxOfferLifetime),
            Errors.Marketplace__ExpiryTooFar(offerExpiry, block.timestamp, config.maxOfferLifetime)
        );
    }

    /**
     * @notice Validate price and currency
     * @param price Price to validate
     * @param currency Currency to validate
     */
    function _validatePrice(uint256 price, bytes3 currency) internal view {
        _validateNonZeroPrice(price);
        require(_marketplaceStorage().allowedCurrencies[currency], Errors.Marketplace__InvalidCurrency(currency));
    }

    /**
     * @notice Validate that a unit price is non-zero
     * @param price Price to validate
     */
    function _validateNonZeroPrice(uint256 price) internal pure {
        require(price != 0, Errors.Marketplace__ZeroPrice());
    }

    /**
     * @notice Validate asset support and transfer shape
     * @param offer The offer input that contains token metadata and transfer constraints
     * @return assetType Resolved asset type from the asset manager
     */
    function _validateAsset(OfferInput calldata offer) internal view returns (AssetType assetType) {
        address assetManager = _marketplaceStorage().assetManager;
        require(assetManager != address(0), Errors.Marketplace__AssetManagerNotSet());
        assetType = IAssetManager(assetManager).validateAsset(offer.tokenAddress, offer.tokenId, offer.totalAmount);
    }

    /**
     * @notice Validate that the caller is either the offer owner (enabled) or holds INTEREST_DISCOVERY_OPERATOR
     * @param caller Address of the caller
     * @param owner_ Offer owner
     */
    function _validateOwnerOrOperator(address caller, address owner_) internal view {
        if (caller == owner_) {
            require(_isAccountEnabled(owner_), Errors.Marketplace__NotAuthorized(caller));
        } else {
            _checkRoles(INTEREST_DISCOVERY_OPERATOR);
        }
    }

    /**
     * @notice Validate that the caller is authorized for owner-scoped operations and the owner can receive escrow
     * @param caller Address of the caller
     * @param owner_ Offer owner and escrow withdrawal recipient
     */
    function _validateOwnerOrOperatorWithEnabledOwner(address caller, address owner_) internal view {
        _validateOwnerOrOperator(caller, owner_);
        require(_isAccountEnabled(owner_), Errors.Marketplace__NotAuthorized(caller));
    }

    /**
     * @notice Validate that the activation deadline for an expressed interest has not passed
     * @param offerId Offer identifier
     * @param saleEnd End of the interest-collection period
     */
    function _validateInterestActivationWindow(uint256 offerId, uint256 saleEnd) internal view {
        uint256 activationDeadline = _getInterestActivationDeadline(offerId, saleEnd);
        // slither-disable-next-line timestamp
        require(
            block.timestamp < activationDeadline + 1,
            Errors.Marketplace__InterestActivationWindowExpired(offerId, activationDeadline, block.timestamp)
        );
    }

    /**
     * @notice Load and validate that an interest exists
     * @param interestId Interest identifier
     * @return interest Interest storage pointer
     */
    function _getInterest(uint256 interestId) internal view returns (Interest storage interest) {
        interest = _marketplaceStorage().interests[interestId];
        if (interest.status == InterestStatus.NON_EXISTING) {
            revert Errors.Marketplace__InterestNotFound(interestId);
        }
    }

    /**
     * @notice Validate amounts for an offer
     * @param offer The offer to validate amounts for
     * @param amount The amount to validate
     */
    // slither-disable-start timestamp
    function _validateAmounts(Offer storage offer, uint256 amount) internal view {
        require(amount != 0, Errors.Marketplace__ZeroAmount());
        require(
            !(amount > offer.amounts.available),
            Errors.Marketplace__InsufficientAvailableAmount(amount, offer.amounts.available)
        );
        require(amount % offer.lot == 0, Errors.Marketplace__AmountNotMultipleOfLot(offer.lot, amount));
    }

    // slither-disable-end timestamp

    /**
     * @notice Return whether cumulative expressed interest has reached the configured threshold
     * @param interestedUnits Cumulative expressed-interest amount
     * @param minSaleUnits Configured minimum threshold
     * @return reached True when `interestedUnits >= minSaleUnits`
     */
    function _hasReachedThreshold(uint256 interestedUnits, uint256 minSaleUnits) internal pure returns (bool reached) {
        return minSaleUnits - 1 < interestedUnits;
    }

    /**
     * @notice Validate that a sale mode is one of the supported enum values
     * @param saleModeRaw Raw sale mode value to validate
     */
    function _validateSaleMode(uint8 saleModeRaw) internal pure {
        require(saleModeRaw < 3, Errors.Marketplace__InvalidSaleMode(saleModeRaw));
    }

    /**
     * @notice Validate minimum threshold settings for an interest-discovery offer
     * @param minSaleUnits Minimum threshold to validate
     * @param totalAmount Total amount offered
     * @param lot Lot size for the offer
     */
    function _validateMinSaleUnits(uint256 minSaleUnits, uint256 totalAmount, uint256 lot) internal pure {
        require(minSaleUnits > 0, Errors.Marketplace__InvalidMinSaleUnits(minSaleUnits, totalAmount, lot));
        require(
            minSaleUnits - 1 < totalAmount && minSaleUnits % lot == 0,
            Errors.Marketplace__InvalidMinSaleUnits(minSaleUnits, totalAmount, lot)
        );
    }

    /**
     * @notice Validate that cumulative expressed interest has reached the configured threshold
     * @param offerId Offer identifier
     * @param interestedUnits Cumulative expressed-interest amount
     * @param minSaleUnits Configured minimum threshold
     */
    function _validateThresholdReached(uint256 offerId, uint256 interestedUnits, uint256 minSaleUnits) internal pure {
        require(
            _hasReachedThreshold(interestedUnits, minSaleUnits),
            Errors.Marketplace__ThresholdNotReached(offerId, interestedUnits, minSaleUnits)
        );
    }

    /**
     * @notice Validate that the sender is not the owner of the offer
     * @param sender Address of the sender
     * @param owner_ Address of the owner
     */
    function _validateNotOwner(address sender, address owner_) internal pure {
        require(sender != owner_, Errors.Marketplace__SenderIsOwner());
    }

    /**
     * @notice Validate that the caller is the expected address
     * @param caller Address of the caller
     * @param owner_ Expected owner address
     */
    function _doAddressesMatch(address caller, address owner_) internal pure {
        require(caller == owner_, Errors.Marketplace__NotAuthorized(caller));
    }

    /**
     * @notice Validate that the caller is the expected actor and that actor is currently enabled in EntityRegistry.
     * @dev Actor-identity authorization is only valid while the actor account is enabled.
     *      Use this check on any path where authority comes from a stored business-actor identity.
     * @param caller Address of the caller
     * @param actor Expected actor address
     */
    function _requireEnabledActor(address caller, address actor) internal view {
        _doAddressesMatch(caller, actor);
        require(_isAccountEnabled(actor), Errors.Marketplace__NotAuthorized(caller));
    }

    /**
     * @notice Return whether an actor is enabled in the configured EntityRegistry.
     * @dev Marketplace initialization wires EntityRegistry; the zero-address branch is retained defensively.
     * @param actor Actor address to check
     * @return enabled True when registry reports the actor as enabled
     */
    function _isAccountEnabled(address actor) internal view returns (bool enabled) {
        address entityRegistry = _dependenciesStorage().entityRegistry;
        return entityRegistry == address(0) || IEntityRegistry(entityRegistry).isAccountEnabled(actor);
    }

    /**
     * @notice Validate a deal status
     * @param actual Actual status of the deal
     * @param desired Desired status of the deal
     */
    function _validateDealStatus(DealStatus actual, DealStatus desired) internal pure {
        if (actual != desired) {
            revert Errors.Marketplace__InvalidStatus(uint8(actual));
        }
    }

    /**
     * @notice Validate deposit amounts
     * @param total Total amount to validate
     * @param lot Lot size to validate
     */
    function _validateDepositAmounts(uint256 total, uint256 lot) internal pure {
        require(total != 0 && lot != 0, Errors.Marketplace__ZeroAmount());
        require(!(total < lot), Errors.Marketplace__LotSizeTooLarge());
        require(total % lot == 0, Errors.Marketplace__TotalAmountNotMultipleOfLot());
    }

    /**
     * @notice Validate an interest lifecycle status
     * @param interestId Interest identifier
     * @param actual Actual status
     * @param desired Desired status
     */
    function _validateInterestStatus(uint256 interestId, InterestStatus actual, InterestStatus desired) internal pure {
        if (actual != desired) {
            revert Errors.Marketplace__InvalidInterestStatus(interestId, uint8(actual));
        }
    }

    /**
     * @notice Returns whether the sale mode follows the direct-deal family
     * @param saleMode Sale mode to inspect
     * @return direct True for MARKETPLACE and REDEMPTION
     */
    function _isDirectSaleMode(SaleMode saleMode) internal pure returns (bool direct) {
        return saleMode == SaleMode.MARKETPLACE || saleMode == SaleMode.REDEMPTION;
    }

    /**
     * @notice Validates that the offer can use the direct-deal function family
     * @param offer Offer to validate
     * @param offerId Offer identifier
     */
    // solhint-disable-next-line ordering
    function _validateDirectSaleMode(Offer storage offer, uint256 offerId) internal view {
        if (!_isDirectSaleMode(offer.saleMode)) {
            revert Errors.Marketplace__NotMarketplaceOffer(offerId);
        }
    }

    /**
     * @notice Validates that the offer can use marketplace-only function family
     * @param offer Offer to validate
     * @param offerId Offer identifier
     */
    // solhint-disable-next-line ordering
    function _validateMarketplaceSaleMode(Offer storage offer, uint256 offerId) internal view {
        if (offer.saleMode != SaleMode.MARKETPLACE) {
            revert Errors.Marketplace__NotMarketplaceOffer(offerId);
        }
    }

    /**
     * @notice Validates that the offer uses the interest-discovery function family
     * @param offer Offer to validate
     * @param offerId Offer identifier
     */
    // solhint-disable-next-line ordering
    function _validateInterestDiscoverySaleMode(Offer storage offer, uint256 offerId) internal view {
        if (offer.saleMode != SaleMode.INTEREST_DISCOVERY) {
            revert Errors.Marketplace__NotInterestDiscoveryOffer(offerId);
        }
    }

    /**
     * @notice Stores and validates the direct-sale allowlist for one offer
     * @param offerId Offer identifier
     * @param allowedBuyers Allowlisted buyers from input
     */
    function _storeAllowedBuyers(uint256 offerId, address[] calldata allowedBuyers) internal {
        MarketplaceState storage $ = _marketplaceStorage();
        for (uint256 i; i < allowedBuyers.length; ++i) {
            address buyer = allowedBuyers[i];
            require(buyer != address(0), Errors.ZeroAddress());
            require(!$.isAllowedBuyerByOfferId[offerId][buyer], Errors.Marketplace__DuplicateAllowedBuyer(buyer));

            $.isAllowedBuyerByOfferId[offerId][buyer] = true;
            $.allowedBuyersByOfferId[offerId].push(buyer);
        }
    }

    /**
     * @notice Validates whether a buyer may directly accept an offer
     * @param offer Offer being accepted
     * @param offerId Offer identifier
     * @param buyer Buyer attempting acceptance
     */
    // solhint-disable-next-line ordering
    function _validateBuyerAllowed(Offer storage offer, uint256 offerId, address buyer) internal view {
        MarketplaceState storage $ = _marketplaceStorage();
        uint256 allowedBuyerCount = $.allowedBuyersByOfferId[offerId].length;
        if (offer.saleMode == SaleMode.REDEMPTION || (offer.saleMode == SaleMode.MARKETPLACE && allowedBuyerCount != 0))
        {
            require($.isAllowedBuyerByOfferId[offerId][buyer], Errors.Marketplace__BuyerNotAllowed(offerId, buyer));
        }
    }
}

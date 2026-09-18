// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {
    AssetType,
    CounterOfferInput,
    DealStatus,
    DealType,
    OfferInput,
    PaymentResolutionInput,
    SaleMode
} from "../MarketStructs.sol";
import {IEntityEligibilityAdmin} from "../../base/IEntityEligibilityAdmin.sol";

/**
 * @title IMarketplace
 * @author DEUSS Team
 * @notice Interface for Marketplace contract managing asset offers and deals
 * @dev solhint-disable ordering because the functions are logically ordered differently into groups
 *
 * solhint-disable ordering
 */
interface IMarketplace is IEntityEligibilityAdmin {
    /**
     * @notice Emitted when a new offer is registered
     * @param offerId The ID of the offer
     * @param owner The address of the offer owner
     * @param tokenAddress The token contract address
     * @param tokenId The token identifier
     * @param assetType The token standard of the offer
     * @param saleMode The sale flow used by the offer
     */
    event OfferRegistered(
        uint256 indexed offerId,
        address indexed owner,
        address indexed tokenAddress,
        uint256 tokenId,
        AssetType assetType,
        SaleMode saleMode
    );

    /* solhint-disable gas-indexed-events */
    /**
     * @notice Emitted with immutable terms for a newly registered offer
     * @param offerId The ID of the offer
     * @param totalAmount The total amount placed into the offer
     * @param lot The minimum lot granularity for accepted amounts
     * @param unitPrice The price per token unit
     * @param currency Offer currency encoded as bytes3
     * @param expiry Offer expiry timestamp
     * @param allowCounterOffers Whether counter offers are allowed
     */
    event OfferTermsRegistered(
        uint256 indexed offerId,
        uint256 totalAmount,
        uint256 lot,
        uint256 unitPrice,
        bytes3 currency,
        uint256 expiry,
        bool allowCounterOffers
    );

    /**
     * @notice Emitted with interest-discovery terms for a newly registered interest-discovery offer
     * @param offerId The ID of the offer
     * @param minSaleUnits Minimum sale units required for interest-discovery offers
     */
    event InterestDiscoveryConfigured(uint256 indexed offerId, uint256 minSaleUnits);
    /* solhint-enable gas-indexed-events */

    /**
     * @notice Emitted when offer amounts are updated
     * @param offerId The ID of the offer
     * @param availableAmount The new available amount
     * @param inDealsAmount The new amount in deals
     * @param soldAmount The new sold amount
     */
    event AmountsUpdated(
        uint256 indexed offerId, uint256 indexed availableAmount, uint256 indexed inDealsAmount, uint256 soldAmount
    );

    /**
     * @notice Emitted when an offer is cancelled
     * @param offerId The ID of the offer
     * @param canceller The address of the canceller
     */
    event OfferCancelled(uint256 indexed offerId, address indexed canceller);

    /**
     * @notice Emitted when a counter offer is created
     * @param offerId ID of the original offer
     * @param dealId ID of the deal created as a result of the counter offer
     * @param owner Address of the counter offer owner
     */
    event CounterOfferCreated(uint256 indexed offerId, uint256 indexed dealId, address indexed owner);

    /**
     * @notice Emitted when counter offer deal is cancelled
     * @param dealId The ID of the counter offer deal
     * @param canceller The address of the canceller
     */
    event CounterOfferCancelled(uint256 indexed dealId, address indexed canceller);

    /**
     * @notice Emitted when counter offer deal is resolved
     * @param dealId The ID of the counter offer deal
     * @param accepted Was the counter offer accepted?
     * @param tokenId Token identifier from the underlying offer
     * @param amount Token amount for the deal
     * @param currency Offer currency (bytes3, same encoding as `Offer.currency`)
     * @param buyer Counter offer creator (deal buyer)
     * @param seller Original offer owner
     */
    event CounterOfferResolved(
        uint256 indexed dealId,
        bool indexed accepted,
        uint256 indexed tokenId,
        uint256 amount,
        bytes3 currency,
        address buyer,
        address seller
    );

    /**
     * @notice Emitted when a deal is created
     * @param offerId The ID of the offer
     * @param dealId The ID of the deal
     * @param buyer Deal creator
     * @param dealType Whether this is a direct offer acceptance or a counter offer proposal
     * @param amount Token amount for the deal
     * @param price Total price for this deal
     */
    event DealCreated(
        uint256 indexed offerId,
        uint256 indexed dealId,
        address indexed buyer,
        DealType dealType,
        uint256 amount,
        uint256 price
    );

    /* solhint-disable gas-indexed-events */
    /**
     * @notice Emitted with payment and expiry terms for a newly created deal
     * @param dealId The ID of the deal
     * @param paymentDeadline The payment deadline timestamp of the deal, or zero for unresolved counter offers
     * @param counterOfferExpiry Counter-offer expiry timestamp, or zero for direct deals
     * @param disputeDeadline Deadline after which a paid deal leaves the dispute buffer, or zero before payment is due
     */
    event DealTermsRegistered(
        uint256 indexed dealId, uint256 paymentDeadline, uint256 counterOfferExpiry, uint256 disputeDeadline
    );
    /* solhint-enable gas-indexed-events */

    /**
     * @notice Emitted when a deal status is updated with offer context and previous status
     * @param dealId The ID of the deal
     * @param offerId The ID of the parent offer
     * @param newStatus The new status of the deal
     * @param oldStatus The previous status of the deal
     */
    event DealStatusUpdated(uint256 indexed dealId, uint256 indexed offerId, uint8 indexed newStatus, uint8 oldStatus);

    /**
     * @notice Emitted when deal payment is resolved
     * @param dealId The ID of the deal
     * @param paid Whether the deal is resolved as paid
     * @param resolver The account that resolved payment
     */
    event PaymentResolved(uint256 indexed dealId, bool indexed paid, address indexed resolver);

    /**
     * @notice Emitted when one batched payment-resolution item is skipped after reverting
     * @param dealId The ID of the deal that failed to resolve
     * @param paid Requested payment resolution for the deal
     * @param resolver The account that submitted the batch
     * @param failureData Raw revert data returned by the failed item
     */
    event PaymentResolutionSkipped(
        uint256 indexed dealId, bool indexed paid, address indexed resolver, bytes failureData
    );

    /* solhint-disable gas-indexed-events */
    /**
     * @notice Emitted after a batched payment-resolution call finishes
     * @param resolver The account that submitted the batch
     * @param requested Number of requested resolution items
     * @param succeeded Number of successfully resolved items
     * @param skipped Number of skipped items
     */
    event PaymentResolutionsBatchProcessed(
        address indexed resolver, uint256 indexed requested, uint256 indexed succeeded, uint256 skipped
    );
    /* solhint-enable gas-indexed-events */

    /**
     * @notice Emitted when one batched settlement item is skipped after reverting
     * @param dealId The ID of the deal that failed to settle
     * @param settler The account that submitted the batch
     * @param failureData Raw revert data returned by the failed item
     */
    event DealSettlementSkipped(uint256 indexed dealId, address indexed settler, bytes failureData);

    /* solhint-disable gas-indexed-events */
    /**
     * @notice Emitted after a batched settlement call finishes
     * @param settler The account that submitted the batch
     * @param requested Number of requested settlement items
     * @param succeeded Number of successfully settled items
     * @param skipped Number of skipped items
     */
    event DealSettlementsBatchProcessed(
        address indexed settler, uint256 indexed requested, uint256 indexed succeeded, uint256 skipped
    );
    /* solhint-enable gas-indexed-events */

    /**
     * @notice Emitted when one investor expresses interest in an interest-discovery offer
     * @param offerId The linked offer identifier
     * @param interestId The newly created interest identifier
     * @param investor The investor that expressed interest
     * @param amount Reserved token amount
     * @param price Total price reserved for this interest
     */
    event InterestExpressed(
        uint256 indexed offerId, uint256 indexed interestId, address indexed investor, uint256 amount, uint256 price
    );

    /**
     * @notice Emitted when an interest changes status with offer context and previous status
     * @param interestId The interest identifier
     * @param offerId The linked offer identifier
     * @param newStatus The new interest status
     * @param oldStatus The previous interest status
     */
    event InterestStatusUpdated(
        uint256 indexed interestId, uint256 indexed offerId, uint8 indexed newStatus, uint8 oldStatus
    );

    /**
     * @notice Emitted when the frozen state of an offer is changed
     * @param offerId The ID of the offer
     * @param frozen Whether the offer is now frozen
     */
    event OfferFrozenSet(uint256 indexed offerId, bool indexed frozen);

    /**
     * @notice Emitted when the frozen state of a deal is changed
     * @param dealId The ID of the deal
     * @param frozen Whether the deal is now frozen
     */
    event DealFrozenSet(uint256 indexed dealId, bool indexed frozen);

    /**
     * @notice Emitted when the non-deal escrow balance of an offer is seized
     * @param offerId The ID of the offer whose offer-level escrow balance was seized
     * @param beneficiary The address receiving the seized tokens
     * @param amount The amount of tokens seized from the offer-level escrow surface
     * @param reason An opaque identifier for the legal/compliance reason for the seizure
     * @param caller The address that triggered the seizure
     */
    event OfferEscrowSeized(
        uint256 indexed offerId, address indexed beneficiary, uint256 amount, bytes32 indexed reason, address caller
    );

    /**
     * @notice Emitted when a deal is seized
     * @param dealId The ID of the seized deal
     * @param offerId The ID of the parent offer
     * @param beneficiary The address receiving the seized tokens
     * @param amount The amount of tokens seized from escrow
     * @param reason An opaque identifier for the legal/compliance reason for the seizure
     * @param caller The address that triggered the seizure
     */
    event DealSeized(
        uint256 indexed dealId,
        uint256 indexed offerId,
        address indexed beneficiary,
        uint256 amount,
        bytes32 reason,
        address caller
    );

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Register a new offer for asset trading
     * @param offer The offer input containing token metadata, amounts, and pricing
     * @return offerId The unique identifier for the registered offer
     * @dev Proper validation of input data is performed including asset support, amounts, pricing, and expiry lifetime bounds
     * @dev Seller wallet/entity enabled state and entity type are validated before escrow creation
     */
    function registerOffer(OfferInput calldata offer) external returns (uint256 offerId);

    /**
     * @notice Cancel an existing offer
     * @param offerId The ID of the offer to cancel
     * @dev Direct-sale offers can be cancelled only by the enabled offer owner.
     * @dev Expired failed INTEREST_DISCOVERY offers can be cancelled by the enabled offer owner or
     *      INTEREST_DISCOVERY_OPERATOR while the offer owner remains enabled.
     * @dev Reverts if the offer is frozen
     * @dev Cancelling marks offer state as cancelled and optionally withdraws currently available escrowed amount
     * @dev For INTEREST_DISCOVERY failed books, cancellation releases both available and reserved-interest inventory.
     *      Withdrawal still routes to the escrow depositor; if the owner is disabled, use re-enable-and-retry or
     *      freeze + seize recovery.
     */
    function cancelOffer(uint256 offerId) external;

    /**
     * @notice Withdraw currently withdrawable escrow inventory from an offer
     * @param offerId The offer identifier
     * @dev MARKETPLACE and REDEMPTION offers require cancellation first.
     * @dev Reverts if the offer is frozen
     * @dev INTEREST_DISCOVERY offers require expiry first and may withdraw only the unreserved amount when the threshold was reached.
     * @dev Payout is routed to the escrow depositor (`offer.owner`) via `EscrowManager.withdraw`. If the token layer
     *      rejects transfers to that wallet at execution time (for example because the account was later disabled in
     *      `EntityRegistry`), escrow release is blocked until the wallet is re-enabled or the frozen offer is seized
     *      to an eligible beneficiary.
     */
    function withdrawAvailable(uint256 offerId) external;

    /**
     * @notice Accept an offer by creating a deal
     * @param offerId The ID of the offer to accept
     * @param amount The amount of tokens to accept (must be greater than 0 and a multiple of lot size)
     * @return dealId The unique identifier for the created deal
     * @dev Reverts if the offer is cancelled or frozen
     * @dev Validates offer expiry and amount constraints
     * @dev Creates a PENDING deal that requires payment within the deadline
     */
    function acceptOffer(uint256 offerId, uint256 amount) external returns (uint256 dealId);

    /**
     * @notice Express binding interest in an interest-discovery offer without creating a deal yet
     * @param offerId The ID of the offer to reserve inventory from
     * @param amount The amount of tokens to reserve
     * @return interestId The unique identifier for the expressed interest
     * @dev Reverts if the offer is cancelled or frozen
     */
    function expressInterest(uint256 offerId, uint256 amount) external returns (uint256 interestId);

    /**
     * @notice Activate a previously expressed interest into a normal deal
     * @param interestId The interest identifier to activate
     * @return dealId The unique identifier for the created deal
     * @dev Reverts if the linked offer is cancelled or frozen
     * @dev Activation is allowed once minSaleUnits is reached and through saleEnd plus the snapshotted payment expiry
     * @dev If activated through saleEnd, the deal payment deadline is saleEnd plus the snapshotted payment expiry
     * @dev If activated after saleEnd, the deal payment deadline is block.timestamp plus the snapshotted payment expiry
     * @dev Investor entity-type eligibility is enforced when interest is expressed; activation rechecks enabled wallets
     */
    function activateInterest(uint256 interestId) external returns (uint256 dealId);

    /**
     * @notice Close expired expressed interests in bounded batches after the activation deadline passes
     * @param offerId The linked interest-discovery offer
     * @param interestIds The specific interest identifiers to close
     * @dev Caller must be the enabled offer owner or hold INTEREST_DISCOVERY_OPERATOR
     * @dev Intentionally remains callable while the offer is frozen
     * @dev Reverts if the offer was already cancelled
     */
    function closeExpiredInterests(uint256 offerId, uint256[] calldata interestIds) external;

    /**
     * @notice Creates a counter offer to an existing offer
     * @param counterOffer The counter offer input containing offer ID, amount, price, and expiry
     * @return dealId The unique identifier for the counter offer deal
     * @dev Creates a PROPOSED deal that the original offer owner can accept or decline
     * @dev Validates sender authorization, non-zero unit price, expiry lifetime bounds, and offer constraints
     */
    function createCounterOffer(CounterOfferInput calldata counterOffer) external returns (uint256 dealId);

    /**
     * @notice Cancels a counter offer
     * @param dealId The ID of the counter offer deal to cancel
     * @dev Only the counter offer creator can cancel it, and only while it remains unexpired
     * @dev Reverts if the counter offer itself or its parent offer is frozen
     * @dev Changes deal status to CANCELLED
     */
    function cancelCounterOffer(uint256 dealId) external;

    /**
     * @notice Resolves a counter offer by accepting or declining it
     * @param dealId The ID of the counter offer deal to resolve
     * @param accepted Whether to accept (true) or decline (false) the counter offer
     * @dev Only the original offer owner can resolve counter offers
     * @dev Reverts if the counter offer itself or its parent offer is frozen
     * @dev If accepted, requires the parent offer to be unexpired and converts counter offer to a PENDING deal
     * @dev If declined, sets deal status to DECLINED
     */
    function resolveCounterOffer(uint256 dealId, bool accepted) external;

    /**
     * @notice Resolve payment status of a deal
     * @param dealId The ID of the deal to resolve payment for
     * @param paid Whether to resolve as paid (`true`) or unpaid (`false`)
     * @dev When `paid == true`, caller must have PAYMENT_HANDLER role and deal must be in PENDING or pre-arbitration
     *      UNPAID status; if currently UNPAID, the deal must not have been arbitrated (`disputeBuffer != 0`)
     * @dev When `paid == false`, callable by anyone after payment deadline has passed, but only from PENDING status
     * @dev Remains callable while the deal or its parent offer is frozen; freeze does not pause deadlines
     * @dev Changes deal status to PAID or UNPAID and emits PaymentResolved
     */
    function resolvePayment(uint256 dealId, bool paid) external;

    /**
     * @notice Resolve multiple deal payment statuses in one call
     * @param resolutions Ordered payment-resolution requests
     */
    function resolvePayments(PaymentResolutionInput[] calldata resolutions) external;

    /**
     * @notice Initiate a dispute for an unpaid deal
     * @param dealId The ID of the deal to dispute
     * @dev Only the buyer can initiate a dispute
     * @dev Remains callable while the deal or its parent offer is frozen; freeze does not pause deadlines
     * @dev Reverts if the caller is not the buyer, deal is not in UNPAID status, or dispute period has expired
     * @dev Changes deal status to IN_DISPUTE
     */
    function initiateDispute(uint256 dealId) external;

    /**
     * @notice Resolve a dispute for a deal by an arbitrator
     * @param dealId The ID of the deal to resolve
     * @param status The new status for the deal (PAID or UNPAID)
     * @dev Only addresses with ARBITRATOR role can call this function
     * @dev Remains callable while the deal or its parent offer is frozen; freeze does not pause arbitration
     * @dev Reverts if the deal is not in IN_DISPUTE status or if the new status is invalid
     * @dev Prevents future disputes by setting dispute buffer to 0
     */
    function resolveDispute(uint256 dealId, DealStatus status) external;

    /**
     * @notice Settle a deal after payment resolution
     * @param dealId The ID of the deal to settle
     * @dev Can be called by anyone once the deal is in PAID or UNPAID status
     * @dev Reverts if the deal itself or its parent offer is frozen
     * @dev For UNPAID deals, requires dispute period to have expired
     * @dev Transfers tokens to buyer if PAID, restores seller availability if UNPAID
     * @dev Changes deal status to SUCCESSFUL if PAID or UNSUCCESSFUL if UNPAID and updates offer amounts
     * @dev For PAID deals, `deal.buyer` must still be enabled in EntityRegistry before settlement finalizes
     * @dev Settlement uses fixed recipients: PAID deals claim escrow to `deal.buyer`, UNPAID deals restore
     *      availability for later seller withdrawal. If the paid buyer is disabled or asset-level transfer policy
     *      later rejects a payout recipient, normal settlement/withdrawal is blocked until the recipient is re-enabled
     *      or the frozen position is seized to an eligible beneficiary.
     */
    function settleDeal(uint256 dealId) external;

    /**
     * @notice Settle multiple deals in one call, skipping individual items that revert
     * @param dealIds Ordered deal identifiers to attempt to settle
     * @dev Emits DealSettlementSkipped for each failed item and DealSettlementsBatchProcessed at the end
     */
    function settleDeals(uint256[] calldata dealIds) external;

    /**
     * @notice Seize the non-deal escrow balance of a frozen offer
     * @param offerId The ID of the offer to seize from
     * @param beneficiary The address that will receive the seized tokens
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Caller must have SEIZURE_ROLE
     * @dev Offer must exist, be frozen, beneficiary/reason must be non-zero, and beneficiary must be an enabled wallet
     * @dev Must have either non-zero available balance or non-zero reservedInterestUnits (or both)
     * @dev For INTEREST_DISCOVERY offers with reservedInterestUnits > 0: zeroes reservedInterestUnits, sets the
     *      offer-level flag and includes the reserved amount in the escrow claim
     * @dev Operationally this is also the privileged recovery path for offers whose normal withdrawal recipient can no
     *      longer receive tokens (for example because the account became disabled after the offer/deal was created).
     * @dev Sets available to 0, marks the offer as cancelled, and calls EscrowManager.claim for the total amount
     * @dev Emits OfferCancelled, AmountsUpdated, and OfferEscrowSeized
     */
    function seizeOfferEscrow(uint256 offerId, address beneficiary, bytes32 reason) external;

    /**
     * @notice Seize the escrowed tokens of a frozen deal from a frozen parent offer
     * @param dealId The ID of the deal to seize
     * @param beneficiary The address that will receive the seized tokens
     * @param reason Opaque identifier for the legal/compliance reason
     * @dev Caller must have SEIZURE_ROLE
     * @dev Deal must exist, be frozen, parent offer must be frozen, beneficiary must be an enabled wallet, and deal
     *      must be in PENDING/UNPAID/IN_DISPUTE/PAID
     * @dev Operationally this is also the privileged recovery path for a paid deal whose buyer can no longer receive
     *      tokens through the normal settlement path.
     * @dev Decrements offer.amounts.inDeals, calls EscrowManager.claim, sets deal status to SEIZED
     * @dev Emits DealStatusUpdated, AmountsUpdated, and DealSeized
     */
    function seizeDeal(uint256 dealId, address beneficiary, bytes32 reason) external;

    /**
     * @notice Set the frozen state of an offer
     * @param offerId The ID of the offer to freeze or unfreeze
     * @param frozen True to freeze, false to unfreeze
     * @dev Only callable by addresses with FREEZE_ROLE
     * @dev Offer must exist; emits OfferFrozenSet
     * @dev Freeze alone does not reroute or release escrow. Recovery of a blocked payout requires either re-enabling
     *      the original recipient or freezing first and then calling the appropriate seizure function.
     */
    function setOfferFrozen(uint256 offerId, bool frozen) external;

    /**
     * @notice Set the frozen state of a deal
     * @param dealId The ID of the deal to freeze or unfreeze
     * @param frozen True to freeze, false to unfreeze
     * @dev Only callable by addresses with FREEZE_ROLE
     * @dev Deal must exist; emits DealFrozenSet
     * @dev Freeze alone does not release escrow. It is only a prerequisite for the seizure-based recovery path.
     */
    function setDealFrozen(uint256 dealId, bool frozen) external;
}

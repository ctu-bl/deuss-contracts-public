// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @notice Enum representing supported token standards in marketplace flows
 * @dev Shared `MarketStructs` definitions used across `Marketplace`, `OrderbookMarketplace`, and `EscrowManager`.
 * @param NONE Unconfigured or unsupported type
 * @param ERC20 ERC-20 fungible token
 * @param ERC721 ERC-721 non-fungible token
 * @param ERC1155 ERC-1155 multi-token
 * @param ERC6909 ERC-6909 multi-token
 */
enum AssetType {
    NONE,
    ERC20,
    ERC721,
    ERC1155,
    ERC6909
}

/**
 * @notice Enum representing the status of a deal in the marketplace
 * @param NON_EXISTING Deal does not exist (default state)
 * @param PENDING Deal is created and payment by buyer is expected
 * @param PAID Payment has been received and confirmed
 * @param UNPAID Payment was not received within the deadline
 * @param CANCELLED Deal was cancelled by the buyer
 * @param IN_DISPUTE Deal is currently under dispute resolution
 * @param PROPOSED Counter offer deal is proposed and awaiting response
 * @param DECLINED Counter offer deal was declined by the original offer owner
 * @param SUCCESSFUL Deal was settled with confirmed payment (tokens transferred to buyer)
 * @param UNSUCCESSFUL Deal was settled without confirmed payment (inventory restored to seller availability)
 * @param SEIZED Deal was seized by a SEIZURE_ROLE holder; tokens transferred to a beneficiary
 */
enum DealStatus {
    NON_EXISTING,
    PENDING,
    PAID,
    UNPAID,
    CANCELLED,
    IN_DISPUTE,
    PROPOSED,
    DECLINED,
    SUCCESSFUL,
    UNSUCCESSFUL,
    SEIZED
}

/**
 * @notice Enum signaling whether the deal belongs to a regular or counter offer
 * @param OFFER Regular offer deal (direct acceptance of an offer)
 * @param COUNTER_OFFER Counter offer deal (proposed alternative terms)
 */
enum DealType {
    OFFER,
    COUNTER_OFFER
}

/**
 * @notice Enum representing supported sale flows for an offer
 * @param MARKETPLACE Standard direct marketplace flow where accepting an offer creates a deal immediately
 * @param REDEMPTION Direct redemption-style flow where only allowlisted buyers may accept the offer
 * @param INTEREST_DISCOVERY Threshold-gated flow where investors reserve inventory first and activate later
 */
enum SaleMode {
    MARKETPLACE,
    REDEMPTION,
    INTEREST_DISCOVERY
}

/**
 * @notice Enum representing the lifecycle of one expressed interest
 * @param NON_EXISTING Default state
 * @param EXPRESSED Investor expressed binding interest and reserved inventory
 * @param ACTIVATED Interest was converted into a normal deal
 * @param CLOSED Interest can no longer be activated
 * @param SEIZED Interest inventory was seized by a SEIZURE_ROLE holder
 */
enum InterestStatus {
    NON_EXISTING,
    EXPRESSED,
    ACTIVATED,
    CLOSED,
    SEIZED
}

/**
 * @notice Structure representing an offer input for registration
 * @param tokenAddress Address of the token contract
 * @param tokenId ID of the specific token (must be 0 for ERC20)
 * @param totalAmount Total amount of tokens to be sold in the offer
 * @param lot Lot size for trading (trade amount must be greater than 0 and a multiple of lot)
 * @param unitPrice Price per unit in the specified currency
 * @param currency Currency code for pricing encoded as bytes3 (e.g., bytes3("EUR"))
 * @param expiry Expiry timestamp of the offer (must be in the future)
 * @param allowCounterOffers Whether counter offers are allowed for this offer
 * @param allowedBuyers Optional direct-sale allowlist; empty means unrestricted for MARKETPLACE and invalid for REDEMPTION
 * @param saleMode Sale flow for this offer
 * @param minSaleUnits Minimum expressed-interest threshold for interest-discovery offers
 */
// solhint-disable-next-line gas-struct-packing
struct OfferInput {
    address tokenAddress;
    uint256 tokenId;
    uint256 totalAmount;
    uint256 lot;
    uint256 unitPrice;
    bytes3 currency;
    uint256 expiry;
    bool allowCounterOffers;
    address[] allowedBuyers;
    SaleMode saleMode;
    uint256 minSaleUnits;
}

/**
 * @notice Structure representing a counter offer input
 * @param offerId ID of the original offer being countered
 * @param expiry Expiry timestamp of the counter offer (must be in the future)
 * @param amount Amount of tokens to counter (must be greater than 0 and a multiple of original offer's lot)
 * @param unitPrice Unit price proposed in the counter offer (must be non-zero)
 */
struct CounterOfferInput {
    uint256 offerId;
    uint256 expiry;
    uint256 amount;
    uint256 unitPrice;
}

/**
 * @notice One payment-resolution item for batched deal processing
 * @param dealId ID of the deal to resolve
 * @param paid Whether to resolve the deal as paid (`true`) or unpaid (`false`)
 */
struct PaymentResolutionInput {
    uint256 dealId;
    bool paid;
}

/**
 * @notice Structure representing the token amounts for an offer
 * @param total Total amount of tokens deposited in the offer
 * @param available Amount of tokens available for new deals
 * @param inDeals Amount of tokens currently locked in pending deals
 * @param sold Amount of tokens successfully sold to buyers
 */
struct Amounts {
    uint256 total;
    uint256 available;
    uint256 inDeals;
    uint256 sold;
}

/**
 * @notice Structure representing a registered offer in the marketplace
 * @param owner Address of the offer owner (creator)
 * @param assetType Token standard for this offer
 * @param tokenAddress Address of the token contract
 * @param tokenId ID of the specific token
 * @param lot Lot size for trading (minimum tradeable amount)
 * @param unitPrice Price per unit in the specified currency
 * @param currency Currency code for pricing (converted to bytes3)
 * @param expiry Expiry timestamp of the offer
 * @param amounts Token amounts tracking (total, available, inDeals, sold)
 * @param allowCounterOffers Whether counter offers are allowed for this offer
 * @param saleMode Sale flow for this offer
 */
// solhint-disable-next-line gas-struct-packing
struct Offer {
    bytes3 currency;
    bool allowCounterOffers;
    SaleMode saleMode;
    AssetType assetType;
    address owner;
    address tokenAddress;
    uint256 tokenId;
    uint256 lot;
    uint256 unitPrice;
    uint256 expiry;
    Amounts amounts;
}

/**
 * @notice Interest-discovery-only state kept separately from the generic offer
 * @param minSaleUnits Minimum threshold required before interests can be activated into deals
 * @param interestedUnits Cumulative amount of expressed interest
 * @param reservedInterestUnits Inventory currently reserved by expressed interests
 * @param paymentExpiryThreshold Per-offer activation offset and activated-deal payment window snapshotted at registration
 */
struct InterestDiscoveryState {
    uint256 minSaleUnits;
    uint256 interestedUnits;
    uint256 reservedInterestUnits;
    uint256 paymentExpiryThreshold;
}

/**
 * @notice One investor's pre-payment binding interest for an interest-discovery offer
 * @param offerId Offer this interest belongs to
 * @param amount Reserved token amount
 * @param investor Investor that expressed the interest
 * @param price Total price derived from `offer.unitPrice * amount`
 * @param status Lifecycle status for the interest
 */
struct Interest {
    uint256 offerId;
    uint256 amount;
    address investor;
    uint256 price;
    InterestStatus status;
}

/**
 * @notice Structure representing a deal in the marketplace
 * @param offerId ID of the offer this deal is based on
 * @param amount Amount of tokens in the deal
 * @param buyer Address of the buyer (deal creator)
 * @param price Total price of the deal (amount * unitPrice)
 * @param counterOfferExpiry Acceptance deadline for counter offers (0 for regular deals)
 * @param paymentDeadline Payment deadline for PENDING deals
 * @param disputeBuffer Dispute buffer period end timestamp
 * @param status Current status of the deal
 * @param dealType Type of deal (OFFER or COUNTER_OFFER)
 */
struct Deal {
    uint256 offerId;
    uint256 amount;
    address buyer;
    uint256 price;
    uint256 counterOfferExpiry;
    uint256 paymentDeadline;
    uint256 disputeBuffer;
    DealStatus status;
    DealType dealType;
}

/**
 * @notice Shared input payload used when constructing a marketplace deal in storage
 * @param offerId Linked offer identifier
 * @param amount Token amount for the deal
 * @param buyer Buyer address for the deal
 * @param price Total deal price
 * @param counterOfferExpiry Expiry timestamp for counter offers, or zero for direct deals
 * @param paymentDeadline Payment deadline for pending deals, or zero for proposed counter offers
 * @param status Initial deal status
 * @param dealType Deal type to persist
 */
struct DealCreationInput {
    uint256 offerId;
    uint256 amount;
    address buyer;
    uint256 price;
    uint256 counterOfferExpiry;
    uint256 paymentDeadline;
    DealStatus status;
    DealType dealType;
}

/**
 * @notice Structure holding freeze state for an offer or deal
 * @param frozen Whether the offer/deal is currently frozen
 * @param frozenBy Address that applied the freeze
 * @param totalFrozen Cumulative seconds the offer/deal has spent frozen across all freeze/unfreeze cycles
 * @param reason On-chain reason for the freeze
 * @param frozenAt Timestamp when the freeze was applied; used to compute frozen duration on unfreeze
 */
struct FreezeData {
    bool frozen;
    address frozenBy;
    uint64 totalFrozen;
    bytes32 reason;
    uint256 frozenAt;
}

/**
 * @notice Structure representing an escrow for token custody
 * @param depositor Address of the token depositor (offer owner)
 * @param assetType Token standard stored for transfer dispatch
 * @param tokenAddress Address of the token contract
 * @param tokenId ID of the specific token
 * @param amount Amount of tokens currently held in escrow
 * @param moduleType Module type this escrow belongs to (e.g. interest discovery, orderbook)
 * @param moduleAddress Module address that created this escrow
 */
struct Escrow {
    address depositor;
    AssetType assetType;
    address tokenAddress;
    uint256 tokenId;
    uint256 amount;
    bytes32 moduleType;
    address moduleAddress;
}

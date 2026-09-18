// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-small-strings */

abstract contract PropertiesDescriptions {
    string internal constant SPLY_01 =
        "SPLY-01: Total supply of the issued bond token equals the sum of tracked balances";
    string internal constant SPLY_02 =
        "SPLY-02: Total supply of the issued bond token never increases above the initial issued supply";
    string internal constant SPLY_03 =
        "SPLY-03: Bond nominal value for the issued token remains equal to the setup nominal value";
    string internal constant SPLY_04 =
        "SPLY-04: Total face value equals tracked balance face value using the bond nominal value";
    string internal constant SPLY_05 = "SPLY-05: Current-block totalSupplyAt matches current totalSupply";

    string internal constant ESCR_01 = "ESCR-01: EscrowManager token balance equals the sum of tracked escrow amounts";
    string internal constant ESCR_02 =
        "ESCR-02: Every tracked escrow amount matches the tracked offer holdings for its sale mode";
    string internal constant ESCR_10 = "ESCR-10: Registering an offer creates a linked escrow";
    string internal constant ESCR_11 = "ESCR-11: Registering an offer funds escrow with the deposited amount";
    string internal constant ESCR_12 = "ESCR-12: Cancelling an offer withdraws its previously available amount";
    string internal constant ESCR_13 = "ESCR-13: Settling a paid deal decreases escrow by the settled amount";
    string internal constant ESCR_14 = "ESCR-14: withdrawAvailable decreases escrow by the withdrawn amount";
    string internal constant ESCR_15 = "ESCR-15: Settling an unpaid deal leaves escrow amount unchanged";
    string internal constant ESCR_16 = "ESCR-16: settleDeals applies aggregate escrow deltas for settled deals";
    string internal constant ESCR_20 = "ESCR-20: createEscrow stores the expected escrow fields";
    string internal constant ESCR_20_DEPOSITOR = "ESCR-20.depositor: createEscrow stores the expected depositor";
    string internal constant ESCR_20_TOKEN = "ESCR-20.tokenAddress: createEscrow stores the expected token address";
    string internal constant ESCR_20_TOKEN_ID = "ESCR-20.tokenId: createEscrow stores the expected token ID";
    string internal constant ESCR_20_AMOUNT = "ESCR-20.amount: createEscrow stores the expected amount";
    string internal constant ESCR_20_ASSET_TYPE = "ESCR-20.assetType: createEscrow stores the expected asset type";
    string internal constant ESCR_20_MODULE_TYPE = "ESCR-20.moduleType: createEscrow stores the expected module type";
    string internal constant ESCR_21 = "ESCR-21: createEscrow increments nextEscrowId by one";
    string internal constant ESCR_22 = "ESCR-22: createEscrow increases EscrowManager balance by the deposited amount";
    string internal constant ESCR_23 = "ESCR-23: createEscrow decreases depositor balance by the deposited amount";
    string internal constant ESCR_24 = "ESCR-24: createEscrow increases reserved balance by the deposited amount";
    string internal constant ESCR_25 = "ESCR-25: createEscrow does not unexpectedly revert";
    string internal constant ESCR_26 = "ESCR-26: Unauthorized createEscrow reverts with module not registered";
    string internal constant ESCR_30 = "ESCR-30: withdraw decreases escrow.amount by the withdrawn amount";
    string internal constant ESCR_31 = "ESCR-31: withdraw increases depositor balance by the withdrawn amount";
    string internal constant ESCR_32 = "ESCR-32: withdraw decreases EscrowManager balance by the withdrawn amount";
    string internal constant ESCR_33 = "ESCR-33: withdraw does not unexpectedly revert";
    string internal constant ESCR_40 = "ESCR-40: claim decreases escrow.amount by the claimed amount";
    string internal constant ESCR_41 = "ESCR-41: claim increases beneficiary balance by the claimed amount";
    string internal constant ESCR_42 = "ESCR-42: claim decreases EscrowManager balance by the claimed amount";
    string internal constant ESCR_43 = "ESCR-43: claim does not unexpectedly revert";
    string internal constant ESCR_50 = "ESCR-50: sweep does not mutate any tracked escrow amount";
    string internal constant ESCR_51 = "ESCR-51: sweep does not decrease EscrowManager balance below reserved amount";
    string internal constant ESCR_52 = "ESCR-52: sweep does not unexpectedly revert";
    string internal constant ESCR_53 =
        "ESCR-53: directTransferToEscrow decreases the sender balance by the transferred amount";
    string internal constant ESCR_54 =
        "ESCR-54: directTransferToEscrow increases EscrowManager balance by the transferred amount";
    string internal constant ESCR_55 = "ESCR-55: directTransferToEscrow does not mutate any tracked escrow amount";
    string internal constant ESCR_56 = "ESCR-56: directTransferToEscrow does not change reserved escrow accounting";
    string internal constant ESCR_57 =
        "ESCR-57: directTransferToEscrow increases sweepable surplus by the transferred amount";
    string internal constant ESCR_58 =
        "ESCR-58: directTransferToEscrow only reverts when protected receiver push-transfer guard rejects it";
    string internal constant ESCR_60 = "ESCR-60: EscrowManager balance is greater than or equal to reserved amount";
    string internal constant ESCR_61 = "ESCR-61: registerModule / deactivateModule do not mutate escrow accounting";
    string internal constant ESCR_61_TRACKED_SUM =
        "ESCR-61.trackedEscrowAmountSum: module auth changes preserve tracked escrow amount sum";
    string internal constant ESCR_61_BALANCE =
        "ESCR-61.escrowBalance: module auth changes preserve EscrowManager balance";
    string internal constant ESCR_61_RESERVED =
        "ESCR-61.escrowReserved: module auth changes preserve reserved escrow accounting";
    string internal constant ESCR_62 = "ESCR-62: deactivated module is not authorized for further escrow actions";
    string internal constant ESCR_62_AUTHORIZED =
        "ESCR-62.authorized: deactivated module is not authorized for the test module type";
    string internal constant ESCR_62_MODULE_TYPE = "ESCR-62.moduleType: deactivated module has no recorded module type";
    string internal constant ESCR_63 = "ESCR-63: registerModule does not unexpectedly revert";
    string internal constant ESCR_64 =
        "ESCR-64: deactivateModule only reverts for active escrows after handler preconditions";
    string internal constant ESCR_70 =
        "ESCR-70: EscrowManager multi-standard coverage calls do not unexpectedly revert";
    string internal constant ESCR_71 =
        "ESCR-71: ERC721 balanceHeld coverage reports one for a minted escrow-held token";
    string internal constant ESCR_72 = "ESCR-72: EscrowManager invalid asset-type coverage reverts as expected";

    string internal constant MKT_80 = "MKT-80: Marketplace admin and view coverage calls do not unexpectedly revert";
    string internal constant MKT_81 = "MKT-81: setBondRegistry only reverts when the registry is already set";
    string internal constant MKT_82 =
        "MKT-82: Directed Marketplace defensive-branch coverage reverts with the expected selector";

    string internal constant BMF_10 = "BMF-10: setAdapter stores the expected metadata adapter";
    string internal constant BMF_20 = "BMF-20: matchesFilter returns the expected directed predicate result";
    string internal constant BMF_30 = "BMF-30: invalid filter ranges revert with the expected selector";

    string internal constant OB_10 = "OB-10: OrderbookMarketplace admin address wiring matches expected values";
    string internal constant OB_10_ASSET_MANAGER =
        "OB-10.assetManager: OrderbookMarketplace asset manager wiring matches setup";
    string internal constant OB_10_ENTITY_REGISTRY =
        "OB-10.entityRegistry: OrderbookMarketplace entity registry wiring matches setup";
    string internal constant OB_10_ESCROW_MANAGER =
        "OB-10.escrowManager: OrderbookMarketplace escrow manager wiring matches setup";
    string internal constant OB_10_MARKET_FILTER =
        "OB-10.marketFilter: OrderbookMarketplace market filter wiring matches setup";
    string internal constant OB_11 = "OB-11: OrderbookMarketplace admin numeric configuration matches expected values";
    string internal constant OB_11_PAYMENT_EXPIRY_THRESHOLD =
        "OB-11.paymentExpiryThreshold: OrderbookMarketplace payment expiry threshold matches setup";
    string internal constant OB_11_MIN_EXPIRY_THRESHOLD =
        "OB-11.minExpiryThreshold: OrderbookMarketplace minimum expiry threshold matches setup";
    string internal constant OB_11_DISPUTE_BUFFER_PERIOD =
        "OB-11.disputeBufferPeriod: OrderbookMarketplace dispute buffer period matches setup";
    string internal constant OB_11_MAX_RECENT_OBSERVATIONS =
        "OB-11.maxRecentObservations: OrderbookMarketplace TWAP observation cap matches the contract constant";
    string internal constant OB_12 = "OB-12: OrderbookMarketplace delegate mutator calls do not unexpectedly revert";
    string internal constant OB_13 =
        "OB-13: Directed OrderbookMarketplace revert coverage returns the expected selector";
    string internal constant OB_14 =
        "OB-14: OrderbookMarketplace internal coverage surfaces do not unexpectedly revert";

    string internal constant OFER_01 =
        "OFER-01: For every tracked offer, available plus inDeals plus sold is bounded by total";
    string internal constant OFER_10 = "OFER-10: Registering an offer stores the expected offer fields";
    string internal constant OFER_10_OWNER = "OFER-10.owner: Registering an offer stores the expected owner";
    string internal constant OFER_10_TOTAL = "OFER-10.total: Registering an offer stores the expected total amount";
    string internal constant OFER_10_AVAILABLE =
        "OFER-10.available: Registering an offer initializes available to total amount";
    string internal constant OFER_10_IN_DEALS = "OFER-10.inDeals: Registering an offer initializes inDeals to zero";
    string internal constant OFER_10_SOLD = "OFER-10.sold: Registering an offer initializes sold to zero";
    string internal constant OFER_10_LOT = "OFER-10.lot: Registering an offer stores the expected lot size";
    string internal constant OFER_10_UNIT_PRICE =
        "OFER-10.unitPrice: Registering an offer stores the expected unit price";
    string internal constant OFER_10_EXPIRY = "OFER-10.expiry: Registering an offer stores the expected expiry";
    string internal constant OFER_10_SALE_MODE = "OFER-10.saleMode: Registering an offer stores the expected sale mode";
    string internal constant OFER_10_COUNTER_OFFERS =
        "OFER-10.allowCounterOffers: Registering an offer stores the expected counter-offer flag";
    string internal constant OFER_10_MIN_SALE_UNITS =
        "OFER-10.minSaleUnits: Registering an offer stores the expected minimum sale units";
    string internal constant OFER_10_PAYMENT_EXPIRY_THRESHOLD =
        "OFER-10.paymentExpiryThreshold: Registering an interest-discovery offer snapshots the payment expiry threshold";
    string internal constant OFER_10_INTERESTED_UNITS =
        "OFER-10.interestedUnits: Registering an offer initializes interested units to zero";
    string internal constant OFER_10_RESERVED_INTEREST =
        "OFER-10.reservedInterestUnits: Registering an offer initializes reserved interest units to zero";
    string internal constant OFER_10_ALLOWED_BUYERS =
        "OFER-10.allowedBuyers: Registering an offer stores the expected allowed buyers";
    string internal constant OFER_11 = "OFER-11: Registering an offer increments the offer counter by one";
    string internal constant OFER_12 = "OFER-12: Registering an offer decreases seller balance by the deposited amount";
    string internal constant OFER_13 = "OFER-13: registerOffer does not unexpectedly revert";
    string internal constant OFER_20 = "OFER-20: Accepting an offer moves amount from available into inDeals";
    string internal constant OFER_21 = "OFER-21: Cancelling an offer marks it cancelled and zeroes available";
    string internal constant OFER_21_EXPIRY =
        "OFER-21.expiry: Cancelling an offer latches expiry to the cancellation timestamp";
    string internal constant OFER_22 = "OFER-22: cancelOffer does not unexpectedly revert";
    string internal constant OFER_30 = "OFER-30: Settling a paid deal moves amount from inDeals into sold";
    string internal constant OFER_31 =
        "OFER-31: Settling an unpaid deal moves amount from inDeals back into available without increasing sold";
    string internal constant OFER_32 = "OFER-32: settleDeals decreases offer inDeals by the settled amount";
    string internal constant OFER_33 = "OFER-33: settleDeals increases offer available by the unpaid settled amount";
    string internal constant OFER_34 = "OFER-34: settleDeals increases offer sold by the paid settled amount";
    string internal constant OFER_40 = "OFER-40: Non-inventory actions do not mutate offer balances";
    string internal constant OFER_50 = "OFER-50: withdrawAvailable removes the withdrawn amount from available";
    string internal constant OFER_51 = "OFER-51: withdrawAvailable increases seller balance by the withdrawn amount";
    string internal constant OFER_52 = "OFER-52: withdrawAvailable does not unexpectedly revert";
    string internal constant OFER_60 = "OFER-60: setOfferFrozen stores the requested frozen flag";
    string internal constant OFER_61 = "OFER-61: setOfferFrozen does not unexpectedly revert";
    string internal constant OFER_62 =
        "OFER-62: seizeOfferEscrow cancels the offer and clears seizable non-deal inventory";
    string internal constant OFER_62_CANCELLED = "OFER-62.cancelled: seizeOfferEscrow marks the offer cancelled";
    string internal constant OFER_62_AVAILABLE = "OFER-62.available: seizeOfferEscrow clears available inventory";
    string internal constant OFER_62_IN_DEALS = "OFER-62.inDeals: seizeOfferEscrow preserves in-deal inventory";
    string internal constant OFER_62_SOLD = "OFER-62.sold: seizeOfferEscrow preserves sold inventory";
    string internal constant OFER_62_RESERVED_INTEREST =
        "OFER-62.reservedInterestUnits: seizeOfferEscrow clears or preserves reserved interest correctly";
    string internal constant OFER_62_RESERVED_SEIZED =
        "OFER-62.reservedInterestSeized: seizeOfferEscrow records reserved-interest seizure";
    string internal constant OFER_63 =
        "OFER-63: seizeDeal moves the seized amount out of inDeals without changing available or sold";
    string internal constant OFER_63_IN_DEALS = "OFER-63.inDeals: seizeDeal decreases inDeals by the seized amount";
    string internal constant OFER_63_AVAILABLE = "OFER-63.available: seizeDeal preserves available inventory";
    string internal constant OFER_63_SOLD = "OFER-63.sold: seizeDeal preserves sold inventory";
    string internal constant OFER_64 = "OFER-64: seizeOfferEscrow does not unexpectedly revert";
    string internal constant OFER_70 = "OFER-70: setMaxCounterOffersPerUser stores the requested non-zero cap";
    string internal constant OFER_71 = "OFER-71: setMaxCounterOffersPerUser only reverts for zero cap";
    string internal constant OFER_72 = "OFER-72: Failed counter-offer cap updates leave the stored cap unchanged";

    string internal constant DEAL_01 = "DEAL-01: Accepting an offer creates a pending deal with expected fields";
    string internal constant DEAL_01_OFFER_ID = "DEAL-01.offerId: acceptOffer creates a deal for the expected offer";
    string internal constant DEAL_01_BUYER = "DEAL-01.buyer: acceptOffer stores the expected buyer";
    string internal constant DEAL_01_AMOUNT = "DEAL-01.amount: acceptOffer stores the expected amount";
    string internal constant DEAL_01_PRICE = "DEAL-01.price: acceptOffer stores unitPrice times amount";
    string internal constant DEAL_01_PAYMENT_DEADLINE =
        "DEAL-01.paymentDeadline: acceptOffer sets the sale-mode payment deadline";
    string internal constant DEAL_01_DISPUTE_BUFFER =
        "DEAL-01.disputeBuffer: acceptOffer derives dispute buffer from payment deadline";
    string internal constant DEAL_01_STATUS = "DEAL-01.status: acceptOffer creates a PENDING deal";
    string internal constant DEAL_01_DEAL_TYPE = "DEAL-01.dealType: acceptOffer creates an OFFER deal";
    string internal constant DEAL_01_BUYER_NOT_OWNER = "DEAL-01.buyer: acceptOffer does not allow self-dealing";
    string internal constant DEAL_01_LOT_NONZERO = "DEAL-01.lot: accepted offer lot is non-zero";
    string internal constant DEAL_01_AMOUNT_LOT_MULTIPLE =
        "DEAL-01.amount: acceptOffer amount is a multiple of the offer lot";
    string internal constant DEAL_01_DIRECT_SALE_MODE = "DEAL-01.saleMode: acceptOffer only creates direct-sale deals";
    string internal constant DEAL_02 = "DEAL-02: Accepting an offer increments the deal counter by one";
    string internal constant DEAL_03 = "DEAL-03: acceptOffer does not unexpectedly revert";
    string internal constant DEAL_10 = "DEAL-10: resolvePayment marks the selected deal as PAID";
    string internal constant DEAL_12 = "DEAL-12: resolvePayment(false) marks the selected deal as UNPAID";
    string internal constant DEAL_11 = "DEAL-11: resolvePayment does not unexpectedly revert";
    string internal constant DEAL_13 = "DEAL-13: resolvePayment(true) rejects callers without PAYMENT_HANDLER";
    string internal constant DEAL_14 =
        "DEAL-14: resolvePayments applies the expected PAID and UNPAID statuses across a mixed batch";
    string internal constant DEAL_14_PAID_STATUS =
        "DEAL-14-PAID-STATUS: resolvePayments marks the paid batch item as PAID";
    string internal constant DEAL_14_UNPAID_STATUS =
        "DEAL-14-UNPAID-STATUS: resolvePayments marks the unpaid batch item as UNPAID";
    string internal constant DEAL_15 =
        "DEAL-15: resolvePayments unpaid-only batches remain permissionless and skipped duplicates do not corrupt the deal";
    string internal constant DEAL_15_RESOLVER_NOT_PAYMENT_HANDLER =
        "DEAL-15-RESOLVER-NOT-PAYMENT-HANDLER: duplicate unpaid coverage uses a caller without PAYMENT_HANDLER";
    string internal constant DEAL_15_STATUS =
        "DEAL-15-STATUS: duplicate unpaid resolution leaves the deal marked UNPAID";
    string internal constant DEAL_15_OFFER_ID =
        "DEAL-15-OFFER-ID: duplicate unpaid resolution preserves the deal offerId";
    string internal constant DEAL_15_AMOUNT = "DEAL-15-AMOUNT: duplicate unpaid resolution preserves the deal amount";
    string internal constant DEAL_15_BUYER = "DEAL-15-BUYER: duplicate unpaid resolution preserves the deal buyer";
    string internal constant DEAL_15_PRICE = "DEAL-15-PRICE: duplicate unpaid resolution preserves the deal price";
    string internal constant DEAL_15_COUNTER_OFFER_EXPIRY =
        "DEAL-15-COUNTER-OFFER-EXPIRY: duplicate unpaid resolution preserves the counter-offer expiry";
    string internal constant DEAL_15_PAYMENT_DEADLINE =
        "DEAL-15-PAYMENT-DEADLINE: duplicate unpaid resolution preserves the payment deadline";
    string internal constant DEAL_15_DISPUTE_BUFFER =
        "DEAL-15-DISPUTE-BUFFER: duplicate unpaid resolution preserves the dispute buffer";
    string internal constant DEAL_15_DEAL_TYPE =
        "DEAL-15-DEAL-TYPE: duplicate unpaid resolution preserves the deal type";
    string internal constant DEAL_16 =
        "DEAL-16: resolvePayments with any paid item rejects callers without PAYMENT_HANDLER before mutating deals";
    string internal constant DEAL_16_REVERTS = "DEAL-16-REVERTS: unauthorized mixed payment resolution reports failure";
    string internal constant DEAL_16_ERROR =
        "DEAL-16-ERROR: unauthorized mixed payment resolution reverts with Unauthorized()";
    string internal constant DEAL_16_OFFER_ID =
        "DEAL-16-OFFER-ID: unauthorized mixed payment resolution preserves each deal offerId";
    string internal constant DEAL_16_AMOUNT =
        "DEAL-16-AMOUNT: unauthorized mixed payment resolution preserves each deal amount";
    string internal constant DEAL_16_BUYER =
        "DEAL-16-BUYER: unauthorized mixed payment resolution preserves each deal buyer";
    string internal constant DEAL_16_PRICE =
        "DEAL-16-PRICE: unauthorized mixed payment resolution preserves each deal price";
    string internal constant DEAL_16_COUNTER_OFFER_EXPIRY =
        "DEAL-16-COUNTER-OFFER-EXPIRY: unauthorized mixed payment resolution preserves each counter-offer expiry";
    string internal constant DEAL_16_PAYMENT_DEADLINE =
        "DEAL-16-PAYMENT-DEADLINE: unauthorized mixed payment resolution preserves each payment deadline";
    string internal constant DEAL_16_DISPUTE_BUFFER =
        "DEAL-16-DISPUTE-BUFFER: unauthorized mixed payment resolution preserves each dispute buffer";
    string internal constant DEAL_16_STATUS =
        "DEAL-16-STATUS: unauthorized mixed payment resolution preserves each deal status";
    string internal constant DEAL_16_DEAL_TYPE =
        "DEAL-16-DEAL-TYPE: unauthorized mixed payment resolution preserves each deal type";
    string internal constant DEAL_17 = "DEAL-17: resolvePayments does not unexpectedly revert";
    string internal constant DEAL_18 =
        "DEAL-18: resolvePayments skips a paid item whose pending deal has passed its payment deadline";
    string internal constant DEAL_18_BEFORE_PENDING =
        "DEAL-18-BEFORE-PENDING: expired paid coverage starts from a pending deal";
    string internal constant DEAL_18_OFFER_ID = "DEAL-18-OFFER-ID: expired paid coverage preserves the deal offerId";
    string internal constant DEAL_18_AMOUNT = "DEAL-18-AMOUNT: expired paid coverage preserves the deal amount";
    string internal constant DEAL_18_BUYER = "DEAL-18-BUYER: expired paid coverage preserves the deal buyer";
    string internal constant DEAL_18_PRICE = "DEAL-18-PRICE: expired paid coverage preserves the deal price";
    string internal constant DEAL_18_COUNTER_OFFER_EXPIRY =
        "DEAL-18-COUNTER-OFFER-EXPIRY: expired paid coverage preserves the counter-offer expiry";
    string internal constant DEAL_18_PAYMENT_DEADLINE =
        "DEAL-18-PAYMENT-DEADLINE: expired paid coverage preserves the payment deadline";
    string internal constant DEAL_18_DISPUTE_BUFFER =
        "DEAL-18-DISPUTE-BUFFER: expired paid coverage preserves the dispute buffer";
    string internal constant DEAL_18_STATUS = "DEAL-18-STATUS: expired paid coverage preserves the deal status";
    string internal constant DEAL_18_DEAL_TYPE = "DEAL-18-DEAL-TYPE: expired paid coverage preserves the deal type";
    string internal constant DEAL_20 = "DEAL-20: settleDeal marks the selected deal with its terminal outcome";
    string internal constant DEAL_21 = "DEAL-21: settleDeal increases buyer balance by the settled amount";
    string internal constant DEAL_23 = "DEAL-23: Settling an unpaid deal leaves buyer balance unchanged";
    string internal constant DEAL_22 = "DEAL-22: settleDeal does not unexpectedly revert";
    string internal constant DEAL_24 = "DEAL-24: settleDeals leaves skipped invalid deals unchanged";
    string internal constant DEAL_30 =
        "DEAL-30: createCounterOffer creates a proposed counter-offer deal with expected fields";
    string internal constant DEAL_30_OFFER_ID = "DEAL-30.offerId: createCounterOffer stores the expected offer ID";
    string internal constant DEAL_30_BUYER = "DEAL-30.buyer: createCounterOffer stores the expected buyer";
    string internal constant DEAL_30_AMOUNT = "DEAL-30.amount: createCounterOffer stores the expected amount";
    string internal constant DEAL_30_PRICE = "DEAL-30.price: createCounterOffer stores the expected price";
    string internal constant DEAL_30_COUNTER_EXPIRY =
        "DEAL-30.counterOfferExpiry: createCounterOffer stores the expected counter-offer expiry";
    string internal constant DEAL_30_PAYMENT_DEADLINE =
        "DEAL-30.paymentDeadline: createCounterOffer initializes payment deadline to zero";
    string internal constant DEAL_30_DISPUTE_BUFFER =
        "DEAL-30.disputeBuffer: createCounterOffer initializes dispute buffer to zero";
    string internal constant DEAL_30_STATUS = "DEAL-30.status: createCounterOffer creates a PROPOSED deal";
    string internal constant DEAL_30_TYPE = "DEAL-30.dealType: createCounterOffer creates a COUNTER_OFFER deal";
    string internal constant DEAL_31 = "DEAL-31: createCounterOffer increments the deal counter by one";
    string internal constant DEAL_32 = "DEAL-32: createCounterOffer does not unexpectedly revert";
    string internal constant DEAL_40 = "DEAL-40: cancelCounterOffer marks the selected deal as CANCELLED";
    string internal constant DEAL_40_OFFER_ID = "DEAL-40.offerId: cancelCounterOffer preserves the offer ID";
    string internal constant DEAL_40_AMOUNT = "DEAL-40.amount: cancelCounterOffer preserves the amount";
    string internal constant DEAL_40_BUYER = "DEAL-40.buyer: cancelCounterOffer preserves the buyer";
    string internal constant DEAL_40_PRICE = "DEAL-40.price: cancelCounterOffer preserves the price";
    string internal constant DEAL_40_COUNTER_EXPIRY =
        "DEAL-40.counterOfferExpiry: cancelCounterOffer preserves the counter-offer expiry";
    string internal constant DEAL_40_PAYMENT_DEADLINE =
        "DEAL-40.paymentDeadline: cancelCounterOffer leaves payment deadline unset";
    string internal constant DEAL_40_DISPUTE_BUFFER =
        "DEAL-40.disputeBuffer: cancelCounterOffer leaves dispute buffer unset";
    string internal constant DEAL_40_STATUS = "DEAL-40.status: cancelCounterOffer marks the selected deal as CANCELLED";
    string internal constant DEAL_40_TYPE =
        "DEAL-40.dealType: cancelCounterOffer preserves the counter-offer deal type";
    string internal constant DEAL_41 = "DEAL-41: cancelCounterOffer does not unexpectedly revert";
    string internal constant DEAL_50 =
        "DEAL-50: resolveCounterOffer(true) converts the proposal into a pending marketplace deal";
    string internal constant DEAL_50_OFFER_ID = "DEAL-50.offerId: resolveCounterOffer(true) preserves the offer ID";
    string internal constant DEAL_50_AMOUNT = "DEAL-50.amount: resolveCounterOffer(true) preserves the amount";
    string internal constant DEAL_50_BUYER = "DEAL-50.buyer: resolveCounterOffer(true) preserves the buyer";
    string internal constant DEAL_50_PRICE = "DEAL-50.price: resolveCounterOffer(true) preserves the price";
    string internal constant DEAL_50_STATUS = "DEAL-50.status: resolveCounterOffer(true) converts the deal to PENDING";
    string internal constant DEAL_50_COUNTER_EXPIRY =
        "DEAL-50.counterOfferExpiry: resolveCounterOffer(true) clears the counter-offer expiry";
    string internal constant DEAL_50_PAYMENT_DEADLINE =
        "DEAL-50.paymentDeadline: resolveCounterOffer(true) sets a payment deadline";
    string internal constant DEAL_50_DISPUTE_BUFFER =
        "DEAL-50.disputeBuffer: resolveCounterOffer(true) sets dispute buffer from payment deadline";
    string internal constant DEAL_50_TYPE = "DEAL-50.dealType: resolveCounterOffer(true) converts the deal to OFFER";
    string internal constant DEAL_51 =
        "DEAL-51: resolveCounterOffer(false) marks the proposal declined and clears the counter-offer expiry";
    string internal constant DEAL_51_OFFER_ID = "DEAL-51.offerId: resolveCounterOffer(false) preserves the offer ID";
    string internal constant DEAL_51_AMOUNT = "DEAL-51.amount: resolveCounterOffer(false) preserves the amount";
    string internal constant DEAL_51_BUYER = "DEAL-51.buyer: resolveCounterOffer(false) preserves the buyer";
    string internal constant DEAL_51_PRICE = "DEAL-51.price: resolveCounterOffer(false) preserves the price";
    string internal constant DEAL_51_STATUS = "DEAL-51.status: resolveCounterOffer(false) marks the proposal DECLINED";
    string internal constant DEAL_51_COUNTER_OFFER_EXPIRY =
        "DEAL-51.counterOfferExpiry: resolveCounterOffer(false) clears the counter-offer expiry";
    string internal constant DEAL_51_PAYMENT_DEADLINE =
        "DEAL-51.paymentDeadline: resolveCounterOffer(false) leaves payment deadline unset";
    string internal constant DEAL_51_DISPUTE_BUFFER =
        "DEAL-51.disputeBuffer: resolveCounterOffer(false) leaves dispute buffer unset";
    string internal constant DEAL_51_DEAL_TYPE =
        "DEAL-51.dealType: resolveCounterOffer(false) preserves the counter-offer deal type";
    string internal constant DEAL_52 = "DEAL-52: resolveCounterOffer does not unexpectedly revert";
    string internal constant DEAL_60 = "DEAL-60: initiateDispute marks the selected unpaid deal as IN_DISPUTE";
    string internal constant DEAL_60_STATUS = "DEAL-60.status: initiateDispute marks the deal IN_DISPUTE";
    string internal constant DEAL_60_DISPUTE_BUFFER =
        "DEAL-60.disputeBuffer: initiateDispute preserves the dispute buffer";
    string internal constant DEAL_61 = "DEAL-61: initiateDispute does not unexpectedly revert";
    string internal constant DEAL_62 = "DEAL-62: resolveDispute stores the arbitrator status and clears disputeBuffer";
    string internal constant DEAL_62_STATUS = "DEAL-62.status: resolveDispute stores the arbitrator status";
    string internal constant DEAL_62_DISPUTE_BUFFER = "DEAL-62.disputeBuffer: resolveDispute clears disputeBuffer";
    string internal constant DEAL_63 = "DEAL-63: resolveDispute does not unexpectedly revert";
    string internal constant DEAL_64 = "DEAL-64: setDealFrozen stores the requested frozen flag";
    string internal constant DEAL_64_FROZEN = "DEAL-64.frozen: setDealFrozen stores the requested frozen flag";
    string internal constant DEAL_64_STATUS = "DEAL-64.status: setDealFrozen preserves deal status";
    string internal constant DEAL_65 = "DEAL-65: setDealFrozen does not unexpectedly revert";
    string internal constant DEAL_66 = "DEAL-66: seizeDeal marks the selected deal as SEIZED";
    string internal constant DEAL_66_STATUS = "DEAL-66.status: seizeDeal marks the deal SEIZED";
    string internal constant DEAL_66_OFFER_ID = "DEAL-66.offerId: seizeDeal preserves the parent offer ID";
    string internal constant DEAL_66_AMOUNT = "DEAL-66.amount: seizeDeal preserves the deal amount";
    string internal constant DEAL_66_BUYER = "DEAL-66.buyer: seizeDeal preserves the buyer";
    string internal constant DEAL_66_PRICE = "DEAL-66.price: seizeDeal preserves the deal price";
    string internal constant DEAL_67 = "DEAL-67: seizeDeal does not unexpectedly revert";

    string internal constant INTR_01 = "INTR-01: interestedUnits is monotonically non-decreasing";
    string internal constant INTR_10 = "INTR-10: expressInterest reserves available inventory";
    string internal constant INTR_11 = "INTR-11: expressInterest stores the expected interest fields";
    string internal constant INTR_11_OFFER_ID = "INTR-11.offerId: expressInterest stores the expected offer ID";
    string internal constant INTR_11_AMOUNT = "INTR-11.amount: expressInterest stores the expected amount";
    string internal constant INTR_11_INVESTOR = "INTR-11.investor: expressInterest stores the expected investor";
    string internal constant INTR_11_PRICE = "INTR-11.price: expressInterest stores the expected price";
    string internal constant INTR_11_STATUS = "INTR-11.status: expressInterest creates an EXPRESSED interest";
    string internal constant INTR_11_LOT_NONZERO = "INTR-11.lot: expressed-interest offer lot is non-zero";
    string internal constant INTR_11_AMOUNT_LOT_MULTIPLE =
        "INTR-11.amount: expressInterest amount is a multiple of the offer lot";
    string internal constant INTR_12 = "INTR-12: expressInterest increments the interest counter by one";
    string internal constant INTR_13 = "INTR-13: expressInterest does not unexpectedly revert";
    string internal constant INTR_20 = "INTR-20: activateInterest moves reserved interest inventory into deals";
    string internal constant INTR_21 = "INTR-21: activateInterest marks the selected interest as activated";
    string internal constant INTR_22 = "INTR-22: activateInterest creates a pending deal with expected fields";
    string internal constant INTR_22_OFFER_ID =
        "INTR-22.offerId: activateInterest creates a deal for the expected offer";
    string internal constant INTR_22_BUYER = "INTR-22.buyer: activateInterest creates a deal for the expected buyer";
    string internal constant INTR_22_AMOUNT =
        "INTR-22.amount: activateInterest creates a deal with the expected amount";
    string internal constant INTR_22_PRICE = "INTR-22.price: activateInterest creates a deal with the expected price";
    string internal constant INTR_22_PAYMENT_DEADLINE =
        "INTR-22.paymentDeadline: activateInterest gives activated interests the expected payment window";
    string internal constant INTR_22_DISPUTE_BUFFER =
        "INTR-22.disputeBuffer: activateInterest derives dispute buffer from the created payment deadline";
    string internal constant INTR_22_STATUS = "INTR-22.status: activateInterest creates a PENDING deal";
    string internal constant INTR_22_DEAL_TYPE = "INTR-22.dealType: activateInterest creates an OFFER deal";
    string internal constant INTR_23 = "INTR-23: activateInterest increments the deal counter by one";
    string internal constant INTR_24 = "INTR-24: activateInterest does not unexpectedly revert";
    string internal constant INTR_30 = "INTR-30: closeExpiredInterests marks selected interests as closed";
    string internal constant INTR_31 = "INTR-31: closeExpiredInterests releases reserved interest inventory";
    string internal constant INTR_32 = "INTR-32: closeExpiredInterests does not unexpectedly revert";
    string internal constant INTR_40 =
        "INTR-40: withdrawAvailable clears successful interest-discovery available inventory";
    string internal constant INTR_41 = "INTR-41: withdrawAvailable for interest-discovery does not unexpectedly revert";
    string internal constant INTR_42 = "INTR-42: withdrawAvailable rejects failed interest-discovery books";
    string internal constant INTR_43 = "INTR-43: failed interest-discovery cancellation clears reserved interest units";

    string internal constant PAUS_01 =
        "PAUS-01: Bond status and token pause state remain aligned for the fuzzed bond token id";

    string internal constant TKN_01 = "TKN-01: Every tracked frozen balance is bounded by its token balance";
    string internal constant TKN_10 = "TKN-10: approve writes the expected allowance";
    string internal constant TKN_11 = "TKN-11: approve does not mutate owner or spender balances";
    string internal constant TKN_12 = "TKN-12: nonzero-to-nonzero approve overwrites the allowance";
    string internal constant TKN_13 = "TKN-13: batch grantRoles rejects role bitmaps outside BaseToken.ALL_ROLES";
    string internal constant TKN_20 = "TKN-20: transfer decreases sender balance and increases receiver balance";
    string internal constant TKN_21 = "TKN-21: transferFrom via allowance spends the transferred allowance";
    string internal constant TKN_22 = "TKN-22: transferFrom via operator does not spend allowance";
    string internal constant TKN_30 = "TKN-30: setOperator stores the expected operator approval";
    string internal constant TKN_31 = "TKN-31: enabling an unregistered operator reverts";
    string internal constant TKN_40 = "TKN-40: freeze increases frozen balance without changing total balance";
    string internal constant TKN_41 = "TKN-41: unfreeze decreases frozen balance without changing total balance";
    string internal constant TKN_50 = "TKN-50: forcedTransfer moves balance and releases frozen tokens if needed";
    string internal constant TKN_51 = "TKN-51: burn decreases holder balance, frozen balance, and total supply";
    string internal constant TKN_52 = "TKN-52: forcedTransfer into protected custody reverts without mutation";
    string internal constant TKN_52_REVERT = "TKN-52.revert: forcedTransfer into protected custody must revert";
    string internal constant TKN_52_ERROR =
        "TKN-52.error: forcedTransfer into protected custody reverts with protected receiver error";
    string internal constant TKN_52_FROM_BALANCE =
        "TKN-52.from.balance: protected-receiver forcedTransfer leaves source balance unchanged";
    string internal constant TKN_52_FROM_FROZEN =
        "TKN-52.from.frozen: protected-receiver forcedTransfer leaves source frozen balance unchanged";
    string internal constant TKN_52_TO_BALANCE =
        "TKN-52.to.balance: protected-receiver forcedTransfer leaves receiver balance unchanged";
    string internal constant TKN_52_TO_FROZEN =
        "TKN-52.to.frozen: protected-receiver forcedTransfer leaves receiver frozen balance unchanged";
    string internal constant TKN_52_SUPPLY =
        "TKN-52.supply: protected-receiver forcedTransfer leaves total supply unchanged";
    string internal constant TKN_60 = "TKN-60: contract pause state matches the requested state";
    string internal constant TKN_61 =
        "TKN-61: bond suspension state and token-id pause state match the requested state";
    string internal constant TKN_62 = "TKN-62: contract pause blocks token actions";
    string internal constant TKN_63 = "TKN-63: token-id pause blocks normal transfers";
    string internal constant TKN_70 = "TKN-70: current-block account checkpoints match current account state";
    string internal constant TKN_71 = "TKN-71: future-block checkpoint queries revert";
    string internal constant TKN_80 = "TKN-80: protectAddress marks the selected address protected";
    string internal constant TKN_81 = "TKN-81: protected receivers reject third-party normal transfers";

    // EntityRegistry invariants
    string internal constant ER_01 =
        "ER-01: For every tracked entity, each account in entity.accounts[] links back to that entity with a correct 1-based entityAccountIndex";

    string internal constant ER_10 = "ER-10: Registering an entity sets its status to ENABLED with the supplied typeId";
    string internal constant ER_10_STATUS = "ER-10.status: Registering an entity sets status to ENABLED";
    string internal constant ER_10_TYPE_ID = "ER-10.typeId: Registering an entity stores the supplied typeId";
    string internal constant ER_11 = "ER-11: Registering an entity leaves its accounts array empty";
    string internal constant ER_12 = "ER-12: registerEntity does not unexpectedly revert";

    string internal constant ER_20 = "ER-20: setEntityStatus updates the entity status to the requested value";
    string internal constant ER_21 = "ER-21: setEntityStatus does not unexpectedly revert";

    string internal constant ER_30 =
        "ER-30: Accepted account registration sets status to ENABLED and links it to the correct entity";
    string internal constant ER_30_STATUS = "ER-30.status: Accepted account registration sets status to ENABLED";
    string internal constant ER_30_ENTITY_ID =
        "ER-30.entityId: Accepted account registration links it to the correct entity";
    string internal constant ER_30_REGISTERED =
        "ER-30.registered: Accepted account registration marks the account as registered";
    string internal constant ER_31 = "ER-31: Accepted account registration appends it to the entity accounts array";
    string internal constant ER_32 =
        "ER-32: requestAccountRegistration plus acceptAccountRegistration does not unexpectedly revert";
    string internal constant ER_33 =
        "ER-33: requestAccountRegistration rejects callers that are not enabled entity managers";

    string internal constant ER_40 = "ER-40: setAccountStatus updates the account status to the requested value";
    string internal constant ER_41 = "ER-41: setAccountStatus does not unexpectedly revert";

    string internal constant ER_50 = "ER-50: removeAccount clears the account record (status becomes NONE)";
    string internal constant ER_51 = "ER-51: removeAccount decrements the entity accounts array length by one";
    string internal constant ER_52 = "ER-52: removeAccount does not unexpectedly revert";

    string internal constant ER_60 = "ER-60: transferAccountToEntity links the account to the new entity";
    string internal constant ER_61 =
        "ER-61: transferAccountToEntity removes the account from the old entity accounts array";
    string internal constant ER_62 =
        "ER-62: transferAccountToEntity appends the account to the new entity accounts array";
    string internal constant ER_63 = "ER-63: transferAccountToEntity does not unexpectedly revert";

    string internal constant ER_70 = "ER-70: setEntityManager sets the manager flag to the requested value";
    string internal constant ER_71 = "ER-71: setEntityManager does not unexpectedly revert";
    string internal constant ER_80 = "ER-80: registerEntity access overload stores the supplied authority and managers";
    string internal constant ER_81 = "ER-81: EntityRegistry stores the expected metadata reference";
    string internal constant ER_82 = "ER-82: setEntityAuthority stores the expected authority";
    string internal constant ER_83 = "ER-83: setAccountRoleFlags stores the expected role bitmap";
    string internal constant ER_84 = "ER-84: EntityRegistry view surface returns expected values for enabled accounts";
    string internal constant ER_85 = "ER-85: Disabled accounts are rejected by account-gated views";
    string internal constant ER_86 = "ER-86: Disabled entities are rejected by account-gated transfer views";
    string internal constant ER_87 = "ER-87: defineEntityType stores non-zero name and caps and starts unfrozen";
    string internal constant ER_88 = "ER-88: freezeEntityType stores the frozen flag";
    string internal constant ER_89 = "ER-89: EntityRegistry grantRoles overloads grant the selected role";
    string internal constant ER_90 = "ER-90: EntityRegistry reports expected ERC165 support";
    string internal constant ER_91 =
        "ER-91: EntityRegistry account swap-and-pop keeps account and entity links consistent";
    string internal constant ER_92 = "ER-92: requestAccountRegistration stores the pending requester and role flags";
    string internal constant ER_93 =
        "ER-93: requestAccountRegistration leaves the account unregistered and entity account count unchanged";
    string internal constant ER_94 =
        "ER-94: repeated requestAccountRegistration for the same account/entity overwrites pending data";
    string internal constant ER_95 =
        "ER-95: requestAccountRegistration supports multiple pending entities for one account";
    string internal constant ER_96 =
        "ER-96: requestAccountRegistration rejects callers that are not enabled entity managers";
    string internal constant ER_97 = "ER-97: requestAccountRegistration rejects a zero account";
    string internal constant ER_98 =
        "ER-98: requestAccountRegistration rejects zero, missing, or disabled entities with the expected selector";
    string internal constant ER_99 = "ER-99: requestAccountRegistration rejects already registered accounts";
    string internal constant ER_100 =
        "ER-100: acceptAccountRegistration registers the account with the pending role flags";
    string internal constant ER_101 = "ER-101: acceptAccountRegistration increments entity account count";
    string internal constant ER_102 = "ER-102: acceptAccountRegistration deletes the accepted pending request";
    string internal constant ER_103 = "ER-103: acceptAccountRegistration rejects missing pending requests";
    string internal constant ER_104 = "ER-104: acceptAccountRegistration rejects already registered accounts";
    string internal constant ER_105 =
        "ER-105: acceptAccountRegistration rejects requests whose requester is no longer manager/admin";
    string internal constant ER_106 =
        "ER-106: failed accept after requester revocation leaves pending request data intact";
    string internal constant ER_107 =
        "ER-107: pending requests survive direct registration and account removal until accepted";
    string internal constant ER_110 = "ER-110: admin registerAccount registers the account with supplied role flags";
    string internal constant ER_111 = "ER-111: admin registerAccount increments entity account count";
    string internal constant ER_112 = "ER-112: non-admin registerAccount reverts with Unauthorized";
    string internal constant ER_113 = "ER-113: admin registerAccount rejects a zero account";
    string internal constant ER_114 =
        "ER-114: admin registerAccount rejects zero, missing, or disabled entities with the expected selector";
    string internal constant ER_115 = "ER-115: admin registerAccount rejects already registered accounts";

    string internal constant BOND_01 =
        "BOND-01: For every tracked bond version, token total supply equals mintedSupply minus total burned amount";
    string internal constant BOND_02 =
        "BOND-02: For every tracked bond version, remainingIssuableSupply plus mintedSupply equals maxSupply plus issuer-reclaimed amount";
    string internal constant BOND_03 =
        "BOND-03: For every tracked active bond version, the token pause flag equals status being Suspended";
    string internal constant BOND_04 =
        "BOND-04: For every tracked bond version, tokenId reverse mapping, token address, and computed tokenId are consistent";
    string internal constant BOND_05 =
        "BOND-05: For every tracked bond version, tranche issue counts sum to mintedSupply";
    string internal constant BOND_10 =
        "BOND-10: publishBond successor creates version equal to previous latest plus one";
    string internal constant BOND_11 = "BOND-11: publishBond successor initializes the bond with Published status";
    string internal constant BOND_12 =
        "BOND-12: publishBond successor sets mintedSupply to zero and remainingIssuableSupply to maxSupply";
    string internal constant BOND_13 = "BOND-13: publishBond does not mutate the previous active version";
    string internal constant BOND_14 = "BOND-14: publishBond does not unexpectedly revert";
    string internal constant BOND_15 = "BOND-15: publishBond successor does not change activeVersion";
    string internal constant BOND_16 =
        "BOND-16: publishBond successor writes all bond fields, including isGuaranteed, from input";
    string internal constant BOND_20 = "BOND-20: updatePublishedBond preserves tokenId and trancheCount";
    string internal constant BOND_21 =
        "BOND-21: updatePublishedBond resets remainingIssuableSupply to the new maxSupply";
    string internal constant BOND_22 = "BOND-22: updatePublishedBond keeps the bond status as Published";
    string internal constant BOND_23 = "BOND-23: updatePublishedBond does not unexpectedly revert";
    string internal constant BOND_24 =
        "BOND-24: updatePublishedBond writes all mutable bond fields and preserves isGuaranteed";
    string internal constant BOND_30 = "BOND-30: issueBond increases mintedSupply by the issued amount";
    string internal constant BOND_31 = "BOND-31: issueBond decreases remainingIssuableSupply by the issued amount";
    string internal constant BOND_32 =
        "BOND-32: issueBond appends exactly one tranche with issueCount equal to the issued amount";
    string internal constant BOND_33 = "BOND-33: issueBond increases issuer token balance by the issued amount";
    string internal constant BOND_34 = "BOND-34: issueBond increases token total supply by the issued amount";
    string internal constant BOND_35 = "BOND-35: issueBond transitions Published status to Issued on first issuance";
    string internal constant BOND_36 =
        "BOND-36: First issuance of a successor version transitions the previous active version to Replaced";
    string internal constant BOND_37 = "BOND-37: issueBond does not unexpectedly revert";
    string internal constant BOND_38 = "BOND-38: issueBond from a non-issuable status reverts with InvalidBondStatus";
    string internal constant BOND_39 =
        "BOND-39: First issuance of a successor version updates activeVersion to the issued successor";
    string internal constant BOND_40 = "BOND-40: closeIssuance sets issuanceClosed to true";
    string internal constant BOND_41 = "BOND-41: closeIssuance does not mutate the bond status";
    string internal constant BOND_42 = "BOND-42: closeIssuance does not unexpectedly revert";
    string internal constant BOND_50 = "BOND-50: cancelBond transitions Published status to Cancelled";
    string internal constant BOND_51 = "BOND-51: cancelBond does not unexpectedly revert";
    string internal constant BOND_52 =
        "BOND-52: cancelBond from a non-Published status or after issuance reverts with InvalidBondStatus or BondAlreadyIssued";
    string internal constant BOND_53 =
        "BOND-53: cancelBond preserves latestVersion and clears activeVersion only when cancelling the active draft";
    string internal constant BOND_60 = "BOND-60: suspendBond transitions Issued status to Suspended";
    string internal constant BOND_61 = "BOND-61: suspendBond pauses the bond token id";
    string internal constant BOND_62 = "BOND-62: unsuspendBond transitions Suspended status back to Issued";
    string internal constant BOND_63 = "BOND-63: unsuspendBond unpauses the bond token id";
    string internal constant BOND_64 = "BOND-64: suspendBond and unsuspendBond do not unexpectedly revert";
    string internal constant BOND_65 = "BOND-65: suspendBond from a non-Issued status reverts with InvalidBondStatus";
    string internal constant BOND_66 =
        "BOND-66: unsuspendBond from a non-Suspended status reverts with InvalidBondStatus";
    string internal constant BOND_70 = "BOND-70: closeBond requires token total supply to be zero";
    string internal constant BOND_71 = "BOND-71: closeBond transitions Issued or Suspended status to Redeemed";
    string internal constant BOND_72 = "BOND-72: closeBond does not unexpectedly revert";
    string internal constant BOND_73 =
        "BOND-73: closeBond on a non-closeable status, non-zero supply, or active version with pending Published successor reverts";
    string internal constant BOND_80 = "BOND-80: burnBond decreases the source token balance by the burned amount";
    string internal constant BOND_81 = "BOND-81: burnBond decreases token total supply by the burned amount";
    string internal constant BOND_82 = "BOND-82: burnBond does not change mintedSupply";
    string internal constant BOND_83 =
        "BOND-83: ISSUER_RECLAIM burnBond increases remainingIssuableSupply by the burned amount";
    string internal constant BOND_84 = "BOND-84: FINAL_SETTLEMENT burnBond does not change remainingIssuableSupply";
    string internal constant BOND_85 = "BOND-85: burnBond and burnBondBatch do not unexpectedly revert";
    string internal constant BOND_86 =
        "BOND-86: burnBond from a caller that is neither bond issuer nor enabled BURNER reverts with UnauthorizedBurnCaller";
    string internal constant BOND_87 =
        "BOND-87: issueBond from a caller that is neither publisher nor issuer reverts with UnauthorizedIssuer";
    string internal constant BOND_88 = "BOND-88: issueBond after closeIssuance reverts with IssuanceClosed";
    string internal constant BOND_89 = "BOND-89: issueBond with zero amount reverts with IssuanceAmountIsZero";
    string internal constant BOND_90 =
        "BOND-90: issueBond above remaining issuable supply reverts with MaxSupplyExceeded";
    string internal constant BOND_91 = "BOND-91: issueBond after maturity reverts with MaturityDateExpired";
    string internal constant BOND_92 =
        "BOND-92: closeIssuance from an invalid lifecycle status reverts with InvalidBondStatus";
    string internal constant BOND_93 =
        "BOND-93: closeIssuance from a caller that is neither publisher nor issuer reverts with UnauthorizedIssuanceCloser";
    string internal constant BOND_94 =
        "BOND-94: closeIssuance on an already closed version reverts with IssuanceClosed";
    string internal constant BOND_95 =
        "BOND-95: burnBond with a source disallowed for the burn kind reverts with InvalidBurnSource";
    string internal constant BOND_96 =
        "BOND-96: burnBond from an invalid lifecycle status reverts with InvalidBondStatus";
    string internal constant BOND_97 =
        "BOND-97: burnBondBatch with mismatched array lengths reverts with LengthMismatch";
    string internal constant BOND_98 =
        "BOND-98: burnBondBatch validates each source and reverts with InvalidBurnSource";
    string internal constant BOND_99 =
        "BOND-99: publishBond from a non-Issued active version reverts with ActiveVersionNotIssuable";
    string internal constant BOND_100 =
        "BOND-100: publishBond with an already Published successor reverts with SuccessorAlreadyPublished";
    string internal constant BOND_101 =
        "BOND-101: updatePublishedBond on a non-Published version reverts with InvalidBondStatus";
    string internal constant BOND_102 = "BOND-102: issueBond leaves the issued version in Issued status";
    string internal constant BOND_103 =
        "BOND-103: issueBond successor cutover from a Suspended active version reverts with InvalidBondStatus";
    string internal constant BOND_104 =
        "BOND-104: ISSUER_RECLAIM that includes frozen issuer inventory reverts with FrozenIssuerReclaimDenied";
    string internal constant BOND_105 = "BOND-105: rotateIssuer writes the requested replacement issuer";
    string internal constant BOND_106 = "BOND-106: rotateIssuer preserves bond lifecycle and accounting fields";
    string internal constant BOND_106_STATUS = "BOND-106.status: rotateIssuer preserves lifecycle status";
    string internal constant BOND_106_ISSUANCE_CLOSED =
        "BOND-106.issuanceClosed: rotateIssuer preserves the issuance-closed flag";
    string internal constant BOND_106_IS_GUARANTEED =
        "BOND-106.isGuaranteed: rotateIssuer preserves the guarantee flag";
    string internal constant BOND_106_TOKEN_ID_PAUSED =
        "BOND-106.tokenIdPaused: rotateIssuer preserves token pause state";
    string internal constant BOND_106_TRANCHE_COUNT = "BOND-106.trancheCount: rotateIssuer preserves tranche count";
    string internal constant BOND_106_TOKEN_ID = "BOND-106.tokenId: rotateIssuer preserves token id";
    string internal constant BOND_106_TOKEN_ADDRESS = "BOND-106.tokenAddress: rotateIssuer preserves token address";
    string internal constant BOND_106_MINTED_SUPPLY = "BOND-106.mintedSupply: rotateIssuer preserves minted supply";
    string internal constant BOND_106_REMAINING_ISSUABLE_SUPPLY =
        "BOND-106.remainingIssuableSupply: rotateIssuer preserves remaining issuable supply";
    string internal constant BOND_106_MAX_SUPPLY = "BOND-106.maxSupply: rotateIssuer preserves max supply";
    string internal constant BOND_106_TOTAL_SUPPLY = "BOND-106.totalSupply: rotateIssuer preserves token supply";
    string internal constant BOND_106_CURRENCY = "BOND-106.currency: rotateIssuer preserves currency";
    string internal constant BOND_106_NOMINAL_VALUE = "BOND-106.bondNominalValue: rotateIssuer preserves nominal value";
    string internal constant BOND_106_COUPON_RATE_TYPE =
        "BOND-106.couponRateType: rotateIssuer preserves coupon rate type";
    string internal constant BOND_106_COUPON_FREQUENCY =
        "BOND-106.couponFrequency: rotateIssuer preserves coupon frequency";
    string internal constant BOND_106_ISSUANCE_COUNTRY =
        "BOND-106.issuanceCountry: rotateIssuer preserves issuance country";
    string internal constant BOND_106_MATURITY_DATE = "BOND-106.maturityDate: rotateIssuer preserves maturity date";
    string internal constant BOND_106_COUPON_RATES_HASH =
        "BOND-106.couponRatesHash: rotateIssuer preserves coupon rates";
    string internal constant BOND_106_LATEST_VERSION = "BOND-106.latestVersion: rotateIssuer preserves latest version";
    string internal constant BOND_106_ACTIVE_VERSION = "BOND-106.activeVersion: rotateIssuer preserves active version";
    string internal constant BOND_107 = "BOND-107: rotateIssuer does not move old or new issuer token balances";
    string internal constant BOND_108 = "BOND-108: rotateIssuer does not unexpectedly revert";
    string internal constant BOND_109 =
        "BOND-109: rotateIssuer from a non-recoverable status reverts with InvalidBondStatus";
    string internal constant BOND_110 = "BOND-110: appendScoring appends and returns the expected scoring record";
    string internal constant BOND_111 = "BOND-111: appendScoring does not unexpectedly revert";
    string internal constant BOND_112 = "BOND-112: invalid appendScoring inputs revert with the expected selector";
    string internal constant BOND_113 = "BOND-113: invalid scoring reads revert with the expected selector";
    string internal constant BOND_114 = "BOND-114: BondRegistry admin surface does not unexpectedly revert";
    string internal constant BOND_115 =
        "BOND-115: protected BondRegistry admin calls revert with the expected selector";
    string internal constant BOND_116 = "BOND-116: invalid publishBond inputs revert with the expected selector";
    string internal constant BOND_117 = "BOND-117: independent bond publication does not unexpectedly revert";
    string internal constant BOND_118 = "BOND-118: BondRegistry getter surface does not unexpectedly revert";

    // AssetManager invariants
    string internal constant ASET_01 =
        "ASET-01: isAssetSupported equals enabled when enforceTokenId is false and equals enabled && isTokenIdAllowed otherwise";
    string internal constant ASET_02 =
        "ASET-02: getAssetType reverts iff config is disabled, and otherwise returns config.assetType";
    string internal constant ASET_10 = "ASET-10: setAsset stores the exact assetType/enabled/enforceTokenId fields";
    string internal constant ASET_10_TYPE = "ASET-10.assetType: setAsset stores the exact asset type";
    string internal constant ASET_10_ENABLED = "ASET-10.enabled: setAsset stores the exact enabled flag";
    string internal constant ASET_10_ENFORCE_TOKEN_ID =
        "ASET-10.enforceTokenId: setAsset stores the exact token ID enforcement flag";
    string internal constant ASET_11 = "ASET-11: setAsset preserves per-tokenId allowlist entries";
    string internal constant ASET_12 =
        "ASET-12: setAsset only reverts with ZeroAddress or AssetManager__InvalidAssetType";
    string internal constant ASET_13 =
        "ASET-13: setAsset reverts with InvalidAssetType iff enabled and assetType == NONE (and token != 0)";
    string internal constant ASET_15 =
        "ASET-15: setAsset success implies token != 0 and !(enabled && assetType == NONE)";
    string internal constant ASET_14 =
        "ASET-14: setAsset/setAssetTokenId do not mutate configs or allowlists of other tokens in the pool";
    string internal constant ASET_20 = "ASET-20: setAssetTokenId sets the allowlist entry to the provided flag";
    string internal constant ASET_21 = "ASET-21: setAssetTokenId leaves token-level asset config unchanged";
    string internal constant ASET_21_TYPE = "ASET-21.assetType: setAssetTokenId preserves asset type";
    string internal constant ASET_21_ENABLED = "ASET-21.enabled: setAssetTokenId preserves enabled flag";
    string internal constant ASET_21_ENFORCE_TOKEN_ID =
        "ASET-21.enforceTokenId: setAssetTokenId preserves token ID enforcement flag";
    string internal constant ASET_22 =
        "ASET-22: setAssetTokenId only reverts with AssetNotSupported or TokenIdAllowlistDisabled";
    string internal constant ASET_23 =
        "ASET-23: setAssetTokenId revert selector matches the first failing predicate given pre-state";
    string internal constant ASET_24 =
        "ASET-24: setAssetTokenId success implies pre-state had config.enabled and config.enforceTokenId";
    string internal constant ASET_30 = "ASET-30: validateAsset succeeds iff state admits the (token, tokenId, amount)";
    string internal constant ASET_31 = "ASET-31: validateAsset revert selector matches the first failing predicate";
    string internal constant ASET_32 = "ASET-32: validateAsset does not mutate any AssetManager state in the pool";
    string internal constant ASET_33 = "ASET-33: validateAsset returns the configured assetType on success";
    string internal constant ASET_40 = "ASET-40: setAsset called by a non-admin always reverts with Unauthorized";
    string internal constant ASET_41 =
        "ASET-41: setAssetTokenId called by a non-admin always reverts with Unauthorized";
    string internal constant ASET_42 = "ASET-42: Non-admin calls do not mutate any AssetManager state in the pool";

    string internal constant ESAU_01 =
        "ESAU-01: moduleTypeOf[m] != 0 iff isAuthorizedModule[moduleTypeOf[m]][m] == true";
    string internal constant ESAU_02 = "ESAU-02: a module address has at most one moduleType with isAuthorized == true";
    string internal constant ESAU_10 = "ESAU-10: registerModule sets moduleTypeOf and isAuthorizedModule in sync";
    string internal constant ESAU_10_MODULE_TYPE = "ESAU-10.moduleTypeOf: registerModule stores the module type";
    string internal constant ESAU_10_AUTHORIZED =
        "ESAU-10.isAuthorizedModule: registerModule authorizes the module for its type";
    string internal constant ESAU_11 = "ESAU-11: registerModule does not mutate other (type,address) pairs";
    string internal constant ESAU_11_MODULE_TYPE =
        "ESAU-11.moduleTypeOf: registerModule preserves non-target module type records";
    string internal constant ESAU_11_AUTHORIZED =
        "ESAU-11.isAuthorizedModule: registerModule preserves non-target authorization records";
    string internal constant ESAU_12 = "ESAU-12: registerModule revert selector matches the first failing predicate";
    string internal constant ESAU_13 =
        "ESAU-13: registerModule success implies pre-state moduleTypeOf[addr] == 0 and inputs non-zero";
    string internal constant ESAU_13_MODULE_TYPE =
        "ESAU-13.moduleType: registerModule success implies non-zero module type input";
    string internal constant ESAU_13_MODULE_ADDRESS =
        "ESAU-13.moduleAddress: registerModule success implies non-zero module address input";
    string internal constant ESAU_13_PRE_MODULE_TYPE =
        "ESAU-13.preModuleType: registerModule success implies the module was previously unregistered";
    string internal constant ESAU_20 = "ESAU-20: deactivateModule clears moduleTypeOf and isAuthorizedModule in sync";
    string internal constant ESAU_20_MODULE_TYPE =
        "ESAU-20.moduleTypeOf: deactivateModule clears the recorded module type";
    string internal constant ESAU_20_AUTHORIZED =
        "ESAU-20.isAuthorizedModule: deactivateModule clears module authorization";
    string internal constant ESAU_21 = "ESAU-21: deactivateModule does not mutate other (type,address) pairs";
    string internal constant ESAU_21_MODULE_TYPE =
        "ESAU-21.moduleTypeOf: deactivateModule preserves non-target module type records";
    string internal constant ESAU_21_AUTHORIZED =
        "ESAU-21.isAuthorizedModule: deactivateModule preserves non-target authorization records";
    string internal constant ESAU_22 =
        "ESAU-22: deactivateModule revert selector matches the first failing predicate, including active escrow guard";
    string internal constant ESAU_23 =
        "ESAU-23: deactivateModule success implies pre-state moduleTypeOf[addr] == moduleType and inputs non-zero";
    string internal constant ESAU_23_MODULE_TYPE =
        "ESAU-23.moduleType: deactivateModule success implies non-zero module type input";
    string internal constant ESAU_23_MODULE_ADDRESS =
        "ESAU-23.moduleAddress: deactivateModule success implies non-zero module address input";
    string internal constant ESAU_23_PRE_MODULE_TYPE =
        "ESAU-23.preModuleType: deactivateModule success implies pre-state module type matched input";
    string internal constant ESAU_30 = "ESAU-30: setAssetManager updates the wired AssetManager on success";
    string internal constant ESAU_30_ASSET_MANAGER =
        "ESAU-30.assetManager: setAssetManager stores the requested AssetManager";
    string internal constant ESAU_30_NONZERO =
        "ESAU-30.nonzero: setAssetManager success implies a non-zero AssetManager";
    string internal constant ESAU_31 = "ESAU-31: setAssetManager reverts with ZeroAddress when the new address is zero";
    string internal constant ESAU_32 = "ESAU-32: setAssetManager does not mutate the module authorization matrix";
    string internal constant ESAU_33 = "ESAU-33: setAssetManager failure implies the requested address was zero";
    string internal constant ESAU_34 = "ESAU-34: restoreAssetManager directed self-call succeeds";
    string internal constant ESAU_40 =
        "ESAU-40: createEscrow from an unregistered caller reverts with ModuleNotRegistered";
    string internal constant ESAU_41 =
        "ESAU-41: createEscrow from an unregistered caller does not mutate authorization state or nextEscrowId";
    string internal constant ESAU_41_AUTH_MATRIX =
        "ESAU-41.authMatrix: unregistered createEscrow preserves module authorization state";
    string internal constant ESAU_41_NEXT_ID = "ESAU-41.nextEscrowId: unregistered createEscrow preserves nextEscrowId";
    string internal constant ESAU_41_ASSET_MANAGER =
        "ESAU-41.assetManager: unregistered createEscrow preserves AssetManager wiring";
    string internal constant ESAU_42 = "ESAU-42: createEscrow from an unregistered caller must fail";
    string internal constant ESAU_50 =
        "ESAU-50: withdraw/claim revert selector matches state (EscrowNotFound vs ModuleNotAuthorized)";
    string internal constant ESAU_51 =
        "ESAU-51: withdraw/claim from an unauthorized caller does not mutate authorization state or nextEscrowId";
    string internal constant ESAU_51_AUTH_MATRIX =
        "ESAU-51.authMatrix: unauthorized withdraw/claim preserves module authorization state";
    string internal constant ESAU_51_NEXT_ID =
        "ESAU-51.nextEscrowId: unauthorized withdraw/claim preserves nextEscrowId";
    string internal constant ESAU_52 = "ESAU-52: withdraw/claim from an unauthorized caller must fail";
    string internal constant ESAU_60 = "ESAU-60: sweep revert selector matches the first failing predicate given state";
    string internal constant ESAU_61 = "ESAU-61: sweep does not mutate the module authorization matrix";
    string internal constant ESAU_70 =
        "ESAU-70: admin-guarded EscrowManager entrypoints revert with Unauthorized for non-admin callers";
    string internal constant ESAU_71 =
        "ESAU-71: non-admin EscrowManager attempts do not mutate authorization state or assetManager wiring";
    string internal constant ESAU_71_AUTH_MATRIX =
        "ESAU-71.authMatrix: non-admin EscrowManager attempt preserves module authorization state";
    string internal constant ESAU_71_ASSET_MANAGER =
        "ESAU-71.assetManager: non-admin EscrowManager attempt preserves AssetManager wiring";
    string internal constant ESAU_71_NEXT_ID =
        "ESAU-71.nextEscrowId: non-admin EscrowManager attempt preserves nextEscrowId";
    string internal constant ESAU_72 =
        "ESAU-72: admin-guarded EscrowManager entrypoints must fail for non-admin callers";

    string internal constant PR_10 = "PR-10: grantWalletPolicyAdmin marks the admin as granted for the wallet";
    string internal constant PR_11 = "PR-11: revokeWalletPolicyAdmin clears the admin flag for the wallet";
    string internal constant PR_12 = "PR-12: wallet policy admin mutations are scoped to the selected wallet";
    string internal constant PR_13 =
        "PR-13: wallet policy admin mutations revert only for the expected permission or state reason";

    string internal constant PR_70 = "PR-70: advancePolicyEpoch increments epoch and preserves wallet owner";
    string internal constant PR_70_EPOCH = "PR-70.epoch: advancePolicyEpoch increments the selected wallet epoch";
    string internal constant PR_70_OWNER = "PR-70.owner: advancePolicyEpoch preserves the wallet owner";
    string internal constant PR_70_INCREMENT =
        "PR-70.increment: wallet ownership transfer increments the policy epoch by one";
    string internal constant PR_70_MONOTONIC =
        "PR-70.monotonic: wallet ownership transfer strictly increases the policy epoch";
    string internal constant PR_71 = "PR-71: advancePolicyEpoch clears selected current-epoch delegated policy state";
    string internal constant PR_71_PRE_USER_ROLES =
        "PR-71.preUserRoles: policy epoch reset coverage starts with user roles present";
    string internal constant PR_71_PRE_ADMIN = "PR-71.preAdmin: policy epoch reset coverage starts with admin present";
    string internal constant PR_71_PRE_OPERATION_ROLES =
        "PR-71.preOperationRoles: policy epoch reset coverage starts with operation roles present";
    string internal constant PR_71_PRE_OPERATION_MODULE =
        "PR-71.preOperationModule: policy epoch reset coverage starts with an operation module when seeded";
    string internal constant PR_71_ADMIN = "PR-71.admin: advancePolicyEpoch clears selected delegated admin state";
    string internal constant PR_71_USER_ROLES = "PR-71.userRoles: advancePolicyEpoch clears selected user roles";
    string internal constant PR_71_OPERATION_ROLES =
        "PR-71.operationRoles: advancePolicyEpoch clears selected operation roles";
    string internal constant PR_71_OPERATION_MODULE =
        "PR-71.operationModule: advancePolicyEpoch clears selected operation module";
    string internal constant PR_71_CAN_EXECUTE =
        "PR-71.canExecute: advancePolicyEpoch invalidates selected delegated execution";
    string internal constant PR_72 = "PR-72: advancePolicyEpoch reverts only for unauthorized caller or zero reason";
    string internal constant PR_73 =
        "PR-73: failed advancePolicyEpoch preserves selected epoch and delegated policy state";
    string internal constant PR_73_EPOCH = "PR-73.epoch: failed advancePolicyEpoch preserves the selected epoch";
    string internal constant PR_73_OWNER = "PR-73.owner: failed advancePolicyEpoch preserves the wallet owner";
    string internal constant PR_73_ADMIN = "PR-73.admin: failed advancePolicyEpoch preserves selected admin state";
    string internal constant PR_73_USER_ROLES =
        "PR-73.userRoles: failed advancePolicyEpoch preserves selected user roles";
    string internal constant PR_73_OPERATION_ROLES =
        "PR-73.operationRoles: failed advancePolicyEpoch preserves selected operation roles";
    string internal constant PR_73_OPERATION_MODULE =
        "PR-73.operationModule: failed advancePolicyEpoch preserves selected operation module";
    string internal constant PR_73_CAN_EXECUTE =
        "PR-73.canExecute: failed advancePolicyEpoch preserves selected delegated execution";
    string internal constant PR_74 = "PR-74: advancePolicyEpoch preserves sibling wallet policy state";
    string internal constant PR_74_EPOCH = "PR-74.epoch: advancePolicyEpoch preserves sibling wallet epoch";
    string internal constant PR_74_OWNER = "PR-74.owner: advancePolicyEpoch preserves sibling wallet owner";
    string internal constant PR_74_ADMIN = "PR-74.admin: advancePolicyEpoch preserves sibling admin state";
    string internal constant PR_74_USER_ROLES = "PR-74.userRoles: advancePolicyEpoch preserves sibling user roles";
    string internal constant PR_74_OPERATION_ROLES =
        "PR-74.operationRoles: advancePolicyEpoch preserves sibling operation roles";
    string internal constant PR_74_OPERATION_MODULE =
        "PR-74.operationModule: advancePolicyEpoch preserves sibling operation module";
    string internal constant PR_74_CAN_EXECUTE =
        "PR-74.canExecute: advancePolicyEpoch preserves sibling delegated execution";
    string internal constant PR_75 =
        "PR-75: advancePolicyEpoch harness pre-state contains reachable delegated policy state";
    string internal constant PR_75_ADMIN = "PR-75.admin: advancePolicyEpoch pre-state has selected admin";
    string internal constant PR_75_USER_ROLES = "PR-75.userRoles: advancePolicyEpoch pre-state has selected user roles";
    string internal constant PR_75_OPERATION_ROLES =
        "PR-75.operationRoles: advancePolicyEpoch pre-state has selected operation roles";
    string internal constant PR_75_OPERATION_MODULE =
        "PR-75.operationModule: advancePolicyEpoch pre-state has selected operation module";
    string internal constant PR_75_CAN_EXECUTE =
        "PR-75.canExecute: advancePolicyEpoch pre-state has reachable delegated execution";
    string internal constant PR_76 = "PR-76: Policy allow-module seed call succeeds";
    string internal constant PR_77 = "PR-77: Policy owner seed call succeeds";

    string internal constant PR_20 = "PR-20: grantUserRoles ORs new roles into the existing user bitmap";
    string internal constant PR_21 = "PR-21: revokeUserRoles clears exactly the requested user-role bits";
    string internal constant PR_22 = "PR-22: setUserRoles stores the exact user-role bitmap";
    string internal constant PR_23 = "PR-23: user role mutations are scoped to the selected wallet";
    string internal constant PR_24 =
        "PR-24: user role mutations revert only for the expected permission or bitmap reason";

    string internal constant PR_30 = "PR-30: grantOperationRoles ORs new roles into the operation bitmap";
    string internal constant PR_31 = "PR-31: revokeOperationRoles clears exactly the requested operation-role bits";
    string internal constant PR_32 = "PR-32: setOperationRoles stores the exact operation-role bitmap";
    string internal constant PR_33 = "PR-33: operation role mutations are scoped to the selected wallet";
    string internal constant PR_34 =
        "PR-34: operation role mutations revert only for the expected permission or bitmap reason";

    string internal constant PR_40 = "PR-40: setOperationModule stores the selected module for the operation";
    string internal constant PR_41 = "PR-41: operation module mutations are scoped to the selected wallet";
    string internal constant PR_42 =
        "PR-42: operation module updates revert only for unauthorized callers or disallowed modules";

    string internal constant PR_50 = "PR-50: setPolicyModuleAllowed stores the exact module allowlist status";
    string internal constant PR_51 = "PR-51: setRoleLabel stores the exact role label";
    string internal constant PR_52 = "PR-52: setPolicyModuleAllowed does not unexpectedly revert";
    string internal constant PR_53 = "PR-53: setRoleLabel does not unexpectedly revert when called by the owner";

    string internal constant PR_60 = "PR-60: canExecute matches the harness model for roles and modules";
    string internal constant PR_61 = "PR-61: checkOperationModule diagnostics match the configured module state";
    string internal constant PR_61_HAS_MODULE =
        "PR-61.hasModule: checkOperationModule reports whether the operation has a module";
    string internal constant PR_61_MODULE =
        "PR-61.module: checkOperationModule reports the configured operation module";
    string internal constant PR_61_MODULE_ALLOWED =
        "PR-61.moduleAllowed: checkOperationModule reports module allowlist status";
    string internal constant PR_61_MODULE_CALL_SUCCEEDED =
        "PR-61.moduleCallSucceeded: checkOperationModule reports whether module call returned a valid bool";
    string internal constant PR_61_MODULE_AUTHORIZED =
        "PR-61.moduleAuthorized: checkOperationModule reports module authorization result";
    string internal constant PR_62 =
        "PR-62: CompanyWallet.execute follows owner bypass plus PolicyRegistry authorization";
    string internal constant PR_62_SUCCESS =
        "PR-62.success: CompanyWallet.execute success matches expected authorization";
    string internal constant PR_62_ERROR = "PR-62.error: unauthorized CompanyWallet.execute reverts with Unauthorized";
    string internal constant PR_62_CALL_COUNT =
        "PR-62.callCount: CompanyWallet.execute mutates target call count only on success";
    string internal constant PR_62_LAST_CALLER =
        "PR-62.lastCaller: successful CompanyWallet.execute calls the target as the wallet";
    string internal constant PR_62_FLAG = "PR-62.flag: CompanyWallet.execute applies or preserves target flag state";
    string internal constant PR_62_NUMBER =
        "PR-62.number: CompanyWallet.execute applies or preserves target number state";
    string internal constant PR_63 = "PR-63: computeOperationKey equals keccak256(abi.encode(target, selector))";
    string internal constant PR_64 = "PR-64: CompanyWallet directed admin and view calls do not unexpectedly revert";
    string internal constant PR_65 =
        "PR-65: CompanyWallet renounceOwnership reverts with the disabled-renounce selector";

    string internal constant DEP_01 =
        "DEP-01: A non-zero dependency slot is never overwritten with a different address";
    string internal constant DEP_02 = "DEP-02: A dependency slot that was non-zero never resets to zero";
    string internal constant DEP_03 = "DEP-03: Unauthorized callers cannot set a dependency (G-7)";
    string internal constant DEP_04 =
        "DEP-04: Setting an already-wired dependency reverts with the matching AlreadySet error";
    string internal constant WALLET_01 =
        "WALLET-01: An ownership change increments the wallet ownership epoch by exactly +1";
    string internal constant WALLET_02 = "WALLET-02: The wallet ownership epoch never decreases";
    string internal constant WALLET_03 = "WALLET-03: The wallet ownership epoch is initialized to 1";
    string internal constant WALLET_04 = "WALLET-04: A non-ownership-change operation leaves the epoch unchanged";
    string internal constant WALLET_12 = "WALLET-12: transferOwnership does not revert unexpectedly";
    string internal constant WALLET_22 = "WALLET-22: execute does not revert unexpectedly";
    string internal constant WALLET_G8 =
        "WALLET-G8: execute rejects an invalid target (address(0), the wallet itself, or an EOA)";
    string internal constant WALLET_G9 =
        "WALLET-G9: a non-owner execute succeeds iff PolicyRegistry.canExecute returns true (X-3)";
    string internal constant TL_G15 = "TL-G15: An operation is only scheduled with delay >= getMinDelay()";
    string internal constant TL_G16_READY = "TL-G16: A successful execute had the operation in Ready state";
    string internal constant TL_G16_PREDECESSOR = "TL-G16: A successful execute had its predecessor already done";
    string internal constant TL_I8_NO_REGRESSION = "TL-I8: A Done operation never regresses to a non-Done state";
    string internal constant TL_I8_READY_TO_DONE = "TL-I8: A successful execute transitions the op Ready -> Done";
    string internal constant TL_I8_NO_REPLAY =
        "TL-I8: Executing an unset/non-ready operation never succeeds (no replay)";
    string internal constant TL_E1 =
        "TL-E1: An operation's effective timestamp is never earlier than scheduleTime + minDelay";
    string internal constant TL_UPDATE_DELAY = "TL-UPDATE-DELAY: updateDelay stores the exact new minimum delay";
}

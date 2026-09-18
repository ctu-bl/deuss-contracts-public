// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @notice Represents the frequency of coupon payments
 * @param Annual 1 payment per year
 * @param SemiAnnual 2 payments per year
 * @param Quarterly 4 payments per year
 * @param Monthly 12 payments per year
 * @param Daily 360 payments per year
 */
enum CouponFrequency {
    Annual,
    SemiAnnual,
    Quarterly,
    Monthly,
    Daily
}

/**
 * @notice Represents the status of a bond
 * @param Unregistered Bond is not registered
 * @param Published Bond has been published and is awaiting issuance
 * @param Issued Bond has been issued
 * @param Suspended Bond is temporarily suspended
 * @param Redeemed Bond has been fully redeemed through principal redemption flow
 * @param Cancelled Bond has been cancelled
 * @param Replaced Bond has been replaced by another bond
 */
enum BondStatus {
    Unregistered,
    Published,
    Issued,
    Suspended,
    Redeemed,
    Cancelled,
    Replaced
}

/**
 * @notice Represents the protocol meaning of a bond burn.
 * @param ISSUER_RECLAIM Issuer reclaim burn that reopens future issuance capacity
 * @param FINAL_SETTLEMENT Settlement burn that only reduces live supply
 */
enum BurnKind {
    ISSUER_RECLAIM,
    FINAL_SETTLEMENT
}

/**
 * @notice Represents the status of a company wallet in the bond registry
 * @param Unregistered Company wallet is not registered
 * @param Registered Company wallet is registered
 * @param Suspended Company wallet is suspended
 */
enum CompanyAccountStatus {
    Unregistered,
    Registered,
    Suspended
}

/**
 * @notice Represents the type of coupon payments
 * @param ZERO_COUPON No coupon payments
 * @param FIXED Fixed rate for entire bond lifetime
 * @param FLOATING Floating rate - Variable rates that can change over time
 */
enum CouponRateType {
    ZERO_COUPON,
    FIXED,
    FLOATING
}

/**
 * @notice Represents metadata for a company wallet in the bond registry
 * @param owner Address of the company wallet owner
 * @param status Current status of the company wallet
 */
struct CompanyWalletMetadata {
    address owner;
    CompanyAccountStatus status;
}

/**
 * @notice Represents coupon rates for a bond
 * @param paymentTimestamps Inclusive timestamp checkpoints at which coupon rates become effective
 * @param rates Corresponding coupon rates for each timestamp checkpoint, expressed in basis points
 */
struct CouponRates {
    uint256[] paymentTimestamps;
    uint256[] rates;
}

/**
 * @notice Represents a bond — shared economics and token identity for one ISIN/version
 * @param isin ISIN code of the bond
 * @param issuer Address of the bond issuer
 * @param tokenAddress Token contract address used for this bond version
 * @param status Current status of the bond
 * @param couponFrequency Frequency of coupon payments
 * @param trancheCount Number of tranches issued so far
 * @param currency Currency code of the bond
 * @param couponRateType Type of coupon payments
 * @param bondNominalValue Nominal (face) value of the bond
 * @param maxSupply Maximum live (concurrently outstanding) supply capacity. Issuer-reclaim burns restore
 *        `remainingIssuableSupply`, so this caps reissuable headroom, not the total amount ever issued
 * @param mintedSupply Cumulative amount ever issued across all tranches. Monotonically increasing; never reduced
 *        by burns. Live/circulating supply is the token contract's `totalSupply(tokenId)`, not this value
 * @param maturityDate Maturity date of the bond
 * @param tokenId Token Id
 * @param couponRates Coupon rates for the bond, expressed in basis points
 * @param remainingIssuableSupply Remaining issuance headroom against `maxSupply`; decreased on issue, restored
 *        on issuer-reclaim burn
 * @param issuanceClosed Permanent flag blocking future issuance
 * @param isGuaranteed Whether this bond version is backed by a guarantee
 * @param issuanceCountry Numeric ISO 3166 country code of the bond issuance
 */
// solhint-disable-next-line gas-struct-packing
struct Bond {
    bytes12 isin;
    address issuer;
    address tokenAddress;
    BondStatus status;
    CouponFrequency couponFrequency;
    uint16 trancheCount;
    bytes3 currency;
    CouponRateType couponRateType;
    uint256 bondNominalValue;
    uint256 maxSupply;
    uint256 mintedSupply;
    uint256 maturityDate;
    uint256 tokenId;
    CouponRates couponRates;
    uint256 remainingIssuableSupply;
    bool issuanceClosed;
    bool isGuaranteed;
    uint16 issuanceCountry;
}

/**
 * @notice Represents one issuance slice (tranche) under a bond
 * @param issueDate Timestamp when this tranche was issued
 * @param issueCount Number of tokens issued in this tranche
 */
struct Tranche {
    uint256 issueDate;
    uint256 issueCount;
}

/**
 * @notice Represents a scoring record for an issuer wallet
 * @param defaultProbabilityBps Issuer default probability in basis points (0..10_000, where 10_000 = 100%)
 * @param issueDate Timestamp when the scoring was issued (must be non-zero)
 * @param expirationDate Timestamp when the scoring expires (must be greater than issueDate)
 * @param distributorId Fixed-size identifier of the scoring distributor (must be non-zero)
 */
struct Scoring {
    uint16 defaultProbabilityBps;
    uint64 issueDate;
    uint64 expirationDate;
    bytes32 distributorId;
}

/**
 * @notice Represents input data for creating a bond
 * @param isin ISIN code of the bond. Must be 12 bytes using the StringExtensions ISIN charset rules
 * @param currency Currency code of the bond. Must be exactly 3 uppercase ASCII letters.
 * @param bondNominalValue Nominal (face) value of the bond
 * @param maxSupply Maximum live (concurrently outstanding) supply capacity; reissuable headroom, not total ever issued
 * @param couponRates Coupon rates for the bond, expressed in basis points
 * @param couponRateType Type of coupon payments
 * @param maturityDate Maturity date of the bond
 * @param couponFrequency Frequency of coupon payments
 * @param issuer Bond issuer
 * @param isGuaranteed Whether this bond version is backed by a guarantee
 * @param issuanceCountry Numeric ISO 3166 country code of the bond issuance
 */
// solhint-disable-next-line gas-struct-packing
struct BondInput {
    string isin;
    string currency;
    uint256 bondNominalValue;
    uint256 maxSupply;
    CouponRates couponRates;
    CouponRateType couponRateType;
    uint256 maturityDate;
    CouponFrequency couponFrequency;
    address issuer;
    bool isGuaranteed;
    uint16 issuanceCountry;
}

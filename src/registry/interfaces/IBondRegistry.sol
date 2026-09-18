// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// DEUSS:
import {
    Bond,
    BondInput,
    BondStatus,
    BurnKind,
    CouponFrequency,
    CouponRateType,
    Scoring,
    Tranche
} from "../BondStructs.sol";

/**
 * @title IBondRegistry
 * @author DEUSS Team
 * @notice The IBondRegistry interface defines the functions and events for managing bond registrations
 */
interface IBondRegistry is IERC165 {
    /**
     * @notice This event is emitted when a currency's allowed status is updated
     * @param currency The 3-letter ISO 4217 currency code (bytes3)
     * @param allowed True if the currency is allowed, false if disabled
     * @param changedBy The address who updated the currency status
     */
    event AllowedCurrencyUpdated(bytes3 indexed currency, bool indexed allowed, address indexed changedBy);

    /**
     * @notice Emitted when a bond is cancelled before issuance
     * @dev Emitted by the `cancelBond` function
     * @param isin The ISIN of the cancelled bond
     * @param version The cancelled bond version
     * @param executor The address that executed the close
     */
    event BondCancelled(bytes12 indexed isin, uint8 indexed version, address indexed executor);

    /**
     * @notice Emitted when a bond tranche is issued and tokens are minted
     * @param isin The ISIN of the issued bond
     * @param tokenId Token Id
     * @param amount The number of tokens minted for this tranche
     * @param trancheId The sequential tranche identifier
     * @param version The bond version
     * @param caller The address that called `issueBond`
     */
    event BondIssued(
        bytes12 indexed isin,
        uint256 indexed tokenId,
        uint256 indexed amount,
        uint16 trancheId,
        uint8 version,
        address caller
    );
    // BondIssued keeps the original compact shape.

    /**
     * @notice Emitted when bond tokens are burned through the registry
     * @param isin The ISIN of the burned bond
     * @param version The burned bond version
     * @param from The source account whose tokens were burned
     * @param amount The amount burned
     * @param kind The burn semantic applied to accounting
     * @param caller The address that called the burn entrypoint
     */
    event BondBurned(
        bytes12 indexed isin, uint8 version, address indexed from, uint256 indexed amount, BurnKind kind, address caller
    );

    /**
     * @notice Emitted when a bond is published with immutable issuance metadata.
     * @param isin The ISIN of the published bond.
     * @param issuer The issuer address.
     * @param version The published bond version.
     * @param tokenId The associated token ID.
     * @param tokenAddress The shared token contract address.
     * @param currency The bond currency code.
     * @param bondNominalValue The nominal value represented by one bond token.
     * @param maxSupply The maximum live (reissuable) supply capacity for the bond, not the total amount ever issued.
     * @param maturityDate The bond maturity timestamp.
     * @param couponFrequency The coupon payment frequency.
     * @param couponRateType The coupon rate type.
     * @param isGuaranteed True if the bond is guaranteed.
     * @param issuanceCountry The issuance country code.
     * @param publisher The address that published the bond.
     */
    event BondPublished(
        bytes12 indexed isin,
        address indexed issuer,
        uint8 indexed version,
        uint256 tokenId,
        address tokenAddress,
        bytes3 currency,
        uint256 bondNominalValue,
        uint256 maxSupply,
        uint256 maturityDate,
        CouponFrequency couponFrequency,
        CouponRateType couponRateType,
        bool isGuaranteed,
        uint16 issuanceCountry,
        address publisher
    );

    /**
     * @notice Emitted when a published bond is updated with the resulting bond metadata.
     * @param isin The ISIN of the bond.
     * @param version The new version number.
     * @param publisher The address that updated the bond.
     * @param issuer The issuer address.
     * @param tokenId The associated token ID.
     * @param tokenAddress The shared token contract address.
     * @param currency The bond currency code.
     * @param bondNominalValue The nominal value represented by one bond token.
     * @param maxSupply The maximum live (reissuable) supply capacity for the bond, not the total amount ever issued.
     * @param maturityDate The bond maturity timestamp.
     * @param couponFrequency The coupon payment frequency.
     * @param couponRateType The coupon rate type.
     * @param isGuaranteed True if the bond is guaranteed.
     * @param issuanceCountry The issuance country code.
     */
    event PublishedBondUpdated(
        bytes12 indexed isin,
        uint8 indexed version,
        address indexed publisher,
        address issuer,
        uint256 tokenId,
        address tokenAddress,
        bytes3 currency,
        uint256 bondNominalValue,
        uint256 maxSupply,
        uint256 maturityDate,
        CouponFrequency couponFrequency,
        CouponRateType couponRateType,
        bool isGuaranteed,
        uint16 issuanceCountry
    );

    /**
     * @notice Emitted when a bond is redeemed and subsequently closed
     * @dev Emitted by the `closeBond` function
     * @param isin The bond ISIN
     * @param version The redeemed bond version
     * @param executor The address that executed the close
     */
    event BondRedeemed(bytes12 indexed isin, uint8 indexed version, address indexed executor);

    /**
     * @notice Emitted when a bond is suspended
     * @param isin The ISIN of the suspended bond
     * @param version The suspended bond version
     * @param executor The address that executed the suspension
     */
    event BondSuspended(bytes12 indexed isin, uint8 indexed version, address indexed executor);

    /**
     * @notice Emitted when a bond suspension is lifted
     * @param isin The ISIN of the unsuspended bond
     * @param version The unsuspended bond version
     * @param executor The address that lifted the suspension
     */
    event BondUnsuspended(bytes12 indexed isin, uint8 indexed version, address indexed executor);

    /**
     * @notice Emitted when future issuance is permanently closed for a bond
     * @param isin The bond ISIN
     * @param version The bond version whose issuance was closed
     * @param caller The address that closed issuance
     */
    event BondIssuanceClosed(bytes12 indexed isin, uint8 indexed version, address indexed caller);

    /**
     * @notice Emitted when governance rotates a bond issuer for recovery.
     * @param isin The bond ISIN.
     * @param version The exact bond version whose issuer was rotated.
     * @param oldIssuer The previous issuer wallet.
     * @param newIssuer The replacement issuer wallet.
     * @param reason Operator-supplied recovery reason code.
     * @param caller The address that executed the rotation.
     */
    event BondIssuerRotated(
        bytes12 indexed isin,
        uint8 version,
        address indexed oldIssuer,
        address indexed newIssuer,
        bytes32 reason,
        address caller
    );

    /**
     * @notice Emitted when the token contract address is set with previous and new addresses.
     * @param previousMultiToken The previous token contract address.
     * @param multiToken The new token contract address.
     */
    event MultiTokenSet(address indexed previousMultiToken, address indexed multiToken);

    /**
     * @notice Emitted when a new scoring record is appended for an issuer wallet
     * @param wallet The issuer wallet address the scoring belongs to
     * @param scoringId The 1-based, wallet-local ID assigned to this scoring record
     * @param defaultProbabilityBps Issuer default probability in basis points
     * @param issueDate Timestamp when the scoring was issued
     * @param expirationDate Timestamp when the scoring expires
     * @param distributorId Fixed-size identifier of the scoring distributor
     * @param caller The address that called `appendScoring`
     */
    event ScoringAppended(
        address indexed wallet,
        uint256 indexed scoringId,
        uint16 defaultProbabilityBps,
        uint64 issueDate,
        uint64 expirationDate,
        bytes32 distributorId,
        address indexed caller
    );

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the owner to grant specified `roles` to a `user`
     * @dev See {OwnableRoles::grantRoles} for more details
     * @param user The address of the user receiving the roles
     * @param roles The roles to be granted
     */
    function grantRoles(address user, uint256 roles) external payable;

    /**
     * @notice Allows the owner to grant specified `roles` to an array of `users`
     * @dev See {OwnableRolesExtension::grantRoles} for more details
     * @param users The addresses of the users receiving the roles
     * @param roles The roles to be granted
     */
    function grantRoles(address[] calldata users, uint256 roles) external payable;

    /**
     * @notice Sets the shared ERC6909 token contract where all bond tokens are minted
     * @param multiToken The address of the ERC6909 token contract
     */
    function setMultiToken(address multiToken) external;

    /*//////////////////////////////////////////////////////////////
                        ROLE-GATED BOND FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cancels a bond version before issuance
     * @dev Can only be called by an address with the cancel role. Bond must be the latest version,
     *      in Published status, and have zero tranches. Cancellation preserves latestVersion so
     *      later republishes use a fresh version/tokenId, and clears activeVersion when the cancelled
     *      version was the active unissued draft.
     * @param isin The ISIN of the bond to cancel
     * @param version The explicit version to cancel
     */
    function cancelBond(string calldata isin, uint8 version) external;

    /**
     * @notice Closes a bond version after supply has reached zero
     * @dev Bond must be in a closeable status and have zero token total supply.
     *      If the target is the active version, no later successor may be pending in Published status.
     *      This entrypoint is reserved for principal redemption flow semantics.
     *      This function can only be called by an address with the close role.
     * @param isin The ISIN of the bond to be closed
     * @param version The explicit version to close
     */
    function closeBond(string memory isin, uint8 version) external;

    /**
     * @notice Permanently blocks future issuance for a bond version
     * @dev Callable only by the bond issuer or an address with PUBLISHER role.
     *      Bond must already be in Issued or Suspended status; Published bonds should be cancelled instead.
     * @param isin The ISIN of the bond
     * @param version The explicit version to close issuance for
     */
    function closeIssuance(string calldata isin, uint8 version) external;

    /**
     * @notice Rotates the stored issuer for a bond version during exceptional recovery.
     * @dev Callable only by an address with ISSUER_RECOVERY role.
     *      The target version must be Published, Issued, Suspended, or Replaced.
     *      This updates registry metadata only; token balances and marketplace positions are recovered separately.
     * @param isin The ISIN of the bond
     * @param version The exact version whose issuer should be rotated
     * @param newIssuer The enabled replacement issuer wallet
     * @param reason Non-zero operator reason code for auditability
     */
    function rotateIssuer(string calldata isin, uint8 version, address newIssuer, bytes32 reason) external;

    /**
     * @notice Burns bond tokens through the registry using the specified burn semantics
     * @dev ISSUER_RECLAIM can burn only unfrozen issuer-held balance because it restores issuance capacity.
     * @param isin The bond ISIN as bytes12
     * @param version The explicit bond version to burn from
     * @param from The source account whose tokens will be burned
     * @param amount The amount to burn
     * @param kind The economic meaning of the burn
     */
    function burnBond(bytes12 isin, uint8 version, address from, uint256 amount, BurnKind kind) external;

    /**
     * @notice Burns bond tokens from multiple source accounts through the registry
     * @dev ISSUER_RECLAIM can burn only unfrozen issuer-held balance because it restores issuance capacity.
     * @param isin The bond ISIN as bytes12
     * @param version The explicit bond version to burn from
     * @param froms The source accounts whose tokens will be burned
     * @param amounts The amounts to burn per source account
     * @param kind The economic meaning applied to the whole batch
     */
    function burnBondBatch(
        bytes12 isin,
        uint8 version,
        address[] calldata froms,
        uint256[] calldata amounts,
        BurnKind kind
    ) external;

    /**
     * @notice Issues a tranche of a specific bond version by minting tokens to the issuer
     * @dev Callable only by an address with PUBLISHER role or by the bond issuer.
     *      Each call creates a new tranche record and mints `amount` tokens.
     *      If this is the first issuance of a successor version, activeVersion is switched and the previous active is marked Replaced.
     * @param isin The ISIN of the bond to issue
     * @param version The explicit version to issue
     * @param amount The number of tokens to issue in this tranche
     */
    function issueBond(string memory isin, uint8 version, uint256 amount) external;

    /**
     * @notice Publishes a new bond to the registry
     * @dev Can only be called by an address with the publisher role.
     * @param bondInput The bond input data
     */
    function publishBond(BondInput calldata bondInput) external;

    /**
     * @notice Sets the allowed status for a given currency code
     * @dev Callable only by addresses with the currency role.
     *      Disabling a currency does not retroactively invalidate published bond versions that already use it.
     * @param currencyCode The 3-letter uppercase ISO 4217-style currency code as a string (e.g., "USD", "EUR")
     * @param allowed True to allow the currency, false to disable it
     */
    function setAllowedCurrency(string memory currencyCode, bool allowed) external;

    /**
     * @notice Suspends a bond, temporarily halting its operations
     * @dev If a caller does not have the suspend role the function call will fail.
     * Once suspended, the bond cannot be interacted with until reactivated.
     * This function can be called even if the linked token contract is globally paused.
     * @param isin The ISIN of the bond to be suspended
     * @param version The explicit version to suspend
     */
    function suspendBond(string memory isin, uint8 version) external;

    /**
     * @notice Unsuspends a bond, restoring its normal operations
     * @dev If a caller does not have the unsuspend role the function call will fail.
     * Once unsuspended, the bond can be interacted with as usual.
     * This function can be called only when the linked token contract is not globally paused.
     * @param isin The ISIN of the bond to be unsuspended
     * @param version The explicit version to unsuspend
     */
    function unsuspendBond(string memory isin, uint8 version) external;

    /**
     * @notice Amends an existing published bond version in place
     * @dev Can only be called by an address with the publisher role.
     *      This is amendment-only: it does NOT create a new version. The bond must already be in Published status.
     *      Changing currency requires the new currency to be allowed; keeping the stored currency is allowed even if
     *      that currency was disabled after publication.
     *      `bondInput.isGuaranteed` must match the stored value for this bond version.
     * @param bondInput The updated bond input data
     * @param version The explicit Published version to amend
     */
    function updatePublishedBond(BondInput calldata bondInput, uint8 version) external;

    /**
     * @notice Appends a new scoring record for an issuer wallet
     * @dev Only callable by addresses with the SCORING role.
     *      Scoring history is append-only; each call assigns the next 1-based wallet-local ID.
     * @param wallet The issuer wallet address to score
     * @param scoring The scoring data to append
     */
    function appendScoring(address wallet, Scoring calldata scoring) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the bond status for the specified ISIN
     * @param isin The bond ISIN as string
     * @return The bond status
     */
    function bondStatus(string memory isin) external view returns (BondStatus);

    /**
     * @notice Retrieves the bond status for the specified ISIN
     * @param isin The bond ISIN as bytes12
     * @return The bond status
     */
    function bondStatus(bytes12 isin) external view returns (BondStatus);

    /**
     * @notice Returns the latest bond data for a given ISIN
     * @param isin The ISIN as bytes12
     * @return The corresponding `Bond` data.
     */
    function getBond(bytes12 isin) external view returns (Bond memory);

    /**
     * @notice Returns the latest bond data for a given ISIN
     * @param isin The ISIN as string
     * @return The corresponding `Bond` data.
     */
    function getBond(string memory isin) external view returns (Bond memory);

    /**
     * @notice Returns bond data for a given ISIN and version
     * @param isin The ISIN as bytes12
     * @param version The version number
     * @return The corresponding Bond data
     */
    function getBondAtVersion(bytes12 isin, uint8 version) external view returns (Bond memory);

    /**
     * @notice Returns bond data for an exact tokenId
     * @param tokenId Token identifier derived from `(isin, version)`, where versions are never reused after cancellation
     * @return The corresponding Bond data
     */
    function getBondByTokenId(uint256 tokenId) external view returns (Bond memory);

    /**
     * @notice Returns the exact `(isin, version)` pair for a tokenId
     * @param tokenId Token identifier derived from `(isin, version)`, where versions are never reused after cancellation
     * @return isin The bond ISIN
     * @return version The explicit bond version
     */
    function getBondSeriesByTokenId(uint256 tokenId) external view returns (bytes12 isin, uint8 version);

    /**
     * @notice Returns the active version number for a given ISIN
     * @dev The active version is the issuer-designated current series for ISIN-only reads
     * @param isin The ISIN as bytes12
     * @return The active version number (0 if ISIN has no bonds)
     */
    function getActiveVersion(bytes12 isin) external view returns (uint8);

    /**
     * @notice Returns the latest created version number for a given ISIN
     * @dev The latest version is the highest version ever published, which may differ from activeVersion
     * @param isin The ISIN as bytes12
     * @return The latest created version number (0 if ISIN has no bonds)
     */
    function getLatestVersion(bytes12 isin) external view returns (uint8);

    /**
     * @notice Returns a specific tranche for a bond by ISIN, version, and tranche ID
     * @param isin The ISIN as bytes12
     * @param version The explicit version
     * @param trancheId The tranche identifier (starts at 1)
     * @return The tranche data
     */
    function getTranche(bytes12 isin, uint8 version, uint16 trancheId) external view returns (Tranche memory);

    /**
     * @notice Checks whether the specified currency is allowed for bond issuance
     * @dev Returns true if the currency is marked as allowed in the internal mapping.
     *      Malformed strings revert during StringExtensions conversion before the mapping lookup.
     * @param currencyCode The 3-letter uppercase ISO 4217-style currency code as a string (e.g., "USD", "EUR")
     * @return True if the currency is allowed, false otherwise
     */
    function isCurrencyAllowed(string memory currencyCode) external view returns (bool);

    /**
     * @notice Returns a specific tranche for a bond by ISIN and tranche ID
     * @param isin The ISIN as bytes12
     * @param trancheId The tranche identifier (starts at 1)
     * @return The tranche data
     */
    function getTranche(bytes12 isin, uint16 trancheId) external view returns (Tranche memory);

    /**
     * @notice Returns the latest tranche for a bond
     * @param isin The ISIN as bytes12
     * @return The latest tranche data
     */
    function getLatestTranche(bytes12 isin) external view returns (Tranche memory);

    /**
     * @notice Returns the tranche count for a bond
     * @param isin The ISIN as bytes12
     * @return The number of tranches
     */
    function getTrancheCount(bytes12 isin) external view returns (uint16);

    /**
     * @notice Convenience getter: returns tranche 1 for a bond (common single-tranche case)
     * @param isin The ISIN as bytes12
     * @return The first tranche data
     */
    function getTranche(bytes12 isin) external view returns (Tranche memory);

    /**
     * @notice Convenience getter: returns tranche 1 for a bond by ISIN string
     * @param isin The ISIN as string
     * @return The first tranche data
     */
    function getTranche(string memory isin) external view returns (Tranche memory);

    /**
     * @notice Returns the ERC6909 token ID for a bond by ISIN string
     * @param isin The ISIN as string
     * @return The token ID
     */
    function getTokenId(string memory isin) external view returns (uint256);

    /**
     * @notice Returns token contract address
     * @return The token address
     */
    function getToken() external view returns (address);

    /**
     * @notice Retrieves the coupon rate for specified ISIN and timestamp
     * @param isin The bond ISIN
     * @param paymentTimestamp Timestamp to resolve against the coupon schedule
     * @return rate Coupon rate for the specified payment timestamp
     */
    function getCouponRateAt(string memory isin, uint256 paymentTimestamp) external view returns (uint256 rate);

    /**
     * @notice Retrieves the last non-zero coupon rate for specified ISIN
     * @param isin The bond ISIN
     * @return rate Coupon rate for the highest previously set payment timestamp
     */
    function getLatestCouponRate(string memory isin) external view returns (uint256 rate);

    /**
     * @notice Retrieves the coupon rate applicable at the current block timestamp
     * @dev Resolves current rate from explicit coupon timestamp checkpoints; couponFrequency is descriptive only
     * @dev Returns 0 for ZERO_COUPON bonds, unissued bonds (no tranches), timestamps before first checkpoint, or at/after maturity
     * @param isin The bond ISIN as bytes12
     * @return rate Coupon rate at current block timestamp
     */
    function getCurrentCouponRate(bytes12 isin) external view returns (uint256 rate);

    /**
     * @notice Same as getCurrentCouponRate but skips the redundant Bond storage load
     * @dev Intended for callers (e.g. OrderbookMarketplace) that already hold the Bond in memory
     * @param bond Bond struct obtained from getBond / getBondByTokenId
     * @return rate Coupon rate at current block timestamp
     */
    function getCurrentCouponRateForBond(Bond calldata bond) external view returns (uint256 rate);

    /**
     * @notice Retrieves all coupon rates for specified ISIN
     * @param isin The bond ISIN
     * @return paymentTimestamps Array of inclusive timestamp checkpoints
     * @return rates Array of rate checkpoints
     */
    function getAllCouponRates(string memory isin)
        external
        view
        returns (uint256[] memory paymentTimestamps, uint256[] memory rates);

    /**
     * @notice Retrieves length of all coupon rates for specified ISIN
     * @param isin The bond ISIN
     * @return length Length of the rate checkpoints
     */
    function getCouponRatesLength(string memory isin) external view returns (uint256 length);

    /**
     * @notice Returns the number of scoring records stored for a wallet
     * @param wallet The issuer wallet address
     * @return The number of scoring records (0 if none)
     */
    function getScoringCount(address wallet) external view returns (uint256);

    /**
     * @notice Returns the scoring record at a specific 1-based ID for a wallet
     * @dev Reverts if scoringId is 0 or greater than the wallet-local count
     * @param wallet The issuer wallet address
     * @param scoringId The 1-based scoring record identifier
     * @return The scoring record
     */
    function getScoringAt(address wallet, uint256 scoringId) external view returns (Scoring memory);

    /**
     * @notice Returns the most recently appended scoring record for a wallet
     * @dev Reverts if the wallet has no scoring records
     * @param wallet The issuer wallet address
     * @return The most recently appended scoring record
     */
    function getLatestScoring(address wallet) external view returns (Scoring memory);
}

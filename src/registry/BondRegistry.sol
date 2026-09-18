// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC6909TokenSupply} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {OwnableRolesExtension} from "../utils/OwnableRolesExtension.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
// DEUSS:
import {AddressExtensions} from "../libs/AddressExtensions.sol";
import {StringExtensions} from "../libs/StringExtensions.sol";
import {BondRegistryStorage} from "./BondRegistryStorage.sol";
import {Bond, BondInput, BondStatus, BurnKind, CouponRates, CouponRateType, Scoring, Tranche} from "./BondStructs.sol";
import {Errors} from "../libs/Errors.sol";
import {IBondRegistry} from "./interfaces/IBondRegistry.sol";
import {IBaseToken} from "../token/base/IBaseToken.sol";
import {IDEUSSToken} from "../token/fungible/IDEUSSToken.sol";

// slither-disable-start uninitialized-state
// @dev Slither may report multiple uninitialized-state variables here due to parser limitations with this
// codebase's contract layout. This detector is disabled for BondRegistry; behavior is covered by tests.
/**
 * @title BondRegistry
 * @author DEUSS Team
 * @notice This contract manages the bond registry, including publishing, issuances, and status updates
 */
contract BondRegistry is IBondRegistry, BondRegistryStorage, OwnableRolesExtension, Initializable, ReentrancyGuard {
    using AddressExtensions for address;
    using StringExtensions for string;

    /// @notice Initial bond version value (versions start at 1)
    uint8 public constant INITIAL_VERSION = 1;
    /// @notice Maximum allowed value for defaultProbabilityBps (100% in basis points)
    uint16 public constant MAX_PROBABILITY_BPS = 10_000;
    /// @notice Role to publish new bonds and update published revisions
    uint256 public constant PUBLISHER = _ROLE_0;
    /// @notice Role to cancel published bonds
    uint256 public constant CANCEL = _ROLE_1;
    /// @notice Role to close bonds with zero remaining supply (transitions Issued/Suspended → Redeemed)
    uint256 public constant CLOSE = _ROLE_2;
    /// @notice Role to manage allowed currencies
    uint256 public constant CURRENCY = _ROLE_3;
    /// @notice Role to suspend issued bonds
    uint256 public constant SUSPEND = _ROLE_4;
    /// @notice Role to unsuspend suspended bonds
    uint256 public constant UNSUSPEND = _ROLE_5;
    /// @notice Role to execute lifecycle settlement burns through the registry
    uint256 public constant BURNER = _ROLE_6;
    /// @notice Role to append issuer scoring records
    uint256 public constant SCORING = _ROLE_7;
    /// @notice Role to rotate bond issuers during exceptional recovery
    uint256 public constant ISSUER_RECOVERY = _ROLE_8;
    /// @notice Bitmask of all BondRegistry roles that may be granted
    uint256 public constant ALL_BR_ROLES =
        PUBLISHER | CANCEL | CLOSE | CURRENCY | SUSPEND | UNSUSPEND | BURNER | SCORING | ISSUER_RECOVERY;

    /**
     * @notice Locks any future initializations or reinitializations
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the bond registry contract
     * @dev The owner of the smart contract is set by deployer
     * @param owner_ The address owner of this contract
     */
    function initialize(address owner_) external initializer {
        __BondRegistry_init(owner_);
    }

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBondRegistry
     */
    function cancelBond(string calldata isin, uint8 version) external onlyRoles(CANCEL) {
        bytes12 isinBytes = isin._isinToBytes12();
        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(bond.status == BondStatus.Published, Errors.BondRegistry__InvalidBondStatus(isinBytes));
        require(bond.trancheCount == 0, Errors.BondRegistry__BondAlreadyIssued(isinBytes));
        require(
            _bondRegistryStorage().isinToLatestVersion[isinBytes] == version,
            Errors.BondRegistry__InvalidBondStatus(isinBytes)
        );
        bond.status = BondStatus.Cancelled;
        // Cancelled versions stay in latestVersion history to avoid tokenId reuse; clear activeVersion only
        // when the cancelled bond was the active unissued draft.
        if (_bondRegistryStorage().isinToActiveVersion[isinBytes] == version) {
            _bondRegistryStorage().isinToActiveVersion[isinBytes] = 0;
        }

        emit BondCancelled(isinBytes, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function closeBond(string calldata isin, uint8 version) external onlyRoles(CLOSE) {
        bytes12 isinBytes = isin._isinToBytes12();
        BondRegistryState storage $ = _bondRegistryStorage();
        Bond storage bond = $.bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(_isCloseableBondStatus(bond.status), Errors.BondRegistry__InvalidBondStatus(isinBytes));
        require(
            IERC6909TokenSupply(bond.tokenAddress).totalSupply(bond.tokenId) == 0,
            Errors.BondRegistry__TotalSupplyNotZero()
        );
        if ($.isinToActiveVersion[isinBytes] == version) {
            uint8 latestVersion = $.isinToLatestVersion[isinBytes];
            if (latestVersion != version) {
                // A later cancelled version is only historical; only a later Published version blocks closing
                // the active bond because it is still a pending successor.
                require(
                    $.bonds[isinBytes][latestVersion].status != BondStatus.Published,
                    Errors.BondRegistry__SuccessorAlreadyPublished(isinBytes)
                );
            }
        }
        if (bond.status == BondStatus.Suspended && !IBaseToken(bond.tokenAddress).paused()) {
            // Closing a suspended zero-supply bond is terminal. Unpause its tokenId so it is not left
            // permanently paused in the Redeemed state. Skipped while the token contract is globally paused,
            // because `unpauseTokenId` is guarded by `whenNotPaused` and would otherwise block closing.
            IBaseToken(bond.tokenAddress).unpauseTokenId(bond.tokenId);
        }

        bond.status = BondStatus.Redeemed;

        emit BondRedeemed(isinBytes, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function issueBond(string calldata isin, uint8 version, uint256 amount) external nonReentrant {
        bytes12 isinBytes = isin._isinToBytes12();

        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(
            bond.status == BondStatus.Published || bond.status == BondStatus.Issued,
            Errors.BondRegistry__InvalidBondStatus(isinBytes)
        );
        if (msg.sender == bond.issuer) {
            _requireEnabledIssuer(bond.issuer);
        } else {
            require(hasAnyRole(msg.sender, PUBLISHER), Errors.BondRegistry__UnauthorizedIssuer(msg.sender));
        }
        require(!bond.issuanceClosed, Errors.BondRegistry__IssuanceClosed(isinBytes));
        require(amount > 0, Errors.BondRegistry__IssuanceAmountIsZero());
        // slither-disable-next-line timestamp
        require(bond.maturityDate > block.timestamp, Errors.BondRegistry__MaturityDateExpired());
        if (amount > bond.remainingIssuableSupply) {
            revert Errors.BondRegistry__MaxSupplyExceeded(amount, bond.remainingIssuableSupply);
        }
        // Cache the first issuance flag
        bool isFirstIssuance = bond.status == BondStatus.Published;

        // Create tranche record
        uint16 trancheId = bond.trancheCount + 1;
        _bondRegistryStorage().tranches[isinBytes][version][trancheId] =
            Tranche({issueDate: block.timestamp, issueCount: amount});

        // Update bond state
        bond.trancheCount = trancheId;
        bond.mintedSupply += amount;
        bond.remainingIssuableSupply -= amount;
        bond.status = BondStatus.Issued;

        // Cutover: if this is the first issuance of a successor version, switch activeVersion and mark previous Replaced
        uint8 currentActiveVersion = _bondRegistryStorage().isinToActiveVersion[isinBytes];
        if (isFirstIssuance && version != currentActiveVersion) {
            Bond storage previousBond = _bondRegistryStorage().bonds[isinBytes][currentActiveVersion];
            require(previousBond.status == BondStatus.Issued, Errors.BondRegistry__InvalidBondStatus(isinBytes));
            previousBond.status = BondStatus.Replaced;
            _bondRegistryStorage().isinToActiveVersion[isinBytes] = version;
        }

        // Mint tokens
        IBaseToken(bond.tokenAddress).mint(bond.issuer, bond.tokenId, amount);

        emit BondIssued(isinBytes, bond.tokenId, amount, trancheId, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function closeIssuance(string calldata isin, uint8 version) external {
        bytes12 isinBytes = isin._isinToBytes12();
        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(
            bond.status == BondStatus.Issued || bond.status == BondStatus.Suspended,
            Errors.BondRegistry__InvalidBondStatus(isinBytes)
        );
        if (msg.sender == bond.issuer) {
            _requireEnabledIssuer(bond.issuer);
        } else {
            require(hasAnyRole(msg.sender, PUBLISHER), Errors.BondRegistry__UnauthorizedIssuanceCloser(msg.sender));
        }
        require(!bond.issuanceClosed, Errors.BondRegistry__IssuanceClosed(isinBytes));

        bond.issuanceClosed = true;

        emit BondIssuanceClosed(isinBytes, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function rotateIssuer(string calldata isin, uint8 version, address newIssuer, bytes32 reason)
        external
        onlyRoles(ISSUER_RECOVERY)
        nonReentrant
    {
        bytes12 isinBytes = isin._isinToBytes12();
        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(
            bond.status == BondStatus.Published || bond.status == BondStatus.Issued
                || bond.status == BondStatus.Suspended || bond.status == BondStatus.Replaced,
            Errors.BondRegistry__InvalidBondStatus(isinBytes)
        );
        require(newIssuer != address(0), Errors.ZeroAddress());
        require(newIssuer != bond.issuer, Errors.BondRegistry__IssuerUnchanged(newIssuer));
        require(reason != bytes32(0), Errors.BondRegistry__ZeroReason());
        _requireEnabledIssuer(newIssuer);

        address oldIssuer = bond.issuer;
        bond.issuer = newIssuer;

        emit BondIssuerRotated(isinBytes, version, oldIssuer, newIssuer, reason, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function burnBond(bytes12 isin, uint8 version, address from, uint256 amount, BurnKind kind) external nonReentrant {
        Bond storage bond = _bondRegistryStorage().bonds[isin][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));

        _validateBurnAuthorization(bond, from, kind);
        _applyBurnAccounting(bond, version, amount, kind);

        emit BondBurned(isin, version, from, amount, kind, msg.sender);

        IDEUSSToken(bond.tokenAddress).burn(from, bond.tokenId, amount);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function burnBondBatch(
        bytes12 isin,
        uint8 version,
        address[] calldata froms,
        uint256[] calldata amounts,
        BurnKind kind
    ) external nonReentrant {
        Bond storage bond = _bondRegistryStorage().bonds[isin][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));

        uint256 fromsLen = froms.length;

        require(fromsLen == amounts.length, Errors.LengthMismatch());

        uint256 totalAmount;
        _validateBurnCaller(bond, kind);
        unchecked {
            for (uint256 i; i < fromsLen; ++i) {
                _validateBurnSource(bond, froms[i], kind);
                totalAmount += amounts[i];
                emit BondBurned(isin, version, froms[i], amounts[i], kind, msg.sender);
            }
        }
        _applyBurnAccounting(bond, version, totalAmount, kind);

        IDEUSSToken(bond.tokenAddress).burnBatch(froms, bond.tokenId, amounts);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function setAllowedCurrency(string calldata currencyCode, bool allowed) external onlyRoles(CURRENCY) {
        bytes3 currencyBytes = currencyCode._currencyToBytes3();

        _bondRegistryStorage().allowedCurrencies[currencyBytes] = allowed;

        emit AllowedCurrencyUpdated(currencyBytes, allowed, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function publishBond(BondInput calldata bondInput) external onlyRoles(PUBLISHER) nonReentrant {
        bytes12 isinBytes = bondInput.isin._isinToBytes12();
        uint8 latestVersion = _bondRegistryStorage().isinToLatestVersion[isinBytes];

        _validateBondInput(bondInput, true);

        uint8 publishedVersion;
        if (latestVersion == 0) {
            publishedVersion = INITIAL_VERSION;
            _bondRegistryStorage().isinToLatestVersion[isinBytes] = INITIAL_VERSION;
            _bondRegistryStorage().isinToActiveVersion[isinBytes] = INITIAL_VERSION;
        } else {
            uint8 activeVersion = _bondRegistryStorage().isinToActiveVersion[isinBytes];
            BondStatus latestStatus = _bondRegistryStorage().bonds[isinBytes][latestVersion].status;
            require(latestStatus != BondStatus.Published, Errors.BondRegistry__SuccessorAlreadyPublished(isinBytes));
            if (activeVersion != 0) {
                require(
                    _bondRegistryStorage().bonds[isinBytes][activeVersion].status == BondStatus.Issued,
                    Errors.BondRegistry__ActiveVersionNotIssuable(isinBytes)
                );
            }
            publishedVersion = latestVersion + 1;
            _bondRegistryStorage().isinToLatestVersion[isinBytes] = publishedVersion;
            if (activeVersion == 0) {
                _bondRegistryStorage().isinToActiveVersion[isinBytes] = publishedVersion;
            }
        }

        _createBond(isinBytes, publishedVersion, bondInput);

        Bond storage publishedBond = _bondRegistryStorage().bonds[isinBytes][publishedVersion];
        emit BondPublished(
            isinBytes,
            publishedBond.issuer,
            publishedVersion,
            publishedBond.tokenId,
            publishedBond.tokenAddress,
            publishedBond.currency,
            publishedBond.bondNominalValue,
            publishedBond.maxSupply,
            publishedBond.maturityDate,
            publishedBond.couponFrequency,
            publishedBond.couponRateType,
            publishedBond.isGuaranteed,
            publishedBond.issuanceCountry,
            msg.sender
        );
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function updatePublishedBond(BondInput calldata bondInput, uint8 version) external onlyRoles(PUBLISHER) {
        bytes12 isinBytes = bondInput.isin._isinToBytes12();

        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status == BondStatus.Published, Errors.BondRegistry__InvalidBondStatus(isinBytes));

        bytes3 inputCurrency = bondInput.currency._currencyToBytes3();
        _validateBondInput(bondInput, inputCurrency != bond.currency);
        require(bondInput.isGuaranteed == bond.isGuaranteed, Errors.BondRegistry__GuaranteeStatusImmutable(isinBytes));

        // Amendment in place — update all mutable fields, preserve tokenId and trancheCount
        bond.issuer = bondInput.issuer;
        bond.couponFrequency = bondInput.couponFrequency;
        bond.currency = inputCurrency;
        bond.bondNominalValue = bondInput.bondNominalValue;
        bond.couponRates = bondInput.couponRates;
        bond.couponRateType = bondInput.couponRateType;
        bond.maxSupply = bondInput.maxSupply;
        bond.remainingIssuableSupply = bondInput.maxSupply;
        bond.maturityDate = bondInput.maturityDate;
        bond.issuanceCountry = bondInput.issuanceCountry;

        emit PublishedBondUpdated(
            isinBytes,
            version,
            msg.sender,
            bond.issuer,
            bond.tokenId,
            bond.tokenAddress,
            bond.currency,
            bond.bondNominalValue,
            bond.maxSupply,
            bond.maturityDate,
            bond.couponFrequency,
            bond.couponRateType,
            bond.isGuaranteed,
            bond.issuanceCountry
        );
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function suspendBond(string calldata isin, uint8 version) external onlyRoles(SUSPEND) nonReentrant {
        bytes12 isinBytes = isin._isinToBytes12();
        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(bond.status == BondStatus.Issued, Errors.BondRegistry__InvalidBondStatus(isinBytes));

        bond.status = BondStatus.Suspended;

        IBaseToken(bond.tokenAddress).pauseTokenId(bond.tokenId);

        emit BondSuspended(isinBytes, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function unsuspendBond(string calldata isin, uint8 version) external onlyRoles(UNSUSPEND) nonReentrant {
        bytes12 isinBytes = isin._isinToBytes12();
        Bond storage bond = _bondRegistryStorage().bonds[isinBytes][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(bond.status == BondStatus.Suspended, Errors.BondRegistry__InvalidBondStatus(isinBytes));

        bond.status = BondStatus.Issued;

        IBaseToken(bond.tokenAddress).unpauseTokenId(bond.tokenId);

        emit BondUnsuspended(isinBytes, version, msg.sender);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function appendScoring(address wallet, Scoring calldata scoring) external onlyRoles(SCORING) {
        require(wallet != address(0), Errors.ZeroAddress());
        require(scoring.issueDate != 0, Errors.BondRegistry__ScoringZeroIssueDate());
        require(scoring.expirationDate > scoring.issueDate, Errors.BondRegistry__ScoringExpirationNotAfterIssue());
        require(scoring.distributorId != bytes32(0), Errors.BondRegistry__ScoringZeroDistributorId());
        require(
            !(scoring.defaultProbabilityBps > MAX_PROBABILITY_BPS),
            Errors.BondRegistry__ScoringProbabilityTooHigh(scoring.defaultProbabilityBps)
        );

        uint256 scoringId = ++_bondRegistryStorage().scoringCount[wallet];
        _bondRegistryStorage().scorings[wallet][scoringId] = scoring;

        emit ScoringAppended(
            wallet,
            scoringId,
            scoring.defaultProbabilityBps,
            scoring.issueDate,
            scoring.expirationDate,
            scoring.distributorId,
            msg.sender
        );
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getScoringCount(address wallet) external view returns (uint256) {
        return _bondRegistryStorage().scoringCount[wallet];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getScoringAt(address wallet, uint256 scoringId) external view returns (Scoring memory) {
        require(
            !(scoringId == 0 || scoringId > _bondRegistryStorage().scoringCount[wallet]),
            Errors.BondRegistry__InvalidScoringId(wallet, scoringId)
        );
        return _bondRegistryStorage().scorings[wallet][scoringId];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getLatestScoring(address wallet) external view returns (Scoring memory) {
        uint256 count = _bondRegistryStorage().scoringCount[wallet];
        require(count != 0, Errors.BondRegistry__ScoringNotFound(wallet));
        return _bondRegistryStorage().scorings[wallet][count];
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBondRegistry
     */
    function bondStatus(string calldata isin) external view returns (BondStatus) {
        bytes12 isinBytes = isin._isinToBytes12();

        return bondStatus(isinBytes);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getBondAtVersion(bytes12 isin, uint8 version) external view returns (Bond memory) {
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));

        return bond;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getBondByTokenId(uint256 tokenId) external view returns (Bond memory) {
        bytes12 isin = _bondRegistryStorage().tokenIdToIsin[tokenId];
        uint8 version = _bondRegistryStorage().tokenIdToVersion[tokenId];
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));

        return bond;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getBondSeriesByTokenId(uint256 tokenId) external view returns (bytes12 isin, uint8 version) {
        isin = _bondRegistryStorage().tokenIdToIsin[tokenId];
        version = _bondRegistryStorage().tokenIdToVersion[tokenId];

        require(
            _bondRegistryStorage().bonds[isin][version].status != BondStatus.Unregistered,
            Errors.BondRegistry__NonExistentBond(isin)
        );
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getToken() external view returns (address) {
        return _bondRegistryStorage().token;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTranche(bytes12 isin, uint16 trancheId) external view returns (Tranche memory) {
        uint8 version = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));
        require(trancheId != 0 && trancheId - 1 < bond.trancheCount, Errors.BondRegistry__InvalidTrancheId(trancheId));
        return _bondRegistryStorage().tranches[isin][version][trancheId];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTranche(bytes12 isin, uint8 version, uint16 trancheId) external view returns (Tranche memory) {
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));
        require(trancheId != 0 && trancheId - 1 < bond.trancheCount, Errors.BondRegistry__InvalidTrancheId(trancheId));
        return _bondRegistryStorage().tranches[isin][version][trancheId];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getLatestTranche(bytes12 isin) external view returns (Tranche memory) {
        uint8 version = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));
        require(bond.trancheCount > 0, Errors.BondRegistry__InvalidTrancheId(0));
        return _bondRegistryStorage().tranches[isin][version][bond.trancheCount];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTrancheCount(bytes12 isin) external view returns (uint16) {
        uint8 version = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));
        return bond.trancheCount;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTranche(bytes12 isin) external view returns (Tranche memory) {
        uint8 version = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));
        require(bond.trancheCount != 0, Errors.BondRegistry__InvalidTrancheId(0));
        return _bondRegistryStorage().tranches[isin][version][1];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTranche(string calldata isin) external view returns (Tranche memory) {
        bytes12 isinBytes = isin._isinToBytes12();
        uint8 version = _bondRegistryStorage().isinToActiveVersion[isinBytes];
        Bond memory bond = _bondRegistryStorage().bonds[isinBytes][version];
        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isinBytes));
        require(bond.trancheCount != 0, Errors.BondRegistry__InvalidTrancheId(0));
        return _bondRegistryStorage().tranches[isinBytes][version][1];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getTokenId(string calldata isin) external view returns (uint256) {
        Bond memory bond = getBond(isin);
        return bond.tokenId;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getAllCouponRates(string calldata isin)
        external
        view
        returns (uint256[] memory paymentTimestamps, uint256[] memory rates)
    {
        Bond memory bond = getBond(isin);

        return (bond.couponRates.paymentTimestamps, bond.couponRates.rates);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getCouponRatesLength(string calldata isin) external view returns (uint256 length) {
        Bond memory bond = getBond(isin);

        return bond.couponRates.paymentTimestamps.length;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getCouponRateAt(string calldata isin, uint256 paymentTimestamp) external view returns (uint256 rate) {
        Bond memory bond = getBond(isin);

        if (!(paymentTimestamp < bond.maturityDate)) {
            return 0;
        }
        return _couponRateAtTimestamp(bond.couponRates, paymentTimestamp);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getCurrentCouponRate(bytes12 isin) external view returns (uint256 rate) {
        return _currentCouponRateFromBond(getBond(isin));
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getCurrentCouponRateForBond(Bond calldata bond) external view returns (uint256 rate) {
        return _currentCouponRateFromBond(bond);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getLatestCouponRate(string calldata isin) external view returns (uint256 rate) {
        Bond memory bond = getBond(isin);
        uint256 length = bond.couponRates.rates.length;

        if (length < 2) {
            return 0;
        }

        // length-1 always contains 0 value representing the outer edge of the coupon validity (e.g. "13th month and forward, rate is 0")
        // length-2 is the last non-zero value
        return bond.couponRates.rates[length - 2];
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBondRegistry
     */
    function grantRoles(address user, uint256 roles)
        public
        payable
        override(IBondRegistry, OwnableRolesExtension)
        onlyOwner
    {
        require(roles & ~ALL_BR_ROLES == 0, Errors.InvalidRoles());

        super.grantRoles(user, roles);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function grantRoles(address[] calldata users, uint256 roles)
        public
        payable
        override(IBondRegistry, OwnableRolesExtension)
        onlyOwner
    {
        require(roles & ~ALL_BR_ROLES == 0, Errors.InvalidRoles());

        super.grantRoles(users, roles);
    }

    /**
     * @notice Sets the shared ERC6909 token contract where all bond tokens are minted
     * @param multiToken The address of the ERC6909 token contract
     */
    function setMultiToken(address multiToken) public onlyOwner {
        require(multiToken != address(0), Errors.ZeroAddress());
        _validateMultiToken(multiToken);
        require(!_bondRegistryStorage().multiTokenLocked, Errors.BondRegistry__MultiTokenLocked());

        address previousMultiToken = _bondRegistryStorage().token;
        _bondRegistryStorage().token = multiToken;
        _bondRegistryStorage().multiTokenLocked = true;

        emit MultiTokenSet(previousMultiToken, multiToken);
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBondRegistry
     */
    function bondStatus(bytes12 isin) public view returns (BondStatus) {
        uint8 activeVersion = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][activeVersion];

        return bond.status;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getBond(string calldata isin) public view returns (Bond memory) {
        bytes12 isinBytes = isin._isinToBytes12();

        return getBond(isinBytes);
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getBond(bytes12 isin) public view returns (Bond memory) {
        uint8 activeVersion = _bondRegistryStorage().isinToActiveVersion[isin];
        Bond memory bond = _bondRegistryStorage().bonds[isin][activeVersion];

        require(bond.status != BondStatus.Unregistered, Errors.BondRegistry__NonExistentBond(isin));

        return bond;
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getActiveVersion(bytes12 isin) public view returns (uint8) {
        return _bondRegistryStorage().isinToActiveVersion[isin];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function getLatestVersion(bytes12 isin) public view returns (uint8) {
        return _bondRegistryStorage().isinToLatestVersion[isin];
    }

    /**
     * @inheritdoc IBondRegistry
     */
    function isCurrencyAllowed(string memory currencyCode) public view returns (bool) {
        bytes3 currencyBytes = currencyCode._currencyToBytes3();

        return _bondRegistryStorage().allowedCurrencies[currencyBytes];
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IBondRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with owner
     * @param owner_ The address that will own the contract
     */
    // solhint-disable-next-line func-name-mixedcase
    function __BondRegistry_init(address owner_) internal onlyInitializing {
        _initializeOwner(owner_ == address(0) ? msg.sender : owner_);
    }

    /**
     * @notice Applies bond-level accounting after a successful token burn.
     * @param bond Bond storage reference.
     * @param version Exact bond version.
     * @param amount Amount successfully burned.
     * @param kind Burn semantic that controls future issuance capacity.
     */
    function _applyBurnAccounting(Bond storage bond, uint8 version, uint256 amount, BurnKind kind) internal {
        if (kind == BurnKind.ISSUER_RECLAIM) {
            _requireUnfrozenIssuerReclaimBalance(bond, version, amount);
            bond.remainingIssuableSupply += amount;
        }
    }

    /**
     * @notice Requires issuer reclaim burns to consume only unfrozen issuer-held balance.
     * @param bond Bond storage reference.
     * @param version Exact bond version.
     * @param amount Reclaim amount.
     */
    function _requireUnfrozenIssuerReclaimBalance(Bond storage bond, uint8 version, uint256 amount) internal view {
        IBaseToken token = IBaseToken(bond.tokenAddress);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);
        uint256 frozenBalance = token.frozenBalanceOf(bond.issuer, bond.tokenId);
        uint256 freeBalance = balance - frozenBalance;

        if (amount > freeBalance) {
            revert Errors.BondRegistry__FrozenIssuerReclaimDenied(bond.issuer, bond.isin, version, amount, freeBalance);
        }
    }

    /**
     * @notice Validates burn status and caller/source authorization.
     * @dev ISSUER_RECLAIM requires Issued status. FINAL_SETTLEMENT allows Issued or Replaced.
     * @param bond Bond storage reference.
     * @param from Burn source account.
     * @param kind Burn semantic requested by the caller.
     */
    function _validateBurnAuthorization(Bond storage bond, address from, BurnKind kind) internal view {
        _validateBurnCaller(bond, kind);
        _validateBurnSource(bond, from, kind);
    }

    /**
     * @notice Validates burn status and caller authorization.
     * @param bond Bond storage reference.
     * @param kind Burn semantic requested by the caller.
     */
    function _validateBurnCaller(Bond storage bond, BurnKind kind) internal view {
        if (kind == BurnKind.ISSUER_RECLAIM) {
            require(bond.status == BondStatus.Issued, Errors.BondRegistry__InvalidBondStatus(bond.isin));
            require(msg.sender == bond.issuer, Errors.BondRegistry__UnauthorizedBurnCaller(msg.sender, uint8(kind)));
            _requireEnabledIssuer(bond.issuer);
            return;
        }

        // FINAL_SETTLEMENT: allow Issued or Replaced (legacy version late migration)
        require(
            bond.status == BondStatus.Issued || bond.status == BondStatus.Replaced,
            Errors.BondRegistry__InvalidBondStatus(bond.isin)
        );
        if (msg.sender == bond.issuer) {
            _requireEnabledIssuer(bond.issuer);
            return;
        }

        require(hasAnyRole(msg.sender, BURNER), Errors.BondRegistry__UnauthorizedBurnCaller(msg.sender, uint8(kind)));
        require(
            IBaseToken(_bondRegistryStorage().token).entityRegistry().isAccountEnabled(msg.sender),
            Errors.BondRegistry__UnauthorizedBurnCaller(msg.sender, uint8(kind))
        );
    }

    /**
     * @notice Validates burn source authorization.
     * @param bond Bond storage reference.
     * @param from Burn source account.
     * @param kind Burn semantic requested by the caller.
     */
    function _validateBurnSource(Bond storage bond, address from, BurnKind kind) internal view {
        if (kind == BurnKind.ISSUER_RECLAIM || msg.sender == bond.issuer) {
            require(from == bond.issuer, Errors.BondRegistry__InvalidBurnSource(from, bond.isin, uint8(kind)));
        }
    }

    /**
     * @notice Resolve the coupon rate applicable at the current block timestamp for the supplied bond
     * @dev Shared path for getCurrentCouponRate(bytes12) and getCurrentCouponRateForBond(Bond)
     * @param bond Bond metadata (isin, couponRateType, couponRates, trancheCount, maturityDate)
     * @return rate Current coupon rate (0 for ZERO_COUPON, unissued bonds, before first checkpoint, or at/after maturity)
     */
    function _currentCouponRateFromBond(Bond memory bond) internal view returns (uint256 rate) {
        if (bond.couponRateType == CouponRateType.ZERO_COUPON) {
            return 0;
        }
        if (bond.trancheCount == 0) {
            return 0;
        }
        uint8 version = _bondRegistryStorage().tokenIdToVersion[bond.tokenId];
        if (_bondRegistryStorage().tranches[bond.isin][version][1].issueDate == 0) {
            return 0;
        }

        // slither-disable-next-line timestamp
        if (!(block.timestamp < bond.maturityDate)) {
            return 0;
        }

        return _couponRateAtTimestamp(bond.couponRates, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns whether bond can be closed in current status
     * @dev Closing is allowed for `Issued` and `Suspended` once total supply is zero.
     *      The terminal transition itself marks the version as `Redeemed`.
     * @param status Bond status to evaluate
     * @return True if status is closeable by `closeBond`
     */
    function _isCloseableBondStatus(BondStatus status) internal pure returns (bool) {
        return status == BondStatus.Issued || status == BondStatus.Suspended;
    }

    /**
     * @notice Returns the coupon rate applicable at a given timestamp
     * @dev Binary search the highest `paymentTimestamps[i]` that is <= `paymentTimestamp`
     * @param couponRates The coupon rates data
     * @param paymentTimestamp The timestamp to resolve
     * @return rate The applicable rate (0 if before first checkpoint)
     */
    function _couponRateAtTimestamp(CouponRates memory couponRates, uint256 paymentTimestamp)
        internal
        pure
        returns (uint256 rate)
    {
        uint256 left = 0;
        uint256 right = couponRates.paymentTimestamps.length;

        while (left < right) {
            uint256 mid = left + (right - left) / 2;
            if (!(couponRates.paymentTimestamps[mid] > paymentTimestamp)) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return left != 0 ? couponRates.rates[left - 1] : 0;
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize and store a new bond struct
     * @dev Populates the bond data for the given ISIN and version using the provided input.
     *      Sets default status to `Published`.
     * @param isin The ISIN identifier as bytes12
     * @param version The version number for this bond
     * @param input Struct containing input parameters for the bond
     */
    function _createBond(bytes12 isin, uint8 version, BondInput memory input) private {
        Bond storage bond = _bondRegistryStorage().bonds[isin][version];

        bond.isin = isin;
        bond.issuer = input.issuer;
        bond.status = BondStatus.Published;
        bond.couponFrequency = input.couponFrequency;
        bond.trancheCount = 0;
        bond.currency = input.currency._currencyToBytes3();
        bond.bondNominalValue = input.bondNominalValue;
        bond.couponRates = input.couponRates;
        bond.couponRateType = input.couponRateType;
        bond.maxSupply = input.maxSupply;
        bond.mintedSupply = 0;
        bond.maturityDate = input.maturityDate;
        bond.tokenAddress = _bondRegistryStorage().token;
        bond.tokenId = _computeTokenId(isin, version);
        bond.remainingIssuableSupply = input.maxSupply;
        bond.issuanceClosed = false;
        bond.isGuaranteed = input.isGuaranteed;
        bond.issuanceCountry = input.issuanceCountry;

        _bondRegistryStorage().tokenIdToIsin[bond.tokenId] = isin;
        _bondRegistryStorage().tokenIdToVersion[bond.tokenId] = version;
    }

    /*//////////////////////////////////////////////////////////////
                         PRIVATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates that the issuer account is currently enabled in EntityRegistry.
     * @dev Actor-identity authorization is only valid while the actor is enabled.
     *      Use this check on any path where authority comes from stored issuer address.
     * @param issuer The issuer address to validate
     */
    function _requireEnabledIssuer(address issuer) private view {
        require(
            IBaseToken(_bondRegistryStorage().token).entityRegistry().isAccountEnabled(issuer),
            Errors.BondRegistry__IssuerNotEnabled(issuer)
        );
    }

    /**
     * @notice Validates the shared token contract address
     * @param multiToken The token contract address to validate
     */
    function _validateMultiToken(address multiToken) private view {
        multiToken.assertAddressNotZero();

        require(
            IERC165(multiToken).supportsInterface(type(IBaseToken).interfaceId),
            Errors.BondRegistry__InvalidMultiToken(multiToken)
        );
        require(
            address(IBaseToken(multiToken).bondRegistry()) == address(this),
            Errors.BondRegistry__InvalidMultiToken(multiToken)
        );
    }

    /**
     * @notice Validates bond input data (shared bond terms only)
     * @param input The bond input data
     * @param requireAllowedCurrency Whether the currency must currently be allowed
     */
    function _validateBondInput(BondInput memory input, bool requireAllowedCurrency) private view {
        require(input.issuer != address(0), Errors.ZeroAddress());
        require(
            IBaseToken(_bondRegistryStorage().token).entityRegistry().isAccountEnabled(input.issuer),
            Errors.BondRegistry__IssuerNotEnabled(input.issuer)
        );
        bytes3 currencyBytes = input.currency._currencyToBytes3();
        require(
            !requireAllowedCurrency || _bondRegistryStorage().allowedCurrencies[currencyBytes],
            Errors.BondRegistry__InvalidCurrency()
        );
        require(input.bondNominalValue != 0, Errors.BondRegistry__BondNominalValueIsZero());
        require(input.maxSupply != 0, Errors.BondRegistry__MaxSupplyIsZero());
        require(input.issuanceCountry != 0, Errors.BondRegistry__IssuanceCountryIsZero());
        // slither-disable-next-line timestamp
        require(input.maturityDate > block.timestamp, Errors.BondRegistry__MaturityDateExpired());

        _validateCouponRates(input.couponRates, input.couponRateType, input.maturityDate);
    }

    /*//////////////////////////////////////////////////////////////
                         PRIVATE PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates the coupon rates structure for a bond
     * @param couponRates The coupon rates data
     * @param couponRateType_ The type of coupon for the bond (fixed, floating, zero coupon)
     * @param maturityDate_ The bond maturity timestamp
     * @dev Ensures the coupon rates and payment timestamps are consistent with the bond's coupon type
     */
    function _validateCouponRates(CouponRates memory couponRates, CouponRateType couponRateType_, uint256 maturityDate_)
        private
        pure
    {
        uint256 paymentTimestampsLength = couponRates.paymentTimestamps.length;
        uint256 ratesLength = couponRates.rates.length;

        require(paymentTimestampsLength == ratesLength, Errors.BondRegistry__CouponRatesLengthMismatch());
        require(
            couponRateType_ != CouponRateType.ZERO_COUPON || paymentTimestampsLength == 0 || ratesLength == 0,
            Errors.BondRegistry__CouponRatesUnexpectedLength()
        );
        if (couponRateType_ == CouponRateType.ZERO_COUPON) {
            // empty array in ZERO_COUPON - no other validations
            return;
        }
        require(
            couponRateType_ != CouponRateType.FIXED || paymentTimestampsLength == 2 || ratesLength == 2,
            Errors.BondRegistry__CouponRatesUnexpectedLength()
        );
        require(
            !(couponRateType_ == CouponRateType.FLOATING && paymentTimestampsLength < 2 && ratesLength < 2),
            Errors.BondRegistry__CouponRatesUnexpectedLength()
        );
        require(!(couponRates.paymentTimestamps[0] == 0), Errors.BondRegistry__PaymentTimestampZero());
        require(couponRates.rates[ratesLength - 1] == 0, Errors.BondRegistry__CouponRatesLastRateNotZero());
        require(
            !(maturityDate_ < couponRates.paymentTimestamps[paymentTimestampsLength - 1]),
            Errors.BondRegistry__PaymentTimestampAfterMaturity()
        );

        for (uint256 i; i < paymentTimestampsLength - 1;) {
            uint256 currentTimestamp = couponRates.paymentTimestamps[i];
            uint256 currentRate = couponRates.rates[i];

            require(
                currentTimestamp < couponRates.paymentTimestamps[i + 1],
                Errors.BondRegistry__PaymentTimestampsUnordered()
            );
            require(currentRate != couponRates.rates[i + 1], Errors.BondRegistry__CouponRatesDuplicate());

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Computes a unique token ID for a bond by hashing its ISIN and version
     * @dev The token ID is used as the ERC6909 token identifier in the shared token contract
     * @param isin The bond's ISIN code
     * @param version The bond's version number
     * @return The computed token ID
     */
    function _computeTokenId(bytes12 isin, uint8 version) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(isin, version)));
    }
}
// slither-disable-end uninitialized-state

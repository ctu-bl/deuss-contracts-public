// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities, gas-small-strings, gas-struct-packing */

import {
    Bond,
    BondInput,
    BondStatus,
    BurnKind,
    CouponFrequency,
    CouponRates,
    CouponRateType,
    Scoring
} from "src/registry/BondStructs.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsBondRegistry is PreconditionsBase {
    struct PublishSuccessorParams {
        uint8 previousActiveVersion;
        BondInput input;
    }

    struct UpdatePublishedParams {
        uint8 version;
        BondInput input;
    }

    struct IssueParams {
        uint8 version;
        uint256 amount;
        bool isFirstIssuance;
        uint8 previousActiveVersion;
    }

    struct VersionParams {
        uint8 version;
    }

    struct RotateIssuerParams {
        uint8 version;
        address oldIssuer;
        address newIssuer;
    }

    struct BurnParams {
        uint8 version;
        address from;
        uint256 amount;
    }

    struct BatchBurnParams {
        uint8 version;
        address[] froms;
        uint256[] amounts;
        uint256 totalAmount;
    }

    struct FrozenIssuerReclaimParams {
        uint8 version;
        address from;
        uint256 amount;
    }

    struct BurnAuthorizationParams {
        uint8 version;
        address from;
        uint256 amount;
        BurnKind kind;
        address caller;
    }

    struct AppendScoringParams {
        address wallet;
        Scoring scoring;
        uint256 previousCount;
    }

    struct InvalidScoringParams {
        address wallet;
        Scoring scoring;
        bytes4 expectedError;
    }

    struct InvalidBondInputParams {
        BondInput input;
        bytes4 expectedError;
    }

    struct BondRegistryViewSurfaceParams {
        uint8 version;
        uint16 trancheId;
        uint16 activeTrancheId;
        uint256 tokenId;
        uint256 couponRateIndex;
    }

    function publishSuccessorPreconditions(uint256 maxSupplySeed)
        internal
        returns (PublishSuccessorParams memory params)
    {
        uint8 latest = _getLatestBondVersion();
        require(latest != 0 && latest < type(uint8).max, ClampFail("no successor slot"));

        uint8 active = _getActiveBondVersion();
        Bond memory activeBond = _getBondAtVersion(active);
        require(activeBond.status == BondStatus.Issued, ClampFail("active version not issued"));
        require(_getBondAtVersion(latest).status != BondStatus.Published, ClampFail("successor already published"));

        params.previousActiveVersion = active;
        params.input = _buildBondInput(issuer, maxSupplySeed);
    }

    function publishBondActiveVersionNotIssuablePreconditions(uint256 maxSupplySeed)
        internal
        returns (PublishSuccessorParams memory params)
    {
        uint8 latest = _getLatestBondVersion();
        require(latest != 0 && latest < type(uint8).max, ClampFail("no successor slot"));

        uint8 active = _getActiveBondVersion();
        require(active != 0, ClampFail("no active version"));
        require(_getBondAtVersion(latest).status != BondStatus.Published, ClampFail("successor already published"));

        Bond memory activeBond = _getBondAtVersion(active);
        require(_getBondAtVersion(latest).status != BondStatus.Published, ClampFail("successor already published"));
        require(activeBond.status != BondStatus.Issued, ClampFail("active version issued"));

        params.previousActiveVersion = active;
        params.input = _buildBondInput(issuer, maxSupplySeed);
    }

    function publishBondSuccessorAlreadyPublishedPreconditions(uint256 maxSupplySeed)
        internal
        returns (PublishSuccessorParams memory params)
    {
        uint8 latest = _getLatestBondVersion();
        require(latest != 0 && latest < type(uint8).max, ClampFail("no successor slot"));

        uint8 active = _getActiveBondVersion();
        Bond memory activeBond = _getBondAtVersion(active);
        require(activeBond.status == BondStatus.Issued, ClampFail("active version not issued"));
        require(_getBondAtVersion(latest).status == BondStatus.Published, ClampFail("no published successor"));

        params.previousActiveVersion = active;
        params.input = _buildBondInput(issuer, maxSupplySeed);
    }

    function updatePublishedPreconditions(uint256 versionSeed, uint256 maxSupplySeed)
        internal
        returns (UpdatePublishedParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionByStatus(versionSeed, BondStatus.Published);
        require(found, ClampFail("no published version"));

        params.version = version;
        params.input = _buildBondInput(_pickUpdateIssuer(maxSupplySeed), maxSupplySeed);
        params.input.isGuaranteed = _getBondAtVersion(version).isGuaranteed;
    }

    function updatePublishedInvalidStatusPreconditions(uint256 versionSeed, uint256 maxSupplySeed)
        internal
        returns (UpdatePublishedParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionNotPublished(versionSeed);
        require(found, ClampFail("no non-published version"));

        params.version = version;
        params.input = _buildBondInput(_pickUpdateIssuer(maxSupplySeed), maxSupplySeed);
        params.input.isGuaranteed = _getBondAtVersion(version).isGuaranteed;
    }

    function issueBondPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (IssueParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        (bool found, uint8 version) = _pickKnownBondVersionIssuable(versionSeed);
        require(found, ClampFail("no issuable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 capped =
            bond.remainingIssuableSupply > BOND_ISSUE_COUNT ? BOND_ISSUE_COUNT : bond.remainingIssuableSupply;
        params.version = version;
        params.amount = fl.clamp(amountSeed, 1, capped);
        params.isFirstIssuance = bond.status == BondStatus.Published;
        params.previousActiveVersion = _getActiveBondVersion();
        if (params.isFirstIssuance && params.version != params.previousActiveVersion) {
            Bond memory previousActiveBond = _getBondAtVersion(params.previousActiveVersion);
            require(previousActiveBond.status == BondStatus.Issued, ClampFail("previous active version not issued"));
        }
    }

    function issueBondSuccessorSuspendedPreviousPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (IssueParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        uint8 active = _getActiveBondVersion();
        require(active != 0, ClampFail("no active version"));
        require(_getBondAtVersion(active).status == BondStatus.Suspended, ClampFail("active version not suspended"));

        (bool found, uint8 version) = _pickPublishedSuccessorVersion(versionSeed, active);
        require(found, ClampFail("no published successor"));

        Bond memory bond = _getBondAtVersion(version);
        require(!bond.issuanceClosed, ClampFail("successor issuance closed"));
        require(bond.remainingIssuableSupply > 0, ClampFail("successor supply exhausted"));
        require(bond.maturityDate > block.timestamp, ClampFail("successor maturity expired"));

        uint256 capped =
            bond.remainingIssuableSupply > BOND_ISSUE_COUNT ? BOND_ISSUE_COUNT : bond.remainingIssuableSupply;
        params.version = version;
        params.amount = fl.clamp(amountSeed, 1, capped);
        params.isFirstIssuance = true;
        params.previousActiveVersion = active;
    }

    function closeIssuancePreconditions(uint256 versionSeed) internal returns (VersionParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionIssuanceUnclosed(versionSeed);
        require(found, ClampFail("no unclosed issuance"));

        params.version = version;
    }

    function cancelBondPreconditions() internal returns (VersionParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionCancellable();
        require(found, ClampFail("no cancellable version"));

        params.version = version;
    }

    function suspendBondPreconditions(uint256 versionSeed) internal returns (VersionParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionByStatus(versionSeed, BondStatus.Issued);
        require(found, ClampFail("no issued version"));

        params.version = version;
    }

    function unsuspendBondPreconditions(uint256 versionSeed) internal returns (VersionParams memory params) {
        require(!token.paused(), ClampFail("token contract paused"));

        (bool found, uint8 version) = _pickKnownBondVersionByStatus(versionSeed, BondStatus.Suspended);
        require(found, ClampFail("no suspended version"));

        params.version = version;
    }

    function closeBondPreconditions(uint256 versionSeed) internal returns (VersionParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionCloseable(versionSeed);
        require(found, ClampFail("no closeable version"));

        params.version = version;
    }

    function rotateIssuerPreconditions(uint256 versionSeed, uint256 issuerSeed)
        internal
        returns (RotateIssuerParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionIssuerRotatablePreferReplaced(versionSeed);
        require(found, ClampFail("no issuer-rotatable version"));

        params = _buildRotateIssuerParams(version, issuerSeed);
    }

    function rotateIssuerInvalidStatusPreconditions(uint256 versionSeed, uint256 issuerSeed)
        internal
        returns (RotateIssuerParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionIssuerRotationInvalidStatus(versionSeed);
        require(found, ClampFail("no issuer-rotation invalid-status version"));

        params = _buildRotateIssuerParams(version, issuerSeed);
    }

    function _buildRotateIssuerParams(uint8 version, uint256 issuerSeed)
        internal
        returns (RotateIssuerParams memory params)
    {
        Bond memory bond = _getBondAtVersion(version);
        address newIssuer = _pickDifferentUser(issuerSeed, bond.issuer);
        require(newIssuer != address(0), ClampFail("no replacement issuer"));
        require(entityRegistry.isAccountEnabled(newIssuer), ClampFail("replacement issuer disabled"));

        params.version = version;
        params.oldIssuer = bond.issuer;
        params.newIssuer = newIssuer;
    }

    function burnReclaimPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (BurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionReclaimable(versionSeed, address(0));
        require(found, ClampFail("no reclaimable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 freeBalance = _freeBalance(bond.issuer, bond.tokenId);
        require(freeBalance > 0, ClampFail("issuer free balance zero"));

        params.version = version;
        params.from = bond.issuer;
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function burnSettlementPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (BurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionSettlementBurnable(versionSeed, address(0));
        require(found, ClampFail("no settlement-burnable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);
        params.version = version;
        params.from = bond.issuer;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function burnSettlementHolderPreconditions(uint256 versionSeed, uint256 holderSeed, uint256 amountSeed)
        internal
        returns (BurnParams memory params)
    {
        (bool found, uint8 version, address holder) = _pickKnownBondVersionSettlementHolder(versionSeed, holderSeed);
        require(found, ClampFail("no non-issuer settlement source"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(holder, bond.tokenId);
        params.version = version;
        params.from = holder;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function burnBatchReclaimPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (BatchBurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionReclaimable(versionSeed, address(0));
        require(found, ClampFail("no batch-reclaimable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 freeBalance = _freeBalance(bond.issuer, bond.tokenId);
        params.version = version;
        params = _buildIssuerBatchBurn(params, bond.issuer, amountSeed, freeBalance);
    }

    function burnReclaimFrozenIssuerPreconditions(uint256 versionSeed, uint256 freezeAmountSeed, uint256 amountSeed)
        internal
        returns (FrozenIssuerReclaimParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        (bool found, uint8 version) = _pickKnownBondVersionReclaimable(versionSeed, address(0));
        require(found, ClampFail("no reclaimable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 freeBefore = _freeBalance(bond.issuer, bond.tokenId);
        require(freeBefore > 0, ClampFail("issuer free balance zero"));

        uint256 freezeAmount = fl.clamp(freezeAmountSeed, 1, freeBefore);
        token.freezePartialTokens(bond.issuer, bond.tokenId, freezeAmount);

        uint256 freeAfter = _freeBalance(bond.issuer, bond.tokenId);
        uint256 frozenAfter = token.frozenBalanceOf(bond.issuer, bond.tokenId);

        params.version = version;
        params.from = bond.issuer;
        params.amount = freeAfter + fl.clamp(amountSeed, 1, frozenAfter);
    }

    function burnBatchSettlementPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (BatchBurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionSettlementBurnable(versionSeed, address(0));
        require(found, ClampFail("no batch-settlement-burnable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);
        params.version = version;
        params = _buildIssuerBatchBurn(params, bond.issuer, amountSeed, balance);
    }

    function bondRegistryViewSurfacePreconditions(uint256 versionSeed, uint256 trancheSeed, uint256 intervalSeed)
        internal
        returns (BondRegistryViewSurfaceParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionWithTranche(versionSeed);
        require(found, ClampFail("no version with tranche"));

        Bond memory bond = _getBondAtVersion(version);
        Bond memory activeBond = _getBondAtVersion(_getActiveBondVersion());
        require(activeBond.trancheCount != 0, ClampFail("active has no tranche"));

        params.version = version;
        params.trancheId = uint16(fl.clamp(trancheSeed, 1, bond.trancheCount));
        params.activeTrancheId = uint16(fl.clamp(trancheSeed, 1, activeBond.trancheCount));
        params.tokenId = bond.tokenId;
        params.couponRateIndex = 1 + (intervalSeed % 3);
    }

    function appendScoringPreconditions(uint256 walletSeed, uint256 scoringSeed)
        internal
        view
        returns (AppendScoringParams memory params)
    {
        params.wallet = users[walletSeed % users.length];
        params.previousCount = bondRegistry.getScoringCount(params.wallet);
        params.scoring = _buildValidScoring(scoringSeed);
    }

    function appendScoringInvalidPreconditions(uint256 caseSeed, uint256 scoringSeed)
        internal
        view
        returns (InvalidScoringParams memory params)
    {
        params.wallet = users[caseSeed % users.length];
        params.scoring = _buildValidScoring(scoringSeed);

        uint256 invalidCase = caseSeed % 5;
        if (invalidCase == 0) {
            params.wallet = address(0);
            params.expectedError = bytes4(keccak256("ZeroAddress()"));
        } else if (invalidCase == 1) {
            params.scoring.issueDate = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__ScoringZeroIssueDate()"));
        } else if (invalidCase == 2) {
            params.scoring.expirationDate = params.scoring.issueDate;
            params.expectedError = bytes4(keccak256("BondRegistry__ScoringExpirationNotAfterIssue()"));
        } else if (invalidCase == 3) {
            params.scoring.distributorId = bytes32(0);
            params.expectedError = bytes4(keccak256("BondRegistry__ScoringZeroDistributorId()"));
        } else {
            params.scoring.defaultProbabilityBps = uint16(bondRegistry.MAX_PROBABILITY_BPS() + 1);
            params.expectedError = bytes4(keccak256("BondRegistry__ScoringProbabilityTooHigh(uint16)"));
        }
    }

    function publishBondInvalidInputPreconditions(uint256 caseSeed, uint256 maxSupplySeed)
        internal
        view
        returns (InvalidBondInputParams memory params)
    {
        params.input = _buildFixedBondInput(BOND_INVALID_INPUT_ISIN, address(this), maxSupplySeed);

        uint256 invalidCase = caseSeed % 14;
        if (invalidCase == 0) {
            params.input.issuer = address(0);
            params.expectedError = bytes4(keccak256("ZeroAddress()"));
        } else if (invalidCase == 1) {
            params.input.issuer = BOND_UNREGISTERED_ISSUER;
            params.expectedError = bytes4(keccak256("BondRegistry__IssuerNotEnabled(address)"));
        } else if (invalidCase == 2) {
            params.input.currency = "USD";
            params.expectedError = bytes4(keccak256("BondRegistry__InvalidCurrency()"));
        } else if (invalidCase == 3) {
            params.input.bondNominalValue = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__BondNominalValueIsZero()"));
        } else if (invalidCase == 4) {
            params.input.maxSupply = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__MaxSupplyIsZero()"));
        } else if (invalidCase == 5) {
            params.input.maturityDate = block.timestamp;
            params.expectedError = bytes4(keccak256("BondRegistry__MaturityDateExpired()"));
        } else if (invalidCase == 6) {
            params.input.couponRates.paymentTimestamps = new uint256[](2);
            params.input.couponRates.rates = new uint256[](1);
            params.input.couponRates.paymentTimestamps[0] = 1;
            params.input.couponRates.paymentTimestamps[1] = 2;
            params.input.couponRates.rates[0] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesLengthMismatch()"));
        } else if (invalidCase == 7) {
            params.input.couponRateType = CouponRateType.ZERO_COUPON;
            params.input.couponRates.paymentTimestamps = new uint256[](1);
            params.input.couponRates.rates = new uint256[](1);
            params.input.couponRates.paymentTimestamps[0] = 1;
            params.input.couponRates.rates[0] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesUnexpectedLength()"));
        } else if (invalidCase == 8) {
            params.input.couponRateType = CouponRateType.FIXED;
            params.input.couponRates.paymentTimestamps = new uint256[](3);
            params.input.couponRates.rates = new uint256[](3);
            params.input.couponRates.paymentTimestamps[0] = 1;
            params.input.couponRates.paymentTimestamps[1] = 2;
            params.input.couponRates.paymentTimestamps[2] = 3;
            params.input.couponRates.rates[0] = BOND_COUPON_RATE;
            params.input.couponRates.rates[1] = BOND_COUPON_RATE + 1;
            params.input.couponRates.rates[2] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesUnexpectedLength()"));
        } else if (invalidCase == 9) {
            params.input.couponRateType = CouponRateType.FLOATING;
            params.input.couponRates.paymentTimestamps = new uint256[](1);
            params.input.couponRates.rates = new uint256[](1);
            params.input.couponRates.paymentTimestamps[0] = 1;
            params.input.couponRates.rates[0] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesUnexpectedLength()"));
        } else if (invalidCase == 10) {
            params.input.couponRates.paymentTimestamps[0] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__PaymentTimestampZero()"));
        } else if (invalidCase == 11) {
            params.input.couponRates.rates[1] = BOND_COUPON_RATE + 1;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesLastRateNotZero()"));
        } else if (invalidCase == 12) {
            params.input.couponRates.paymentTimestamps[0] = 2;
            params.input.couponRates.paymentTimestamps[1] = 1;
            params.expectedError = bytes4(keccak256("BondRegistry__PaymentTimestampsUnordered()"));
        } else {
            params.input.couponRates.rates[0] = 0;
            params.input.couponRates.rates[1] = 0;
            params.expectedError = bytes4(keccak256("BondRegistry__CouponRatesDuplicate()"));
        }
    }

    function issueBondUnauthorizedPreconditions(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed)
        internal
        returns (IssueParams memory params, address caller)
    {
        params = issueBondPreconditions(versionSeed, amountSeed);
        address bondIssuer = _getBondAtVersion(params.version).issuer;
        caller = _pickUnauthorizedIssuer(callerSeed, bondIssuer);
        require(caller != address(0), ClampFail("no unauthorized issuer caller"));
    }

    function issueBondClosedPreconditions(uint256 versionSeed) internal returns (IssueParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionIssuanceClosedIssuableStatus(versionSeed);
        require(found, ClampFail("no issuance-closed issuable-status version"));

        params.version = version;
        params.amount = 1;
    }

    function issueBondZeroAmountPreconditions(uint256 versionSeed) internal returns (IssueParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionIssuable(versionSeed);
        require(found, ClampFail("no zero-amount issuable version"));

        params.version = version;
        params.amount = 0;
    }

    function issueBondMaxSupplyExceededPreconditions(uint256 versionSeed) internal returns (IssueParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionIssuable(versionSeed);
        require(found, ClampFail("no max-supply issuable version"));

        Bond memory bond = _getBondAtVersion(version);
        params.version = version;
        params.amount = bond.remainingIssuableSupply + 1;
    }

    function issueBondMaturityExpiredPreconditions(uint256 versionSeed) internal returns (IssueParams memory params) {
        (bool found, uint8 version) = _pickKnownBondVersionExpiredForIssuance(versionSeed);
        require(found, ClampFail("no maturity-expired issuable-status version"));

        params.version = version;
        params.amount = 1;
    }

    function issueBondInvalidStatusPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionNotIssuable(versionSeed);
        require(found, ClampFail("no non-issuable version"));
        return picked;
    }

    function cancelBondInvalidPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionNotCancellable(versionSeed);
        require(found, ClampFail("no non-cancellable version"));
        return picked;
    }

    function suspendBondInvalidStatusPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionNotIssued(versionSeed);
        require(found, ClampFail("no non-Issued version"));
        return picked;
    }

    function unsuspendBondInvalidStatusPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionNotSuspended(versionSeed);
        require(found, ClampFail("no non-Suspended version"));
        return picked;
    }

    function closeBondInvalidPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionNotCloseable(versionSeed);
        require(found, ClampFail("no non-closeable version"));
        return picked;
    }

    function closeIssuanceInvalidStatusPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionCloseIssuanceInvalidStatus(versionSeed);
        require(found, ClampFail("no close-issuance invalid-status version"));
        return picked;
    }

    function closeIssuanceUnauthorizedPreconditions(uint256 versionSeed, uint256 callerSeed)
        internal
        returns (uint8 version, address caller)
    {
        VersionParams memory params = closeIssuancePreconditions(versionSeed);
        Bond memory bond = _getBondAtVersion(params.version);

        caller = _pickUnauthorizedIssuanceCloser(callerSeed, bond.issuer);
        require(caller != address(0), ClampFail("no unauthorized issuance closer"));

        return (params.version, caller);
    }

    function closeIssuanceAlreadyClosedPreconditions(uint256 versionSeed) internal returns (uint8 version) {
        (bool found, uint8 picked) = _pickKnownBondVersionIssuanceClosedCloseIssuanceStatus(versionSeed);
        require(found, ClampFail("no already-closed issuance version"));
        return picked;
    }

    function burnReclaimUnauthorizedPreconditions(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed)
        internal
        returns (BurnParams memory params, address caller)
    {
        (bool found, uint8 version) = _pickKnownBondVersionByStatus(versionSeed, BondStatus.Issued);
        require(found, ClampFail("no Issued version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);
        require(balance > 0, ClampFail("issuer balance zero"));

        caller = _pickUnauthorizedBurner(callerSeed, bond.issuer);
        require(caller != address(0), ClampFail("no unauthorized caller"));

        params.version = version;
        params.from = bond.issuer;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function burnSettlementUnauthorizedPreconditions(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed)
        internal
        returns (BurnParams memory params, address caller)
    {
        (bool found, uint8 version) = _pickKnownBondVersionSettlementBurnable(versionSeed, address(0));
        require(found, ClampFail("no settlement-burnable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);

        caller = _pickUnauthorizedBurner(callerSeed, bond.issuer);
        require(caller != address(0), ClampFail("no unauthorized caller"));

        params.version = version;
        params.from = bond.issuer;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function burnSettlementBurnerNotEnabledPreconditions(uint256 versionSeed, uint256 amountSeed)
        internal
        returns (BurnParams memory params, address caller)
    {
        (bool found, uint8 version) = _pickKnownBondVersionSettlementBurnable(versionSeed, address(0));
        require(found, ClampFail("no settlement-burnable version"));

        Bond memory bond = _getBondAtVersion(version);
        uint256 balance = token.balanceOf(bond.issuer, bond.tokenId);

        caller = FUZZ_TOKEN_UNREGISTERED_OPERATOR;
        require(!entityRegistry.isAccountEnabled(caller), ClampFail("burner caller enabled"));
        bondRegistry.grantRoles(caller, bondRegistry.BURNER());

        params.version = version;
        params.from = bond.issuer;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function burnInvalidSourcePreconditions(uint256 versionSeed, uint256 kindSeed, uint256 fromSeed)
        internal
        returns (BurnAuthorizationParams memory params)
    {
        bool settlement = kindSeed % 2 == 1;
        (bool found, uint8 version) = settlement
            ? _pickKnownBondVersionSettlementStatus(versionSeed)
            : _pickKnownBondVersionByStatus(versionSeed, BondStatus.Issued);
        require(found, ClampFail("no invalid-source burn-status version"));

        Bond memory bond = _getBondAtVersion(version);
        address from = _pickDifferentUser(fromSeed, bond.issuer);
        require(from != address(0), ClampFail("no invalid burn source"));

        params.version = version;
        params.from = from;
        params.amount = 1;
        params.kind = settlement ? BurnKind.FINAL_SETTLEMENT : BurnKind.ISSUER_RECLAIM;
        params.caller = bond.issuer;
    }

    function burnInvalidStatusPreconditions(uint256 versionSeed, uint256 kindSeed)
        internal
        returns (BurnAuthorizationParams memory params)
    {
        bool settlement = kindSeed % 2 == 1;
        (bool found, uint8 version) = _pickKnownBondVersionBurnInvalidStatus(versionSeed, settlement);
        require(found, ClampFail("no invalid burn-status version"));

        Bond memory bond = _getBondAtVersion(version);
        params.version = version;
        params.from = bond.issuer;
        params.amount = 1;
        params.kind = settlement ? BurnKind.FINAL_SETTLEMENT : BurnKind.ISSUER_RECLAIM;
        params.caller = settlement ? address(this) : bond.issuer;
    }

    function burnBatchLengthMismatchPreconditions(uint256 versionSeed)
        internal
        returns (BatchBurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersion(versionSeed);
        require(found, ClampFail("no existing batch-length-mismatch version"));

        Bond memory bond = _getBondAtVersion(version);
        params.version = version;
        params.froms = new address[](1);
        params.amounts = new uint256[](2);
        params.froms[0] = bond.issuer;
        params.amounts[0] = 1;
        params.amounts[1] = 1;
        params.totalAmount = 2;
    }

    function burnBatchInvalidSourcePreconditions(uint256 versionSeed, uint256 fromSeed)
        internal
        returns (BatchBurnParams memory params)
    {
        (bool found, uint8 version) = _pickKnownBondVersionByStatus(versionSeed, BondStatus.Issued);
        require(found, ClampFail("no batch invalid-source Issued version"));

        Bond memory bond = _getBondAtVersion(version);
        address invalidSource = _pickDifferentUser(fromSeed, bond.issuer);
        require(invalidSource != address(0), ClampFail("no batch invalid source"));

        params.version = version;
        params.froms = new address[](2);
        params.amounts = new uint256[](2);
        params.froms[0] = bond.issuer;
        params.froms[1] = invalidSource;
        params.amounts[0] = 1;
        params.amounts[1] = 1;
        params.totalAmount = 2;
    }

    function _pickUnauthorizedBurner(uint256 seed, address bondIssuer) internal returns (address caller) {
        uint256 len = users.length;
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            address candidate = users[(start + i) % len];
            if (candidate != bondIssuer && !bondRegistry.hasAnyRole(candidate, bondRegistry.BURNER())) {
                return candidate;
            }
        }
        return address(0);
    }

    function _pickUnauthorizedIssuer(uint256 seed, address bondIssuer) internal returns (address caller) {
        uint256 len = users.length;
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            address candidate = users[(start + i) % len];
            if (candidate != bondIssuer && !bondRegistry.hasAnyRole(candidate, bondRegistry.PUBLISHER())) {
                return candidate;
            }
        }
        return address(0);
    }

    function _pickUnauthorizedIssuanceCloser(uint256 seed, address bondIssuer) internal returns (address caller) {
        uint256 len = users.length;
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            address candidate = users[(start + i) % len];
            if (candidate != bondIssuer && !bondRegistry.hasAnyRole(candidate, bondRegistry.PUBLISHER())) {
                return candidate;
            }
        }
        return address(0);
    }

    function _buildIssuerBatchBurn(
        BatchBurnParams memory params,
        address bondIssuer,
        uint256 amountSeed,
        uint256 maxAmount
    ) internal returns (BatchBurnParams memory) {
        require(maxAmount > 0, ClampFail("batch burn balance zero"));

        uint256 totalAmount = fl.clamp(amountSeed, 1, maxAmount);
        params.totalAmount = totalAmount;

        if (totalAmount == 1) {
            params.froms = new address[](1);
            params.amounts = new uint256[](1);
            params.froms[0] = bondIssuer;
            params.amounts[0] = 1;
            return params;
        }

        uint256 firstAmount = fl.clamp(amountSeed >> 128, 1, totalAmount - 1);
        params.froms = new address[](2);
        params.amounts = new uint256[](2);
        params.froms[0] = bondIssuer;
        params.froms[1] = bondIssuer;
        params.amounts[0] = firstAmount;
        params.amounts[1] = totalAmount - firstAmount;

        return params;
    }

    function _freeBalance(address account, uint256 tokenId) internal view returns (uint256) {
        uint256 balance = token.balanceOf(account, tokenId);
        uint256 frozenBalance = token.frozenBalanceOf(account, tokenId);
        return balance > frozenBalance ? balance - frozenBalance : 0;
    }

    function _buildBondInput(address bondIssuer, uint256 maxSupplySeed) internal returns (BondInput memory input) {
        CouponRateType couponRateType;
        uint256[] memory paymentTimestamps;
        uint256[] memory rates;
        uint256 rate = BOND_COUPON_RATE + (maxSupplySeed % 1_000);
        uint256 couponVariant = maxSupplySeed % 3;

        if (couponVariant == 1) {
            couponRateType = CouponRateType.ZERO_COUPON;
            paymentTimestamps = new uint256[](0);
            rates = new uint256[](0);
        } else if (couponVariant == 2) {
            couponRateType = CouponRateType.FLOATING;
            paymentTimestamps = new uint256[](3);
            rates = new uint256[](3);
            paymentTimestamps[0] = 1;
            paymentTimestamps[1] = 2;
            paymentTimestamps[2] = 3;
            rates[0] = rate;
            rates[1] = rate + 1;
            rates[2] = 0;
        } else {
            couponRateType = CouponRateType.FIXED;
            paymentTimestamps = new uint256[](2);
            rates = new uint256[](2);
            paymentTimestamps[0] = 1;
            paymentTimestamps[1] = 2;
            rates[0] = rate;
            rates[1] = 0;
        }

        input = BondInput({
            isin: BOND_ISIN,
            issuer: bondIssuer,
            currency: BOND_CURRENCY,
            bondNominalValue: BOND_NOMINAL_VALUE + (maxSupplySeed % 10),
            maxSupply: fl.clamp(maxSupplySeed, 1, BOND_ISSUE_COUNT),
            couponRates: CouponRates(paymentTimestamps, rates),
            couponRateType: couponRateType,
            maturityDate: block.timestamp + 365 days + (maxSupplySeed % (30 days)),
            couponFrequency: CouponFrequency(uint8(maxSupplySeed % 5)),
            isGuaranteed: maxSupplySeed % 2 == 1,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
    }

    function _buildFixedBondInput(string memory isin, address bondIssuer, uint256 maxSupplySeed)
        internal
        view
        returns (BondInput memory input)
    {
        uint256[] memory paymentTimestamps = new uint256[](2);
        uint256[] memory rates = new uint256[](2);
        paymentTimestamps[0] = 1;
        paymentTimestamps[1] = 2;
        rates[0] = BOND_COUPON_RATE + (maxSupplySeed % 1_000);
        rates[1] = 0;

        input = BondInput({
            isin: isin,
            issuer: bondIssuer,
            currency: BOND_CURRENCY,
            bondNominalValue: BOND_NOMINAL_VALUE + (maxSupplySeed % 10),
            maxSupply: (maxSupplySeed % BOND_ISSUE_COUNT) + 1,
            couponRates: CouponRates(paymentTimestamps, rates),
            couponRateType: CouponRateType.FIXED,
            maturityDate: block.timestamp + 365 days + (maxSupplySeed % (30 days)),
            couponFrequency: CouponFrequency(uint8(maxSupplySeed % 5)),
            isGuaranteed: maxSupplySeed % 2 == 1,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
    }

    function _buildZeroCouponBondInput(string memory isin, address bondIssuer, uint256 maxSupplySeed)
        internal
        view
        returns (BondInput memory input)
    {
        uint256[] memory paymentTimestamps = new uint256[](0);
        uint256[] memory rates = new uint256[](0);

        input = BondInput({
            isin: isin,
            issuer: bondIssuer,
            currency: BOND_CURRENCY,
            bondNominalValue: BOND_NOMINAL_VALUE + (maxSupplySeed % 10),
            maxSupply: (maxSupplySeed % BOND_ISSUE_COUNT) + 1,
            couponRates: CouponRates(paymentTimestamps, rates),
            couponRateType: CouponRateType.ZERO_COUPON,
            maturityDate: block.timestamp + 365 days + (maxSupplySeed % (30 days)),
            couponFrequency: CouponFrequency(uint8(maxSupplySeed % 5)),
            isGuaranteed: maxSupplySeed % 2 == 1,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
    }

    function _buildValidScoring(uint256 scoringSeed) internal pure returns (Scoring memory scoring) {
        uint64 issueDate = uint64(1 + (scoringSeed % 1_000_000));
        bytes32 distributorId = bytes32(uint256(keccak256(abi.encodePacked(scoringSeed))) | uint256(1));

        scoring = Scoring({
            defaultProbabilityBps: uint16(scoringSeed % 10_001),
            issueDate: issueDate,
            expirationDate: issueDate + 1,
            distributorId: distributorId
        });
    }

    function _pickUpdateIssuer(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }
}

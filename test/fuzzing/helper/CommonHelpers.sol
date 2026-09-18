// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-strict-inequalities, no-empty-blocks */

import {FuzzBase} from "@perimetersec/fuzzlib/src/FuzzBase.sol";
import {Deal, Interest, InterestDiscoveryState, Offer, SaleMode} from "src/marketplace/MarketStructs.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {Bond, BondStatus} from "src/registry/BondStructs.sol";
import {Account, EntityStatus, PendingAccountRegistration} from "src/registry/EntityStructs.sol";
import {FuzzStorageVariables} from "./FuzzStorageVariables.sol";

abstract contract CommonHelpers is FuzzBase, FuzzStorageVariables {
    bytes4 internal constant _CLAMP_FAIL_SELECTOR = bytes4(keccak256("ClampFail(string)"));

    function _onOfferTracked(uint256) internal virtual {}

    function _onDealTracked(uint256) internal virtual {}

    function _onInterestTracked(uint256) internal virtual {}

    function _onEscrowTracked(uint256) internal virtual {}

    function _onEntityTracked(bytes32) internal virtual {}

    function _onFuzzEntityTracked(bytes32) internal virtual {}

    function _onOfferEvicted(uint256) internal virtual {}

    function _onDealEvicted(uint256) internal virtual {}

    function _onInterestEvicted(uint256) internal virtual {}

    function _onEscrowEvicted(uint256) internal virtual {}

    function _onEntityEvicted(bytes32) internal virtual {}

    function _onFuzzEntityEvicted(bytes32) internal virtual {}

    function _trackOfferId(uint256 offerId) internal {
        if (offerId == 0 || trackedOffer[offerId]) return;

        // Keep a bounded set of real offer IDs that the harness can later pick
        // from and scan for broader cross-offer invariants.
        trackedOffer[offerId] = true;
        if (knownOfferIds.length < MAX_TRACKED_ITEMS) {
            knownOfferIds.push(offerId);
            // Notify derived helpers that this ID just entered the tracked set.
            _onOfferTracked(offerId);
            return;
        }

        // Once the bounded array is full, overwrite one slot in round-robin
        // order so tracking remains capped and fuzz runs do not grow memory
        // usage without bound.
        uint256 idx = trackedOfferCursor % MAX_TRACKED_ITEMS;
        uint256 evicted = knownOfferIds[idx];
        // trackedOffer means "currently present in knownOfferIds", not "seen at
        // least once", so the evicted ID must be cleared before replacement.
        trackedOffer[evicted] = false;
        // Let higher layers clean up any side indexes that still reference the
        // evicted ID, such as FuzzStateIndex buckets.
        _onOfferEvicted(evicted);
        knownOfferIds[idx] = offerId;
        ++trackedOfferCursor;
        // Notify derived helpers that the replacement ID is now selectable.
        _onOfferTracked(offerId);
    }

    function _trackDealId(uint256 dealId) internal {
        if (dealId == 0 || trackedDeal[dealId]) return;

        // Keep a bounded set of real deal IDs that later handlers can act on.
        trackedDeal[dealId] = true;
        if (knownDealIds.length < MAX_TRACKED_ITEMS) {
            knownDealIds.push(dealId);
            // Notify derived helpers that this deal is now part of the tracked set.
            _onDealTracked(dealId);
            return;
        }

        // Apply the same round-robin bounded replacement policy as offers.
        uint256 idx = trackedDealCursor % MAX_TRACKED_ITEMS;
        uint256 evicted = knownDealIds[idx];
        // trackedDeal means "currently present in knownDealIds", not "seen at
        // least once", so the evicted ID must be cleared before replacement.
        trackedDeal[evicted] = false;
        // Give higher layers a chance to remove stale references to the deal.
        _onDealEvicted(evicted);
        knownDealIds[idx] = dealId;
        ++trackedDealCursor;
        // The new deal now belongs to the tracked set.
        _onDealTracked(dealId);
    }

    function _trackEscrowId(uint256 escrowId) internal {
        if (escrowId == 0 || trackedEscrow[escrowId]) return;

        // Keep a bounded set of real escrow IDs that later handlers can act on
        // and scan for cross-escrow invariants.
        trackedEscrow[escrowId] = true;
        if (knownEscrowIds.length < MAX_TRACKED_ITEMS) {
            knownEscrowIds.push(escrowId);
            _onEscrowTracked(escrowId);
            return;
        }

        uint256 idx = trackedEscrowCursor % MAX_TRACKED_ITEMS;
        // trackedEscrow means "currently present in knownEscrowIds", not "seen
        // at least once", so the evicted ID must be cleared before replacement.
        uint256 evicted = knownEscrowIds[idx];
        trackedEscrow[evicted] = false;
        _onEscrowEvicted(evicted);
        knownEscrowIds[idx] = escrowId;
        ++trackedEscrowCursor;
        _onEscrowTracked(escrowId);
    }

    function _trackEntityId(bytes32 entityId) internal {
        if (entityId == bytes32(0) || trackedEntity[entityId]) return;

        trackedEntity[entityId] = true;
        if (knownEntityIds.length < MAX_TRACKED_ITEMS) {
            knownEntityIds.push(entityId);
            _onEntityTracked(entityId);
            return;
        }

        uint256 idx = trackedEntityCursor % MAX_TRACKED_ITEMS;
        bytes32 evicted = knownEntityIds[idx];
        trackedEntity[evicted] = false;
        _onEntityEvicted(evicted);
        knownEntityIds[idx] = entityId;
        ++trackedEntityCursor;
        _onEntityTracked(entityId);
    }

    function _trackFuzzEntityId(bytes32 entityId) internal {
        _trackEntityId(entityId);

        if (entityId == bytes32(0) || trackedFuzzEntity[entityId]) return;

        trackedFuzzEntity[entityId] = true;
        if (knownFuzzEntityIds.length < MAX_TRACKED_ITEMS) {
            knownFuzzEntityIds.push(entityId);
            _onFuzzEntityTracked(entityId);
            return;
        }

        uint256 idx = trackedFuzzEntityCursor % MAX_TRACKED_ITEMS;
        bytes32 evicted = knownFuzzEntityIds[idx];
        trackedFuzzEntity[evicted] = false;
        _onFuzzEntityEvicted(evicted);
        knownFuzzEntityIds[idx] = entityId;
        ++trackedFuzzEntityCursor;
        _onFuzzEntityTracked(entityId);
    }

    function _trackPendingRegistration(address account, bytes32 entityId) internal {
        if (account == address(0) || entityId == bytes32(0)) return;

        bytes32 key = _pendingRegistrationKey(account, entityId);
        if (trackedPendingRegistration[key]) return;

        trackedPendingRegistration[key] = true;
        PendingRegistrationRef memory ref = PendingRegistrationRef({account: account, entityId: entityId});
        if (knownPendingRegistrations.length < MAX_TRACKED_ITEMS) {
            knownPendingRegistrations.push(ref);
            return;
        }

        uint256 idx = trackedPendingRegistrationCursor % MAX_TRACKED_ITEMS;
        PendingRegistrationRef memory evicted = knownPendingRegistrations[idx];
        trackedPendingRegistration[_pendingRegistrationKey(evicted.account, evicted.entityId)] = false;
        knownPendingRegistrations[idx] = ref;
        ++trackedPendingRegistrationCursor;
    }

    function _clearPendingRegistration(address account, bytes32 entityId) internal {
        trackedPendingRegistration[_pendingRegistrationKey(account, entityId)] = false;
    }

    function _pickTrackedPendingRegistration(uint256 seed)
        internal
        returns (bool found, address account, bytes32 entityId)
    {
        uint256 len = knownPendingRegistrations.length;
        if (len == 0) return (false, address(0), bytes32(0));

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            PendingRegistrationRef memory candidate = knownPendingRegistrations[(start + i) % len];
            bytes32 key = _pendingRegistrationKey(candidate.account, candidate.entityId);
            if (!trackedPendingRegistration[key]) continue;

            if (_isPendingRegistrationLive(candidate.account, candidate.entityId)) {
                return (true, candidate.account, candidate.entityId);
            }

            trackedPendingRegistration[key] = false;
        }

        return (false, address(0), bytes32(0));
    }

    function _trackInterestId(uint256 interestId) internal {
        if (interestId == 0 || trackedInterest[interestId]) return;

        trackedInterest[interestId] = true;
        if (knownInterestIds.length < MAX_TRACKED_ITEMS) {
            knownInterestIds.push(interestId);
            // Notify derived helpers that this interest is now tracked.
            _onInterestTracked(interestId);
            return;
        }

        // Interests use the same bounded round-robin replacement policy.
        uint256 idx = trackedInterestCursor % MAX_TRACKED_ITEMS;
        uint256 evicted = knownInterestIds[idx];
        trackedInterest[evicted] = false;
        // Give higher layers a chance to remove stale references to the interest.
        _onInterestEvicted(evicted);
        knownInterestIds[idx] = interestId;
        ++trackedInterestCursor;
        // The replacement interest is now part of the tracked set.
        _onInterestTracked(interestId);
    }

    function _trackBondVersion(uint8 version) internal {
        if (version == 0 || trackedBondVersion[version]) return;

        trackedBondVersion[version] = true;
        if (knownBondVersions.length < MAX_TRACKED_ITEMS) {
            knownBondVersions.push(version);
            return;
        }

        uint256 idx = trackedBondVersionCursor % MAX_TRACKED_ITEMS;
        trackedBondVersion[knownBondVersions[idx]] = false;
        knownBondVersions[idx] = version;
        ++trackedBondVersionCursor;
    }

    function _pickKnownBondVersion(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate != 0) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionByStatus(uint256 seed, BondStatus target)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;
            if (_getBondAtVersion(candidate).status == target) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionWithTranche(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;
            if (_getBondAtVersion(candidate).trancheCount != 0) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionNotPublished(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;
            if (_getBondAtVersion(candidate).status != BondStatus.Published) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (
                (bond.status == BondStatus.Published || bond.status == BondStatus.Issued) && !bond.issuanceClosed
                    && bond.remainingIssuableSupply > 0 && bond.maturityDate > block.timestamp
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionCloseable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint8 activeVersion = _getActiveBondVersion();
        uint8 latestVersion = _getLatestBondVersion();
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            bool activeHasPendingSuccessor = candidate == activeVersion && latestVersion != candidate
                && _getBondAtVersion(latestVersion).status == BondStatus.Published;
            if (
                (bond.status == BondStatus.Issued || bond.status == BondStatus.Suspended)
                    && token.totalSupply(bond.tokenId) == 0 && !activeHasPendingSuccessor
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuerRotatablePreferReplaced(uint256 seed)
        internal
        returns (bool found, uint8 version)
    {
        (found, version) = _pickKnownBondVersionByStatus(seed, BondStatus.Replaced);
        if (found) return (true, version);

        return _pickKnownBondVersionIssuerRotatable(seed);
    }

    function _pickKnownBondVersionIssuerRotatable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            BondStatus status = _getBondAtVersion(candidate).status;
            if (
                status == BondStatus.Published || status == BondStatus.Issued || status == BondStatus.Suspended
                    || status == BondStatus.Replaced
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuerRotationInvalidStatus(uint256 seed)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            BondStatus status = _getBondAtVersion(candidate).status;
            if (status == BondStatus.Cancelled || status == BondStatus.Redeemed) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickPublishedSuccessorVersion(uint256 seed, uint8 activeVersion)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0 || candidate == activeVersion) continue;
            if (_getBondAtVersion(candidate).status == BondStatus.Published) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuanceUnclosed(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (!bond.issuanceClosed && (bond.status == BondStatus.Issued || bond.status == BondStatus.Suspended)) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionCancellable() internal returns (bool found, uint8 version) {
        uint8 latest = _getLatestBondVersion();
        if (latest == 0) return (false, 0);

        Bond memory bond = _getBondAtVersion(latest);
        if (bond.status == BondStatus.Published && bond.trancheCount == 0) {
            return (true, latest);
        }

        return (false, 0);
    }

    function _pickKnownBondVersionReclaimable(uint256 seed, address from) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            address burnSource = from == address(0) ? bond.issuer : from;
            if (
                bond.status == BondStatus.Issued && (from == address(0) || bond.issuer == from)
                    && _isBondReclaimSourceUsable(burnSource, bond.tokenId)
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionSettlementBurnable(uint256 seed, address from)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            address burnSource = from == address(0) ? bond.issuer : from;
            if (
                (bond.status == BondStatus.Issued || bond.status == BondStatus.Replaced)
                    && (from == address(0) || bond.issuer == from) && _isBondBurnSourceUsable(burnSource, bond.tokenId)
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionSettlementHolder(uint256 versionSeed, uint256 holderSeed)
        internal
        returns (bool found, uint8 version, address holder)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0, address(0));

        uint256 versionStart = fl.clamp(versionSeed, 0, len - 1);
        uint256 holderSlots = users.length + 1;
        uint256 holderStart = fl.clamp(holderSeed, 0, holderSlots - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidateVersion = knownBondVersions[(versionStart + i) % len];
            if (candidateVersion == 0) continue;

            Bond memory bond = _getBondAtVersion(candidateVersion);
            bool statusAllowed = bond.status == BondStatus.Issued || bond.status == BondStatus.Replaced;
            if (!statusAllowed) continue;

            for (uint256 j; j < holderSlots; ++j) {
                address candidateHolder = _settlementBurnSourceAt((holderStart + j) % holderSlots);
                if (candidateHolder == bond.issuer) continue;
                if (_isBondBurnSourceUsable(candidateHolder, bond.tokenId)) {
                    return (true, candidateVersion, candidateHolder);
                }
            }
        }

        return (false, 0, address(0));
    }

    function _isBondBurnSourceUsable(address account, uint256 tokenId) internal view returns (bool) {
        return !token.paused() && entityRegistry.isAccountEnabled(account) && !token.isAddressProtected(account)
            && token.balanceOf(account, tokenId) > 0;
    }

    function _isBondReclaimSourceUsable(address account, uint256 tokenId) internal view returns (bool) {
        if (!_isBondBurnSourceUsable(account, tokenId)) return false;

        uint256 balance = token.balanceOf(account, tokenId);
        uint256 frozenBalance = token.frozenBalanceOf(account, tokenId);
        return balance > frozenBalance;
    }

    function _settlementBurnSourceAt(uint256 index) internal view returns (address) {
        if (index < users.length) return users[index];
        return address(this);
    }

    function _pickKnownBondVersionNotIssuable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (bond.status != BondStatus.Published && bond.status != BondStatus.Issued) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionNotCancellable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (bond.status != BondStatus.Published || bond.trancheCount != 0) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionNotIssued(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            if (_getBondAtVersion(candidate).status != BondStatus.Issued) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionNotSuspended(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            if (_getBondAtVersion(candidate).status != BondStatus.Suspended) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionNotCloseable(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint8 activeVersion = _getActiveBondVersion();
        uint8 latestVersion = _getLatestBondVersion();
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            bool statusOk = bond.status == BondStatus.Issued || bond.status == BondStatus.Suspended;
            bool activeHasPendingSuccessor = candidate == activeVersion && latestVersion != candidate
                && _getBondAtVersion(latestVersion).status == BondStatus.Published;
            if (!statusOk || token.totalSupply(bond.tokenId) > 0 || activeHasPendingSuccessor) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuanceClosedIssuableStatus(uint256 seed)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (bond.issuanceClosed && bond.status == BondStatus.Issued) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionIssuanceClosedCloseIssuanceStatus(uint256 seed)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (bond.issuanceClosed && (bond.status == BondStatus.Issued || bond.status == BondStatus.Suspended)) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionExpiredForIssuance(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            Bond memory bond = _getBondAtVersion(candidate);
            if (
                !bond.issuanceClosed && (bond.status == BondStatus.Published || bond.status == BondStatus.Issued)
                    && bond.maturityDate <= block.timestamp
            ) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionCloseIssuanceInvalidStatus(uint256 seed)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            BondStatus status = _getBondAtVersion(candidate).status;
            if (status != BondStatus.Issued && status != BondStatus.Suspended) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionSettlementStatus(uint256 seed) internal returns (bool found, uint8 version) {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            BondStatus status = _getBondAtVersion(candidate).status;
            if (status == BondStatus.Issued || status == BondStatus.Replaced) {
                return (true, candidate);
            }
        }

        return (false, 0);
    }

    function _pickKnownBondVersionBurnInvalidStatus(uint256 seed, bool settlement)
        internal
        returns (bool found, uint8 version)
    {
        uint256 len = knownBondVersions.length;
        if (len == 0) return (false, 0);

        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            uint8 candidate = knownBondVersions[(start + i) % len];
            if (candidate == 0) continue;

            BondStatus status = _getBondAtVersion(candidate).status;
            bool statusAllowed =
                settlement ? status == BondStatus.Issued || status == BondStatus.Replaced : status == BondStatus.Issued;
            if (!statusAllowed) return (true, candidate);
        }

        return (false, 0);
    }

    function _pickDifferentUser(uint256 seed, address excluded) internal returns (address picked) {
        uint256 len = users.length;
        uint256 start = fl.clamp(seed, 0, len - 1);
        for (uint256 i; i < len; ++i) {
            address candidate = users[(start + i) % len];
            if (candidate != excluded) return candidate;
        }
        return address(0);
    }

    function _isDirectSaleMode(SaleMode saleMode) internal pure returns (bool direct) {
        return saleMode == SaleMode.MARKETPLACE || saleMode == SaleMode.REDEMPTION;
    }

    function _isBuyerAllowed(uint256 offerId, Offer memory offer, address buyer) internal view returns (bool allowed) {
        (,,, address[] memory allowedBuyers,) = marketplace.getOfferData(offerId);
        if (offer.saleMode == SaleMode.MARKETPLACE && allowedBuyers.length == 0) {
            return true;
        }
        if (offer.saleMode != SaleMode.REDEMPTION && offer.saleMode != SaleMode.MARKETPLACE) {
            return false;
        }

        for (uint256 i; i < allowedBuyers.length; ++i) {
            if (allowedBuyers[i] == buyer) return true;
        }

        return false;
    }

    function _interestActivationDeadline(uint256 offerExpiry, InterestDiscoveryState memory state)
        internal
        view
        returns (uint256 activationDeadline)
    {
        return offerExpiry + state.paymentExpiryThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                                GENERIC
    //////////////////////////////////////////////////////////////*/

    function _decodeUint256(bytes memory data) internal pure returns (uint256 decoded) {
        if (data.length < 32) return 0;
        decoded = abi.decode(data, (uint256));
    }

    function _allowClampFail(bytes4 errorSelector, string memory context) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = _CLAMP_FAIL_SELECTOR;
        fl.errAllow(errorSelector, allowedErrors, context);
    }

    function _emptyAddressArray() internal pure returns (address[] memory arr) {
        arr = new address[](0);
    }

    function _emptyUintArray() internal pure returns (uint256[] memory arr) {
        arr = new uint256[](0);
    }

    function _singleActorArray(address actor) internal pure returns (address[] memory actors) {
        actors = new address[](1);
        actors[0] = actor;
    }

    function _twoActorArray(address actor0, address actor1) internal pure returns (address[] memory actors) {
        actors = new address[](2);
        actors[0] = actor0;
        actors[1] = actor1;
    }

    function _singleUintArray(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _emptyBytes32Array() internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](0);
    }

    function _singleBytes32Array(bytes32 value) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](1);
        arr[0] = value;
    }

    function _twoBytes32Array(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](2);
        arr[0] = a;
        arr[1] = b;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function _getOffer(uint256 offerId) internal view returns (Offer memory offer) {
        (offer,,,,) = marketplace.getOfferData(offerId);
    }

    function _getDeal(uint256 dealId) internal view returns (Deal memory deal) {
        (deal,) = marketplace.getDealData(dealId);
    }

    function _getInterest(uint256 interestId) internal view returns (Interest memory interest) {
        interest = marketplace.getInterestData(interestId);
    }

    function _isOfferCancelled(uint256 offerId) internal view returns (bool cancelled) {
        (cancelled,,) = marketplace.getOfferFlags(offerId);
    }

    function _getEscrowIdByOfferId(uint256 offerId) internal view returns (uint256 escrowId) {
        (,,,, escrowId) = marketplace.getOfferData(offerId);
    }

    function _isOfferFrozen(uint256 offerId) internal view returns (bool frozen) {
        (, frozen,) = marketplace.getOfferFlags(offerId);
    }

    function _isDealFrozen(uint256 dealId) internal view returns (bool frozen) {
        (, frozen) = marketplace.getDealData(dealId);
    }

    function _getOfferCounter() internal view returns (uint256 offerCounter) {
        return _getMarketplaceCounters().offerCounter;
    }

    function _getDealCounter() internal view returns (uint256 dealCounter) {
        return _getMarketplaceCounters().dealCounter;
    }

    function _getInterestCounter() internal view returns (uint256 interestCounter) {
        return _getMarketplaceCounters().interestCounter;
    }

    function _getMarketplaceCounters() private view returns (MarketplaceStorage.Counters memory counters) {
        (, counters) = marketplace.getConfigAndCounters();
    }

    function _getMarketplaceConfig() private view returns (MarketplaceStorage.Config memory config) {
        (config,) = marketplace.getConfigAndCounters();
    }

    function _getInterestDiscoveryState(uint256 offerId) internal view returns (InterestDiscoveryState memory state) {
        (, state,,,) = marketplace.getOfferData(offerId);
    }

    function _getDisputeBufferPeriod() internal view returns (uint256 disputeBufferPeriod) {
        return _getMarketplaceConfig().disputeBufferPeriod;
    }

    function _getMarketplacePaymentExpiryThreshold() internal view returns (uint256 paymentExpiryThreshold) {
        return _getMarketplaceConfig().marketplacePaymentExpiryThreshold;
    }

    function _getInterestDiscoveryPaymentExpiryThreshold() internal view returns (uint256 paymentExpiryThreshold) {
        return _getMarketplaceConfig().interestDiscoveryPaymentExpiryThreshold;
    }

    function _getRedemptionPaymentThreshold() internal view returns (uint256 paymentExpiryThreshold) {
        return _getMarketplaceConfig().redemptionPaymentExpiryThreshold;
    }

    function _getMaxCounterOffersPerUser() internal view returns (uint256 maxCounterOffersPerUser) {
        return _getMarketplaceConfig().maxCounterOffersPerUser;
    }

    function _getCounterOfferCount(address user, uint256 offerId) internal view returns (uint256 counterOfferCount) {
        return marketplace.getCounterOfferCount(user, offerId);
    }

    function _tokenPaused() internal view returns (bool) {
        return _tokenPaused(bondTokenId);
    }

    function _tokenPaused(uint256 tokenId) internal view returns (bool) {
        return token.paused() || token.isTokenPaused(tokenId);
    }

    function _offerTokenPaused(uint256 offerId) internal view returns (bool) {
        Offer memory offer = _getOffer(offerId);

        return _tokenPaused(offer.tokenId);
    }

    function _getBondAtVersion(uint8 version) internal view returns (Bond memory bond) {
        bond = bondRegistry.getBondAtVersion(BOND_ISIN_BYTES12, version);
    }

    function _getLatestBondVersion() internal view returns (uint8) {
        return bondRegistry.getLatestVersion(BOND_ISIN_BYTES12);
    }

    function _getActiveBondVersion() internal view returns (uint8) {
        return bondRegistry.getActiveVersion(BOND_ISIN_BYTES12);
    }

    function _getEntityStatus(bytes32 entityId) internal view returns (EntityStatus) {
        return entityRegistry.getEntityStatus(entityId);
    }

    function _getEntityAccountCount(bytes32 entityId) internal view returns (uint256) {
        return entityRegistry.getEntityAccounts(entityId).length;
    }

    function _getAccountData(address account) internal view returns (Account memory) {
        return entityRegistry.getAccount(account);
    }

    function _getPendingRegistration(address account, bytes32 entityId)
        internal
        view
        returns (PendingAccountRegistration memory)
    {
        return entityRegistry.getPendingAccountRegistration(account, entityId);
    }

    function _isAccountRegistered(address account) internal view returns (bool) {
        return entityRegistry.isAccountRegistered(account);
    }

    function _isPendingRegistrationLive(address account, bytes32 entityId) internal view returns (bool) {
        return _getPendingRegistration(account, entityId).requester != address(0);
    }

    function _isEntityManagerSet(bytes32 entityId, address manager) internal view returns (bool) {
        return entityRegistry.isEntityManager(entityId, manager);
    }

    function _pendingRegistrationKey(address account, bytes32 entityId) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, entityId));
    }
}

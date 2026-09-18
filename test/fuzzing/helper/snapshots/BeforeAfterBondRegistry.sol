// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-strict-inequalities */

import {Bond, BondStatus, Tranche} from "src/registry/BondStructs.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers and aggregate consistency checks for BondRegistry fuzz actions.
abstract contract BeforeAfterBondRegistry is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                              BITMASKS
    //////////////////////////////////////////////////////////////*/

    // Inconsistency bitmask layout used by `_setBondVersionsConsistencyState`.
    // Packing six bool accumulators into a single uint256 keeps the loop frame
    // small enough for both via-ir and the legacy codegen.
    uint256 private constant _MASK_SUPPLY = 1 << 0;
    uint256 private constant _MASK_CAPACITY = 1 << 1;
    uint256 private constant _MASK_PAUSE = 1 << 2;
    uint256 private constant _MASK_REVERSE = 1 << 3;
    uint256 private constant _MASK_TRANCHE = 1 << 4;
    uint256 private constant _MASK_GLOBAL = _MASK_SUPPLY | _MASK_CAPACITY | _MASK_PAUSE;

    /*//////////////////////////////////////////////////////////////
                         ACCOUNT SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    function _beforeBondAccounts(uint8 version, address[] memory accounts) internal {
        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
        _setBondVersionAccountBalances(BEFORE, version, accounts);
    }

    function _afterBondAccounts(uint8 version, address[] memory accounts) internal {
        _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
        _setBondVersionAccountBalances(AFTER, version, accounts);
    }

    /*//////////////////////////////////////////////////////////////
                         VERSION CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /// @dev Walk tracked bond versions, refresh per-version snapshots, and write
    /// the cross-version consistency flags for `callNum`. Per-version checks
    /// live in their own frames and aggregate via a single bitmask local so
    /// neither the legacy nor the via-ir pipeline runs out of stack slots.
    function _setBondVersionsConsistencyState(uint8 callNum) internal {
        uint256 inconsistencies;
        for (uint256 i; i < knownBondVersions.length; ++i) {
            uint8 version = knownBondVersions[i];
            if (version == 0) continue;

            Bond memory bond = _getBondAtVersion(version);
            _setBondVersionState(callNum, version, bond);
            inconsistencies |= _accumulateBondVersionInconsistencies(version, bond);
        }
        states[callNum].allTrackedBondsConsistent = (inconsistencies & _MASK_GLOBAL) == 0;
        states[callNum].allTrackedBondSupplyConsistent = (inconsistencies & _MASK_SUPPLY) == 0;
        states[callNum].allTrackedBondCapacityConsistent = (inconsistencies & _MASK_CAPACITY) == 0;
        states[callNum].allTrackedBondPauseConsistent = (inconsistencies & _MASK_PAUSE) == 0;
        states[callNum].allTrackedBondReverseMappingsConsistent = (inconsistencies & _MASK_REVERSE) == 0;
        states[callNum].allTrackedBondTranchesConsistent = (inconsistencies & _MASK_TRANCHE) == 0;
    }

    /*//////////////////////////////////////////////////////////////
                         CONSISTENCY CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Hides the 3-tuple destructuring of `_checkBondVersionAccounting`
    /// inside its own frame so it does not pile onto the loop frame in
    /// `_setBondVersionsConsistencyState`.
    function _accumulateBondVersionInconsistencies(uint8 version, Bond memory bond)
        internal
        view
        returns (uint256 mask)
    {
        (bool supplyOk, bool capacityOk, bool pauseOk) = _checkBondVersionAccounting(version, bond);
        if (!supplyOk) mask |= _MASK_SUPPLY;
        if (!capacityOk) mask |= _MASK_CAPACITY;
        if (!pauseOk) mask |= _MASK_PAUSE;
        if (!_checkBondReverseMappings(version, bond)) mask |= _MASK_REVERSE;
        if (!_checkBondTrancheConsistency(version, bond)) mask |= _MASK_TRANCHE;
    }

    /// @dev Per-version supply/capacity/pause checks isolated in their own frame
    /// so the legacy codegen can fit `_setBondVersionsConsistencyState`.
    function _checkBondVersionAccounting(uint8 version, Bond memory bond)
        internal
        view
        returns (bool supplyOk, bool capacityOk, bool pauseOk)
    {
        uint256 burnedTotal = burnedReclaimed[version] + burnedSettled[version];
        uint256 live = token.totalSupply(bond.tokenId);
        supplyOk = bond.mintedSupply >= burnedTotal && live == bond.mintedSupply - burnedTotal;
        capacityOk = bond.remainingIssuableSupply + bond.mintedSupply == bond.maxSupply + burnedReclaimed[version];
        bool isActive = bond.status == BondStatus.Published || bond.status == BondStatus.Issued
            || bond.status == BondStatus.Suspended;
        pauseOk = !isActive || (bond.status == BondStatus.Suspended) == token.isTokenPaused(bond.tokenId);
    }

    /// @dev Reverse-mapping consistency checks isolated in their own frame.
    function _checkBondReverseMappings(uint8 version, Bond memory bond) internal view returns (bool) {
        (bytes12 reverseIsin, uint8 reverseVersion) = bondRegistry.getBondSeriesByTokenId(bond.tokenId);
        Bond memory reverseBond = bondRegistry.getBondByTokenId(bond.tokenId);
        uint256 expectedTokenId = uint256(keccak256(abi.encodePacked(BOND_ISIN_BYTES12, version)));
        if (reverseIsin != BOND_ISIN_BYTES12 || reverseVersion != version) return false;
        if (bond.tokenAddress != address(token) || bond.tokenId != expectedTokenId) return false;
        if (
            reverseBond.isin != BOND_ISIN_BYTES12 || reverseBond.tokenId != bond.tokenId
                || reverseBond.status != bond.status || reverseBond.tokenAddress != address(token)
        ) return false;
        return true;
    }

    /// @dev Tranche-issue-sum consistency check isolated in its own frame.
    function _checkBondTrancheConsistency(uint8 version, Bond memory bond) internal view returns (bool) {
        uint256 trancheIssueSum;
        for (uint256 trancheId = 1; trancheId <= bond.trancheCount; ++trancheId) {
            Tranche memory tranche = bondRegistry.getTranche(BOND_ISIN_BYTES12, version, uint16(trancheId));
            trancheIssueSum += tranche.issueCount;
        }
        return trancheIssueSum == bond.mintedSupply;
    }

    /*//////////////////////////////////////////////////////////////
                          SNAPSHOT SETTERS
    //////////////////////////////////////////////////////////////*/

    function _setBondVersionState(uint8 callNum, uint8 version, Bond memory bond) internal {
        states[callNum].bondVersionStates[version].status = bond.status;
        states[callNum].bondVersionStates[version].issuanceClosed = bond.issuanceClosed;
        states[callNum].bondVersionStates[version].isGuaranteed = bond.isGuaranteed;
        states[callNum].bondVersionStates[version].tokenIdPaused = token.isTokenPaused(bond.tokenId);
        states[callNum].bondVersionStates[version].trancheCount = bond.trancheCount;
        states[callNum].bondVersionStates[version].tokenId = bond.tokenId;
        states[callNum].bondVersionStates[version].tokenAddress = bond.tokenAddress;
        states[callNum].bondVersionStates[version].mintedSupply = bond.mintedSupply;
        states[callNum].bondVersionStates[version].remainingIssuableSupply = bond.remainingIssuableSupply;
        states[callNum].bondVersionStates[version].maxSupply = bond.maxSupply;
        states[callNum].bondVersionStates[version].totalSupply = token.totalSupply(bond.tokenId);
        states[callNum].bondVersionStates[version].issuerBalance = token.balanceOf(bond.issuer, bond.tokenId);
        states[callNum].bondVersionStates[version].issuer = bond.issuer;
        states[callNum].bondVersionStates[version].currency = bond.currency;
        states[callNum].bondVersionStates[version].bondNominalValue = bond.bondNominalValue;
        states[callNum].bondVersionStates[version].couponRateType = uint8(bond.couponRateType);
        states[callNum].bondVersionStates[version].couponFrequency = uint8(bond.couponFrequency);
        states[callNum].bondVersionStates[version].issuanceCountry = bond.issuanceCountry;
        states[callNum].bondVersionStates[version].maturityDate = bond.maturityDate;
        states[callNum].bondVersionStates[version].couponRatesHash =
            keccak256(abi.encode(bond.couponRates.paymentTimestamps, bond.couponRates.rates));
    }

    function _setBondVersionAccountBalances(uint8 callNum, uint8 version, address[] memory accounts) internal {
        Bond memory bond = _getBondAtVersion(version);

        for (uint256 i; i < accounts.length; ++i) {
            address account = accounts[i];
            if (account == address(0)) continue;

            states[callNum].bondVersionAccountBalances[version][account] = token.balanceOf(account, bond.tokenId);
        }
    }
}

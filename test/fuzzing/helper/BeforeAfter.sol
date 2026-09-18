// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BeforeAfterAssetManager} from "./snapshots/BeforeAfterAssetManager.sol";
import {BeforeAfterBondRegistry} from "./snapshots/BeforeAfterBondRegistry.sol";
import {BeforeAfterEntityRegistry} from "./snapshots/BeforeAfterEntityRegistry.sol";
import {BeforeAfterEscrowAuth} from "./snapshots/BeforeAfterEscrowAuth.sol";
import {BeforeAfterDEUSSToken} from "./snapshots/BeforeAfterDEUSSToken.sol";
import {BeforeAfterMarketplace} from "./snapshots/BeforeAfterMarketplace.sol";
import {BeforeAfterPolicyRegistry} from "./snapshots/BeforeAfterPolicyRegistry.sol";
import {BeforeAfterDEP} from "./snapshots/BeforeAfterDEP.sol";
import {BeforeAfterTL} from "./snapshots/BeforeAfterTL.sol";
import {BeforeAfterWALLET} from "./snapshots/BeforeAfterWALLET.sol";
import {SnapshotTypes} from "./snapshots/SnapshotTypes.sol";

/// @notice Aggregates domain-specific before/after snapshot helpers behind the stable handler API.
abstract contract BeforeAfter is
    BeforeAfterMarketplace,
    BeforeAfterBondRegistry,
    BeforeAfterEntityRegistry,
    BeforeAfterDEUSSToken,
    BeforeAfterAssetManager,
    BeforeAfterPolicyRegistry,
    BeforeAfterEscrowAuth,
    BeforeAfterDEP,
    BeforeAfterTL,
    BeforeAfterWALLET
{
    function _before(address[] memory actors, uint256[] memory offerIds, uint256[] memory dealIds)
        internal
        override(SnapshotTypes)
    {
        _setState(BEFORE, actors, offerIds, dealIds, _emptyUintArray());
    }

    function _before(
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal override(SnapshotTypes) {
        _setState(BEFORE, actors, offerIds, dealIds, interestIds);
    }

    function _after(address[] memory actors, uint256[] memory offerIds, uint256[] memory dealIds)
        internal
        override(SnapshotTypes)
    {
        _setState(AFTER, actors, offerIds, dealIds, _emptyUintArray());
    }

    function _after(
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal override(SnapshotTypes) {
        _setState(AFTER, actors, offerIds, dealIds, interestIds);
    }

    function _setState(uint8 callNum, address[] memory actors, uint256[] memory offerIds, uint256[] memory dealIds)
        internal
    {
        _setState(callNum, actors, offerIds, dealIds, _emptyUintArray());
    }

    function _setState(
        uint8 callNum,
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal {
        _setMarketplaceState(callNum, actors, offerIds, dealIds, interestIds);
        _setBondVersionsConsistencyState(callNum);
    }
}

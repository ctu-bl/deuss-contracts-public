// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for DependenciesBase write-once wiring (G-7 / I-4).
/// @dev Captures the three dependency slots exposed by the deployed Marketplace (a concrete
///      DependenciesBase consumer). DependenciesBase itself is a concrete-but-inherited wiring
///      base; EntityEligibilityGuard and EligibilityModuleBase are abstract, so the
///      independently-deployable instance that exposes the dependency setters/getters is
///      `marketplace` (Marketplace -> EligibilityModuleBase -> EntityEligibilityGuard ->
///      DependenciesBase).
abstract contract BeforeAfterDEP is SnapshotTypes {
    function _beforeDEP() internal {
        _setDEPState(BEFORE);
    }

    function _afterDEP() internal {
        _setDEPState(AFTER);
    }

    /// @notice Reads each dependency address from the target DependenciesBase consumer into states.
    function _setDEPState(uint8 callNum) internal {
        states[callNum].depBondRegistry = marketplace.getBondRegistry();
        states[callNum].depEscrowManager = marketplace.getEscrowManager();
        states[callNum].depEntityRegistry = marketplace.getEntityRegistry();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Errors} from "src/libs/Errors.sol";
import {PreconditionsDEP} from "../helper/preconditions/PreconditionsDEP.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

/// @notice Invariants for DependenciesBase write-once dependency wiring (G-7 / I-4).
/// @dev All slots are read from the deployed Marketplace target via the DEP snapshot.
abstract contract Properties_DEP is PropertiesBase {
    /// @notice DEP-01: a non-zero dependency slot is never overwritten with a different address.
    /// @dev Write-once-no-overwrite. Evaluated for all three slots every call.
    function invariant_DEP_01() internal {
        if (states[BEFORE].depBondRegistry != address(0)) {
            fl.eq(states[AFTER].depBondRegistry, states[BEFORE].depBondRegistry, DEP_01);
        }
        if (states[BEFORE].depEscrowManager != address(0)) {
            fl.eq(states[AFTER].depEscrowManager, states[BEFORE].depEscrowManager, DEP_01);
        }
        if (states[BEFORE].depEntityRegistry != address(0)) {
            fl.eq(states[AFTER].depEntityRegistry, states[BEFORE].depEntityRegistry, DEP_01);
        }
    }

    /// @notice DEP-02: a dependency slot that was non-zero never resets back to zero.
    /// @dev Never-back-to-zero. The setter has no path to clear a slot.
    function invariant_DEP_02() internal {
        if (states[BEFORE].depBondRegistry != address(0)) {
            fl.t(states[AFTER].depBondRegistry != address(0), DEP_02);
        }
        if (states[BEFORE].depEscrowManager != address(0)) {
            fl.t(states[AFTER].depEscrowManager != address(0), DEP_02);
        }
        if (states[BEFORE].depEntityRegistry != address(0)) {
            fl.t(states[AFTER].depEntityRegistry != address(0), DEP_02);
        }
    }

    /// @notice DEP-03: an unauthorized caller can never set a dependency (G-7 access control).
    /// @dev The call must have reverted with Unauthorized() and every slot must be unchanged.
    function invariant_DEP_03(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, DEP_03);

        bytes4[] memory allowedErrors = new bytes4[](1);
        // Solady OwnableRoles.onlyRoles reverts with Unauthorized() (0x82b42900).
        allowedErrors[0] = 0x82b42900;
        fl.errAllow(errorSelector, allowedErrors, DEP_03);

        fl.eq(states[AFTER].depBondRegistry, states[BEFORE].depBondRegistry, DEP_03);
        fl.eq(states[AFTER].depEscrowManager, states[BEFORE].depEscrowManager, DEP_03);
        fl.eq(states[AFTER].depEntityRegistry, states[BEFORE].depEntityRegistry, DEP_03);
    }

    /// @notice DEP-04: the only acceptable revert for an authorized non-zero set is the matching
    ///         per-slot AlreadySet error (i.e. the slot was already wired). This confirms a set
    ///         against an already-populated slot is rejected rather than silently overwriting.
    function invariant_DEP_04(PreconditionsDEP.DepSlot slot, bytes4 errorSelector) internal {
        bytes4 expected;
        if (slot == PreconditionsDEP.DepSlot.BondRegistry) {
            expected = Errors.DependenciesBase__BondRegistryAlreadySet.selector;
        } else if (slot == PreconditionsDEP.DepSlot.EscrowManager) {
            expected = Errors.DependenciesBase__EscrowManagerAlreadySet.selector;
        } else {
            expected = Errors.DependenciesBase__EntityRegistryAlreadySet.selector;
        }

        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expected;
        fl.errAllow(errorSelector, allowedErrors, DEP_04);
    }
}

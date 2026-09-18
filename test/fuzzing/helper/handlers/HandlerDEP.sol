// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {DependenciesBase} from "src/base/DependenciesBase.sol";
import {PreconditionsDEP} from "../preconditions/PreconditionsDEP.sol";
import {PostconditionsDEP} from "../postconditions/PostconditionsDEP.sol";

/// @title HandlerDEP
/// @notice Stateful fuzz handlers for DependenciesBase write-once wiring (G-7 / I-4).
/// @dev DependenciesBase is a concrete-but-inherited wiring base; its independently-deployable
///      consumer in this harness is `marketplace` (Marketplace -> EligibilityModuleBase ->
///      EntityEligibilityGuard -> DependenciesBase). In FuzzSetup the escrowManager and
///      entityRegistry slots are already wired (non-zero) and bondRegistry is unset, so these
///      handlers exercise: (a) overwrite attempts on already-wired slots, (b) the first
///      legitimate 0->concrete transition of an unset slot, and (c) unauthorized-caller rejection.
abstract contract HandlerDEP is PreconditionsDEP, PostconditionsDEP {
    /// @notice Attempts to set a dependency slot from the authorized ADMIN (address(this)).
    /// @param slotSeed Seed selecting which of the three dependency slots to target.
    /// @param valueSeed Seed deriving the non-zero candidate address.
    function handler_setDependency(uint256 slotSeed, uint256 valueSeed) public {
        SetDependencyParams memory params = setDependencyPreconditions(slotSeed, valueSeed);

        _beforeDEP();

        (bool success, bytes memory returnData) =
            fl.doFunctionCall(address(marketplace), _encodeSet(params.slot, params.newValue));

        setDependencyPostconditions(success, returnData, params);
    }

    /// @notice Attempts to set a dependency slot from a non-ADMIN caller (access control, G-7).
    /// @param slotSeed Seed selecting which of the three dependency slots to target.
    /// @param valueSeed Seed deriving the non-zero candidate address.
    /// @param callerSeed Seed selecting a non-admin caller from the users pool.
    function handler_setDependencyUnauthorized(uint256 slotSeed, uint256 valueSeed, uint256 callerSeed) public {
        SetDependencyParams memory params = setDependencyUnauthorizedPreconditions(slotSeed, valueSeed, callerSeed);

        _beforeDEP();

        (bool success, bytes memory returnData) =
            fl.doFunctionCall(address(marketplace), _encodeSet(params.slot, params.newValue), params.caller);

        setDependencyPostconditions(success, returnData, params);
    }

    /// @notice Encodes the matching DependenciesBase setter call for the chosen slot.
    function _encodeSet(DepSlot slot, address newValue) internal pure returns (bytes memory) {
        if (slot == DepSlot.BondRegistry) {
            return abi.encodeWithSelector(DependenciesBase.setBondRegistry.selector, newValue);
        } else if (slot == DepSlot.EscrowManager) {
            return abi.encodeWithSelector(DependenciesBase.setEscrowManager.selector, newValue);
        } else {
            return abi.encodeWithSelector(DependenciesBase.setEntityRegistry.selector, newValue);
        }
    }
}

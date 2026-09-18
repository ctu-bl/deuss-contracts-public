// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsBase} from "./PreconditionsBase.sol";

/// @notice Parameter builders for DependenciesBase write-once wiring handlers (G-7 / I-4).
abstract contract PreconditionsDEP is PreconditionsBase {
    /// @dev Identifies which of the three dependency slots a handler targets.
    enum DepSlot {
        BondRegistry,
        EscrowManager,
        EntityRegistry
    }

    struct SetDependencyParams {
        DepSlot slot;
        address newValue;
        address caller;
        bool authorized;
    }

    /// @notice Builds params for an authorized dependency-set attempt against the chosen slot.
    /// @dev `address(this)` holds the Marketplace ADMIN role (granted in FuzzSetup._grantRoles),
    ///      so the default caller is authorized. The fuzzed `newValue` is forced non-zero so the
    ///      ZeroAddress guard is never the cause of a revert we attribute to write-once.
    function setDependencyPreconditions(uint256 slotSeed, uint256 valueSeed)
        internal
        view
        returns (SetDependencyParams memory params)
    {
        params.slot = DepSlot(slotSeed % 3);

        // Force a non-zero, non-precompile address so reverts are attributable to write-once,
        // not to the ZeroAddress() guard.
        address candidate = address(uint160(uint256(keccak256(abi.encodePacked(valueSeed, slotSeed))) | 0x10000));
        params.newValue = candidate;

        params.caller = address(this);
        params.authorized = true;
    }

    /// @notice Builds params for an unauthorized dependency-set attempt (access control, G-7).
    /// @dev Picks a non-admin user from the users pool as the caller.
    function setDependencyUnauthorizedPreconditions(uint256 slotSeed, uint256 valueSeed, uint256 callerSeed)
        internal
        view
        returns (SetDependencyParams memory params)
    {
        params = setDependencyPreconditions(slotSeed, valueSeed);

        address caller = users[callerSeed % users.length];
        require(!marketplace.hasAnyRole(caller, marketplace.ADMIN()), ClampFail("caller already has ADMIN"));
        require(caller != marketplace.owner(), ClampFail("caller is owner"));

        params.caller = caller;
        params.authorized = false;
    }
}

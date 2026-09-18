// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {PreconditionsWALLET} from "../preconditions/PreconditionsWALLET.sol";
import {PostconditionsWALLET} from "../postconditions/PostconditionsWALLET.sol";

/// @title HandlerWALLET
/// @notice Stateful fuzz handlers for invariant I-3: the CompanyWallet ownership epoch.
/// @dev Uses the dedicated `walletEpochA` / `walletEpochB` pair (kept separate from the PolicyRegistry
///      handlers' shared `policyWalletA` / `policyWalletB` so the epoch churn here does not reset their
///      epoch-scoped policy state). `transferOwnership` is the epoch-bumping operation (routes through
///      `_setOwner`, which does `_ownershipEpoch + 1`); it is `onlyOwner`, so the call is made as the
///      wallet's live current owner. `execute` is exercised as a non-bumping control to confirm the epoch
///      stays flat across unrelated wallet activity.
abstract contract HandlerWALLET is PreconditionsWALLET, PostconditionsWALLET {
    /// @notice Performs an owner-authorized ownership transfer, which advances the wallet's epoch by +1.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    /// @param newOwnerSeed Seed selecting the incoming owner from the EOA candidate pool.
    function handler_changeOwner(uint256 walletSeed, uint256 newOwnerSeed) public {
        ChangeOwnerParams memory params = changeOwnerPreconditions(walletSeed, newOwnerSeed);

        _beforeWALLET();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(params.wallet),
            abi.encodeWithSignature("transferOwnership(address)", params.newOwner),
            params.currentOwner
        );

        changeOwnerPostconditions(success, returnData, params);

        // Restore the original owner. With the dedicated walletEpochA/B pair this is no longer required
        // for correctness (nothing hardcodes the owner anymore), but it keeps each wallet pinned to
        // WALLET_EPOCH_OWNER_A/B instead of drifting into the USER pool: otherwise executeAsNonOwner's
        // non-owner caller set (USER1-3 / outsider) could collide with the live owner and trip the
        // "caller is the owner" clamp, shrinking that path's coverage. The I-3 epoch invariant already ran
        // above (the bump is captured in the before/after snapshot); the extra rotation only advances the
        // epoch further, which keeps it monotonic.
        if (success) {
            fl.doFunctionCall(
                address(params.wallet),
                abi.encodeWithSignature("transferOwnership(address)", params.currentOwner),
                params.newOwner
            );
        }
    }

    /// @notice Performs an owner-authorized `execute` call that must NOT change the ownership epoch.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    function handler_execute(uint256 walletSeed) public {
        ExecuteParams memory params = executePreconditions(walletSeed);

        _beforeWALLET();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(params.wallet),
            abi.encodeWithSelector(CompanyWallet.execute.selector, params.target, params.value, params.data),
            params.currentOwner
        );

        executePostconditions(success, returnData, params);
    }

    /// @notice G-8: owner-authorized `execute` with an invalid target must revert.
    /// @dev `kind` selects the violated target-guard leg: 0 = address(0), 1 = the wallet itself, 2 = an EOA.
    ///      The call is made as the live owner, so the target guard is the only reachable revert cause.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    /// @param kind Selects which target-guard leg is violated (clamped to [0, 2]).
    function handler_executeInvalidTarget(uint256 walletSeed, uint8 kind) public {
        ExecuteInvalidTargetParams memory params = executeInvalidTargetPreconditions(walletSeed, kind);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(params.wallet),
            abi.encodeWithSelector(CompanyWallet.execute.selector, params.target, params.value, params.data),
            params.currentOwner
        );

        executeInvalidTargetPostconditions(success, returnData, params);
    }

    /// @notice G-9 / X-3: a non-owner `execute` succeeds IFF `PolicyRegistry.canExecute` returns true.
    /// @dev Picks a non-owner caller and a valid (target, selector). When `grantRole` is true the caller is
    ///      first authorized for that operation via the wallet owner; the precondition then reads the live
    ///      `canExecute` decision as ground truth. The postcondition asserts success <=> that decision.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    /// @param callerSeed Seed selecting a non-owner caller (USER pool / outsider).
    /// @param targetSeed Seed selecting the operation calldata payload.
    /// @param grantRole Whether to first authorize the caller for the chosen (target, selector).
    function handler_executeAsNonOwner(uint256 walletSeed, uint256 callerSeed, uint256 targetSeed, bool grantRole)
        public
    {
        ExecuteAsNonOwnerParams memory params =
            executeAsNonOwnerPreconditions(walletSeed, callerSeed, targetSeed, grantRole);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(params.wallet),
            abi.encodeWithSelector(CompanyWallet.execute.selector, params.target, params.value, params.data),
            params.caller
        );

        executeAsNonOwnerPostconditions(success, returnData, params);
    }
}

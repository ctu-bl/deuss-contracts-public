// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {FuzzPolicyTarget} from "../../mocks/PolicyRegistryFuzzMocks.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsWALLET is PreconditionsBase {
    struct ChangeOwnerParams {
        CompanyWallet wallet;
        address currentOwner;
        address newOwner;
    }

    struct ExecuteParams {
        CompanyWallet wallet;
        address currentOwner;
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Parameters for an owner-authorized `execute` call with an invalid target (G-8).
    /// @dev `kind` selects which leg of the target guard
    ///      `target != address(0) && target != address(this) && target.code.length != 0` is violated.
    struct ExecuteInvalidTargetParams {
        CompanyWallet wallet;
        uint8 kind;
        address currentOwner;
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Parameters for a non-owner `execute` call gated by `PolicyRegistry.canExecute` (G-9 / X-3).
    /// @dev `expectedAuthorized` mirrors the on-chain policy decision for the chosen (caller, target, selector)
    ///      so the postcondition can assert success <=> canExecute and revert <=> !canExecute.
    struct ExecuteAsNonOwnerParams {
        CompanyWallet wallet;
        bytes4 selector;
        bool expectedAuthorized;
        address currentOwner;
        address caller;
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Candidate new owners for the epoch-bumping ownership transfer.
    /// @dev EOAs only; `_setOwner` rejects transfers to the current owner, so the caller is filtered.
    function _walletNewOwnerCandidates() internal pure returns (address[3] memory candidates) {
        candidates = [USER1, USER2, USER3];
    }

    /// @notice Builds parameters for the epoch-bumping `transferOwnership` call.
    /// @dev Selects walletEpochA or walletEpochB by seed, reads the live current owner (which is the
    ///      authorized caller for `transferOwnership`), and picks a new owner that differs from it so the
    ///      `CompanyWallet__OwnerTransferToSelf` guard does not clamp the call. These wallets are
    ///      dedicated to the WALLET vertical so the epoch bump does not reset policyWalletA/B state.
    /// @param walletSeed Seed selecting which dedicated wallet to mutate.
    /// @param newOwnerSeed Seed selecting the incoming owner from the candidate pool.
    function changeOwnerPreconditions(uint256 walletSeed, uint256 newOwnerSeed)
        internal
        view
        returns (ChangeOwnerParams memory params)
    {
        params.wallet = (walletSeed % 2 == 0) ? walletEpochA : walletEpochB;
        params.currentOwner = params.wallet.owner();
        require(params.currentOwner != address(0), ClampFail("wallet owner is zero"));

        address[3] memory candidates = _walletNewOwnerCandidates();
        address chosen = candidates[newOwnerSeed % 3];
        // Rotate to the next candidate if the seeded one collides with the current owner.
        if (chosen == params.currentOwner) {
            chosen = candidates[(newOwnerSeed + 1) % 3];
        }
        require(chosen != params.currentOwner, ClampFail("new owner equals current owner"));
        require(chosen != address(0), ClampFail("new owner is zero"));

        params.newOwner = chosen;
    }

    /// @notice Builds parameters for an owner-authorized `execute` call.
    /// @dev `execute` does NOT bump the epoch; it is exercised so the WALLET invariants observe a
    ///      non-bumping operation and confirm the epoch stays flat across it. The call targets the
    ///      sibling dedicated wallet (non-zero code, not self) with a benign `ownershipEpoch()` view payload.
    /// @param walletSeed Seed selecting which dedicated wallet executes the call.
    function executePreconditions(uint256 walletSeed) internal view returns (ExecuteParams memory params) {
        params.wallet = (walletSeed % 2 == 0) ? walletEpochA : walletEpochB;
        params.currentOwner = params.wallet.owner();
        require(params.currentOwner != address(0), ClampFail("wallet owner is zero"));

        // Target the OTHER dedicated wallet: non-zero code, not address(this), not address(0).
        params.target = address(params.wallet) == address(walletEpochA) ? address(walletEpochB) : address(walletEpochA);
        params.value = 0;
        // data.length must be > 3; ownershipEpoch() selector is a safe 4-byte payload.
        params.data = abi.encodeWithSelector(CompanyWallet.ownershipEpoch.selector);
    }

    /// @notice Builds parameters for an owner-authorized `execute` whose target violates the G-8 guard.
    /// @dev `execute` requires `target != address(0) && target != address(this) && target.code.length != 0`.
    ///      `kind` selects which leg is violated: 0 = zero target, 1 = the wallet itself, 2 = a known EOA
    ///      (POLICY_OUTSIDER has no deployed code). The call is made as the live owner so the only reason it
    ///      can revert is the target guard (CompanyWallet__InvalidCallTarget) — the owner path bypasses policy.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    /// @param kind Selects which target-guard leg is violated (clamped to [0, 2]).
    function executeInvalidTargetPreconditions(uint256 walletSeed, uint8 kind)
        internal
        returns (ExecuteInvalidTargetParams memory params)
    {
        params.wallet = (walletSeed % 2 == 0) ? walletEpochA : walletEpochB;
        params.currentOwner = params.wallet.owner();
        require(params.currentOwner != address(0), ClampFail("wallet owner is zero"));

        params.kind = uint8(fl.clamp(uint256(kind), 0, 2));
        if (params.kind == 0) {
            params.target = address(0);
        } else if (params.kind == 1) {
            params.target = address(params.wallet);
        } else {
            // POLICY_OUTSIDER is an unfunded EOA with no deployed code (target.code.length == 0).
            params.target = POLICY_OUTSIDER;
            require(POLICY_OUTSIDER.code.length == 0, ClampFail("EOA target unexpectedly has code"));
        }

        params.value = 0;
        // data.length must be > 3 so the target guard (checked first) is the sole revert cause.
        params.data = abi.encodeWithSelector(CompanyWallet.ownershipEpoch.selector);
    }

    /// @notice Builds parameters for a non-owner `execute` gated by `PolicyRegistry.canExecute` (G-9 / X-3).
    /// @dev Picks a non-owner caller and a valid contract target/selector (FuzzPolicyTarget.setNumber). When
    ///      `grantRole` is true the caller is first granted a user role for that operation via the live owner,
    ///      so the harness exercises both authorized and unauthorized non-owner paths. `expectedAuthorized`
    ///      is the on-chain policy decision read AFTER any grant, mirroring `canExecute`'s role/module logic.
    /// @param walletSeed Seed selecting walletEpochA or walletEpochB.
    /// @param callerSeed Seed selecting a non-owner caller (USER pool / POLICY_OUTSIDER).
    /// @param targetSeed Seed selecting the operation calldata payload.
    /// @param grantRole Whether to first authorize the caller for the chosen (target, selector).
    function executeAsNonOwnerPreconditions(uint256 walletSeed, uint256 callerSeed, uint256 targetSeed, bool grantRole)
        internal
        returns (ExecuteAsNonOwnerParams memory params)
    {
        params.wallet = (walletSeed % 2 == 0) ? walletEpochA : walletEpochB;
        params.currentOwner = params.wallet.owner();
        require(params.currentOwner != address(0), ClampFail("wallet owner is zero"));

        // Pick a NON-owner caller from the EOA pool (USER1/2/3 + outsider), filtering the owner out.
        params.caller = _walletNonOwnerCaller(callerSeed);
        require(params.caller != params.currentOwner, ClampFail("caller is the owner"));
        require(params.caller != address(0), ClampFail("caller is zero"));

        // Valid contract target with a deterministic, non-zero-selector operation.
        params.target = address(policyTarget);
        params.selector = FuzzPolicyTarget.setNumber.selector;
        uint256 numberValue = fl.clamp(targetSeed, 0, POLICY_MAX_ROLE_BITMAP);
        params.data = abi.encodeWithSelector(params.selector, numberValue);
        params.value = 0;

        // Optionally authorize this caller for (target, selector) before the execute attempt. The grant is
        // performed by the wallet owner (a policy operator) and is best-effort: a duplicate-grant revert is
        // tolerated because the post-grant canExecute read below establishes the ground truth either way.
        if (grantRole) {
            uint256 roleBit = 1;
            // Explicit selector constants disambiguate the overloaded grant functions.
            fl.doFunctionCall(
                address(policyRegistry),
                abi.encodeWithSelector(_GRANT_USER_ROLES_SELECTOR, address(params.wallet), params.caller, roleBit),
                params.currentOwner
            );
            fl.doFunctionCall(
                address(policyRegistry),
                abi.encodeWithSelector(
                    _GRANT_OPERATION_ROLES_SELECTOR, address(params.wallet), params.target, params.selector, roleBit
                ),
                params.currentOwner
            );
        }

        // Ground-truth policy decision read AFTER the optional grant, from the live registry.
        params.expectedAuthorized =
            policyRegistry.canExecute(address(params.wallet), params.caller, params.target, params.value, params.data);
    }

    /// @notice Returns a non-owner caller for the WALLET execute authorization checks.
    /// @dev Draws from {USER1, USER2, USER3, POLICY_OUTSIDER}; never returns either wallet owner.
    function _walletNonOwnerCaller(uint256 callerSeed) internal pure returns (address caller) {
        uint256 option = callerSeed % 4;
        if (option == 0) return USER1;
        if (option == 1) return USER2;
        if (option == 2) return USER3;
        return POLICY_OUTSIDER;
    }
}

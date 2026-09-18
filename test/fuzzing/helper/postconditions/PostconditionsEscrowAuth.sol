// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsEscrowAuth} from "../preconditions/PreconditionsEscrowAuth.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsEscrowAuth is PostconditionsBase {
    /// @dev Runs the global module-sync invariants across the entire fuzz pool. Called from
    /// every EscrowManager authorization postcondition regardless of handler outcome, so a
    /// storage collision that touched a non-target (type, addr) pair would surface here.
    function _runEscrowAuthGlobals() internal {
        for (uint256 i; i < knownEscrowModules.length; ++i) {
            address moduleAddr = knownEscrowModules[i];
            invariant_ESAU_01(moduleAddr);
            invariant_ESAU_02(moduleAddr);
        }
    }

    function registerModulePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEscrowAuth.RegisterModuleParams memory params
    ) internal {
        _afterEscrowAuth();

        if (success) {
            invariant_ESAU_10(params.moduleAddr, params.moduleType);
            invariant_ESAU_11(params.moduleAddr, params.moduleType);
            invariant_ESAU_13(params.moduleAddr, params.moduleType);
        } else {
            invariant_ESAU_11(params.moduleAddr, params.moduleType);
            invariant_ESAU_12(params.moduleAddr, params.moduleType, _returnSelector(returnData));
        }
        _runEscrowAuthGlobals();
    }

    function deactivateModulePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEscrowAuth.DeactivateModuleParams memory params
    ) internal {
        _afterEscrowAuth();

        if (success) {
            invariant_ESAU_20(params.moduleAddr, params.moduleType);
            invariant_ESAU_21(params.moduleAddr, params.moduleType);
            invariant_ESAU_23(params.moduleAddr, params.moduleType);
        } else {
            invariant_ESAU_21(params.moduleAddr, params.moduleType);
            invariant_ESAU_22(params.moduleAddr, params.moduleType, _returnSelector(returnData));
        }
        _runEscrowAuthGlobals();
    }

    function setAssetManagerPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEscrowAuth.SetAssetManagerParams memory params
    ) internal {
        _afterEscrowAuth();

        if (success) {
            invariant_ESAU_30(params.newAssetManager);
            invariant_ESAU_32();
        } else {
            // The only revert path is `new == address(0)`. Any other failure is a bug.
            invariant_ESAU_31(_returnSelector(returnData));
            invariant_ESAU_32();
            invariant_ESAU_33(params.newAssetManager);
        }
        _runEscrowAuthGlobals();
    }

    function restoreAssetManagerPostconditions(bool success) internal {
        invariant_ESAU_34(success);
    }

    function createEscrowAsActorPostconditions(bool success, bytes memory returnData) internal {
        _afterEscrowAuth();
        invariant_ESAU_40(_returnSelector(returnData));
        invariant_ESAU_41();
        invariant_ESAU_42(success);
        _runEscrowAuthGlobals();
    }

    function withdrawOrClaimAsActorPostconditions(bool success, bytes memory returnData, bool escrowExisted) internal {
        _afterEscrowAuth();
        invariant_ESAU_50(escrowExisted, _returnSelector(returnData));
        invariant_ESAU_51();
        invariant_ESAU_52(success);
        _runEscrowAuthGlobals();
    }

    function sweepPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEscrowAuth.EscrowAuthSweepParams memory params,
        uint256 preSurplus
    ) internal {
        _afterEscrowAuth();

        invariant_ESAU_61();

        if (!success) {
            invariant_ESAU_60(
                params.assetType,
                params.tokenId,
                params.amount,
                params.beneficiary,
                preSurplus,
                _returnSelector(returnData)
            );
        }
        _runEscrowAuthGlobals();
    }

    function adminUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        _afterEscrowAuth();
        invariant_ESAU_70(_returnSelector(returnData));
        invariant_ESAU_71();
        invariant_ESAU_72(success);
        _runEscrowAuthGlobals();
    }
}

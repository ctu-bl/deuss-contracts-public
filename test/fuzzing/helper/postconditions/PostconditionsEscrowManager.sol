// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {PreconditionsEscrowManager} from "../preconditions/PreconditionsEscrowManager.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsEscrowManager is PostconditionsBase {
    function escrowManagerCoverageCallPostconditions(bool success, bytes memory returnData) internal {
        invariant_ESCR_70(success, _returnSelector(returnData));
    }

    function createEscrowPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256 escrowId,
        PreconditionsEscrowManager.CreateEscrowParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate, _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_20(escrowId, params.depositor, address(token), bondTokenId, params.amount);
            invariant_ESCR_21();
            invariant_ESCR_22(params.amount);
            invariant_ESCR_23(params.depositor, params.amount);
            invariant_ESCR_24(params.amount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_25(_returnSelector(returnData));
        }
    }

    function createEscrowUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        invariant_ESCR_26(success, _returnSelector(returnData));
    }

    function withdrawEscrowPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256 escrowId,
        uint256 amount
    ) internal {
        if (success) {
            _after(actorsToUpdate, _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_30(escrowId, amount);
            invariant_ESCR_31(actorsToUpdate[0], amount);
            invariant_ESCR_32(amount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_33(_returnSelector(returnData));
        }
    }

    function claimEscrowPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256 escrowId,
        uint256 amount
    ) internal {
        if (success) {
            _after(actorsToUpdate, _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_40(escrowId, amount);
            invariant_ESCR_41(actorsToUpdate[0], amount);
            invariant_ESCR_42(amount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_43(_returnSelector(returnData));
        }
    }

    function sweepPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_50();
            invariant_ESCR_51();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_52(_returnSelector(returnData));
        }
    }

    function directTransferToEscrowPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        uint256 amount
    ) internal {
        if (success) {
            _after(actorsToUpdate, _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_53(actorsToUpdate[0], amount);
            invariant_ESCR_54(amount);
            invariant_ESCR_55();
            invariant_ESCR_56();
            invariant_ESCR_57(amount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_58(_returnSelector(returnData));
        }
    }

    function registerModulePostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_61();
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_63(_returnSelector(returnData));
        }
    }

    function deactivateModulePostconditions(bool success, bytes memory returnData, address moduleAddress) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_ESCR_61();
            invariant_ESCR_62(moduleAddress);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_ESCR_64(_returnSelector(returnData));
        }
    }
}

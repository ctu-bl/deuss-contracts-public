// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsDEUSSToken} from "../preconditions/PreconditionsDEUSSToken.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsDEUSSToken is PostconditionsBase {
    function approvePostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate,
        PreconditionsDEUSSToken.ApproveParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
            invariant_TKN_10(params.owner, params.spender, params.amount);
            invariant_TKN_11(params.owner, params.spender);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_10);
        }
    }

    function approveOverwriteExistingPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate,
        PreconditionsDEUSSToken.ApproveParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
            invariant_TKN_12(params.owner, params.spender, params.amount);
            invariant_TKN_11(params.owner, params.spender);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_12);
        }
    }

    function grantRolesBatchInvalidRolesPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsDEUSSToken.GrantRolesBatchParams memory params
    ) internal {
        _afterToken(params.users, _emptyAddressArray(), _emptyAddressArray());
        invariant_TKN_13(success, _returnSelector(returnData), params.users, params.beforeRoles);
    }

    function transferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TransferParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_20(params.from, params.to, params.amount);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_20);
        }
    }

    function transferFromAllowancePostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate,
        PreconditionsDEUSSToken.AllowanceTransferParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
            invariant_TKN_20(params.owner, params.receiver, params.amount);
            invariant_TKN_21(params.owner, params.spender, params.amount);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_21);
        }
    }

    function setOperatorPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate,
        PreconditionsDEUSSToken.OperatorParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
            invariant_TKN_30(params.owner, params.operator, params.approved);
            invariant_TKN_11(params.owner, params.operator);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_30);
        }
    }

    function setOperatorUnregisteredPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate
    ) internal {
        _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
        invariant_TKN_31(success, _returnSelector(returnData));
    }

    function transferFromOperatorPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate,
        PreconditionsDEUSSToken.OperatorTransferParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
            invariant_TKN_20(params.owner, params.receiver, params.amount);
            invariant_TKN_22(params.owner, params.operator);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_22);
        }
    }

    function batchTransferFromSingleReceiverPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TransferParams memory params
    ) internal {
        transferPostconditions(success, returnData, actorsToUpdate, params);
    }

    function batchTransferFromMultipleReceiversPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TransferParams memory params
    ) internal {
        transferPostconditions(success, returnData, actorsToUpdate, params);
    }

    function freezePartialTokensPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.FreezeParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_40(params.account, params.amount);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_40);
        }
    }

    function batchFreezePartialTokensPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.FreezeParams memory params
    ) internal {
        freezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    function unfreezePartialTokensPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.FreezeParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_41(params.account, params.amount);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_41);
        }
    }

    function batchUnfreezePartialTokensPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.FreezeParams memory params
    ) internal {
        unfreezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    function forcedTransferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.ForcedTransferParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_50(params.from, params.to, params.amount, params.expectedFrozenAfter);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_50);
        }
    }

    function batchForcedTransferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.ForcedTransferParams memory params
    ) internal {
        forcedTransferPostconditions(success, returnData, actorsToUpdate, params);
    }

    function forcedTransferToProtectedReceiverPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate
    ) internal {
        _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
        invariant_TKN_52(success, _returnSelector(returnData), actorsToUpdate[0], actorsToUpdate[1]);
    }

    function batchForcedTransferToProtectedReceiverPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate
    ) internal {
        forcedTransferToProtectedReceiverPostconditions(success, returnData, actorsToUpdate);
    }

    function burnPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TokenBurnParams memory params
    ) internal {
        if (success) {
            _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_51(params.from, params.amount, params.expectedFrozenAfter);
            _assertActorCheckpoints(actorsToUpdate);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_51);
        }
    }

    function burnBatchPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TokenBurnParams memory params
    ) internal {
        burnPostconditions(success, returnData, actorsToUpdate, params);
    }

    function setContractPausePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsDEUSSToken.PauseParams memory params
    ) internal {
        if (success) {
            _afterToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_60(params.paused);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_60);
        }
    }

    function setBondSuspendedPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsDEUSSToken.BondSuspensionParams memory params
    ) internal {
        if (success) {
            _afterToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_61(params.suspended);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_61);
        }
    }

    function contractPauseBlocksActionPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        address[] memory ownersToUpdate,
        address[] memory spendersToUpdate
    ) internal {
        _afterToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);
        invariant_TKN_62(success, _returnSelector(returnData));
        invariant_TKN_60(true);
    }

    function tokenIdPauseBlocksTransferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.TransferParams memory params
    ) internal {
        _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
        invariant_TKN_63(success, _returnSelector(returnData), params.from, params.to);
        invariant_TKN_61(true);
    }

    function futureCheckpointPostconditions(bool success, bytes memory returnData) internal {
        invariant_TKN_71(success, _returnSelector(returnData));
    }

    function protectAddressPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsDEUSSToken.ProtectAddressParams memory params
    ) internal {
        if (success) {
            _afterToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());
            invariant_TKN_80(params.account);
            onSuccessInvariantsGeneral(returnData);
        } else {
            _unexpectedTokenRevert(_returnSelector(returnData), TKN_80);
        }
    }

    function protectedReceiverTransferPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsDEUSSToken.ProtectedReceiverTransferParams memory params
    ) internal {
        _afterToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());
        invariant_TKN_81(success, _returnSelector(returnData), params.from, params.to);
    }

    function _assertActorCheckpoints(address[] memory actors) internal {
        for (uint256 i; i < actors.length; ++i) {
            if (actors[i] == address(0)) continue;
            invariant_TKN_70(actors[i]);
        }
    }

    function _unexpectedTokenRevert(bytes4 errorSelector, string memory context) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, context);
    }
}

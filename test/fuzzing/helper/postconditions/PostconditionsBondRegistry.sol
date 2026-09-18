// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {PreconditionsBondRegistry} from "../preconditions/PreconditionsBondRegistry.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";
import {Scoring} from "src/registry/BondStructs.sol";

abstract contract PostconditionsBondRegistry is PostconditionsBase {
    function publishSuccessorPostconditions(
        bool success,
        bytes memory returnData,
        uint8 newVersion,
        PreconditionsBondRegistry.PublishSuccessorParams memory params
    ) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_10(newVersion);
            invariant_BOND_11(newVersion);
            invariant_BOND_12(newVersion);
            invariant_BOND_13(params.previousActiveVersion);
            invariant_BOND_15();
            invariant_BOND_16(newVersion, params.input);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_14(_returnSelector(returnData));
        }
    }

    function updatePublishedPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.UpdatePublishedParams memory params
    ) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_20(params.version);
            invariant_BOND_21(params.version);
            invariant_BOND_22(params.version);
            invariant_BOND_24(params.version, params.input);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_23(_returnSelector(returnData));
        }
    }

    function issueBondPostconditions(
        bool success,
        bytes memory returnData,
        address[] memory actorsToUpdate,
        PreconditionsBondRegistry.IssueParams memory params
    ) internal {
        if (success) {
            _after(actorsToUpdate, _emptyUintArray(), _emptyUintArray());
            invariant_BOND_30(params.version, params.amount);
            invariant_BOND_31(params.version, params.amount);
            invariant_BOND_32(params.version, params.amount);
            invariant_BOND_33(params.version, params.amount);
            invariant_BOND_34(params.version, params.amount);
            invariant_BOND_102(params.version);
            if (params.isFirstIssuance) {
                invariant_BOND_35(params.version);
                if (params.previousActiveVersion != params.version) {
                    invariant_BOND_36(params.previousActiveVersion);
                    invariant_BOND_39(params.version);
                }
            }
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_37(_returnSelector(returnData));
        }
    }

    function closeIssuancePostconditions(bool success, bytes memory returnData, uint8 version) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_40(version);
            invariant_BOND_41(version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_42(_returnSelector(returnData));
        }
    }

    function cancelBondPostconditions(bool success, bytes memory returnData, uint8 version) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_50(version);
            invariant_BOND_53(version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_51(_returnSelector(returnData));
        }
    }

    function suspendBondPostconditions(bool success, bytes memory returnData, uint8 version) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_60(version);
            invariant_BOND_61(version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_64(_returnSelector(returnData));
        }
    }

    function unsuspendBondPostconditions(bool success, bytes memory returnData, uint8 version) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_62(version);
            invariant_BOND_63(version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_64(_returnSelector(returnData));
        }
    }

    function closeBondPostconditions(bool success, bytes memory returnData, uint8 version) internal {
        if (success) {
            invariant_BOND_70(version);
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            invariant_BOND_71(version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_72(_returnSelector(returnData));
        }
    }

    function rotateIssuerPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.RotateIssuerParams memory params
    ) internal {
        if (success) {
            _afterBondAccounts(params.version, _twoActorArray(params.oldIssuer, params.newIssuer));
            invariant_BOND_105(params.version, params.newIssuer);
            invariant_BOND_106(params.version);
            invariant_BOND_107(params.version, params.oldIssuer, params.newIssuer);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_108(_returnSelector(returnData));
        }
    }

    function rotateIssuerInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_109(success, _returnSelector(returnData));
    }

    function burnReclaimPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.BurnParams memory params
    ) internal {
        if (success) {
            _afterBondAccounts(params.version, _singleActorArray(params.from));
            invariant_BOND_80(params.version, params.from, params.amount);
            invariant_BOND_81(params.version, params.amount);
            invariant_BOND_82(params.version);
            invariant_BOND_83(params.version, params.amount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_85(_returnSelector(returnData));
        }
    }

    function burnSettlementPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.BurnParams memory params
    ) internal {
        if (success) {
            _afterBondAccounts(params.version, _singleActorArray(params.from));
            invariant_BOND_80(params.version, params.from, params.amount);
            invariant_BOND_81(params.version, params.amount);
            invariant_BOND_82(params.version);
            invariant_BOND_84(params.version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_85(_returnSelector(returnData));
        }
    }

    function burnBatchReclaimPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.BatchBurnParams memory params
    ) internal {
        if (success) {
            _afterBondAccounts(params.version, params.froms);
            invariant_BOND_80_BATCH(params.version, params.froms, params.amounts);
            invariant_BOND_81(params.version, params.totalAmount);
            invariant_BOND_82(params.version);
            invariant_BOND_83(params.version, params.totalAmount);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_85(_returnSelector(returnData));
        }
    }

    function burnReclaimFrozenIssuerPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_104(success, _returnSelector(returnData));
    }

    function burnBatchSettlementPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.BatchBurnParams memory params
    ) internal {
        if (success) {
            _afterBondAccounts(params.version, params.froms);
            invariant_BOND_80_BATCH(params.version, params.froms, params.amounts);
            invariant_BOND_81(params.version, params.totalAmount);
            invariant_BOND_82(params.version);
            invariant_BOND_84(params.version);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_85(_returnSelector(returnData));
        }
    }

    function publishBondActiveVersionNotIssuablePostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_99(success, _returnSelector(returnData));
    }

    function publishBondSuccessorAlreadyPublishedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_100(success, _returnSelector(returnData));
    }

    function updatePublishedInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_101(success, _returnSelector(returnData));
    }

    function issueBondInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_38(success, _returnSelector(returnData));
    }

    function issueBondUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_87(success, _returnSelector(returnData));
    }

    function issueBondClosedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_88(success, _returnSelector(returnData));
    }

    function issueBondZeroAmountPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_89(success, _returnSelector(returnData));
    }

    function issueBondMaxSupplyExceededPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_90(success, _returnSelector(returnData));
    }

    function issueBondMaturityExpiredPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_91(success, _returnSelector(returnData));
    }

    function issueBondSuccessorSuspendedPreviousPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_103(success, _returnSelector(returnData));
    }

    function cancelBondInvalidPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_52(success, _returnSelector(returnData));
    }

    function suspendBondInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_65(success, _returnSelector(returnData));
    }

    function unsuspendBondInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_66(success, _returnSelector(returnData));
    }

    function closeBondInvalidPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_73(success, _returnSelector(returnData));
    }

    function closeIssuanceInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_92(success, _returnSelector(returnData));
    }

    function closeIssuanceUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_93(success, _returnSelector(returnData));
    }

    function closeIssuanceAlreadyClosedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_94(success, _returnSelector(returnData));
    }

    function burnUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_86(success, _returnSelector(returnData));
    }

    function burnInvalidSourcePostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_95(success, _returnSelector(returnData));
    }

    function burnInvalidStatusPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_96(success, _returnSelector(returnData));
    }

    function burnBatchLengthMismatchPostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_97(success, _returnSelector(returnData));
    }

    function burnBatchInvalidSourcePostconditions(bool success, bytes memory returnData) internal {
        invariant_BOND_98(success, _returnSelector(returnData));
    }

    function appendScoringPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsBondRegistry.AppendScoringParams memory params
    ) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            uint256 scoringId = params.previousCount + 1;
            Scoring memory stored = bondRegistry.getScoringAt(params.wallet, scoringId);
            Scoring memory latest = bondRegistry.getLatestScoring(params.wallet);

            invariant_BOND_110(params.wallet, scoringId, params.scoring, stored, latest);
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_111(_returnSelector(returnData));
        }
    }

    function appendScoringInvalidPostconditions(bool success, bytes memory returnData, bytes4 expectedError) internal {
        invariant_BOND_112(success, _returnSelector(returnData), expectedError);
    }

    function scoringInvalidQueryPostconditions(bool success, bytes memory returnData, bytes4 expectedError) internal {
        invariant_BOND_113(success, _returnSelector(returnData), expectedError);
    }

    function bondRegistryAdminSuccessPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_114(_returnSelector(returnData));
        }
    }

    function bondRegistryExpectedRevertPostconditions(bool success, bytes memory returnData, bytes4 expectedError)
        internal
    {
        invariant_BOND_115(success, _returnSelector(returnData), expectedError);
    }

    function publishBondInvalidInputPostconditions(bool success, bytes memory returnData, bytes4 expectedError)
        internal
    {
        invariant_BOND_116(success, _returnSelector(returnData), expectedError);
    }

    function publishIndependentBondPostconditions(bool success, bytes memory returnData) internal {
        if (success) {
            _after(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());
            onSuccessInvariantsGeneral(returnData);
        } else {
            invariant_BOND_117(_returnSelector(returnData));
        }
    }

    function bondRegistryViewPostconditions(bool success, bytes memory returnData) internal {
        if (!success) {
            invariant_BOND_118(_returnSelector(returnData));
        }
    }

    function bondRegistryViewSurfacePostconditions(
        bool seriesSuccess,
        bytes memory seriesReturnData,
        PreconditionsBondRegistry.BondRegistryViewSurfaceParams memory params
    ) internal {
        if (seriesSuccess) {
            (bytes12 reverseIsin, uint8 reverseVersion) = abi.decode(seriesReturnData, (bytes12, uint8));
            invariant_BOND_04(reverseIsin, reverseVersion, params.version);
        }
    }
}

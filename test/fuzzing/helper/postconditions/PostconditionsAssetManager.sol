// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsAssetManager} from "../preconditions/PreconditionsAssetManager.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsAssetManager is PostconditionsBase {
    function setAssetPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsAssetManager.SetAssetParams memory params
    ) internal {
        _afterAsset();

        if (success) {
            invariant_ASET_15(params.token, params.assetType, params.enabled);
            invariant_ASET_10(params.token, params.assetType, params.enabled, params.enforceTokenId);
            invariant_ASET_11(params.token);
            invariant_ASET_14(params.token);
            invariant_ASET_01(params.token);
            invariant_ASET_02(params.token);
        } else {
            invariant_ASET_12(_returnSelector(returnData));
            invariant_ASET_13(params.token, params.assetType, params.enabled, _returnSelector(returnData));
            invariant_ASET_14(params.token);
        }
    }

    function setAssetTokenIdPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsAssetManager.SetAssetTokenIdParams memory params
    ) internal {
        _afterAsset();

        if (success) {
            invariant_ASET_24(params.token);
            invariant_ASET_20(params.token, params.tokenId, params.enabled);
            invariant_ASET_21(params.token);
            invariant_ASET_14(params.token);
            invariant_ASET_01(params.token);
        } else {
            invariant_ASET_22(_returnSelector(returnData));
            invariant_ASET_23(params.token, _returnSelector(returnData));
            invariant_ASET_14(params.token);
        }
    }

    function validateAssetPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsAssetManager.ValidateAssetParams memory params
    ) internal {
        _afterAsset();

        invariant_ASET_30(params.token, params.tokenId, params.amount, success, _returnSelector(returnData));
        if (success) {
            invariant_ASET_33(params.token, returnData);
        }
        invariant_ASET_32();
    }

    function setAssetUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        _afterAsset();
        invariant_ASET_40(success, _returnSelector(returnData));
        invariant_ASET_42();
    }

    function setAssetTokenIdUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        _afterAsset();
        invariant_ASET_41(success, _returnSelector(returnData));
        invariant_ASET_42();
    }
}

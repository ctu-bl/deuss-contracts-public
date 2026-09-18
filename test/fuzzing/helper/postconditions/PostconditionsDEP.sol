// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsDEP} from "../preconditions/PreconditionsDEP.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

/// @notice Postcondition checks for DependenciesBase write-once wiring (G-7 / I-4).
abstract contract PostconditionsDEP is PostconditionsBase {
    /// @notice Validates a dependency-set attempt against the write-once + access-control invariants.
    /// @dev Regardless of success, every slot must satisfy write-once (no overwrite, no reset to
    ///      zero). On a failed authorized attempt the matching AlreadySet error is allowed
    ///      (the slot was already wired in FuzzSetup). On an unauthorized attempt the access-control
    ///      invariant requires the call to have reverted and left the slot unchanged.
    function setDependencyPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsDEP.SetDependencyParams memory params
    ) internal {
        _afterDEP();

        // I-4 / G-7: write-once on all three slots, evaluated every call.
        invariant_DEP_01();
        invariant_DEP_02();

        if (params.authorized) {
            if (!success) {
                // The only acceptable revert for an authorized, non-zero set is AlreadySet.
                invariant_DEP_04(params.slot, _returnSelectorDEP(returnData));
            }
        } else {
            // G-7: unauthorized callers can never set a dependency.
            invariant_DEP_03(success, _returnSelectorDEP(returnData));
        }
    }

    function _returnSelectorDEP(bytes memory returnData) internal pure returns (bytes4 errorSelector) {
        if (returnData.length > 3) {
            errorSelector = bytes4(returnData);
        }
    }
}

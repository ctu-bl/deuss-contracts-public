// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsWALLET} from "../preconditions/PreconditionsWALLET.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsWALLET is PostconditionsBase {
    function changeOwnerPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsWALLET.ChangeOwnerParams memory params
    ) internal {
        if (success) {
            _afterWALLET();
            bool isA = address(params.wallet) == address(walletEpochA);
            // I-3 (c): both wallets are initialized to a non-zero epoch (>= 1).
            invariant_WALLET_03(true);
            invariant_WALLET_03(false);
            // I-3 (a): the transfer bumps the selected wallet's epoch by exactly +1 and never decreases it.
            invariant_WALLET_01(isA);
            invariant_WALLET_02(isA);
            // The non-mutated sibling wallet's epoch must be unchanged.
            invariant_WALLET_02(!isA);
            invariant_WALLET_04(!isA);
        } else {
            invariant_WALLET_12(_returnSelectorWALLET(returnData));
        }
    }

    function executePostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsWALLET.ExecuteParams memory params
    ) internal {
        if (success) {
            _afterWALLET();
            // execute() must NOT change the ownership epoch of either wallet.
            invariant_WALLET_02(true);
            invariant_WALLET_02(false);
            invariant_WALLET_04(true);
            invariant_WALLET_04(false);
        } else {
            invariant_WALLET_22(_returnSelectorWALLET(returnData));
        }
        params; // silence unused-parameter lint
    }

    /// @notice G-8: `execute` MUST reject an invalid target (address(0) / the wallet itself / an EOA).
    /// @dev The call is made as the owner, so the target guard is the only reachable revert cause. Asserting
    ///      `success == false` proves it reverted; asserting the `CompanyWallet__InvalidCallTarget` selector
    ///      proves it reverted for the target guard and not some unrelated auth/policy reason.
    function executeInvalidTargetPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsWALLET.ExecuteInvalidTargetParams memory params
    ) internal {
        invariant_WALLET_G8(success, _returnSelectorWALLET(returnData));
        params; // silence unused-parameter lint
    }

    /// @notice G-9 / X-3: a non-owner `execute` succeeds IFF `PolicyRegistry.canExecute` returned true.
    /// @dev `params.expectedAuthorized` is the live registry decision captured in preconditions. The
    ///      invariant asserts success <=> expectedAuthorized (i.e. revert <=> !canExecute).
    function executeAsNonOwnerPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsWALLET.ExecuteAsNonOwnerParams memory params
    ) internal {
        invariant_WALLET_G9(success, params.expectedAuthorized);
        returnData;
    }

    function _returnSelectorWALLET(bytes memory returnData) internal pure returns (bytes4 errorSelector) {
        if (returnData.length > 3) {
            errorSelector = bytes4(returnData);
        }
    }
}

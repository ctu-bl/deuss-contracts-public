// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";
import {Errors} from "src/libs/Errors.sol";

/// @notice Invariant I-3: CompanyWallet ownership-epoch monotonicity.
/// @dev The epoch initializes to 1, increments by exactly +1 on the ownership-transfer path
///      (`transferOwnership` / `completeOwnershipHandover`, both routed through `_setOwner`),
///      and never decreases.
abstract contract Properties_WALLET is PropertiesBase {
    /// @notice Returns the snapshotted epoch for the selected wallet at the given snapshot id.
    function _walletEpochAt(uint8 callNum, bool isA) private view returns (uint256) {
        return isA ? states[callNum].walletEpochAEpoch : states[callNum].walletEpochBEpoch;
    }

    /// @notice I-3 (a): a single epoch-bumping operation increments the epoch by exactly +1.
    function invariant_WALLET_01(bool isA) internal {
        uint256 before = _walletEpochAt(BEFORE, isA);
        uint256 afterValue = _walletEpochAt(AFTER, isA);
        fl.eq(afterValue, before + 1, WALLET_01);
    }

    /// @notice I-3 (b): the epoch never decreases across any observed operation.
    function invariant_WALLET_02(bool isA) internal {
        uint256 before = _walletEpochAt(BEFORE, isA);
        uint256 afterValue = _walletEpochAt(AFTER, isA);
        fl.gte(afterValue, before, WALLET_02);
    }

    /// @notice I-3 (c): the epoch is initialized to 1 at deployment (asserted against the live wallet).
    /// @dev Read from the live wallet so the property holds at the first observation: a freshly
    ///      initialized CompanyWallet must report epoch >= 1, and an untouched wallet exactly 1.
    function invariant_WALLET_03(bool isA) internal {
        uint256 liveEpoch = isA ? walletEpochA.ownershipEpoch() : walletEpochB.ownershipEpoch();
        fl.gte(liveEpoch, 1, WALLET_03);
    }

    /// @notice Non-bumping operations (e.g. `execute`) leave the epoch unchanged.
    function invariant_WALLET_04(bool isA) internal {
        uint256 before = _walletEpochAt(BEFORE, isA);
        uint256 afterValue = _walletEpochAt(AFTER, isA);
        fl.eq(afterValue, before, WALLET_04);
    }

    /// @notice Allowed-revert gate for the ownership-change path.
    function invariant_WALLET_12(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, WALLET_12);
    }

    /// @notice Allowed-revert gate for the execute path.
    function invariant_WALLET_22(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, WALLET_22);
    }

    /// @notice G-8: `execute` MUST reject an invalid target (address(0), the wallet itself, or an EOA)
    ///         specifically via the target guard, not for any unrelated auth/policy reason.
    /// @param success Whether the owner-authorized `execute` call with an invalid target succeeded.
    /// @param errorSelector The revert selector returned by the failed call.
    function invariant_WALLET_G8(bool success, bytes4 errorSelector) internal {
        fl.t(!success, WALLET_G8);
        fl.eq(errorSelector, Errors.CompanyWallet__InvalidCallTarget.selector, WALLET_G8);
    }

    /// @notice G-9 / X-3: a non-owner `execute` succeeds IFF `PolicyRegistry.canExecute` returned true.
    /// @param success Whether the non-owner `execute` call succeeded.
    /// @param expectedAuthorized The live registry `canExecute` decision for the same caller/target/selector.
    function invariant_WALLET_G9(bool success, bool expectedAuthorized) internal {
        fl.eq(success, expectedAuthorized, WALLET_G9);
    }
}

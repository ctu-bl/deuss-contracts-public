// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for the CompanyWallet ownership-epoch (I-3) fuzz vertical.
/// @dev Captures the ownership epoch (and current owner) of both dedicated WALLET-vertical wallets so
///      the WALLET invariants can assert monotonic +1 increments and a non-decreasing epoch across
///      calls. These wallets are separate from policyWalletA/B so the epoch churn does not reset the
///      epoch-scoped policy state the PolicyRegistry handlers rely on.
abstract contract BeforeAfterWALLET is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                           SNAPSHOT ENTRYPOINTS
    //////////////////////////////////////////////////////////////*/

    function _beforeWALLET() internal {
        _setWALLETState(BEFORE);
    }

    function _afterWALLET() internal {
        _setWALLETState(AFTER);
    }

    /*//////////////////////////////////////////////////////////////
                            SNAPSHOT SETTER
    //////////////////////////////////////////////////////////////*/

    function _setWALLETState(uint8 callNum) internal {
        states[callNum].walletEpochAEpoch = walletEpochA.ownershipEpoch();
        states[callNum].walletEpochBEpoch = walletEpochB.ownershipEpoch();
        states[callNum].walletEpochAOwner = walletEpochA.owner();
        states[callNum].walletEpochBOwner = walletEpochB.owner();
    }
}

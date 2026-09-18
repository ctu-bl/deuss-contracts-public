// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PropertiesBase} from "./PropertiesBase.sol";

/// @notice Invariants for the governance TimelockController (prefix TL).
/// @dev OperationState enum mirror: 0 = Unset, 1 = Waiting, 2 = Ready, 3 = Done.
abstract contract Properties_TL is PropertiesBase {
    uint8 internal constant TL_STATE_UNSET = 0;
    uint8 internal constant TL_STATE_WAITING = 1;
    uint8 internal constant TL_STATE_READY = 2;
    uint8 internal constant TL_STATE_DONE = 3;

    /// @notice G-15: an operation can only be scheduled with delay >= getMinDelay().
    /// @dev Asserted in the schedule postcondition on the success path.
    function invariant_TL_G15(uint256 usedDelay, uint256 minDelayAtSchedule) internal {
        fl.gte(usedDelay, minDelayAtSchedule, TL_G15);
    }

    /// @notice G-16: a successful execute had the op ready AND its predecessor done.
    /// @dev Readiness/predecessor-done are captured in the BEFORE snapshot (pre-execution).
    function invariant_TL_G16(bytes32 opId) internal {
        fl.t(states[BEFORE].timelockOpStates[opId].ready, TL_G16_READY);
        fl.t(states[BEFORE].timelockOpStates[opId].predecessorDone, TL_G16_PREDECESSOR);
    }

    /// @notice I-8: state lifecycle is monotonic and replay-free.
    /// @dev An op that was Done in BEFORE must still be Done in AFTER (no Done -> other).
    function invariant_TL_I8_NoRegression(bytes32 opId) internal {
        if (states[BEFORE].timelockOpStates[opId].opState == TL_STATE_DONE) {
            fl.eq(uint256(states[AFTER].timelockOpStates[opId].opState), uint256(TL_STATE_DONE), TL_I8_NO_REGRESSION);
        }
    }

    /// @notice I-8: a successful execute must have started from a Ready op (not Unset/Waiting/Done).
    function invariant_TL_I8_ReadyToDone(bytes32 opId) internal {
        fl.eq(uint256(states[BEFORE].timelockOpStates[opId].opState), uint256(TL_STATE_READY), TL_I8_READY_TO_DONE);
        fl.eq(uint256(states[AFTER].timelockOpStates[opId].opState), uint256(TL_STATE_DONE), TL_I8_READY_TO_DONE);
    }

    /// @notice I-8: executing an unscheduled (Unset) or non-ready op must NOT succeed.
    /// @dev Called on the failure path of execute when the op was not Ready before the call.
    function invariant_TL_I8_NoReplayOrUnset(bool executeSucceeded, uint8 stateBefore) internal {
        if (stateBefore != TL_STATE_READY) {
            fl.eq(executeSucceeded, false, TL_I8_NO_REPLAY);
        }
    }

    /// @notice E-1: an op's done-timestamp anchor is never earlier than scheduleTime + minDelay.
    /// @dev The on-chain `getTimestamp` returns scheduleTime + delay (the effective time). Since the
    ///      schedule used delay >= minDelayAtSchedule (G-15), the effective time is never earlier than
    ///      scheduleTime + minDelayAtSchedule, i.e. no privileged op becomes effective early.
    function invariant_TL_E1(uint256 effectiveTimestamp, uint256 scheduleTime, uint256 minDelayAtSchedule) internal {
        fl.gte(effectiveTimestamp, scheduleTime + minDelayAtSchedule, TL_E1);
    }
}

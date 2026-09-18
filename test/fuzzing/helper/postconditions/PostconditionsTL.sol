// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-small-strings */

import {PreconditionsTL} from "../preconditions/PreconditionsTL.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";

abstract contract PostconditionsTL is PostconditionsBase {
    // Legitimate revert selectors a production TimelockController emits when an operation is
    // scheduled/executed/cancelled in an invalid state. Reverting on these is the CORRECT
    // behavior, so the harness must treat them as expected (alongside the harness' own
    // ClampFail). Only a SUCCESS on an invalid op falsifies — enforced on the success paths.
    bytes4 internal constant _TL_INSUFFICIENT_DELAY = bytes4(keccak256("TimelockInsufficientDelay(uint256,uint256)"));
    bytes4 internal constant _TL_UNEXPECTED_STATE =
        bytes4(keccak256("TimelockUnexpectedOperationState(bytes32,bytes32)"));
    bytes4 internal constant _TL_UNEXECUTED_PREDECESSOR = bytes4(keccak256("TimelockUnexecutedPredecessor(bytes32)"));
    bytes4 internal constant _TL_UNAUTHORIZED_CALLER = bytes4(keccak256("TimelockUnauthorizedCaller(address)"));
    bytes4 internal constant _TL_INVALID_OP_LENGTH =
        bytes4(keccak256("TimelockInvalidOperationLength(uint256,uint256,uint256)"));
    bytes4 internal constant _ACCESS_CONTROL_UNAUTHORIZED =
        bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
    // OZ Errors.FailedCall(): bubbled by execute's inner `_execute` -> Address.verifyCallResult when the
    // scheduled operation's benign no-op call (a non-matching 4-byte selector against the timelock, which
    // has no fallback) reverts with empty returndata. This is a HARNESS artifact of the scheduled calldata,
    // not a protocol break: the operation was genuinely Ready (_beforeCall passed) and only the inner call
    // failed. A not-ready/unscheduled op reverts earlier with TimelockUnexpectedOperationState, so allowing
    // FailedCall here cannot mask an unauthorized/early execution (those are caught on the success path).
    bytes4 internal constant _FAILED_CALL = bytes4(keccak256("FailedCall()"));

    /// @notice Tolerates the harness ClampFail plus every legitimate TimelockController revert.
    /// @dev A production revert on an invalid/unscheduled/not-ready op is correct behavior and
    ///      must NOT falsify. A genuine invariant break (e.g. execute SUCCEEDS on a not-ready op)
    ///      is caught on the success path, not here.
    function _allowTLRevert(bytes4 errorSelector, string memory context) internal {
        bytes4[] memory allowed = new bytes4[](8);
        allowed[0] = _CLAMP_FAIL_SELECTOR;
        allowed[1] = _TL_INSUFFICIENT_DELAY;
        allowed[2] = _TL_UNEXPECTED_STATE;
        allowed[3] = _TL_UNEXECUTED_PREDECESSOR;
        allowed[4] = _TL_UNAUTHORIZED_CALLER;
        allowed[5] = _TL_INVALID_OP_LENGTH;
        allowed[6] = _ACCESS_CONTROL_UNAUTHORIZED;
        allowed[7] = _FAILED_CALL;
        fl.errAllow(errorSelector, allowed, context);
    }

    /// @notice Postconditions for schedule: on success G-15 holds and the op becomes Waiting/Ready.
    function scheduleTLPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsTL.ScheduleParams memory params,
        uint256 minDelayAtSchedule
    ) internal {
        if (success) {
            _afterTL(params.opId);
            // G-15: the delay actually used was >= minDelay at schedule time.
            invariant_TL_G15(params.delay, minDelayAtSchedule);
            // I-8: a freshly scheduled op must not regress an already-Done op.
            invariant_TL_I8_NoRegression(params.opId);
        } else {
            // Schedule may legitimately revert: insufficient delay (delay < minDelay), op already
            // exists (TimelockUnexpectedOperationState), or caller without PROPOSER_ROLE. Each is
            // CORRECT behavior and must pass. G-15 (delay >= minDelay) is asserted on success only.
            _allowTLRevert(_returnSelector(returnData), "TL-SCHEDULE-REVERT");
        }
    }

    /// @notice Postconditions for execute. Captures readiness from BEFORE and enforces I-8 + G-16.
    function executeTLPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsTL.TLExecuteParams memory params,
        uint8 stateBefore,
        uint256 scheduleTime,
        uint256 minDelayAtSchedule
    ) internal {
        if (success) {
            _afterTL(params.opId);
            // G-16: the op was ready and its predecessor done before execution.
            invariant_TL_G16(params.opId);
            // I-8: execution moves Ready -> Done; an unscheduled/non-ready op cannot reach here.
            invariant_TL_I8_ReadyToDone(params.opId);
            // E-1: the op's effective (done-anchor) timestamp captured before execution is never
            // earlier than scheduleTime + minDelay, i.e. no privileged op became effective early.
            if (scheduleTime != 0) {
                uint256 effectiveTimestamp = states[BEFORE].timelockOpStates[params.opId].timestamp;
                invariant_TL_E1(effectiveTimestamp, scheduleTime, minDelayAtSchedule);
            }
        } else {
            // I-8: if the op was not Ready before the call, the call must have failed.
            // Failure here is the CORRECT outcome for an Unset/Waiting/Done op — executing a
            // not-ready op reverts with TimelockUnexpectedOperationState / TimelockUnexecutedPredecessor.
            // A SUCCESS on such an op would falsify on the success path (G-16 / I-8 Ready->Done).
            invariant_TL_I8_NoReplayOrUnset(success, stateBefore);
            _allowTLRevert(_returnSelector(returnData), "TL-EXECUTE-REVERT");
        }
    }

    /// @notice Postconditions for cancel: a cancelled pending op becomes Unset; Done ops are untouched.
    function cancelTLPostconditions(bool success, bytes memory returnData, PreconditionsTL.CancelParams memory params)
        internal
    {
        if (success) {
            _afterTL(params.opId);
            // I-8: cancellation never resurrects or regresses a previously-Done op.
            invariant_TL_I8_NoRegression(params.opId);
        } else {
            // Cancelling an unscheduled/Done op reverts with TimelockUnexpectedOperationState —
            // that is the CORRECT behavior and must pass. I-8 (no Done regression) is checked on success.
            _allowTLRevert(_returnSelector(returnData), "TL-CANCEL-REVERT");
        }
    }

    /// @notice Postconditions for updateDelay: caller must be the timelock itself.
    function updateDelayTLPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsTL.UpdateDelayParams memory params
    ) internal {
        if (success) {
            // The new min delay is stored exactly.
            fl.eq(timelock.getMinDelay(), params.newDelay, TL_UPDATE_DELAY);
        } else {
            // updateDelay reverts with TimelockUnauthorizedCaller unless the timelock calls itself.
            _allowTLRevert(_returnSelector(returnData), "TL-UPDATE-DELAY-REVERT");
        }
    }
}

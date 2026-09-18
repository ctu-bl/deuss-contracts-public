// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {PreconditionsTL} from "../preconditions/PreconditionsTL.sol";
import {PostconditionsTL} from "../postconditions/PostconditionsTL.sol";

/// @title HandlerTL
/// @notice Stateful fuzz handlers for the governance TimelockController vertical slice.
/// @dev The harness (address(this)) holds PROPOSER_ROLE, EXECUTOR_ROLE, and CANCELLER_ROLE
///      (granted in FuzzSetup), so role-gated calls are driven from a real role holder.
///      updateDelay can only be called by the timelock itself, so it is routed through
///      address(timelock) as the caller.
abstract contract HandlerTL is PreconditionsTL, PostconditionsTL {
    /// @notice Schedules a new single-call operation through the PROPOSER path.
    /// @param targetSeed Seed used to pick a predecessor among tracked ops.
    /// @param dataSeed Seed used to derive the call data and salt.
    /// @param delaySeed Seed used to derive the requested delay (mix of valid and too-small).
    /// @param usePredecessor When true, chains onto a tracked op as predecessor.
    function handler_scheduleTL(uint256 targetSeed, uint256 dataSeed, uint256 delaySeed, bool usePredecessor) public {
        ScheduleParams memory params = scheduleTLPreconditions(targetSeed, dataSeed, delaySeed, usePredecessor);

        uint256 minDelayAtSchedule = timelock.getMinDelay();
        _beforeTL(params.opId);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(timelock),
            abi.encodeWithSelector(
                timelock.schedule.selector,
                params.target,
                params.value,
                params.data,
                params.predecessor,
                params.salt,
                params.delay
            ),
            address(this)
        );

        if (success) {
            _trackTimelockOp(params, block.timestamp, minDelayAtSchedule);
        }

        scheduleTLPostconditions(success, returnData, params, minDelayAtSchedule);
    }

    /// @notice Executes an operation through the EXECUTOR path, mixing tracked and random ids.
    /// @dev Echidna advances block.timestamp between calls, so tracked Waiting ops naturally
    ///      become Ready over the campaign without an explicit time-forcing handler.
    /// @param opSeed Seed used to pick the operation id.
    /// @param useTracked When true, targets a real tracked op; otherwise a random (unscheduled) id.
    function handler_executeTL(uint256 opSeed, bool useTracked) public {
        TLExecuteParams memory params = executeTLPreconditions(opSeed, useTracked);

        _beforeTL(params.opId);
        uint8 stateBefore = states[BEFORE].timelockOpStates[params.opId].opState;
        uint256 scheduleTime = trackedOpScheduleTime[params.opId];
        uint256 minDelayAtSchedule = trackedOpMinDelay[params.opId];

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(timelock),
            abi.encodeWithSelector(
                timelock.execute.selector, params.target, params.value, params.data, params.predecessor, params.salt
            ),
            address(this)
        );

        executeTLPostconditions(success, returnData, params, stateBefore, scheduleTime, minDelayAtSchedule);
    }

    /// @notice Cancels an operation through the CANCELLER path, mixing tracked and random ids.
    /// @param opSeed Seed used to pick the operation id.
    /// @param useTracked When true, targets a real tracked op; otherwise a random id.
    function handler_cancelTL(uint256 opSeed, bool useTracked) public {
        CancelParams memory params = cancelTLPreconditions(opSeed, useTracked);

        _beforeTL(params.opId);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(timelock), abi.encodeWithSelector(timelock.cancel.selector, params.opId), address(this)
        );

        cancelTLPostconditions(success, returnData, params);
    }

    /// @notice Updates the minimum delay. Only the timelock itself is authorized, so the call is
    ///         routed through address(timelock) as the caller.
    /// @param delaySeed Seed used to derive the new minimum delay.
    function handler_updateDelayTL(uint256 delaySeed) public {
        UpdateDelayParams memory params = updateDelayTLPreconditions(delaySeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(timelock), abi.encodeWithSelector(timelock.updateDelay.selector, params.newDelay), address(timelock)
        );

        updateDelayTLPostconditions(success, returnData, params);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Records a successfully scheduled op so execute/cancel handlers can target it.
    function _trackTimelockOp(ScheduleParams memory params, uint256 scheduleTime, uint256 minDelayAtSchedule) private {
        bytes32 opId = params.opId;
        if (!trackedOp[opId]) {
            trackedOp[opId] = true;
            trackedOpIds.push(opId);
        }
        trackedOpTarget[opId] = params.target;
        trackedOpValue[opId] = params.value;
        trackedOpData[opId] = params.data;
        trackedOpPredecessor[opId] = params.predecessor;
        trackedOpSalt[opId] = params.salt;
        trackedOpScheduleTime[opId] = scheduleTime;
        trackedOpMinDelay[opId] = minDelayAtSchedule;
    }
}

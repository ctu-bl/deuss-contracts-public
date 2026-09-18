// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for the governance TimelockController fuzz vertical.
/// @dev Captures the lifecycle-relevant fields for the single operation being acted on:
///      its state enum, raw timestamp, readiness, whether its predecessor is done, and the
///      controller-wide minimum delay. The handler records the schedule-time and predecessor
///      for each tracked operation so the postconditions can reconstruct the delay invariants.
abstract contract BeforeAfterTL is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                           SNAPSHOT ENTRYPOINTS
    //////////////////////////////////////////////////////////////*/

    function _beforeTL(bytes32 opId) internal {
        _setTLState(BEFORE, opId);
    }

    function _afterTL(bytes32 opId) internal {
        _setTLState(AFTER, opId);
    }

    /*//////////////////////////////////////////////////////////////
                            SNAPSHOT SETTER
    //////////////////////////////////////////////////////////////*/

    function _setTLState(uint8 callNum, bytes32 opId) internal {
        TimelockControllerUpgradeable tl = timelock;

        TimelockOpState storage opState = states[callNum].timelockOpStates[opId];
        opState.opState = uint8(tl.getOperationState(opId));
        opState.timestamp = tl.getTimestamp(opId);
        opState.ready = tl.isOperationReady(opId);
        opState.pending = tl.isOperationPending(opId);
        opState.done = tl.isOperationDone(opId);

        // Predecessor-done flag: a zero predecessor is treated as already satisfied.
        bytes32 predecessor = trackedOpPredecessor[opId];
        opState.predecessorDone = (predecessor == bytes32(0)) || tl.isOperationDone(predecessor);

        states[callNum].timelockMinDelay = tl.getMinDelay();
    }
}

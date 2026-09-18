// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsBase} from "./PreconditionsBase.sol";

/// @notice Precondition builders for the governance TimelockController fuzz vertical.
/// @dev Operations are single-call operations (target/value/data/predecessor/salt). Handlers
///      schedule into a deterministic, harness-controlled op so that execute/cancel can later
///      target a real, tracked operation as well as random ids.
abstract contract PreconditionsTL is PreconditionsBase {
    struct ScheduleParams {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
        bytes32 opId;
    }

    struct TLExecuteParams {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        bytes32 opId;
    }

    struct CancelParams {
        bytes32 opId;
    }

    struct UpdateDelayParams {
        uint256 newDelay;
    }

    /// @notice Builds a schedule operation. The delay is clamped to be >= the current minDelay
    ///         on a fraction of seeds so that the success path is reachable, while other seeds
    ///         deliberately pick a too-small delay to exercise the rejection branch.
    function scheduleTLPreconditions(uint256 targetSeed, uint256 dataSeed, uint256 delaySeed, bool usePredecessor)
        internal
        returns (ScheduleParams memory params)
    {
        // A benign self-targeting no-op call. Targeting the timelock with empty calldata makes
        // execution succeed (fallback / empty call) without external side effects.
        params.target = address(timelock);
        params.value = 0;
        params.data = abi.encodePacked(bytes4(uint32(dataSeed)));

        // Unique salt per scheduled op so distinct nonces produce distinct ids.
        params.salt = keccak256(abi.encodePacked(address(this), timelockOpNonce, "tl-salt", dataSeed));
        ++timelockOpNonce;

        // Optionally chain onto the most recently scheduled tracked op as a predecessor.
        if (usePredecessor && trackedOpIds.length > 0) {
            params.predecessor = trackedOpIds[targetSeed % trackedOpIds.length];
        } else {
            params.predecessor = bytes32(0);
        }

        uint256 minDelay = timelock.getMinDelay();
        // 75% of the seed space yields a valid delay (>= minDelay); 25% yields a too-small delay.
        if (delaySeed % 4 == 0) {
            params.delay = minDelay == 0 ? 0 : (delaySeed % minDelay);
        } else {
            params.delay = minDelay + (delaySeed % (TL_MAX_EXTRA_DELAY + 1));
        }

        params.opId = timelock.hashOperation(params.target, params.value, params.data, params.predecessor, params.salt);
        require(params.opId != bytes32(0), ClampFail("tl op id is zero"));
    }

    /// @notice Selects an operation to execute, mixing tracked (real) ops with random ids.
    function executeTLPreconditions(uint256 opSeed, bool useTracked)
        internal
        view
        returns (TLExecuteParams memory params)
    {
        if (useTracked && trackedOpIds.length > 0) {
            bytes32 opId = trackedOpIds[opSeed % trackedOpIds.length];
            params.opId = opId;
            params.target = trackedOpTarget[opId];
            params.value = trackedOpValue[opId];
            params.data = trackedOpData[opId];
            params.predecessor = trackedOpPredecessor[opId];
            params.salt = trackedOpSalt[opId];
        } else {
            // A random, almost-certainly-unscheduled op. Execution must revert.
            params.target = address(timelock);
            params.value = 0;
            params.data = abi.encodePacked(bytes4(uint32(opSeed)), opSeed);
            params.predecessor = bytes32(0);
            params.salt = keccak256(abi.encodePacked("tl-random-execute", opSeed));
            params.opId =
                timelock.hashOperation(params.target, params.value, params.data, params.predecessor, params.salt);
        }
    }

    /// @notice Selects an operation to cancel, mixing tracked ids with random ids.
    function cancelTLPreconditions(uint256 opSeed, bool useTracked) internal view returns (CancelParams memory params) {
        if (useTracked && trackedOpIds.length > 0) {
            params.opId = trackedOpIds[opSeed % trackedOpIds.length];
        } else {
            params.opId = keccak256(abi.encodePacked("tl-random-cancel", opSeed));
        }
    }

    /// @notice Builds a new minimum delay value within a bounded range.
    function updateDelayTLPreconditions(uint256 delaySeed) internal pure returns (UpdateDelayParams memory params) {
        params.newDelay = delaySeed % (TL_MAX_MIN_DELAY + 1);
    }
}

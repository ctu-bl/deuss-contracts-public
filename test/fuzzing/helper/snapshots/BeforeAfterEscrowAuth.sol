// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for EscrowManager authorization fuzz actions.
abstract contract BeforeAfterEscrowAuth is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                    ESCROW AUTHORIZATION SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Full-pool snapshot of EscrowManager's authorization matrix plus ambient state
    /// (assetManager wiring, nextEscrowId). Bounded pool x bounded types makes this cheap.
    function _beforeEscrowAuth() internal {
        _setEscrowAuthState(BEFORE);
    }

    function _afterEscrowAuth() internal {
        _setEscrowAuthState(AFTER);
    }

    function _setEscrowAuthState(uint8 callNum) internal {
        for (uint256 i; i < knownEscrowModules.length; ++i) {
            address moduleAddr = knownEscrowModules[i];
            states[callNum].escrowModuleTypeStates[moduleAddr] = escrowManager.moduleTypeOf(moduleAddr);

            for (uint256 j; j < knownEscrowModuleTypes.length; ++j) {
                bytes32 moduleType = knownEscrowModuleTypes[j];
                states[callNum].escrowAuthStates[moduleType][moduleAddr] =
                    escrowManager.isAuthorizedModule(moduleType, moduleAddr);
            }
        }

        states[callNum].escrowAssetManager = escrowManager.assetManager();
        states[callNum].escrowNextId = escrowManager.nextEscrowId();
    }
}

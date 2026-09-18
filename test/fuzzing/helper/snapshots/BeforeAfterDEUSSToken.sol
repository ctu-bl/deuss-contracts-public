// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SnapshotTypes} from "./SnapshotTypes.sol";

/// @notice Before/after snapshot helpers for DEUSSToken fuzz actions.
abstract contract BeforeAfterDEUSSToken is SnapshotTypes {
    /*//////////////////////////////////////////////////////////////
                          TOKEN SNAPSHOT
    //////////////////////////////////////////////////////////////*/

    function _beforeToken(address[] memory actors, address[] memory owners, address[] memory spenders) internal {
        _before(actors, _emptyUintArray(), _emptyUintArray());
        _setTokenPairStates(BEFORE, owners, spenders);
    }

    function _afterToken(address[] memory actors, address[] memory owners, address[] memory spenders) internal {
        _after(actors, _emptyUintArray(), _emptyUintArray());
        _setTokenPairStates(AFTER, owners, spenders);
    }

    function _setTokenPairStates(uint8 callNum, address[] memory owners, address[] memory spenders) internal {
        uint256 pairsLength = owners.length < spenders.length ? owners.length : spenders.length;
        for (uint256 i; i < pairsLength; ++i) {
            address owner = owners[i];
            address spender = spenders[i];
            if (owner == address(0) || spender == address(0)) continue;

            states[callNum].tokenPairStates[owner][spender].allowance = token.allowance(owner, spender, bondTokenId);
            states[callNum].tokenPairStates[owner][spender].operatorApproved = token.isOperator(owner, spender);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Ownable} from "solady/src/auth/Ownable.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

/// @title Properties_ESAU
/// @notice Invariants for the EscrowManager authorization flow. Module registration / deactivation
/// / admin-gated mutators plus the authorization checks on createEscrow, withdraw, claim, and
/// sweep. Positive-path escrow lifecycle is covered by the Marketplace vertical (ESCR-*).
abstract contract Properties_ESAU is PropertiesBase {
    /*//////////////////////////////////////////////////////////////
                            GLOBAL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev moduleTypeOf and isAuthorizedModule are mutated together by registerModule and
    /// deactivateModule, so the two must stay in sync for every module in the fuzz pool.
    function invariant_ESAU_01(address moduleAddr) internal {
        bytes32 recordedType = escrowManager.moduleTypeOf(moduleAddr);
        if (recordedType != bytes32(0)) {
            fl.eq(escrowManager.isAuthorizedModule(recordedType, moduleAddr), true, ESAU_01);
        }
    }

    /// @dev No module may be authorized under two different types simultaneously. The contract
    /// prevents this via the ModuleTypeMismatch / ModuleAlreadyRegistered guards; we verify the
    /// resulting state.
    function invariant_ESAU_02(address moduleAddr) internal {
        uint256 authorizedCount;
        for (uint256 i; i < knownEscrowModuleTypes.length; ++i) {
            bytes32 moduleType = knownEscrowModuleTypes[i];
            if (moduleType == bytes32(0)) continue;
            if (escrowManager.isAuthorizedModule(moduleType, moduleAddr)) ++authorizedCount;
        }
        fl.eq(authorizedCount < 2, true, ESAU_02);
    }

    /*//////////////////////////////////////////////////////////////
                            registerModule
    //////////////////////////////////////////////////////////////*/

    function invariant_ESAU_10(address moduleAddr, bytes32 moduleType) internal {
        fl.eq(uint256(states[AFTER].escrowModuleTypeStates[moduleAddr]), uint256(moduleType), ESAU_10_MODULE_TYPE);
        fl.eq(states[AFTER].escrowAuthStates[moduleType][moduleAddr], true, ESAU_10_AUTHORIZED);
    }

    /// @dev Cross-module isolation. Any module other than the mutated one, and any (type,addr)
    /// pair other than (moduleType, moduleAddr), must be identical before and after.
    function invariant_ESAU_11(address mutatedAddr, bytes32 mutatedType) internal {
        for (uint256 i; i < knownEscrowModules.length; ++i) {
            address m = knownEscrowModules[i];
            if (m != mutatedAddr) {
                fl.eq(
                    uint256(states[AFTER].escrowModuleTypeStates[m]),
                    uint256(states[BEFORE].escrowModuleTypeStates[m]),
                    ESAU_11_MODULE_TYPE
                );
            }
            for (uint256 j; j < knownEscrowModuleTypes.length; ++j) {
                bytes32 t = knownEscrowModuleTypes[j];
                if (m == mutatedAddr && t == mutatedType) continue;
                fl.eq(states[AFTER].escrowAuthStates[t][m], states[BEFORE].escrowAuthStates[t][m], ESAU_11_AUTHORIZED);
            }
        }
    }

    /// @dev On revert, selector must correspond to the first failing predicate evaluated against
    /// pre-state. Evaluation order in _registerModule:
    ///   1. moduleType == 0                    -> InvalidModuleType
    ///   2. moduleAddress == 0                 -> InvalidModuleAddress
    ///   3. moduleTypeOf[addr] != 0 && != type -> ModuleTypeMismatch
    ///   4. moduleTypeOf[addr] == type         -> ModuleAlreadyRegistered (sync guarantees isAuthorized is true)
    function invariant_ESAU_12(address moduleAddr, bytes32 moduleType, bytes4 errorSelector) internal {
        bytes32 preType = states[BEFORE].escrowModuleTypeStates[moduleAddr];

        bytes4 expected;
        if (moduleType == bytes32(0)) {
            expected = Errors.EscrowManager__InvalidModuleType.selector;
        } else if (moduleAddr == address(0)) {
            expected = Errors.EscrowManager__InvalidModuleAddress.selector;
        } else if (preType != bytes32(0) && preType != moduleType) {
            expected = Errors.EscrowManager__ModuleTypeMismatch.selector;
        } else if (preType == moduleType) {
            expected = Errors.EscrowManager__ModuleAlreadyRegistered.selector;
        } else {
            // Inputs satisfied all guards; call should have succeeded. Signal by asserting false.
            fl.t(false, ESAU_12);
            return;
        }
        fl.eq(errorSelector, expected, ESAU_12);
    }

    /// @dev Success-side oracle for `registerModule`. A successful call implies all four guards
    /// passed: inputs non-zero AND pre-state `moduleTypeOf[addr] == 0` (otherwise one of the two
    /// inner requires would have fired). Catches a regression that weakens any guard.
    function invariant_ESAU_13(address moduleAddr, bytes32 moduleType) internal {
        fl.eq(moduleType != bytes32(0), true, ESAU_13_MODULE_TYPE);
        fl.eq(moduleAddr != address(0), true, ESAU_13_MODULE_ADDRESS);
        fl.eq(uint256(states[BEFORE].escrowModuleTypeStates[moduleAddr]), uint256(bytes32(0)), ESAU_13_PRE_MODULE_TYPE);
    }

    /*//////////////////////////////////////////////////////////////
                           deactivateModule
    //////////////////////////////////////////////////////////////*/

    function invariant_ESAU_20(address moduleAddr, bytes32 moduleType) internal {
        fl.eq(uint256(states[AFTER].escrowModuleTypeStates[moduleAddr]), uint256(bytes32(0)), ESAU_20_MODULE_TYPE);
        fl.eq(states[AFTER].escrowAuthStates[moduleType][moduleAddr], false, ESAU_20_AUTHORIZED);
    }

    /// @dev Cross-module isolation for deactivation.
    function invariant_ESAU_21(address mutatedAddr, bytes32 mutatedType) internal {
        for (uint256 i; i < knownEscrowModules.length; ++i) {
            address m = knownEscrowModules[i];
            if (m != mutatedAddr) {
                fl.eq(
                    uint256(states[AFTER].escrowModuleTypeStates[m]),
                    uint256(states[BEFORE].escrowModuleTypeStates[m]),
                    ESAU_21_MODULE_TYPE
                );
            }
            for (uint256 j; j < knownEscrowModuleTypes.length; ++j) {
                bytes32 t = knownEscrowModuleTypes[j];
                if (m == mutatedAddr && t == mutatedType) continue;
                fl.eq(states[AFTER].escrowAuthStates[t][m], states[BEFORE].escrowAuthStates[t][m], ESAU_21_AUTHORIZED);
            }
        }
    }

    /// @dev Evaluation order in deactivateModule:
    ///   1. moduleType == 0                    -> InvalidModuleType
    ///   2. moduleAddress == 0                 -> InvalidModuleAddress
    ///   3. moduleTypeOf[addr] == 0            -> ModuleNotRegistered
    ///   4. moduleTypeOf[addr] != moduleType   -> ModuleTypeMismatch
    ///   5. activeEscrowsByModule[addr] != 0   -> ModuleHasActiveEscrows
    function invariant_ESAU_22(address moduleAddr, bytes32 moduleType, bytes4 errorSelector) internal {
        bytes32 preType = states[BEFORE].escrowModuleTypeStates[moduleAddr];

        bytes4 expected;
        if (moduleType == bytes32(0)) {
            expected = Errors.EscrowManager__InvalidModuleType.selector;
        } else if (moduleAddr == address(0)) {
            expected = Errors.EscrowManager__InvalidModuleAddress.selector;
        } else if (preType == bytes32(0)) {
            expected = Errors.EscrowManager__ModuleNotRegistered.selector;
        } else if (preType != moduleType) {
            expected = Errors.EscrowManager__ModuleTypeMismatch.selector;
        } else {
            expected = Errors.EscrowManager__ModuleHasActiveEscrows.selector;
        }
        fl.eq(errorSelector, expected, ESAU_22);
    }

    /// @dev Success-side oracle for `deactivateModule`. The precise pre-state must match the
    /// inputs so the contract's `ModuleTypeMismatch` guard cannot have been bypassed. Catches the
    /// subtle regression where deactivation accidentally clears `moduleTypeOf` but leaves
    /// `isAuthorizedModule[realType][addr]` set, desynchronising the matrix.
    function invariant_ESAU_23(address moduleAddr, bytes32 moduleType) internal {
        fl.eq(moduleType != bytes32(0), true, ESAU_23_MODULE_TYPE);
        fl.eq(moduleAddr != address(0), true, ESAU_23_MODULE_ADDRESS);
        fl.eq(uint256(states[BEFORE].escrowModuleTypeStates[moduleAddr]), uint256(moduleType), ESAU_23_PRE_MODULE_TYPE);
    }

    /*//////////////////////////////////////////////////////////////
                           setAssetManager
    //////////////////////////////////////////////////////////////*/

    /// @dev On success the wiring must equal the provided address AND that address must be
    /// non-zero. The second assertion catches a regression that removes the `require(assetManager_
    /// != address(0))` guard — without it, the wiring could be cleared silently.
    function invariant_ESAU_30(address expected) internal {
        fl.eq(states[AFTER].escrowAssetManager, expected, ESAU_30_ASSET_MANAGER);
        fl.eq(expected != address(0), true, ESAU_30_NONZERO);
    }

    function invariant_ESAU_31(bytes4 errorSelector) internal {
        fl.eq(errorSelector, Errors.ZeroAddress.selector, ESAU_31);
    }

    function invariant_ESAU_33(address newAssetManager) internal {
        fl.eq(newAssetManager, address(0), ESAU_33);
    }

    function invariant_ESAU_34(bool success) internal {
        fl.eq(success, true, ESAU_34);
    }

    /// @dev AssetManager wiring change must not touch the module authorization matrix.
    function invariant_ESAU_32() internal {
        _assertAuthorizationMatrixUnchanged(ESAU_32);
    }

    /*//////////////////////////////////////////////////////////////
                  createEscrow / withdraw / claim AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function invariant_ESAU_40(bytes4 errorSelector) internal {
        fl.eq(errorSelector, Errors.EscrowManager__ModuleNotRegistered.selector, ESAU_40);
    }

    function invariant_ESAU_42(bool success) internal {
        fl.eq(success, false, ESAU_42);
    }

    function invariant_ESAU_41() internal {
        _assertAuthorizationMatrixUnchanged(ESAU_41_AUTH_MATRIX);
        fl.eq(states[AFTER].escrowNextId, states[BEFORE].escrowNextId, ESAU_41_NEXT_ID);
        fl.eq(states[AFTER].escrowAssetManager, states[BEFORE].escrowAssetManager, ESAU_41_ASSET_MANAGER);
    }

    /// @dev withdraw/claim from an unauthorized caller must revert with EscrowNotFound (when the
    /// escrow slot is empty) or ModuleNotAuthorized (when the slot exists but the caller is not
    /// authorized for its moduleType).
    function invariant_ESAU_50(bool escrowExisted, bytes4 errorSelector) internal {
        bytes4 expected = escrowExisted
            ? Errors.EscrowManager__ModuleNotAuthorized.selector
            : Errors.EscrowManager__EscrowNotFound.selector;
        fl.eq(errorSelector, expected, ESAU_50);
    }

    function invariant_ESAU_52(bool success) internal {
        fl.eq(success, false, ESAU_52);
    }

    function invariant_ESAU_51() internal {
        _assertAuthorizationMatrixUnchanged(ESAU_51_AUTH_MATRIX);
        fl.eq(states[AFTER].escrowNextId, states[BEFORE].escrowNextId, ESAU_51_NEXT_ID);
    }

    /*//////////////////////////////////////////////////////////////
                                sweep
    //////////////////////////////////////////////////////////////*/

    /// @dev Evaluation order for admin-guarded sweep revert:
    ///   1. assetType == NONE                 -> EscrowManager__InvalidAssetType
    ///   2. assetType == ERC20 && tokenId!=0  -> AssetManager__InvalidTokenId
    ///   3. amount == 0                       -> InvalidSweepAmount
    ///   4. beneficiary == 0                  -> InvalidBeneficiary
    ///   5. assetType == ERC721 && amount!=1  -> InvalidERC721Amount
    ///   6. amount > surplus                  -> SweepExceedsSurplus
    function invariant_ESAU_60(
        AssetType assetType,
        uint256 tokenId,
        uint256 amount,
        address beneficiary,
        uint256 surplus,
        bytes4 errorSelector
    ) internal {
        bytes4 expected;
        if (assetType == AssetType.NONE) {
            expected = Errors.EscrowManager__InvalidAssetType.selector;
        } else if (assetType == AssetType.ERC20 && tokenId != 0) {
            expected = Errors.AssetManager__InvalidTokenId.selector;
        } else if (amount == 0) {
            expected = Errors.EscrowManager__InvalidSweepAmount.selector;
        } else if (beneficiary == address(0)) {
            expected = Errors.EscrowManager__InvalidBeneficiary.selector;
        } else if (assetType == AssetType.ERC721 && amount != 1) {
            expected = Errors.EscrowManager__InvalidERC721Amount.selector;
        } else if (amount > surplus) {
            expected = Errors.EscrowManager__SweepExceedsSurplus.selector;
        } else {
            // All predicates satisfied -> sweep should have succeeded; revert indicates a bug.
            fl.t(false, ESAU_60);
            return;
        }
        fl.eq(errorSelector, expected, ESAU_60);
    }

    function invariant_ESAU_61() internal {
        _assertAuthorizationMatrixUnchanged(ESAU_61);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN GATE (Unauthorized)
    //////////////////////////////////////////////////////////////*/

    function invariant_ESAU_70(bytes4 errorSelector) internal {
        fl.eq(errorSelector, Ownable.Unauthorized.selector, ESAU_70);
    }

    function invariant_ESAU_72(bool success) internal {
        fl.eq(success, false, ESAU_72);
    }

    function invariant_ESAU_71() internal {
        _assertAuthorizationMatrixUnchanged(ESAU_71_AUTH_MATRIX);
        fl.eq(states[AFTER].escrowAssetManager, states[BEFORE].escrowAssetManager, ESAU_71_ASSET_MANAGER);
        fl.eq(states[AFTER].escrowNextId, states[BEFORE].escrowNextId, ESAU_71_NEXT_ID);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertAuthorizationMatrixUnchanged(string memory label) private {
        for (uint256 i; i < knownEscrowModules.length; ++i) {
            address m = knownEscrowModules[i];
            fl.eq(
                uint256(states[AFTER].escrowModuleTypeStates[m]),
                uint256(states[BEFORE].escrowModuleTypeStates[m]),
                label
            );
            for (uint256 j; j < knownEscrowModuleTypes.length; ++j) {
                bytes32 t = knownEscrowModuleTypes[j];
                fl.eq(states[AFTER].escrowAuthStates[t][m], states[BEFORE].escrowAuthStates[t][m], label);
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {Ownable} from "solady/src/auth/Ownable.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_ASSET is PropertiesBase {
    /*//////////////////////////////////////////////////////////////
                            GLOBAL CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /// @dev `isAssetSupported` must equal the boolean expressed by the stored config.
    function invariant_ASET_01(address token) internal {
        (, bool enabled, bool enforceTokenId) = assetManager.getAssetConfig(token);

        for (uint256 i; i < knownAssetTokenIds.length; ++i) {
            uint256 tokenId = knownAssetTokenIds[i];
            bool supported = assetManager.isAssetSupported(token, tokenId);
            bool expected = enabled && (!enforceTokenId || assetManager.isTokenIdAllowed(token, tokenId));
            fl.eq(supported, expected, ASET_01);
        }
    }

    /// @dev `getAssetType` must revert iff the config is disabled, and otherwise return the stored type.
    function invariant_ASET_02(address token) internal {
        (AssetType configAssetType, bool enabled,) = assetManager.getAssetConfig(token);

        (bool success, bytes memory returnData) =
            address(assetManager).staticcall(abi.encodeWithSelector(assetManager.getAssetType.selector, token));

        if (enabled) {
            fl.eq(success, true, ASET_02);
            AssetType decoded = abi.decode(returnData, (AssetType));
            fl.eq(uint256(decoded), uint256(configAssetType), ASET_02);
        } else {
            fl.eq(success, false, ASET_02);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                setAsset
    //////////////////////////////////////////////////////////////*/

    function invariant_ASET_10(
        address token,
        AssetType expectedAssetType,
        bool expectedEnabled,
        bool expectedEnforceTokenId
    ) internal {
        fl.eq(uint256(states[AFTER].assetConfigStates[token].assetType), uint256(expectedAssetType), ASET_10_TYPE);
        fl.eq(states[AFTER].assetConfigStates[token].enabled, expectedEnabled, ASET_10_ENABLED);
        fl.eq(states[AFTER].assetConfigStates[token].enforceTokenId, expectedEnforceTokenId, ASET_10_ENFORCE_TOKEN_ID);
    }

    function invariant_ASET_11(address token) internal {
        for (uint256 i; i < knownAssetTokenIds.length; ++i) {
            uint256 tokenId = knownAssetTokenIds[i];
            fl.eq(
                states[AFTER].assetAllowedStates[token][tokenId],
                states[BEFORE].assetAllowedStates[token][tokenId],
                ASET_11
            );
        }
    }

    function invariant_ASET_12(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](2);
        allowedErrors[0] = Errors.ZeroAddress.selector;
        allowedErrors[1] = Errors.AssetManager__InvalidAssetType.selector;
        fl.errAllow(errorSelector, allowedErrors, ASET_12);
    }

    /// @dev When the caller is admin and inputs satisfy preconditions, `setAsset` must succeed.
    /// A failure therefore implies `token == 0` OR `enabled && assetType == NONE`, and the selector
    /// must correspond to that cause.
    function invariant_ASET_13(address token, AssetType assetType, bool enabled, bytes4 errorSelector) internal {
        if (token == address(0)) {
            fl.eq(errorSelector, Errors.ZeroAddress.selector, ASET_13);
        } else {
            fl.eq(enabled && assetType == AssetType.NONE, true, ASET_13);
            fl.eq(errorSelector, Errors.AssetManager__InvalidAssetType.selector, ASET_13);
        }
    }

    /// @dev Success-side oracle: `setAsset` must never accept a zero-address token or the
    /// (enabled=true, assetType=NONE) combination. Catches a regression that silently
    /// removes either of the two `require` guards in `AssetManager.setAsset`.
    function invariant_ASET_15(address token, AssetType assetType, bool enabled) internal {
        fl.eq(token != address(0), true, ASET_15);
        fl.eq(!(enabled && assetType == AssetType.NONE), true, ASET_15);
    }

    /*//////////////////////////////////////////////////////////////
                         CROSS-TOKEN ISOLATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Every token in the fuzz pool OTHER than the mutated target must be identical before
    /// and after the call. Guards against storage collisions or cross-token leakage in mutators.
    function invariant_ASET_14(address targetToken) internal {
        for (uint256 i; i < knownAssetTokens.length; ++i) {
            address other = knownAssetTokens[i];
            if (other == targetToken) continue;
            _assertAssetStateEqual(other, ASET_14);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            setAssetTokenId
    //////////////////////////////////////////////////////////////*/

    function invariant_ASET_20(address token, uint256 tokenId, bool expectedAllowed) internal {
        fl.eq(states[AFTER].assetAllowedStates[token][tokenId], expectedAllowed, ASET_20);
    }

    function invariant_ASET_21(address token) internal {
        fl.eq(
            uint256(states[AFTER].assetConfigStates[token].assetType),
            uint256(states[BEFORE].assetConfigStates[token].assetType),
            ASET_21_TYPE
        );
        fl.eq(
            states[AFTER].assetConfigStates[token].enabled,
            states[BEFORE].assetConfigStates[token].enabled,
            ASET_21_ENABLED
        );
        fl.eq(
            states[AFTER].assetConfigStates[token].enforceTokenId,
            states[BEFORE].assetConfigStates[token].enforceTokenId,
            ASET_21_ENFORCE_TOKEN_ID
        );
    }

    function invariant_ASET_22(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](2);
        allowedErrors[0] = Errors.AssetManager__AssetNotSupported.selector;
        allowedErrors[1] = Errors.AssetManager__TokenIdAllowlistDisabled.selector;
        fl.errAllow(errorSelector, allowedErrors, ASET_22);
    }

    /// @dev `setAssetTokenId` checks config.enabled first, then config.enforceTokenId. The revert
    /// selector must correspond to the first failing predicate evaluated against pre-state.
    function invariant_ASET_23(address token, bytes4 errorSelector) internal {
        bool wasEnabled = states[BEFORE].assetConfigStates[token].enabled;
        bool wasEnforceTokenId = states[BEFORE].assetConfigStates[token].enforceTokenId;

        if (!wasEnabled) {
            fl.eq(errorSelector, Errors.AssetManager__AssetNotSupported.selector, ASET_23);
        } else {
            fl.eq(wasEnforceTokenId, false, ASET_23);
            fl.eq(errorSelector, Errors.AssetManager__TokenIdAllowlistDisabled.selector, ASET_23);
        }
    }

    /// @dev Success-side oracle for `setAssetTokenId`. The two pre-state requirements must hold.
    /// Catches a regression that weakens either `require(config.enabled)` or
    /// `require(config.enforceTokenId)` in `AssetManager.setAssetTokenId`.
    function invariant_ASET_24(address token) internal {
        fl.eq(states[BEFORE].assetConfigStates[token].enabled, true, ASET_24);
        fl.eq(states[BEFORE].assetConfigStates[token].enforceTokenId, true, ASET_24);
    }

    /*//////////////////////////////////////////////////////////////
                             validateAsset
    //////////////////////////////////////////////////////////////*/

    /// @dev Given a pre-state snapshot, validateAsset(token, tokenId, amount) must succeed iff all
    /// four predicates hold; otherwise the selector must correspond to the first failing predicate
    /// in the evaluation order used by the contract.
    function invariant_ASET_30(address token, uint256 tokenId, uint256 amount, bool success, bytes4 errorSelector)
        internal
    {
        AssetManagerConfigState memory cfg = states[BEFORE].assetConfigStates[token];
        bool allowlistOk = !cfg.enforceTokenId || states[BEFORE].assetAllowedStates[token][tokenId];
        bool erc20Ok = cfg.assetType != AssetType.ERC20 || tokenId == 0;
        bool erc721Ok = cfg.assetType != AssetType.ERC721 || amount == 1;

        bool expectedSuccess = cfg.enabled && allowlistOk && erc20Ok && erc721Ok;
        fl.eq(success, expectedSuccess, ASET_30);

        if (!success) {
            bytes4 expectedSelector;
            if (!cfg.enabled) {
                expectedSelector = Errors.AssetManager__AssetNotSupported.selector;
            } else if (!allowlistOk) {
                expectedSelector = Errors.AssetManager__TokenIdNotSupported.selector;
            } else if (!erc20Ok) {
                expectedSelector = Errors.AssetManager__InvalidTokenId.selector;
            } else {
                expectedSelector = Errors.AssetManager__InvalidAmountForERC721.selector;
            }
            fl.eq(errorSelector, expectedSelector, ASET_31);
        }
    }

    /// @dev validateAsset is a view function and must not mutate any token's state in the pool.
    function invariant_ASET_32() internal {
        for (uint256 i; i < knownAssetTokens.length; ++i) {
            _assertAssetStateEqual(knownAssetTokens[i], ASET_32);
        }
    }

    /// @dev On success, validateAsset returns exactly the stored assetType.
    function invariant_ASET_33(address token, bytes memory returnData) internal {
        AssetType returned = abi.decode(returnData, (AssetType));
        fl.eq(uint256(returned), uint256(states[BEFORE].assetConfigStates[token].assetType), ASET_33);
    }

    /*//////////////////////////////////////////////////////////////
                          MODULE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function invariant_ASET_40(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, ASET_40);
        fl.eq(errorSelector, Ownable.Unauthorized.selector, ASET_40);
    }

    function invariant_ASET_41(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, ASET_41);
        fl.eq(errorSelector, Ownable.Unauthorized.selector, ASET_41);
    }

    /// @dev Non-admin attempts must leave the whole pool intact (not just the target token).
    function invariant_ASET_42() internal {
        for (uint256 i; i < knownAssetTokens.length; ++i) {
            _assertAssetStateEqual(knownAssetTokens[i], ASET_42);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertAssetStateEqual(address token, string memory label) private {
        fl.eq(
            uint256(states[AFTER].assetConfigStates[token].assetType),
            uint256(states[BEFORE].assetConfigStates[token].assetType),
            label
        );
        fl.eq(states[AFTER].assetConfigStates[token].enabled, states[BEFORE].assetConfigStates[token].enabled, label);
        fl.eq(
            states[AFTER].assetConfigStates[token].enforceTokenId,
            states[BEFORE].assetConfigStates[token].enforceTokenId,
            label
        );
        for (uint256 j; j < knownAssetTokenIds.length; ++j) {
            uint256 tid = knownAssetTokenIds[j];
            fl.eq(states[AFTER].assetAllowedStates[token][tid], states[BEFORE].assetAllowedStates[token][tid], label);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {AssetType} from "src/marketplace/MarketStructs.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsEscrowAuth is PreconditionsBase {
    struct RegisterModuleParams {
        bytes32 moduleType;
        address moduleAddr;
    }

    struct DeactivateModuleParams {
        bytes32 moduleType;
        address moduleAddr;
    }

    struct SetAssetManagerParams {
        address newAssetManager;
    }

    struct EscrowAuthSweepParams {
        AssetType assetType;
        address token;
        uint256 tokenId;
        uint256 amount;
        address beneficiary;
    }

    function _pickModuleAddr(uint256 seed) internal view returns (address moduleAddr) {
        uint256 len = knownEscrowModules.length;
        require(len != 0, ClampFail("module pool empty"));
        uint256 pick = seed % (len + 1);
        moduleAddr = pick == 0 ? address(0) : knownEscrowModules[pick - 1];
    }

    function _pickModuleType(uint256 seed) internal view returns (bytes32 moduleType) {
        uint256 len = knownEscrowModuleTypes.length;
        require(len != 0, ClampFail("module type pool empty"));
        moduleType = knownEscrowModuleTypes[seed % len];
    }

    function registerModulePreconditions(uint256 moduleTypeSeed, uint256 moduleAddrSeed)
        internal
        view
        returns (RegisterModuleParams memory params)
    {
        params.moduleType = _pickModuleType(moduleTypeSeed);
        params.moduleAddr = _pickModuleAddr(moduleAddrSeed);
    }

    function deactivateModulePreconditions(uint256 moduleTypeSeed, uint256 moduleAddrSeed)
        internal
        view
        returns (DeactivateModuleParams memory params)
    {
        params.moduleType = _pickModuleType(moduleTypeSeed);
        params.moduleAddr = _pickModuleAddr(moduleAddrSeed);
    }

    function setAssetManagerPreconditions(uint256 candidateSeed)
        internal
        view
        returns (SetAssetManagerParams memory params)
    {
        // Pick between: real assetManager (no-op success), a synthetic non-zero address (success
        // + restore), and address(0) (expects ZeroAddress revert). Each hit roughly a third of
        // the time so every branch is exercised.
        uint256 pick = candidateSeed % 3;
        if (pick == 0) {
            params.newAssetManager = address(assetManager);
        } else if (pick == 1) {
            params.newAssetManager = FUZZ_ASSET_TOKEN_1;
        } else {
            params.newAssetManager = address(0);
        }
    }

    /// @dev Sweep input selection. The pool is deliberately restricted to avoid reaching the
    /// `_transferAsset` dispatch on an incompatible token:
    ///   - ERC1155 is excluded because its `balanceOf` selector matches ERC6909 on our real token,
    ///     which would make the ERC1155 branch reach `_transferAsset` and revert with empty data
    ///     on `safeTransferFrom`. That empty-data revert is outside sweep's documented failure
    ///     surface, so we skip this asset type entirely in the sweep harness.
    ///   - For ERC20, `tokenId` is forced non-zero so `InvalidTokenId` fires before the ERC20
    ///     balance probe (which would also revert with empty data on our ERC6909 token).
    /// The remaining assetTypes {NONE, ERC20, ERC721, ERC6909} exercise every sweep revert branch
    /// against a real token with predictable surplus == 0 behaviour.
    function sweepPreconditions(uint256 assetTypeSeed, uint256 tokenIdSeed, uint256 amountSeed, uint256 beneficiarySeed)
        internal
        view
        returns (EscrowAuthSweepParams memory params)
    {
        uint256 atIdx = assetTypeSeed % 4;
        if (atIdx == 0) params.assetType = AssetType.NONE;
        else if (atIdx == 1) params.assetType = AssetType.ERC20;
        else if (atIdx == 2) params.assetType = AssetType.ERC721;
        else params.assetType = AssetType.ERC6909;

        params.token = address(token);

        if (params.assetType == AssetType.ERC20) {
            params.tokenId = (tokenIdSeed % 16) + 1;
        } else {
            params.tokenId = tokenIdSeed % 8;
        }

        params.amount = amountSeed % 4;

        uint256 benPick = beneficiarySeed % (users.length + 1);
        params.beneficiary = benPick == 0 ? address(0) : users[benPick - 1];
    }

    /// @dev Picks a caller that is guaranteed to remain unauthorized. The address is excluded from
    /// the mutable module pools used by this harness and validated as unregistered during setup.
    function _pickUnauthorizedCaller() internal pure returns (address caller) {
        caller = FUZZ_ESCROW_UNAUTH_CALLER;
    }
}

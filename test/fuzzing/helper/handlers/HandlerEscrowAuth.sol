// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AssetType, Escrow} from "src/marketplace/MarketStructs.sol";
import {PreconditionsEscrowAuth} from "../preconditions/PreconditionsEscrowAuth.sol";
import {PostconditionsEscrowAuth} from "../postconditions/PostconditionsEscrowAuth.sol";

/// @title HandlerEscrowAuth
/// @notice Stateful fuzz handlers for the EscrowManager authorization vertical slice.
/// @dev Admin-guarded entrypoints go through `address(this)` (the harness holds ADMIN).
/// Dedicated `_unauthorized` handlers call the same entrypoints from fuzz actors so the
/// solady `onlyRoles` gate is explicitly exercised. The module-only entrypoints (createEscrow,
/// withdraw, claim) are driven with unauthorized callers here; positive-path coverage of
/// createEscrow/withdraw/claim lives in the Marketplace harness (ESCR-10..15).
abstract contract HandlerEscrowAuth is PreconditionsEscrowAuth, PostconditionsEscrowAuth {
    /*//////////////////////////////////////////////////////////////
                            registerModule
    //////////////////////////////////////////////////////////////*/

    function handler_registerModule(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        RegisterModuleParams memory params = registerModulePreconditions(moduleTypeSeed, moduleAddrSeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.registerModule.selector, params.moduleType, params.moduleAddr),
            address(this)
        );

        registerModulePostconditions(success, returnData, params);
    }

    function handler_registerModuleUnauthorized(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public setCurrentActor {
        RegisterModuleParams memory params = registerModulePreconditions(moduleTypeSeed, moduleAddrSeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.registerModule.selector, params.moduleType, params.moduleAddr),
            currentActor
        );

        adminUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                           deactivateModule
    //////////////////////////////////////////////////////////////*/

    function handler_deactivateModule(uint256 moduleTypeSeed, uint256 moduleAddrSeed) public {
        DeactivateModuleParams memory params = deactivateModulePreconditions(moduleTypeSeed, moduleAddrSeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.deactivateModule.selector, params.moduleType, params.moduleAddr),
            address(this)
        );

        deactivateModulePostconditions(success, returnData, params);
    }

    function handler_deactivateModuleUnauthorized(uint256 moduleTypeSeed, uint256 moduleAddrSeed)
        public
        setCurrentActor
    {
        DeactivateModuleParams memory params = deactivateModulePreconditions(moduleTypeSeed, moduleAddrSeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.deactivateModule.selector, params.moduleType, params.moduleAddr),
            currentActor
        );

        adminUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                           setAssetManager
    //////////////////////////////////////////////////////////////*/

    /// @dev If a successful mutation would leave the EscrowManager wired to an address other than
    /// the real AssetManager, the handler explicitly restores the wiring before returning. Any
    /// drift would cause Marketplace.registerOffer to revert with AssetNotSupported and
    /// break OFER-13.
    function handler_setAssetManager(uint256 candidateSeed) public {
        SetAssetManagerParams memory params = setAssetManagerPreconditions(candidateSeed);
        address realAssetManager = address(assetManager);

        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.setAssetManager.selector, params.newAssetManager),
            address(this)
        );

        setAssetManagerPostconditions(success, returnData, params);

        if (success && params.newAssetManager != realAssetManager) {
            (bool restoreSuccess,) = fl.doFunctionCall(
                address(escrowManager),
                abi.encodeWithSelector(escrowManager.setAssetManager.selector, realAssetManager),
                address(this)
            );
            restoreAssetManagerPostconditions(restoreSuccess);
        }
    }

    function handler_setAssetManagerUnauthorized(uint256 candidateSeed) public setCurrentActor {
        SetAssetManagerParams memory params = setAssetManagerPreconditions(candidateSeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.setAssetManager.selector, params.newAssetManager),
            currentActor
        );

        adminUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                  MODULE-ONLY ENTRYPOINTS (unauthorized callers)
    //////////////////////////////////////////////////////////////*/

    /// @notice Calls createEscrow from a caller that is provably not registered as a module.
    /// The authorization check is the first require in createEscrow, so the call must revert
    /// with `ModuleNotRegistered` before any other validation.
    function handler_createEscrowAsActor(uint256 amountSeed, uint256 depositorSeed, uint256 tokenIdSeed) public {
        _beforeEscrowAuth();

        address depositor = users[depositorSeed % users.length];
        address caller = _pickUnauthorizedCaller();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.createEscrow.selector, amountSeed, depositor, address(token), tokenIdSeed
            ),
            caller
        );

        createEscrowAsActorPostconditions(success, returnData);
    }

    /// @notice Calls withdraw from a caller that is not authorized for the selected escrow.
    /// The authorization check is the first require in withdraw, so the call must revert with
    /// either `EscrowNotFound` (no such escrow) or `ModuleNotAuthorized` (escrow exists but
    /// caller is not in its module type's authorization set).
    function handler_withdrawAsActor(uint256 escrowIdSeed, uint256 amountSeed) public {
        _beforeEscrowAuth();

        // Bias escrowId towards valid range so both EscrowNotFound and ModuleNotAuthorized
        // branches are reachable. `nextEscrowId + 2` lets seeds overshoot into the empty tail.
        uint256 maxId = escrowManager.nextEscrowId() + 2;
        uint256 escrowId = maxId == 0 ? 0 : escrowIdSeed % (maxId + 1);
        bool escrowExisted = _getEscrowModuleType(escrowId) != bytes32(0);

        address caller = _pickUnauthorizedCaller();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.withdraw.selector, escrowId, amountSeed),
            caller
        );

        withdrawOrClaimAsActorPostconditions(success, returnData, escrowExisted);
    }

    function handler_claimAsActor(uint256 escrowIdSeed, uint256 amountSeed, uint256 beneficiarySeed) public {
        _beforeEscrowAuth();

        uint256 maxId = escrowManager.nextEscrowId() + 2;
        uint256 escrowId = maxId == 0 ? 0 : escrowIdSeed % (maxId + 1);
        bool escrowExisted = _getEscrowModuleType(escrowId) != bytes32(0);

        address caller = _pickUnauthorizedCaller();
        address beneficiary = users[beneficiarySeed % users.length];

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.claim.selector, escrowId, amountSeed, beneficiary),
            caller
        );

        withdrawOrClaimAsActorPostconditions(success, returnData, escrowExisted);
    }

    /*//////////////////////////////////////////////////////////////
                                sweep
    //////////////////////////////////////////////////////////////*/

    /// @notice Exercises sweep's revert surface as admin. Surplus is effectively zero under this
    /// harness (createEscrow always matches reserved to balance exactly), so the success branch
    /// is only reachable if a prior admin transfer created surplus — which the harness does not
    /// set up. Revert-path coverage is the goal here.
    function handler_sweep(uint256 assetTypeSeed, uint256 tokenIdSeed, uint256 amountSeed, uint256 beneficiarySeed)
        public
    {
        EscrowAuthSweepParams memory params =
            sweepPreconditions(assetTypeSeed, tokenIdSeed, amountSeed, beneficiarySeed);
        _beforeEscrowAuth();

        uint256 preSurplus = _safeGetSweepableAmount(params.assetType, params.token, params.tokenId);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.sweep.selector,
                params.assetType,
                params.token,
                params.tokenId,
                params.amount,
                params.beneficiary
            ),
            address(this)
        );

        sweepPostconditions(success, returnData, params, preSurplus);
    }

    function handler_sweepUnauthorized(
        uint256 assetTypeSeed,
        uint256 tokenIdSeed,
        uint256 amountSeed,
        uint256 beneficiarySeed
    ) public setCurrentActor {
        EscrowAuthSweepParams memory params =
            sweepPreconditions(assetTypeSeed, tokenIdSeed, amountSeed, beneficiarySeed);
        _beforeEscrowAuth();

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.sweep.selector,
                params.assetType,
                params.token,
                params.tokenId,
                params.amount,
                params.beneficiary
            ),
            currentActor
        );

        adminUnauthorizedPostconditions(success, returnData);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getEscrowModuleType(uint256 escrowId) internal view returns (bytes32 moduleType) {
        Escrow memory escrow = escrowManager.getEscrow(escrowId);
        moduleType = escrow.moduleType;
    }

    /// @dev Wraps getSweepableAmount in a staticcall so pre-snapshot surveys never revert for
    /// invalid (assetType, tokenId) combinations — those combinations still need to be observed
    /// to assert the selector mapping later.
    function _safeGetSweepableAmount(AssetType assetType, address tokenAddr, uint256 tokenId)
        internal
        view
        returns (uint256 surplus)
    {
        (bool ok, bytes memory data) = address(escrowManager)
            .staticcall(
                abi.encodeWithSelector(escrowManager.getSweepableAmount.selector, assetType, tokenAddr, tokenId)
            );
        if (ok && data.length > 31) {
            surplus = abi.decode(data, (uint256));
        }
    }
}

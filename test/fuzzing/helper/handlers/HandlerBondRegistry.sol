// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Errors} from "src/libs/Errors.sol";
import {Bond, BondInput, BurnKind, CouponRateType} from "src/registry/BondStructs.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {PreconditionsBondRegistry} from "../preconditions/PreconditionsBondRegistry.sol";
import {PostconditionsBondRegistry} from "../postconditions/PostconditionsBondRegistry.sol";

/// @title HandlerBondRegistry
/// @notice Stateful fuzz handlers for the BondRegistry vertical slice.
abstract contract HandlerBondRegistry is PreconditionsBondRegistry, PostconditionsBondRegistry {
    /// @notice Attempts to publish a successor version of the tracked bond.
    /// @dev On success the new version is added to the bounded tracked bond
    /// version set so later fuzz actions can discover and reuse it.
    /// @param maxSupplySeed Seed used to derive the successor max supply.
    function handler_publishBond(uint256 maxSupplySeed) public {
        PublishSuccessorParams memory params = publishSuccessorPreconditions(maxSupplySeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.publishBond.selector, params.input),
            address(this)
        );

        uint8 newVersion;
        if (success) {
            newVersion = _getLatestBondVersion();
            _trackBondVersion(newVersion);
        }

        publishSuccessorPostconditions(success, returnData, newVersion, params);
    }

    /// @notice Attempts to publish a successor while the active version is not Issued.
    /// @param maxSupplySeed Seed used to derive the attempted successor max supply.
    function handler_publishBondActiveVersionNotIssuable(uint256 maxSupplySeed) public {
        PublishSuccessorParams memory params = publishBondActiveVersionNotIssuablePreconditions(maxSupplySeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.publishBond.selector, params.input),
            address(this)
        );

        publishBondActiveVersionNotIssuablePostconditions(success, returnData);
    }

    /// @notice Attempts to publish a second successor while one is already Published.
    /// @param maxSupplySeed Seed used to derive the attempted successor max supply.
    function handler_publishBondSuccessorAlreadyPublished(uint256 maxSupplySeed) public {
        PublishSuccessorParams memory params = publishBondSuccessorAlreadyPublishedPreconditions(maxSupplySeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.publishBond.selector, params.input),
            address(this)
        );

        publishBondSuccessorAlreadyPublishedPostconditions(success, returnData);
    }

    /// @notice Attempts to amend a tracked bond that is still in Published status.
    /// @param versionSeed Seed used to pick a tracked Published version.
    /// @param maxSupplySeed Seed used to derive the new max supply.
    function handler_updatePublishedBond(uint256 versionSeed, uint256 maxSupplySeed) public {
        UpdatePublishedParams memory params = updatePublishedPreconditions(versionSeed, maxSupplySeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.updatePublishedBond.selector, params.input, params.version),
            address(this)
        );

        updatePublishedPostconditions(success, returnData, params);
    }

    /// @notice Attempts to amend a version whose lifecycle status is not Published.
    /// @param versionSeed Seed used to pick a tracked non-Published version.
    /// @param maxSupplySeed Seed used to derive the attempted new max supply.
    function handler_updatePublishedBondInvalidStatus(uint256 versionSeed, uint256 maxSupplySeed) public {
        UpdatePublishedParams memory params = updatePublishedInvalidStatusPreconditions(versionSeed, maxSupplySeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.updatePublishedBond.selector, params.input, params.version),
            address(this)
        );

        updatePublishedInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts to issue a new tranche under a tracked issuable version.
    /// @dev Issues from the bond issuer so the issuer-authorized issuance path
    /// is exercised. The token is minted to the issuer by the registry.
    /// @param versionSeed Seed used to pick a tracked issuable version.
    /// @param amountSeed Seed used to derive the issued amount.
    function handler_issueBond(uint256 versionSeed, uint256 amountSeed) public {
        IssueParams memory params = issueBondPreconditions(versionSeed, amountSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        address[] memory actorsToUpdate = _singleActorArray(bondIssuer);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Attempts to issue a new tranche through the PUBLISHER-authorized path.
    /// @param versionSeed Seed used to pick a tracked issuable version.
    /// @param amountSeed Seed used to derive the issued amount.
    function handler_issueBondPublisher(uint256 versionSeed, uint256 amountSeed) public {
        IssueParams memory params = issueBondPreconditions(versionSeed, amountSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        address[] memory actorsToUpdate = _singleActorArray(bondIssuer);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            address(this)
        );

        issueBondPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Attempts first issuance of a published successor while the previous active version is suspended.
    /// @dev This state must revert because successor cutover may only replace an Issued active version.
    /// @param versionSeed Seed used to pick a tracked published successor version.
    /// @param amountSeed Seed used to derive the attempted issued amount.
    function handler_issueBondSuccessorSuspendedPrevious(uint256 versionSeed, uint256 amountSeed) public {
        IssueParams memory params = issueBondSuccessorSuspendedPreviousPreconditions(versionSeed, amountSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondSuccessorSuspendedPreviousPostconditions(success, returnData);
    }

    /// @notice Attempts to issue from a caller that is neither publisher nor bond issuer.
    /// @param versionSeed Seed used to pick a tracked issuable version.
    /// @param amountSeed Seed used to derive the issued amount.
    /// @param callerSeed Seed used to pick an unauthorized caller.
    function handler_issueBondUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed) public {
        (IssueParams memory params, address caller) =
            issueBondUnauthorizedPreconditions(versionSeed, amountSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            caller
        );

        issueBondUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts to issue after issuance was permanently closed.
    /// @param versionSeed Seed used to pick a tracked issuance-closed version.
    function handler_issueBondClosed(uint256 versionSeed) public {
        IssueParams memory params = issueBondClosedPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondClosedPostconditions(success, returnData);
    }

    /// @notice Attempts to issue zero tokens under an otherwise issuable version.
    /// @param versionSeed Seed used to pick a tracked issuable version.
    function handler_issueBondZeroAmount(uint256 versionSeed) public {
        IssueParams memory params = issueBondZeroAmountPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondZeroAmountPostconditions(success, returnData);
    }

    /// @notice Attempts to issue more than the version's remaining issuable supply.
    /// @param versionSeed Seed used to pick a tracked issuable version.
    function handler_issueBondMaxSupplyExceeded(uint256 versionSeed) public {
        IssueParams memory params = issueBondMaxSupplyExceededPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondMaxSupplyExceededPostconditions(success, returnData);
    }

    /// @notice Attempts issuance after the bond version has expired.
    /// @param versionSeed Seed used to pick a tracked expired version.
    function handler_issueBondMaturityExpired(uint256 versionSeed) public {
        IssueParams memory params = issueBondMaturityExpiredPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, params.version, params.amount),
            bondIssuer
        );

        issueBondMaturityExpiredPostconditions(success, returnData);
    }

    /// @notice Attempts to permanently block future issuance for a tracked version.
    /// @param versionSeed Seed used to pick a tracked version with open issuance.
    function handler_closeIssuance(uint256 versionSeed) public {
        VersionParams memory params = closeIssuancePreconditions(versionSeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeIssuance.selector, BOND_ISIN, params.version),
            address(this)
        );

        closeIssuancePostconditions(success, returnData, params.version);
    }

    /// @notice Attempts to permanently block future issuance through the issuer-authorized path.
    /// @param versionSeed Seed used to pick a tracked version with open issuance.
    function handler_closeIssuanceIssuer(uint256 versionSeed) public {
        VersionParams memory params = closeIssuancePreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(params.version).issuer;
        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeIssuance.selector, BOND_ISIN, params.version),
            bondIssuer
        );

        closeIssuancePostconditions(success, returnData, params.version);
    }

    /// @notice Attempts to close issuance from a status that disallows the action.
    /// @param versionSeed Seed used to pick a tracked invalid-status version.
    function handler_closeIssuanceInvalidStatus(uint256 versionSeed) public {
        uint8 version = closeIssuanceInvalidStatusPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeIssuance.selector, BOND_ISIN, version),
            address(this)
        );

        closeIssuanceInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts to close issuance from a caller that is neither publisher nor bond issuer.
    /// @param versionSeed Seed used to pick a tracked version with open issuance.
    /// @param callerSeed Seed used to pick an unauthorized caller.
    function handler_closeIssuanceUnauthorized(uint256 versionSeed, uint256 callerSeed) public {
        (uint8 version, address caller) = closeIssuanceUnauthorizedPreconditions(versionSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeIssuance.selector, BOND_ISIN, version),
            caller
        );

        closeIssuanceUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts to close issuance twice on a tracked version.
    /// @param versionSeed Seed used to pick a tracked version with already-closed issuance.
    function handler_closeIssuanceAlreadyClosed(uint256 versionSeed) public {
        uint8 version = closeIssuanceAlreadyClosedPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeIssuance.selector, BOND_ISIN, version),
            bondIssuer
        );

        closeIssuanceAlreadyClosedPostconditions(success, returnData);
    }

    /// @notice Attempts to cancel the latest tracked Published version when it has no tranches yet.
    function handler_cancelBond() public {
        VersionParams memory params = cancelBondPreconditions();

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.cancelBond.selector, BOND_ISIN, params.version),
            address(this)
        );

        cancelBondPostconditions(success, returnData, params.version);
    }

    /// @notice Attempts to suspend a tracked Issued version.
    /// @param versionSeed Seed used to pick a tracked Issued version.
    function handler_suspendBond(uint256 versionSeed) public {
        VersionParams memory params = suspendBondPreconditions(versionSeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.suspendBond.selector, BOND_ISIN, params.version),
            address(this)
        );

        suspendBondPostconditions(success, returnData, params.version);
    }

    /// @notice Attempts to unsuspend a tracked Suspended version.
    /// @param versionSeed Seed used to pick a tracked Suspended version.
    function handler_unsuspendBond(uint256 versionSeed) public {
        VersionParams memory params = unsuspendBondPreconditions(versionSeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.unsuspendBond.selector, BOND_ISIN, params.version),
            address(this)
        );

        unsuspendBondPostconditions(success, returnData, params.version);
    }

    /// @notice Attempts to terminally close a tracked version once its token supply is zero.
    /// @param versionSeed Seed used to pick a tracked closeable version.
    function handler_closeBond(uint256 versionSeed) public {
        VersionParams memory params = closeBondPreconditions(versionSeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeBond.selector, BOND_ISIN, params.version),
            address(this)
        );

        closeBondPostconditions(success, returnData, params.version);
    }

    /// @notice Rotates the issuer for a tracked Published, Issued, Suspended, or Replaced version.
    /// @dev The precondition prefers Replaced versions when reachable so the issuer-recovery
    /// path for superseded versions remains dense in fuzz campaigns.
    /// @param versionSeed Seed used to pick a tracked issuer-rotatable version.
    /// @param issuerSeed Seed used to pick an enabled replacement issuer.
    function handler_rotateIssuer(uint256 versionSeed, uint256 issuerSeed) public {
        RotateIssuerParams memory params = rotateIssuerPreconditions(versionSeed, issuerSeed);

        _beforeBondAccounts(params.version, _twoActorArray(params.oldIssuer, params.newIssuer));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.rotateIssuer.selector,
                BOND_ISIN,
                params.version,
                params.newIssuer,
                keccak256("FUZZ_ISSUER_RECOVERY")
            ),
            address(this)
        );

        rotateIssuerPostconditions(success, returnData, params);
    }

    /// @notice Attempts issuer rotation for a tracked Cancelled or Redeemed version.
    /// @param versionSeed Seed used to pick a tracked issuer-rotation-invalid version.
    /// @param issuerSeed Seed used to pick an enabled replacement issuer.
    function handler_rotateIssuerInvalidStatus(uint256 versionSeed, uint256 issuerSeed) public {
        RotateIssuerParams memory params = rotateIssuerInvalidStatusPreconditions(versionSeed, issuerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.rotateIssuer.selector,
                BOND_ISIN,
                params.version,
                params.newIssuer,
                keccak256("FUZZ_ISSUER_RECOVERY")
            ),
            address(this)
        );

        rotateIssuerInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts an ISSUER_RECLAIM burn against a tracked Issued version.
    /// @dev Prank uses the bond issuer so the issuer-authorized reclaim path is
    /// exercised. Harness-local accounting records the burned amount so supply
    /// invariants can be expressed as equalities.
    /// @param versionSeed Seed used to pick a tracked reclaimable version.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burnBondReclaim(uint256 versionSeed, uint256 amountSeed) public {
        BurnParams memory params = burnReclaimPreconditions(versionSeed, amountSeed);

        _beforeBondAccounts(params.version, _singleActorArray(params.from));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.ISSUER_RECLAIM
            ),
            params.from
        );

        if (success) burnedReclaimed[params.version] += params.amount;

        burnReclaimPostconditions(success, returnData, params);
    }

    /// @notice Attempts an ISSUER_RECLAIM batch burn against a tracked Issued version.
    /// @param versionSeed Seed used to pick a tracked reclaimable version.
    /// @param amountSeed Seed used to derive the total burned amount and split.
    function handler_burnBondBatchReclaim(uint256 versionSeed, uint256 amountSeed) public {
        BatchBurnParams memory params = burnBatchReclaimPreconditions(versionSeed, amountSeed);

        _beforeBondAccounts(params.version, params.froms);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBondBatch.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.froms,
                params.amounts,
                BurnKind.ISSUER_RECLAIM
            ),
            params.froms[0]
        );

        if (success) burnedReclaimed[params.version] += params.totalAmount;

        burnBatchReclaimPostconditions(success, returnData, params);
    }

    /// @notice Attempts an ISSUER_RECLAIM burn that includes frozen issuer inventory.
    /// @dev The handler first freezes part of the issuer's free balance, then attempts
    /// a reclaim amount above the remaining free balance. The burn must revert before
    /// token accounting can release frozen balances.
    /// @param versionSeed Seed used to pick a tracked reclaimable version.
    /// @param freezeAmountSeed Seed used to derive the amount frozen before the burn.
    /// @param amountSeed Seed used to derive how much frozen inventory the burn attempts to include.
    function handler_burnBondReclaimFrozenIssuer(uint256 versionSeed, uint256 freezeAmountSeed, uint256 amountSeed)
        public
    {
        FrozenIssuerReclaimParams memory params =
            burnReclaimFrozenIssuerPreconditions(versionSeed, freezeAmountSeed, amountSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.ISSUER_RECLAIM
            ),
            params.from
        );

        burnReclaimFrozenIssuerPostconditions(success, returnData);
    }

    /// @notice Attempts to issue a tranche on a version whose status disallows issuance.
    /// @dev Picks a version with status outside `{Published, Issued}` so the call must
    /// revert with `BondRegistry__InvalidBondStatus`. Uses the bond issuer as caller so
    /// the auth check (which runs after the status check) does not preempt the assertion.
    /// @param versionSeed Seed used to pick a tracked non-issuable version.
    function handler_issueBondInvalidStatus(uint256 versionSeed) public {
        uint8 version = issueBondInvalidStatusPreconditions(versionSeed);

        address bondIssuer = _getBondAtVersion(version).issuer;
        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.issueBond.selector, BOND_ISIN, version, 1),
            bondIssuer
        );

        issueBondInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts to cancel a version that is no longer cancellable.
    /// @dev Picks a version that is either not Published or already has at least one
    /// tranche so the call must revert with `InvalidBondStatus` or `BondAlreadyIssued`.
    /// @param versionSeed Seed used to pick a tracked non-cancellable version.
    function handler_cancelBondInvalid(uint256 versionSeed) public {
        uint8 version = cancelBondInvalidPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.cancelBond.selector, BOND_ISIN, version),
            address(this)
        );

        cancelBondInvalidPostconditions(success, returnData);
    }

    /// @notice Attempts to suspend a version whose status is not Issued.
    /// @param versionSeed Seed used to pick a tracked non-Issued version.
    function handler_suspendBondInvalidStatus(uint256 versionSeed) public {
        uint8 version = suspendBondInvalidStatusPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.suspendBond.selector, BOND_ISIN, version),
            address(this)
        );

        suspendBondInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts to unsuspend a version whose status is not Suspended.
    /// @param versionSeed Seed used to pick a tracked non-Suspended version.
    function handler_unsuspendBondInvalidStatus(uint256 versionSeed) public {
        uint8 version = unsuspendBondInvalidStatusPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.unsuspendBond.selector, BOND_ISIN, version),
            address(this)
        );

        unsuspendBondInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts to close a version that is not closeable.
    /// @dev Either the status is not in `{Issued, Suspended}` or the token still has a
    /// non-zero supply. Both cases must revert.
    /// @param versionSeed Seed used to pick a tracked non-closeable version.
    function handler_closeBondInvalid(uint256 versionSeed) public {
        uint8 version = closeBondInvalidPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.closeBond.selector, BOND_ISIN, version),
            address(this)
        );

        closeBondInvalidPostconditions(success, returnData);
    }

    /// @notice Attempts an ISSUER_RECLAIM burn from a caller that is not the bond issuer.
    /// @dev Status is held to Issued and `from` is the issuer so the only failure mode
    /// is the unauthorized caller check. Caller comes from the broker pool minus the
    /// issuer wallet.
    /// @param versionSeed Seed used to pick a tracked Issued version.
    /// @param amountSeed Seed used to derive the attempted burn amount.
    /// @param callerSeed Seed used to pick the unauthorized caller from `USERS`.
    function handler_burnBondReclaimUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed) public {
        (BurnParams memory params, address caller) =
            burnReclaimUnauthorizedPreconditions(versionSeed, amountSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.ISSUER_RECLAIM
            ),
            caller
        );

        burnUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts a FINAL_SETTLEMENT burn from a caller that has neither the
    /// issuer role nor the BURNER role.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param amountSeed Seed used to derive the attempted burn amount.
    /// @param callerSeed Seed used to pick the unauthorized caller from `USERS`.
    function handler_burnBondSettlementUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed)
        public
    {
        (BurnParams memory params, address caller) =
            burnSettlementUnauthorizedPreconditions(versionSeed, amountSeed, callerSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.FINAL_SETTLEMENT
            ),
            caller
        );

        burnUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts a FINAL_SETTLEMENT burn from a BURNER caller that is not enabled.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param amountSeed Seed used to derive the attempted burn amount.
    function handler_burnBondSettlementBurnerNotEnabled(uint256 versionSeed, uint256 amountSeed) public {
        (BurnParams memory params, address caller) =
            burnSettlementBurnerNotEnabledPreconditions(versionSeed, amountSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.FINAL_SETTLEMENT
            ),
            caller
        );

        burnUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts a burn from a source address disallowed for the selected burn kind.
    /// @param versionSeed Seed used to pick a version with a burn-compatible status.
    /// @param kindSeed Seed used to select ISSUER_RECLAIM or FINAL_SETTLEMENT.
    /// @param fromSeed Seed used to pick an invalid source address.
    function handler_burnBondInvalidSource(uint256 versionSeed, uint256 kindSeed, uint256 fromSeed) public {
        BurnAuthorizationParams memory params = burnInvalidSourcePreconditions(versionSeed, kindSeed, fromSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                params.kind
            ),
            params.caller
        );

        burnInvalidSourcePostconditions(success, returnData);
    }

    /// @notice Attempts a burn kind from a lifecycle status that disallows it.
    /// @param versionSeed Seed used to pick a tracked invalid-status version.
    /// @param kindSeed Seed used to select ISSUER_RECLAIM or FINAL_SETTLEMENT.
    function handler_burnBondInvalidStatus(uint256 versionSeed, uint256 kindSeed) public {
        BurnAuthorizationParams memory params = burnInvalidStatusPreconditions(versionSeed, kindSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                params.kind
            ),
            params.caller
        );

        burnInvalidStatusPostconditions(success, returnData);
    }

    /// @notice Attempts a batch burn with mismatched `froms` and `amounts` lengths.
    /// @param versionSeed Seed used to pick an existing tracked version.
    function handler_burnBondBatchLengthMismatch(uint256 versionSeed) public {
        BatchBurnParams memory params = burnBatchLengthMismatchPreconditions(versionSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBondBatch.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.froms,
                params.amounts,
                BurnKind.ISSUER_RECLAIM
            ),
            params.froms[0]
        );

        burnBatchLengthMismatchPostconditions(success, returnData);
    }

    /// @notice Attempts a batch ISSUER_RECLAIM burn with an invalid source in the loop.
    /// @param versionSeed Seed used to pick a tracked Issued version.
    /// @param fromSeed Seed used to pick an invalid source address.
    function handler_burnBondBatchInvalidSource(uint256 versionSeed, uint256 fromSeed) public {
        BatchBurnParams memory params = burnBatchInvalidSourcePreconditions(versionSeed, fromSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBondBatch.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.froms,
                params.amounts,
                BurnKind.ISSUER_RECLAIM
            ),
            params.froms[0]
        );

        burnBatchInvalidSourcePostconditions(success, returnData);
    }

    /// @notice Attempts a FINAL_SETTLEMENT burn against a tracked Issued or Replaced version.
    /// @dev Prank uses the harness admin so the BURNER-role path is exercised.
    /// Tokens are pulled from the bond issuer wallet; non-issuer source burns are
    /// exercised by `handler_burnBondSettlementHolder`.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burnBondSettlement(uint256 versionSeed, uint256 amountSeed) public {
        BurnParams memory params = burnSettlementPreconditions(versionSeed, amountSeed);

        _beforeBondAccounts(params.version, _singleActorArray(params.from));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.FINAL_SETTLEMENT
            ),
            address(this)
        );

        if (success) burnedSettled[params.version] += params.amount;

        burnSettlementPostconditions(success, returnData, params);
    }

    /// @notice Attempts a FINAL_SETTLEMENT burn through the issuer-authorized path.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burnBondSettlementIssuer(uint256 versionSeed, uint256 amountSeed) public {
        BurnParams memory params = burnSettlementPreconditions(versionSeed, amountSeed);

        _beforeBondAccounts(params.version, _singleActorArray(params.from));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.FINAL_SETTLEMENT
            ),
            params.from
        );

        if (success) burnedSettled[params.version] += params.amount;

        burnSettlementPostconditions(success, returnData, params);
    }

    /// @notice Attempts a FINAL_SETTLEMENT burn against a non-issuer holder/source.
    /// @dev Prank uses the harness admin so the BURNER-role path can burn broker-held,
    /// escrow-held, or protocol-held balances.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param holderSeed Seed used to pick a non-issuer holder/source with a balance.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burnBondSettlementHolder(uint256 versionSeed, uint256 holderSeed, uint256 amountSeed) public {
        BurnParams memory params = burnSettlementHolderPreconditions(versionSeed, holderSeed, amountSeed);

        _beforeBondAccounts(params.version, _singleActorArray(params.from));

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBond.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.from,
                params.amount,
                BurnKind.FINAL_SETTLEMENT
            ),
            address(this)
        );

        if (success) burnedSettled[params.version] += params.amount;

        burnSettlementPostconditions(success, returnData, params);
    }

    /// @notice Attempts a FINAL_SETTLEMENT batch burn against a tracked Issued or Replaced version.
    /// @param versionSeed Seed used to pick a tracked settlement-burnable version.
    /// @param amountSeed Seed used to derive the total burned amount and split.
    function handler_burnBondBatchSettlement(uint256 versionSeed, uint256 amountSeed) public {
        BatchBurnParams memory params = burnBatchSettlementPreconditions(versionSeed, amountSeed);

        _beforeBondAccounts(params.version, params.froms);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(
                bondRegistry.burnBondBatch.selector,
                BOND_ISIN_BYTES12,
                params.version,
                params.froms,
                params.amounts,
                BurnKind.FINAL_SETTLEMENT
            ),
            address(this)
        );

        if (success) burnedSettled[params.version] += params.totalAmount;

        burnBatchSettlementPostconditions(success, returnData, params);
    }

    /// @notice Exercises the BondRegistry getter surface for tracked versions.
    /// @param versionSeed Seed used to pick a tracked version with at least one tranche.
    /// @param trancheSeed Seed used to select a valid tranche id.
    /// @param intervalSeed Seed used to select coupon lookup intervals.
    function handler_bondRegistryViewSurface(uint256 versionSeed, uint256 trancheSeed, uint256 intervalSeed) public {
        BondRegistryViewSurfaceParams memory params =
            bondRegistryViewSurfacePreconditions(versionSeed, trancheSeed, intervalSeed);

        _expectBondRegistryViewCall(abi.encodeWithSignature("bondStatus(string)", BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSignature("bondStatus(bytes12)", BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSignature("getBond(string)", BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSignature("getBond(bytes12)", BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getBondAtVersion.selector, BOND_ISIN_BYTES12, params.version)
        );
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getBondByTokenId.selector, params.tokenId));

        (bool seriesSuccess, bytes memory seriesReturnData) =
            _callBondRegistryView(abi.encodeWithSelector(bondRegistry.getBondSeriesByTokenId.selector, params.tokenId));

        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getToken.selector));
        _expectBondRegistryViewCall(
            abi.encodeWithSignature("getTranche(bytes12,uint16)", BOND_ISIN_BYTES12, params.activeTrancheId)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSignature(
                "getTranche(bytes12,uint8,uint16)", BOND_ISIN_BYTES12, params.version, params.trancheId
            )
        );
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getLatestTranche.selector, BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getTrancheCount.selector, BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSignature("getTranche(bytes12)", BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSignature("getTranche(string)", BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getTokenId.selector, BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getAllCouponRates.selector, BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getCouponRatesLength.selector, BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getCouponRateAt.selector, BOND_ISIN, 0));
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCouponRateAt.selector, BOND_ISIN, params.couponRateIndex)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRate.selector, BOND_ISIN_BYTES12)
        );
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getLatestCouponRate.selector, BOND_ISIN));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getActiveVersion.selector, BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getLatestVersion.selector, BOND_ISIN_BYTES12));
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.isCurrencyAllowed.selector, BOND_CURRENCY));
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.supportsInterface.selector, type(IBondRegistry).interfaceId)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.supportsInterface.selector, type(IERC165).interfaceId)
        );
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.supportsInterface.selector, bytes4(0xffffffff)));
        _expectBondRegistryViewCall(abi.encodeWithSignature("INITIAL_VERSION()"));
        _expectBondRegistryViewCall(abi.encodeWithSignature("MAX_PROBABILITY_BPS()"));
        _expectCurrentCouponSurface();

        bondRegistryViewSurfacePostconditions(seriesSuccess, seriesReturnData, params);
    }

    /// @notice Publishes an independent zero-coupon bond once and exercises zero-coupon getters.
    /// @param maxSupplySeed Seed used to derive the zero-coupon bond supply.
    function handler_publishIndependentZeroCouponBond(uint256 maxSupplySeed) public {
        if (bondRegistry.getLatestVersion(BOND_ZERO_COUPON_ISIN_BYTES12) == 0) {
            BondInput memory input = _buildZeroCouponBondInput(BOND_ZERO_COUPON_ISIN, address(this), maxSupplySeed);

            _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

            (bool success, bytes memory returnData) = fl.doFunctionCall(
                address(bondRegistry), abi.encodeWithSelector(bondRegistry.publishBond.selector, input), address(this)
            );

            publishIndependentBondPostconditions(success, returnData);
        }

        _expectBondRegistryViewCall(abi.encodeWithSignature("getBond(string)", BOND_ZERO_COUPON_ISIN));
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getLatestCouponRate.selector, BOND_ZERO_COUPON_ISIN)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCouponRatesLength.selector, BOND_ZERO_COUPON_ISIN)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCouponRateAt.selector, BOND_ZERO_COUPON_ISIN, 0)
        );
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRate.selector, BOND_ZERO_COUPON_ISIN_BYTES12)
        );
    }

    /// @notice Appends a valid scoring record and checks scoring getters.
    /// @param walletSeed Seed used to pick a scored wallet.
    /// @param scoringSeed Seed used to derive scoring fields.
    function handler_appendScoring(uint256 walletSeed, uint256 scoringSeed) public {
        AppendScoringParams memory params = appendScoringPreconditions(walletSeed, scoringSeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.appendScoring.selector, params.wallet, params.scoring),
            address(this)
        );

        appendScoringPostconditions(success, returnData, params);
    }

    /// @notice Attempts invalid scoring appends to cover scoring validation selectors.
    /// @param caseSeed Seed used to select the invalid scoring case.
    /// @param scoringSeed Seed used to derive the base scoring fields.
    function handler_appendScoringInvalid(uint256 caseSeed, uint256 scoringSeed) public {
        InvalidScoringParams memory params = appendScoringInvalidPreconditions(caseSeed, scoringSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.appendScoring.selector, params.wallet, params.scoring),
            address(this)
        );

        appendScoringInvalidPostconditions(success, returnData, params.expectedError);
    }

    /// @notice Exercises scoring getter revert paths.
    /// @param scoringIdSeed Seed used to select an invalid scoring id.
    function handler_scoringInvalidQueries(uint256 scoringIdSeed) public {
        uint256 invalidScoringId = (scoringIdSeed % type(uint128).max) + 1;

        (bool latestSuccess, bytes memory latestReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.getLatestScoring.selector, FUZZ_WALLET_8),
            address(this)
        );
        scoringInvalidQueryPostconditions(
            latestSuccess, latestReturnData, Errors.BondRegistry__ScoringNotFound.selector
        );

        (bool atSuccess, bytes memory atReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.getScoringAt.selector, FUZZ_WALLET_8, invalidScoringId),
            address(this)
        );
        scoringInvalidQueryPostconditions(atSuccess, atReturnData, Errors.BondRegistry__InvalidScoringId.selector);
    }

    /// @notice Exercises owner/admin-only helpers on their positive path.
    /// @param roleSeed Seed used to select a valid role for the array grant overload.
    function handler_bondRegistryAdminSurface(uint256 roleSeed) public {
        address[] memory grantees = new address[](2);
        grantees[0] = FUZZ_WALLET_4;
        grantees[1] = FUZZ_WALLET_5;

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool grantSuccess, bytes memory grantReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSignature("grantRoles(address[],uint256)", grantees, _pickBondRole(roleSeed)),
            address(this)
        );
        bondRegistryAdminSuccessPostconditions(grantSuccess, grantReturnData);

        uint256 role = _pickBondRole(roleSeed);
        (bool revokeSuccess, bytes memory revokeReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSignature("revokeRoles(address,uint256)", FUZZ_WALLET_4, role),
            address(this)
        );
        bondRegistryAdminSuccessPostconditions(revokeSuccess, revokeReturnData);

        (bool revokeBatchSuccess, bytes memory revokeBatchReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSignature("revokeRoles(address[],uint256)", grantees, role),
            address(this)
        );
        bondRegistryAdminSuccessPostconditions(revokeBatchSuccess, revokeBatchReturnData);
    }

    /// @notice Attempts to grant an out-of-range role bit.
    function handler_bondRegistryGrantInvalidRole() public {
        (bool invalidRoleSuccess, bytes memory invalidRoleReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSignature("grantRoles(address,uint256)", FUZZ_WALLET_6, bondRegistry.ALL_BR_ROLES() << 1),
            address(this)
        );
        bondRegistryExpectedRevertPostconditions(
            invalidRoleSuccess, invalidRoleReturnData, bytes4(keccak256("InvalidRoles()"))
        );
    }

    /// @notice Attempts to reset the locked multi-token address.
    function handler_bondRegistrySetMultiTokenLocked() public {
        (bool lockedTokenSuccess, bytes memory lockedTokenReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.setMultiToken.selector, address(token)),
            address(this)
        );
        bondRegistryExpectedRevertPostconditions(
            lockedTokenSuccess, lockedTokenReturnData, bytes4(keccak256("BondRegistry__MultiTokenLocked()"))
        );
    }

    /// @notice Attempts to initialize the already-initialized BondRegistry.
    function handler_bondRegistryInitializeAgain() public {
        (bool initSuccess, bytes memory initReturnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.initialize.selector, address(this)),
            address(this)
        );
        bondRegistryExpectedRevertPostconditions(
            initSuccess, initReturnData, bytes4(keccak256("InvalidInitialization()"))
        );
    }

    /// @notice Attempts publishBond with invalid input shapes and expects validation reverts.
    /// @param caseSeed Seed used to select the invalid input case.
    /// @param maxSupplySeed Seed used to derive otherwise valid bond input fields.
    function handler_publishBondInvalidInput(uint256 caseSeed, uint256 maxSupplySeed) public {
        InvalidBondInputParams memory params = publishBondInvalidInputPreconditions(caseSeed, maxSupplySeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(bondRegistry),
            abi.encodeWithSelector(bondRegistry.publishBond.selector, params.input),
            address(this)
        );

        publishBondInvalidInputPostconditions(success, returnData, params.expectedError);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _expectBondRegistryViewCall(bytes memory callData) private {
        _callBondRegistryView(callData);
    }

    function _callBondRegistryView(bytes memory callData) private returns (bool success, bytes memory returnData) {
        (success, returnData) = fl.doFunctionCall(address(bondRegistry), callData, address(this));
        bondRegistryViewPostconditions(success, returnData);
    }

    function _expectCurrentCouponSurface() private {
        Bond memory bond = bondRegistry.getBond(BOND_ISIN_BYTES12);
        _expectBondRegistryViewCall(abi.encodeWithSelector(bondRegistry.getCurrentCouponRateForBond.selector, bond));

        Bond memory zeroCouponBond = bond;
        zeroCouponBond.couponRateType = CouponRateType.ZERO_COUPON;
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRateForBond.selector, zeroCouponBond)
        );

        Bond memory unissuedBond = bond;
        unissuedBond.trancheCount = 0;
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRateForBond.selector, unissuedBond)
        );

        Bond memory noIssueDateBond = bond;
        noIssueDateBond.tokenId = 0;
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRateForBond.selector, noIssueDateBond)
        );

        Bond memory maturedBond = bond;
        maturedBond.maturityDate = block.timestamp;
        _expectBondRegistryViewCall(
            abi.encodeWithSelector(bondRegistry.getCurrentCouponRateForBond.selector, maturedBond)
        );
    }

    function _pickBondRole(uint256 roleSeed) internal view returns (uint256) {
        uint256 idx = roleSeed % 9;
        if (idx == 0) return bondRegistry.PUBLISHER();
        if (idx == 1) return bondRegistry.CANCEL();
        if (idx == 2) return bondRegistry.CLOSE();
        if (idx == 3) return bondRegistry.CURRENCY();
        if (idx == 4) return bondRegistry.SUSPEND();
        if (idx == 5) return bondRegistry.UNSUSPEND();
        if (idx == 6) return bondRegistry.BURNER();
        if (idx == 7) return bondRegistry.SCORING();
        return bondRegistry.ISSUER_RECOVERY();
    }
}

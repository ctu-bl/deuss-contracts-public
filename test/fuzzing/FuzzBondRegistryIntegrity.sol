// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerBondRegistry} from "./helper/handlers/HandlerBondRegistry.sol";

/**
 * @title FuzzBondRegistryIntegrity
 * @notice Checks handler integrity for the BondRegistry fuzz harness
 */
contract FuzzBondRegistryIntegrity is HandlerBondRegistry, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_publishBond`
     * @param maxSupplySeed Seed used to derive the successor max supply
     */
    function fuzz_publishBond(uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_publishBond.selector, maxSupplySeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-PUBLISH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_publishBondActiveVersionNotIssuable`
     * @param maxSupplySeed Seed used to derive the attempted successor max supply
     */
    function fuzz_publishBondActiveVersionNotIssuable(uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_publishBondActiveVersionNotIssuable.selector, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-PUBLISH-ACTIVE-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_publishBondSuccessorAlreadyPublished`
     * @param maxSupplySeed Seed used to derive the attempted successor max supply
     */
    function fuzz_publishBondSuccessorAlreadyPublished(uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_publishBondSuccessorAlreadyPublished.selector, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-PUBLISH-SUCCESSOR-PUBLISHED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_updatePublishedBond`
     * @param versionSeed Seed used to pick a tracked Published version
     * @param maxSupplySeed Seed used to derive the new max supply
     */
    function fuzz_updatePublishedBond(uint256 versionSeed, uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_updatePublishedBond.selector, versionSeed, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-UPDATE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_updatePublishedBondInvalidStatus`
     * @param versionSeed Seed used to pick a tracked non-Published version
     * @param maxSupplySeed Seed used to derive the attempted new max supply
     */
    function fuzz_updatePublishedBondInvalidStatus(uint256 versionSeed, uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_updatePublishedBondInvalidStatus.selector, versionSeed, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-UPDATE-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_issueBond`
     * @param versionSeed Seed used to pick a tracked issuable version
     * @param amountSeed Seed used to derive the issued amount
     */
    function fuzz_issueBond(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBond.selector, versionSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_issueBondPublisher`
     * @param versionSeed Seed used to pick a tracked issuable version
     * @param amountSeed Seed used to derive the issued amount
     */
    function fuzz_issueBondPublisher(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondPublisher.selector, versionSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-PUBLISHER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_issueBondSuccessorSuspendedPrevious`
     * @param versionSeed Seed used to pick a tracked published successor version
     * @param amountSeed Seed used to derive the attempted issued amount
     */
    function fuzz_issueBondSuccessorSuspendedPrevious(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_issueBondSuccessorSuspendedPrevious.selector, versionSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-SUCCESSOR-SUSPENDED-PREVIOUS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_closeIssuance`
     * @param versionSeed Seed used to pick a tracked version with open issuance
     */
    function fuzz_closeIssuance(uint256 versionSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_closeIssuance.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-ISSUANCE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_closeIssuanceIssuer`
     * @param versionSeed Seed used to pick a tracked version with open issuance
     */
    function fuzz_closeIssuanceIssuer(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_closeIssuanceIssuer.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-ISSUANCE-ISSUER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelBond`
     */
    function fuzz_cancelBond() public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_cancelBond.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CANCEL");
        }
    }

    /**
     * @notice Checks the integrity of `handler_suspendBond`
     * @param versionSeed Seed used to pick a tracked Issued version
     */
    function fuzz_suspendBond(uint256 versionSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_suspendBond.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-SUSPEND");
        }
    }

    /**
     * @notice Checks the integrity of `handler_unsuspendBond`
     * @param versionSeed Seed used to pick a tracked Suspended version
     */
    function fuzz_unsuspendBond(uint256 versionSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_unsuspendBond.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-UNSUSPEND");
        }
    }

    /**
     * @notice Checks the integrity of `handler_closeBond`
     * @param versionSeed Seed used to pick a tracked closeable version
     */
    function fuzz_closeBond(uint256 versionSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_closeBond.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_rotateIssuer`
     * @param versionSeed Seed used to pick a tracked issuer-rotatable version
     * @param issuerSeed Seed used to pick an enabled replacement issuer
     */
    function fuzz_rotateIssuer(uint256 versionSeed, uint256 issuerSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_rotateIssuer.selector, versionSeed, issuerSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ROTATE-ISSUER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_rotateIssuerInvalidStatus`
     * @param versionSeed Seed used to pick a tracked issuer-rotation-invalid version
     * @param issuerSeed Seed used to pick an enabled replacement issuer
     */
    function fuzz_rotateIssuerInvalidStatus(uint256 versionSeed, uint256 issuerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_rotateIssuerInvalidStatus.selector, versionSeed, issuerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ROTATE-ISSUER-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondReclaim`
     * @param versionSeed Seed used to pick a tracked reclaimable version
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burnBondReclaim(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_burnBondReclaim.selector, versionSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-RECLAIM");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondSettlement`
     * @param versionSeed Seed used to pick a tracked settlement-burnable version
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burnBondSettlement(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_burnBondSettlement.selector, versionSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-SETTLEMENT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondSettlementIssuer`
     * @param versionSeed Seed used to pick a tracked settlement-burnable version
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burnBondSettlementIssuer(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondSettlementIssuer.selector, versionSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-SETTLEMENT-ISSUER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondSettlementHolder`
     * @param versionSeed Seed used to pick a tracked settlement-burnable version
     * @param holderSeed Seed used to pick a non-issuer holder/source
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burnBondSettlementHolder(uint256 versionSeed, uint256 holderSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondSettlementHolder.selector, versionSeed, holderSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-SETTLEMENT-HOLDER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_issueBondInvalidStatus`
     * @param versionSeed Seed used to pick a tracked non-issuable version
     */
    function fuzz_issueBondInvalidStatus(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondInvalidStatus.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_cancelBondInvalid`
     * @param versionSeed Seed used to pick a tracked non-cancellable version
     */
    function fuzz_cancelBondInvalid(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_cancelBondInvalid.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CANCEL-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_suspendBondInvalidStatus`
     * @param versionSeed Seed used to pick a tracked non-Issued version
     */
    function fuzz_suspendBondInvalidStatus(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_suspendBondInvalidStatus.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-SUSPEND-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_unsuspendBondInvalidStatus`
     * @param versionSeed Seed used to pick a tracked non-Suspended version
     */
    function fuzz_unsuspendBondInvalidStatus(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_unsuspendBondInvalidStatus.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-UNSUSPEND-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_closeBondInvalid`
     * @param versionSeed Seed used to pick a tracked non-closeable version
     */
    function fuzz_closeBondInvalid(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_closeBondInvalid.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-INVALID");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondReclaimUnauthorized`
     * @param versionSeed Seed used to pick a tracked Issued version
     * @param amountSeed Seed used to derive the attempted burn amount
     * @param callerSeed Seed used to pick an unauthorized caller
     */
    function fuzz_burnBondReclaimUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondReclaimUnauthorized.selector, versionSeed, amountSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-RECLAIM-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondSettlementUnauthorized`
     * @param versionSeed Seed used to pick a tracked settlement-burnable version
     * @param amountSeed Seed used to derive the attempted burn amount
     * @param callerSeed Seed used to pick an unauthorized caller
     */
    function fuzz_burnBondSettlementUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondSettlementUnauthorized.selector, versionSeed, amountSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-SETTLEMENT-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBondSettlementBurnerNotEnabled`
     * @param versionSeed Seed used to pick a tracked settlement-burnable version
     * @param amountSeed Seed used to derive the attempted burn amount
     */
    function fuzz_burnBondSettlementBurnerNotEnabled(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondSettlementBurnerNotEnabled.selector, versionSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-SETTLEMENT-BURNER-NOT-ENABLED");
        }
    }

    function fuzz_issueBondUnauthorized(uint256 versionSeed, uint256 amountSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_issueBondUnauthorized.selector, versionSeed, amountSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-UNAUTH");
        }
    }

    function fuzz_issueBondClosed(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondClosed.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-CLOSED");
        }
    }

    function fuzz_issueBondZeroAmount(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondZeroAmount.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-ZERO");
        }
    }

    function fuzz_issueBondMaxSupplyExceeded(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondMaxSupplyExceeded.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-MAX");
        }
    }

    function fuzz_issueBondMaturityExpired(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_issueBondMaturityExpired.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ISSUE-MATURITY");
        }
    }

    function fuzz_closeIssuanceInvalidStatus(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_closeIssuanceInvalidStatus.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-ISSUANCE-INVALID");
        }
    }

    function fuzz_closeIssuanceUnauthorized(uint256 versionSeed, uint256 callerSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_closeIssuanceUnauthorized.selector, versionSeed, callerSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-ISSUANCE-UNAUTH");
        }
    }

    function fuzz_closeIssuanceAlreadyClosed(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_closeIssuanceAlreadyClosed.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-CLOSE-ISSUANCE-CLOSED");
        }
    }

    function fuzz_burnBondInvalidSource(uint256 versionSeed, uint256 kindSeed, uint256 fromSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondInvalidSource.selector, versionSeed, kindSeed, fromSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-INVALID-SOURCE");
        }
    }

    function fuzz_burnBondInvalidStatus(uint256 versionSeed, uint256 kindSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_burnBondInvalidStatus.selector, versionSeed, kindSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-INVALID-STATUS");
        }
    }

    function fuzz_burnBondBatchReclaim(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_burnBondBatchReclaim.selector, versionSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-BATCH-RECLAIM");
        }
    }

    function fuzz_burnBondReclaimFrozenIssuer(uint256 versionSeed, uint256 freezeAmountSeed, uint256 amountSeed)
        public
    {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondReclaimFrozenIssuer.selector, versionSeed, freezeAmountSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-RECLAIM-FROZEN");
        }
    }

    function fuzz_burnBondBatchSettlement(uint256 versionSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondBatchSettlement.selector, versionSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-BATCH-SETTLEMENT");
        }
    }

    function fuzz_burnBondBatchLengthMismatch(uint256 versionSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_burnBondBatchLengthMismatch.selector, versionSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-BATCH-LENGTH");
        }
    }

    function fuzz_burnBondBatchInvalidSource(uint256 versionSeed, uint256 fromSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_burnBondBatchInvalidSource.selector, versionSeed, fromSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-BURN-BATCH-SOURCE");
        }
    }

    function fuzz_bondRegistryViewSurface(uint256 versionSeed, uint256 trancheSeed, uint256 intervalSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_bondRegistryViewSurface.selector, versionSeed, trancheSeed, intervalSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-VIEWS");
        }
    }

    function fuzz_publishIndependentZeroCouponBond(uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_publishIndependentZeroCouponBond.selector, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-PUBLISH-ZERO-COUPON");
        }
    }

    function fuzz_appendScoring(uint256 walletSeed, uint256 scoringSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_appendScoring.selector, walletSeed, scoringSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-SCORING");
        }
    }

    function fuzz_appendScoringInvalid(uint256 caseSeed, uint256 scoringSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_appendScoringInvalid.selector, caseSeed, scoringSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-SCORING-INVALID");
        }
    }

    function fuzz_scoringInvalidQueries(uint256 scoringIdSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_scoringInvalidQueries.selector, scoringIdSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-SCORING-QUERIES");
        }
    }

    function fuzz_bondRegistryAdminSurface(uint256 roleSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_bondRegistryAdminSurface.selector, roleSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ADMIN");
        }
    }

    function fuzz_bondRegistryGrantInvalidRole() public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_bondRegistryGrantInvalidRole.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ADMIN-INVALID-ROLE");
        }
    }

    function fuzz_bondRegistrySetMultiTokenLocked() public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerBondRegistry.handler_bondRegistrySetMultiTokenLocked.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ADMIN-LOCKED-TOKEN");
        }
    }

    function fuzz_bondRegistryInitializeAgain() public {
        bytes memory callData = abi.encodeWithSelector(HandlerBondRegistry.handler_bondRegistryInitializeAgain.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-ADMIN-INIT-AGAIN");
        }
    }

    function fuzz_publishBondInvalidInput(uint256 caseSeed, uint256 maxSupplySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerBondRegistry.handler_publishBondInvalidInput.selector, caseSeed, maxSupplySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-BOND-PUBLISH-INVALID-INPUT");
        }
    }
}

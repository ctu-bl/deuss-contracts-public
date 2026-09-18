// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerMarketplaceLifecycle} from "./helper/handlers/HandlerMarketplaceLifecycle.sol";

/**
 * @title FuzzMarketplaceLifecycle
 * @notice Directed fuzz target for rare Marketplace deadline-gated lifecycle branches.
 */
contract FuzzMarketplaceLifecycle is HandlerMarketplaceLifecycle, FuzzIntegrityBase {
    /**
     * @notice Initializes the directed lifecycle fuzz harness and shared actor state.
     */
    constructor() payable {
        setup();
        setupActors();
        if (VALIDATE_FUZZ_SETUP) validateSetup();
    }

    /**
     * @notice Checks direct-sale `resolvePayment(false)` after the live payment deadline.
     */
    function fuzz_directSaleResolveUnpaid(uint256 offerSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_directSaleResolveUnpaid.selector, offerSeed, amountSeed
        );

        _runLifecycleCall(callData, "IDL-DIRECT-RESOLVE-UNPAID");
    }

    /**
     * @notice Checks unpaid direct-sale settlement after payment and dispute deadlines.
     */
    function fuzz_directSaleSettleUnpaid(uint256 offerSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_directSaleSettleUnpaid.selector, offerSeed, amountSeed
        );

        _runLifecycleCall(callData, "IDL-DIRECT-SETTLE-UNPAID");
    }

    /**
     * @notice Checks cancelled direct-sale `withdrawAvailable` after unpaid settlement returns inventory.
     */
    function fuzz_directSaleWithdrawAfterUnpaidSettlement(uint256 offerSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_directSaleWithdrawAfterUnpaidSettlement.selector, offerSeed, amountSeed
        );

        _runLifecycleCall(callData, "IDL-DIRECT-WITHDRAW-RETURNED");
    }

    /**
     * @notice Checks single expired-interest closeout with non-zero released inventory.
     */
    function fuzz_interestDiscoveryCloseExpiredInterest(uint256 offerSeed, uint256 interestSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_interestDiscoveryCloseExpiredInterest.selector, offerSeed, interestSeed
        );

        _runLifecycleCall(callData, "IDL-INTEREST-CLOSE");
    }

    /**
     * @notice Checks batched expired-interest closeout for at least two interests on one offer.
     */
    function fuzz_interestDiscoveryCloseExpiredInterestsBatch(uint256 offerSeed, uint256 countSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_interestDiscoveryCloseExpiredInterestsBatch.selector,
            offerSeed,
            countSeed
        );

        _runLifecycleCall(callData, "IDL-INTEREST-CLOSE-BATCH");
    }

    /**
     * @notice Checks expired interest-discovery withdrawal when threshold is met and inventory remains.
     */
    function fuzz_interestDiscoveryWithdrawExpiredAvailable(uint256 offerSeed, uint256 interestSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_interestDiscoveryWithdrawExpiredAvailable.selector,
            offerSeed,
            interestSeed
        );

        _runLifecycleCall(callData, "IDL-INTEREST-WITHDRAW-AVAILABLE");
    }

    /**
     * @notice Checks activated-interest `resolvePayment(false)` after the live payment deadline.
     */
    function fuzz_activatedInterestResolveUnpaid(uint256 offerSeed, uint256 interestSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_activatedInterestResolveUnpaid.selector, offerSeed, interestSeed
        );

        _runLifecycleCall(callData, "IDL-ACTIVATED-RESOLVE-UNPAID");
    }

    /**
     * @notice Checks unpaid settlement for a deal created from activated interest.
     */
    function fuzz_activatedInterestSettleUnpaid(uint256 offerSeed, uint256 interestSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_activatedInterestSettleUnpaid.selector, offerSeed, interestSeed
        );

        _runLifecycleCall(callData, "IDL-ACTIVATED-SETTLE-UNPAID");
    }

    /**
     * @notice Checks rare Marketplace validation reverts for wrong sale modes and missing interest.
     */
    function fuzz_marketplaceNegativeValidationSurface(uint256 offerSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerMarketplaceLifecycle.handler_marketplaceNegativeValidationSurface.selector, offerSeed, amountSeed
        );

        _runLifecycleCall(callData, "IDL-MARKETPLACE-NEGATIVE-SURFACE");
    }

    function _runLifecycleCall(bytes memory callData, string memory context) internal {
        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, context);
        }
    }
}

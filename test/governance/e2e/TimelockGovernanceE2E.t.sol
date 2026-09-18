// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {TimelockController} from "src/governance/TimelockController.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {Deal} from "src/marketplace/MarketStructs.sol";
import {BaseToken} from "src/token/base/BaseToken.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";

contract TimelockGovernanceE2ETest is SharedE2EFixture {
    bytes32 private constant _SALT_FREEZE_ROLE = keccak256("e2e.freeze.role");
    bytes32 private constant _SALT_PAYMENT_ROLE = keccak256("e2e.payment.role");
    bytes32 private constant _SALT_TIMELOCK_ADMIN = keccak256("e2e.timelock.admin");
    bytes32 private constant _SALT_PAYMENT_CONFIG = keccak256("e2e.payment.config");
    bytes32 private constant _SALT_FORCE_TRANSFER_ROLE = keccak256("e2e.force.transfer.role");

    uint256 private constant _NEW_MARKETPLACE_PAYMENT_EXPIRY = 3 days;

    /**
     * Scenario:
     *   1. A fresh actor cannot freeze an Marketplace offer.
     *   2. The configured timelock actor schedules and executes a FREEZE_ROLE grant.
     *   3. The newly granted actor freezes the offer.
     *
     * Purpose: prove that a real protocol role can be granted through the deployed
     *          TimelockController and then used in a marketplace business flow.
     */
    function test_e2e_timelock_grantsFreezeRole_thenActorFreezesOffer() public {
        uint256 offerId = _registerOffer();
        address timelockedFreezer = makeAddr("timelockedFreezer");

        vm.prank(timelockedFreezer);
        vm.expectRevert();
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        bytes memory grantFreezeRole = abi.encodeWithSignature(
            "grantRoles(address,uint256)", timelockedFreezer, Marketplace(_marketplace).FREEZE_ROLE()
        );
        _scheduleAndExecute(_marketplace, grantFreezeRole, _SALT_FREEZE_ROLE);

        vm.prank(timelockedFreezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        assertTrue(_isOfferFrozen(offerId), "timelocked freezer did not freeze offer");
    }

    /**
     * Scenario:
     *   1. A PAYMENT_HANDLER grant is scheduled through timelock.
     *   2. A canceller cancels the scheduled operation before execution.
     *   3. The actor still cannot mark a pending deal as paid.
     *
     * Purpose: prove cancelled governance operations do not partially apply and
     *          do not grant marketplace privileges.
     */
    function test_e2e_timelock_cancelledPaymentHandlerGrant_neverTakesEffect() public {
        address cancelledPaymentHandler = makeAddr("cancelledPaymentHandler");
        bytes memory grantPaymentRole = abi.encodeWithSignature(
            "grantRoles(address,uint256)", cancelledPaymentHandler, Marketplace(_marketplace).PAYMENT_HANDLER()
        );

        bytes32 operationId = _schedule(_marketplace, grantPaymentRole, _SALT_PAYMENT_ROLE);
        _grantCancellerRoleToTimelockActor();

        vm.prank(_timelockControllerActor);
        TimelockController(_timelockController).cancel(operationId);

        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, OFFER_LOT, _buyerWallet);

        vm.prank(cancelledPaymentHandler);
        vm.expectRevert();
        Marketplace(_marketplace).resolvePayment(dealId, true);
    }

    /**
     * Scenario:
     *   1. A non-admin cannot directly update marketplace payment expiry.
     *   2. Timelock grants itself ADMIN, then schedules and executes the config update.
     *   3. A newly created deal receives the new payment deadline.
     *
     * Purpose: prove timelock can update live marketplace configuration and the
     *          changed config affects subsequent business state.
     */
    function test_e2e_timelock_updatesMarketplacePaymentExpiry_affectsNewDeals() public {
        address outsider = makeAddr("configOutsider");
        vm.prank(outsider);
        vm.expectRevert();
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(_NEW_MARKETPLACE_PAYMENT_EXPIRY);

        bytes memory grantAdminToTimelock = abi.encodeWithSignature(
            "grantRoles(address,uint256)", _timelockController, Marketplace(_marketplace).ADMIN()
        );
        _scheduleAndExecute(_marketplace, grantAdminToTimelock, _SALT_TIMELOCK_ADMIN);

        bytes memory updatePaymentExpiry =
            abi.encodeCall(MarketplaceBase.setMarketplacePaymentExpiryThreshold, (_NEW_MARKETPLACE_PAYMENT_EXPIRY));
        _scheduleAndExecute(_marketplace, updatePaymentExpiry, _SALT_PAYMENT_CONFIG);

        assertEq(
            _marketplaceConfig().marketplacePaymentExpiryThreshold,
            _NEW_MARKETPLACE_PAYMENT_EXPIRY,
            "payment expiry not updated"
        );

        uint256 offerId = _registerOffer();
        uint256 acceptedAt = block.timestamp;
        uint256 dealId = _acceptOffer(offerId, OFFER_LOT, _buyerWallet);
        Deal memory deal = _getDeal(dealId);

        assertEq(deal.paymentDeadline, acceptedAt + _NEW_MARKETPLACE_PAYMENT_EXPIRY, "new deadline not applied");
    }

    function _marketplaceConfig() internal view returns (MarketplaceStorage.Config memory config) {
        (config,) = MarketplaceBase(_marketplace).getConfigAndCounters();
    }

    /**
     * Scenario:
     *   1. A registered actor without FORCE_TRANSFER_ROLE cannot force-transfer tokens.
     *   2. Timelock grants FORCE_TRANSFER_ROLE on the deployed DEUSSToken.
     *   3. The actor force-transfers bond tokens from issuer wallet to buyer wallet.
     *
     * Purpose: prove token-level emergency transfer authority can be granted
     *          through timelock and used against the live protocol token.
     */
    function test_e2e_timelock_grantsForceTransferRole_thenActorForcedTransfersToken() public {
        address timelockedTransferAgent = makeAddr("timelockedTransferAgent");
        _createAndRegisterEntityWallet(_erAdmin, timelockedTransferAgent);

        uint256 transferAmount = OFFER_LOT;
        uint256 issuerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId);
        uint256 buyerBalanceBefore = IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId);

        vm.prank(timelockedTransferAgent);
        vm.expectRevert();
        IDEUSSToken(_tokenAddr).forcedTransfer(_issuerWallet, _buyerWallet, _bondFTId, transferAmount);

        bytes memory grantForceTransferRole = abi.encodeWithSignature(
            "grantRoles(address,uint256)", timelockedTransferAgent, BaseToken(_tokenAddr).FORCE_TRANSFER_ROLE()
        );
        _scheduleAndExecute(_tokenAddr, grantForceTransferRole, _SALT_FORCE_TRANSFER_ROLE);

        vm.prank(timelockedTransferAgent);
        bool success = IDEUSSToken(_tokenAddr).forcedTransfer(_issuerWallet, _buyerWallet, _bondFTId, transferAmount);

        assertTrue(success, "forced transfer failed");
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, _bondFTId),
            issuerBalanceBefore - transferAmount,
            "issuer balance"
        );
        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId),
            buyerBalanceBefore + transferAmount,
            "buyer balance"
        );
    }
}

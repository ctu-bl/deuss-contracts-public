// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {DealStatus} from "src/marketplace/MarketStructs.sol";
import {IMarketplace} from "src/marketplace/interfaces/IMarketplace.sol";
import {Offer} from "src/marketplace/MarketStructs.sol";
// test files
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";

contract MarketplaceIntegrationTest is MarketplaceFixture {
    // MARKET SITUATION 1:
    // Company offers all bonds
    // Investor buys all of them

    function setUp() public override {
        super.setUp();
        _investor = _createAndRegisterOtherCompany();
    }

    function test_marketSituation01() public {
        // ARRANGE
        uint256 amountOfBondsToBuy = BOND_MAX_SUPPLY;
        (uint256 offerId, uint256 dealId) = _setupMarket(amountOfBondsToBuy, _investor);
        // balances before
        Balances memory balancesBefore = _snapshotBalances();
        // Preconditions
        _dealCannotBeSettledDueToInvalidStatus(dealId, DealStatus.PENDING);
        _dealCannotBeResolvedWhenNotInDispute(dealId, DealStatus.PAID);

        // ACT
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.PAID), uint8(DealStatus.PENDING));

        vm.prank(_paymentProvider);
        IMarketplace(_marketplace).resolvePayment(dealId, true);

        _dealCannotBeResolvedWhenNotInDispute(dealId, DealStatus.PAID);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.SUCCESSFUL), uint8(DealStatus.PAID));
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, 0, 0, amountOfBondsToBuy);

        IMarketplace(_marketplace).settleDeal(dealId);

        _dealCannotBeResolvedWhenNotInDispute(dealId, DealStatus.PAID);

        // ASSERT
        // balances after
        Balances memory balancesAfter = _snapshotBalances();
        // assertion
        assertEq(balancesBefore.investor, 0);
        assertEq(balancesAfter.company, 0);
        assertLt(balancesAfter.escrow, balancesBefore.escrow);
        assertEq(balancesAfter.escrow, 0);
        assertEq(balancesAfter.investor, balancesBefore.investor + amountOfBondsToBuy);
        // amounts in offer
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, 0);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, amountOfBondsToBuy);
    }

    // MARKET SITUATION 2:
    // Company offers all bonds
    // Investor buys 50% of them

    function test_marketSituation02() public {
        // ARRANGE
        uint256 amountOfBondsToBuy = BOND_MAX_SUPPLY / 2;
        (uint256 offerId, uint256 dealId) = _setupMarket(amountOfBondsToBuy, _investor);
        // balances before
        Balances memory balancesBefore = _snapshotBalances();

        // ACT
        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.PAID), uint8(DealStatus.PENDING));

        vm.prank(_paymentProvider);
        IMarketplace(_marketplace).resolvePayment(dealId, true);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.SUCCESSFUL), uint8(DealStatus.PAID));
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, amountOfBondsToBuy, 0, amountOfBondsToBuy);

        IMarketplace(_marketplace).settleDeal(dealId);

        // ASSERT
        // balances after
        Balances memory balancesAfter = _snapshotBalances();
        // assertion
        assertEq(balancesBefore.investor, 0);
        assertEq(balancesAfter.company, 0);
        assertEq(balancesBefore.escrow, BOND_MAX_SUPPLY);
        assertEq(balancesAfter.escrow, balancesBefore.escrow - amountOfBondsToBuy);
        assertEq(balancesAfter.investor, balancesBefore.investor + amountOfBondsToBuy);
        // amounts in offer
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, BOND_MAX_SUPPLY - amountOfBondsToBuy);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, amountOfBondsToBuy);
    }

    // MARKET SITUATION 3:
    // Company offers all bonds
    // Investor want to buy 25% of them, but payment is delayed
    // Deal is marked as NOT PAID
    // Investor disputes the deal
    // Arbitrator rules in favor of investor
    // Deal settles as SUCCESSFUL
    // Investor receives the bonds

    function test_marketSituation03() public {
        // ARRANGE
        uint256 amountOfBondsToBuy = BOND_MAX_SUPPLY / 4;
        (uint256 offerId, uint256 dealId) = _setupMarket(amountOfBondsToBuy, _investor);
        // balances before
        Balances memory balancesBefore = _snapshotBalances();
        // Test preconditions
        _dealCannotBeMarkedAsNotPaidIfExpired(dealId);
        _dealCannotBeDisputedDueToInvalidStatus(dealId, DealStatus.PENDING);

        // ACT
        uint256 dealPaymentDeadline = _getDeal(dealId).paymentDeadline;
        vm.warp(dealPaymentDeadline + 1);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNPAID), uint8(DealStatus.PENDING));

        vm.prank(_paymentProvider);
        IMarketplace(_marketplace).resolvePayment(dealId, false);

        _dealCannotBeSettledDueToDisputePeriodNotExpired(dealId);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.IN_DISPUTE), uint8(DealStatus.UNPAID));

        vm.prank(_investor);
        IMarketplace(_marketplace).initiateDispute(dealId);

        _dealCannotBeResolvedWithInvalidStatus(dealId, DealStatus.NON_EXISTING);
        _dealCannotBeResolvedWithInvalidStatus(dealId, DealStatus.PENDING);
        _dealCannotBeResolvedWithInvalidStatus(dealId, DealStatus.IN_DISPUTE);
        _dealCannotBeResolvedWithInvalidStatus(dealId, DealStatus.SUCCESSFUL);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.PAID), uint8(DealStatus.IN_DISPUTE));

        vm.prank(_arbitrator);
        IMarketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.SUCCESSFUL), uint8(DealStatus.PAID));
        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, (BOND_MAX_SUPPLY) - amountOfBondsToBuy, 0, amountOfBondsToBuy);

        IMarketplace(_marketplace).settleDeal(dealId);

        // ASSERT
        // balances after
        Balances memory balancesAfter = _snapshotBalances();
        // assertion
        assertEq(balancesBefore.investor, 0);
        assertEq(balancesAfter.company, 0);
        assertEq(balancesAfter.escrow, balancesBefore.escrow - amountOfBondsToBuy);
        assertEq(balancesAfter.investor, balancesBefore.investor + amountOfBondsToBuy);
        // amounts in offer
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, (BOND_MAX_SUPPLY) - amountOfBondsToBuy);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, amountOfBondsToBuy);
    }

    // MARKET SITUATION 4:
    // Company offers all bonds
    // Investor buys 10% of them
    // Deal is marked UNPAID
    // Investor disputes the deal
    // Arbitrator rules in favor of company
    // Deal settles as UNSUCCESSFUL
    // Investor does not receive the bonds

    function test_marketSituation04() public {
        // ARRANGE
        uint256 amountOfBondsToBuy = BOND_MAX_SUPPLY / 10;
        (uint256 offerId, uint256 dealId) = _setupMarket(amountOfBondsToBuy, _investor);
        // balances before
        Balances memory balancesBefore = _snapshotBalances();
        // Test preconditions:
        _dealCannotBeMarkedAsNotPaidIfExpired(dealId);
        _dealCannotBeDisputedDueToInvalidStatus(dealId, DealStatus.PENDING);

        // ACT
        uint256 dealPaymentDeadline = _getDeal(dealId).paymentDeadline;
        vm.warp(dealPaymentDeadline + 1);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNPAID), uint8(DealStatus.PENDING));

        vm.prank(_paymentProvider);
        IMarketplace(_marketplace).resolvePayment(dealId, false);

        _dealCannotBeMarkedAsNotPaidDueToInvalidStatus(dealId, DealStatus.UNPAID);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.IN_DISPUTE), uint8(DealStatus.UNPAID));

        vm.prank(_investor);
        IMarketplace(_marketplace).initiateDispute(dealId);

        _dealCannotBeSettledDueToInvalidStatus(dealId, DealStatus.IN_DISPUTE);
        _dealCannotBeMarkedAsNotPaidDueToInvalidStatus(dealId, DealStatus.IN_DISPUTE);
        _dealCannotBeDisputedDueToInvalidStatus(dealId, DealStatus.IN_DISPUTE);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNPAID), uint8(DealStatus.IN_DISPUTE));

        vm.prank(_arbitrator);
        IMarketplace(_marketplace).resolveDispute(dealId, DealStatus.UNPAID);

        _dealCannotBeMarkedAsNotPaidDueToInvalidStatus(dealId, DealStatus.UNPAID);
        _dealCannotBeDisputedIfExpired(dealId);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNSUCCESSFUL), uint8(DealStatus.UNPAID));

        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, (BOND_MAX_SUPPLY), 0, 0);

        IMarketplace(_marketplace).settleDeal(dealId);

        _dealCannotBeMarkedAsNotPaidDueToInvalidStatus(dealId, DealStatus.UNSUCCESSFUL);

        // ASSERT
        // balances after
        Balances memory balancesAfter = _snapshotBalances();
        // assertion
        assertEq(balancesBefore.investor, 0);
        assertEq(balancesAfter.investor, balancesBefore.investor);
        assertEq(balancesAfter.company, balancesBefore.company);
        assertEq(balancesAfter.escrow, balancesBefore.escrow);
        // amounts in offer
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
    }

    // MARKET SITUATION 5:
    // Company offers all bonds
    // Investor buys 10% of them
    // Deal is marked UNPAID
    // Investor disputes the deal
    // Arbitrator resolves dispute by UNPAID
    // Deal settles as UNSUCCESSFUL
    // Investor does not receive the bonds

    function test_marketSituation05() public {
        // ARRANGE
        uint256 amountOfBondsToBuy = BOND_MAX_SUPPLY / 10;
        (uint256 offerId, uint256 dealId) = _setupMarket(amountOfBondsToBuy, _investor);
        // balances before
        Balances memory balancesBefore = _snapshotBalances();

        // ACT
        uint256 dealPaymentDeadline = _getDeal(dealId).paymentDeadline;
        vm.warp(dealPaymentDeadline + 1);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNPAID), uint8(DealStatus.PENDING));

        vm.prank(_paymentProvider);
        IMarketplace(_marketplace).resolvePayment(dealId, false);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.IN_DISPUTE), uint8(DealStatus.UNPAID));

        vm.prank(_investor);
        IMarketplace(_marketplace).initiateDispute(dealId);

        _dealCannotBeMarkedAsPaid(dealId, DealStatus.IN_DISPUTE);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNPAID), uint8(DealStatus.IN_DISPUTE));

        vm.prank(_arbitrator);
        IMarketplace(_marketplace).resolveDispute(dealId, DealStatus.UNPAID);

        _dealCannotBeMarkedAsPaidDueToArbitration(dealId);

        vm.expectEmit();
        emit IMarketplace.DealStatusUpdated(dealId, offerId, uint8(DealStatus.UNSUCCESSFUL), uint8(DealStatus.UNPAID));

        vm.expectEmit();
        emit IMarketplace.AmountsUpdated(offerId, (BOND_MAX_SUPPLY), 0, 0);

        IMarketplace(_marketplace).settleDeal(dealId);

        _dealCannotBeMarkedAsPaid(dealId, DealStatus.UNSUCCESSFUL);

        // ASSERT
        // balances after
        Balances memory balancesAfter = _snapshotBalances();
        // assertion
        assertEq(balancesBefore.investor, 0);
        assertEq(balancesAfter.investor, balancesBefore.investor);
        assertEq(balancesAfter.company, balancesBefore.company);
        assertEq(balancesAfter.escrow, balancesBefore.escrow);
        // amounts in offer
        Offer memory offerRegistered = _getOffer(offerId);
        assertEq(offerRegistered.amounts.available, BOND_MAX_SUPPLY);
        assertEq(offerRegistered.amounts.inDeals, 0);
        assertEq(offerRegistered.amounts.sold, 0);
    }
}

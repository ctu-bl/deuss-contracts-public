// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {Marketplace} from "src/marketplace/Marketplace.sol";
import {AccountStatus} from "src/registry/EntityStructs.sol";
import {DealStatus, InterestDiscoveryState, OfferInput} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";

contract MarketplaceAccessControlE2ETest is SharedE2EFixture {
    uint256 private constant _TRADE_AMOUNT = OFFER_LOT;
    bytes32 private constant _SEIZURE_REASON = keccak256("ACCESS_CONTROL_SEIZURE");

    /**
     * Scenario:
     *   1. A registered buyer opens a pending deal.
     *   2. An address without PAYMENT_HANDLER attempts to mark the deal paid.
     *   3. The configured payment provider marks it paid and settlement succeeds.
     *
     * Purpose: prove payment role checks protect the paid settlement path.
     */
    function test_e2e_nonPaymentHandler_cannotResolvePaid_thenPaymentProviderCanSettle() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);

        address notPaymentHandler = makeAddr("notPaymentHandler");
        vm.prank(notPaymentHandler);
        vm.expectRevert();
        Marketplace(_marketplace).resolvePayment(dealId, true);

        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /**
     * Scenario:
     *   1. A deal becomes UNPAID and the buyer opens a dispute.
     *   2. An address without ARBITRATOR attempts dispute resolution.
     *   3. The configured arbitrator resolves the dispute as PAID.
     *
     * Purpose: prove arbitration cannot be performed by arbitrary callers.
     */
    function test_e2e_nonArbitrator_cannotResolveDispute_thenArbitratorCanResolve() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);

        vm.warp(_getDeal(dealId).paymentDeadline + 1);
        _resolvePayment(dealId, false);
        _initiateDispute(dealId, _buyerWallet);

        address notArbitrator = makeAddr("notArbitrator");
        vm.prank(notArbitrator);
        vm.expectRevert();
        Marketplace(_marketplace).resolveDispute(dealId, DealStatus.PAID);

        _resolveDisputeID(dealId, DealStatus.PAID);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.PAID));
    }

    /**
     * Scenario:
     *   1. A live offer exists.
     *   2. An address without FREEZE_ROLE attempts to freeze it.
     *   3. The configured freezer freezes it.
     *
     * Purpose: prove freeze authority is enforced before governance hold logic.
     */
    function test_e2e_nonFreezer_cannotFreezeOffer_thenFreezerCanFreeze() public {
        uint256 offerId = _registerOffer();

        address notFreezer = makeAddr("notFreezer");
        vm.prank(notFreezer);
        vm.expectRevert();
        Marketplace(_marketplace).setOfferFrozen(offerId, true);

        _setOfferFrozen(offerId, true);
        assertTrue(_isOfferFrozen(offerId), "offer not frozen");
    }

    /**
     * Scenario:
     *   1. A live offer is frozen.
     *   2. An address without SEIZURE_ROLE attempts to seize available escrow.
     *   3. The configured seizure role seizes to a registered beneficiary.
     *
     * Purpose: prove escrow seizure remains behind governance authorization.
     */
    function test_e2e_nonSeizureRole_cannotSeizeOfferEscrow_thenSeizureRoleCanSeize() public {
        uint256 offerId = _registerOffer();
        _setOfferFrozen(offerId, true);

        address beneficiary = makeAddr("accessControlBeneficiary");
        _createAndRegisterEntityWallet(_erAdmin, beneficiary);

        address notSeizure = makeAddr("notSeizure");
        vm.prank(notSeizure);
        vm.expectRevert();
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, _SEIZURE_REASON);

        _seizeAvailable(offerId, beneficiary, _SEIZURE_REASON);
        assertTrue(_isOfferCancelled(offerId), "offer not cancelled after seizure");
    }

    /**
     * Scenario:
     *   1. Issuer registers an interest-discovery offer and an investor expresses interest.
     *   2. The activation window closes.
     *   3. An address holding only ADMIN (not INTEREST_DISCOVERY_OPERATOR) cannot close expired interests.
     *   4. An address holding INTEREST_DISCOVERY_OPERATOR can close expired interests even when the
     *      issuer's account has been disabled.
     *
     * Purpose: prove ADMIN and INTEREST_DISCOVERY_OPERATOR are separate, and that the operational
     * maintenance path does not require ADMIN.
     */
    function test_e2e_pureAdmin_cannotCloseExpiredInterests_operatorCan_whenOwnerDisabled() public {
        _approveEscrowOperator(_issuerWallet);

        uint256 offerId = _registerInterestDiscoveryOffer(OFFER_LOT);
        _expressInterest(offerId, OFFER_LOT, _buyerWallet);

        InterestDiscoveryState memory state = _getInterestDiscoveryState(offerId);
        uint256 activationWindow = state.paymentExpiryThreshold;
        vm.warp(_getOffer(offerId).expiry + activationWindow + 1);

        uint256[] memory interestIds = new uint256[](0);

        // Pure ADMIN cannot close expired interests.
        address pureAdmin = makeAddr("e2ePureAdmin");
        _grantRoles(_marketplace, pureAdmin, Marketplace(_marketplace).ADMIN());
        vm.prank(pureAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);

        // Disable the issuer so the owner path is also closed.
        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_issuerWallet, AccountStatus.DISABLED, "");

        // INTEREST_DISCOVERY_OPERATOR succeeds regardless.
        vm.prank(_adminID);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    /**
     * Scenario:
     *   1. An offer restricts buyers to _buyerWallet.
     *   2. _secondBuyerWallet is registered but not allowlisted and cannot accept.
     *   3. _buyerWallet accepts successfully.
     *
     * Purpose: prove marketplace allowed-buyer filtering works end-to-end.
     */
    function test_e2e_allowedBuyerRestriction_blocksUnlistedBuyer_allowsListedBuyer() public {
        OfferInput memory offer = _createOfferInput();
        offer.totalAmount = _TRADE_AMOUNT * 2;
        address[] memory allowedBuyers = new address[](1);
        allowedBuyers[0] = _buyerWallet;
        offer.allowedBuyers = allowedBuyers;

        vm.prank(_issuerWallet);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);

        vm.prank(_secondBuyerWallet);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__BuyerNotAllowed.selector, offerId, _secondBuyerWallet)
        );
        Marketplace(_marketplace).acceptOffer(offerId, _TRADE_AMOUNT);

        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /**
     * Scenario:
     *   1. A live offer exists.
     *   2. An unregistered EOA attempts to accept it.
     *
     * Purpose: prove marketplace trades require an enabled EntityRegistry account.
     */
    function test_e2e_unregisteredWallet_cannotAcceptOffer() public {
        uint256 offerId = _registerOffer();
        address unregisteredBuyer = makeAddr("unregisteredBuyer");

        vm.prank(unregisteredBuyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, unregisteredBuyer)
        );
        Marketplace(_marketplace).acceptOffer(offerId, _TRADE_AMOUNT);
    }
}

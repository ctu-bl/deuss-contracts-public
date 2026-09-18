// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {DealStatus} from "src/marketplace/MarketStructs.sol";
import {AccountStatus, EntityStatus} from "src/registry/EntityStructs.sol";
import {Errors} from "src/libs/Errors.sol";

contract EntityRegistryTradingE2ETest is SharedE2EFixture {
    uint256 private constant _BROKER_ENTITY_TYPE = 4;
    uint256 private constant _TRADE_AMOUNT = 50;

    /**
     * Scenario:
     *   1. _erAdmin defines a custom BROKER entity type.
     *   2. _erAdmin registers a broker entity with brokerAuthority and brokerManager.
     *   3. _governance grants brokerManager the ONBOARDING role.
     *   4. brokerManager registers a client entity, creates a CompanyWallet for the client, and requests registration.
     *   5. clientWallet accepts an open offer, payment is resolved, deal settles.
     *
     * Purpose: prove that an entity onboarded by a broker (rather than the platform
     *          admin directly) receives a fully functional CompanyWallet that can
     *          participate in marketplace trades end-to-end.
     */
    function test_e2e_broker_onboards_wallets_and_wallets_can_trade() public {
        address brokerManager = makeAddr("brokerManager");
        vm.label(brokerManager, "BrokerManager");

        vm.prank(_erAdmin);
        _er.defineEntityType(_BROKER_ENTITY_TYPE, bytes32("BROKER"), 0);

        address brokerAuthority = makeAddr("brokerAuthority");
        vm.label(brokerAuthority, "BrokerAuthority");
        bytes32 brokerEntityId = keccak256(abi.encodePacked("brokerEntity", brokerManager));
        address[] memory brokerMgrs = new address[](1);
        brokerMgrs[0] = brokerManager;
        vm.prank(_erAdmin);
        _er.registerEntity(brokerEntityId, _BROKER_ENTITY_TYPE, "", brokerAuthority, brokerMgrs);

        uint256 onboardingRole = _er.ONBOARDING();
        _grantRoles(_erAddr, brokerManager, onboardingRole);

        address clientOwner = makeAddr("clientOwner");
        bytes32 clientEntityId = keccak256(abi.encodePacked(clientOwner, _entityNonce));
        ++_entityNonce;

        address[] memory clientMgrs = new address[](1);
        clientMgrs[0] = brokerManager;
        vm.prank(brokerManager);
        _er.registerEntity(clientEntityId, COMPANY_ENTITY, "", clientOwner, clientMgrs);

        address clientWallet = _createCompanyWallet(clientEntityId, clientOwner, brokerManager);

        _requestAndAcceptWalletAccountRegistration(
            brokerManager, clientWallet, clientEntityId, clientOwner, ROLE_FLAGS_EMPTY
        );
        vm.label(clientWallet, "ClientWallet");

        assertTrue(_er.isAccountEnabled(clientWallet), "client wallet not enabled");

        _approveEscrowOperator(clientWallet);

        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, clientWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(clientWallet, _bondFTId), _TRADE_AMOUNT, "client wallet bond balance"
        );
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /**
     * Scenario:
     *   1. _erAdmin registers an entity with oldAuthority and oldManager.
     *   2. oldAuthority rotates to newAuthority via setEntityAuthority.
     *   3. newAuthority removes oldManager and adds newManager.
     *   4. Negative checks: oldManager can no longer create a CompanyWallet
     *      (WalletFactory__NotEntityManager) or request account registration
     *      (ER__NotEntityManagerOrAdmin).
     *   5. newManager onboards newClientWallet; wallet accepts an offer,
     *      payment is resolved, deal settles.
     *
     * Purpose: prove that authority rotation takes effect immediately — revoked
     *          credentials are blocked at the contract level, while the newly
     *          authorised manager can fully operate and complete real trades.
     */
    function test_e2e_authorityRotation_oldManagerBlocked_newManagerCanOnboardAndTrade() public {
        address oldAuthority = makeAddr("oldAuthority");
        address oldManager = makeAddr("oldManager");
        address newAuthority = makeAddr("newAuthority");
        address newManager = makeAddr("newManager");
        vm.label(oldAuthority, "OldAuthority");
        vm.label(oldManager, "OldManager");
        vm.label(newAuthority, "NewAuthority");
        vm.label(newManager, "NewManager");

        bytes32 entityId = keccak256(abi.encodePacked("rotation-entity", oldAuthority));
        address[] memory initMgrs = new address[](1);
        initMgrs[0] = oldManager;
        vm.prank(_erAdmin);
        _er.registerEntity(entityId, COMPANY_ENTITY, "", oldAuthority, initMgrs);

        assertEq(_er.getEntityAuthority(entityId), oldAuthority, "initial authority");
        assertTrue(_er.isEntityManager(entityId, oldManager), "initial manager");

        vm.prank(oldAuthority);
        _er.setEntityAuthority(entityId, newAuthority);
        assertEq(_er.getEntityAuthority(entityId), newAuthority, "authority after rotation");

        vm.prank(newAuthority);
        _er.setEntityManager(entityId, oldManager, false);
        assertFalse(_er.isEntityManager(entityId, oldManager), "old manager disabled");

        vm.expectRevert(abi.encodeWithSelector(Errors.WalletFactory__NotEntityManager.selector, oldManager, entityId));
        _createCompanyWallet(entityId, makeAddr("negTestOwner"), oldManager);

        vm.prank(oldManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ER__NotEntityManagerOrAdmin.selector, oldManager, entityId));
        _er.requestAccountRegistration(makeAddr("negTestAccount"), entityId, ROLE_FLAGS_EMPTY);

        vm.prank(newAuthority);
        _er.setEntityManager(entityId, newManager, true);
        assertTrue(_er.isEntityManager(entityId, newManager), "new manager enabled");

        address newClientOwner = makeAddr("newClientOwner");
        address newClientWallet = _createCompanyWallet(entityId, newClientOwner, newManager);
        _requestAndAcceptWalletAccountRegistration(
            newManager, newClientWallet, entityId, newClientOwner, ROLE_FLAGS_EMPTY
        );
        vm.label(newClientWallet, "NewClientWallet");

        assertTrue(_er.isAccountEnabled(newClientWallet), "new client wallet enabled");

        _approveEscrowOperator(newClientWallet);

        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, newClientWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(
            IDEUSSToken(_tokenAddr).balanceOf(newClientWallet, _bondFTId),
            _TRADE_AMOUNT,
            "new client wallet bond balance"
        );
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /**
     * Scenario:
     *   1. _buyerWallet completes one successful trade while enabled.
     *   2. EntityRegistry guard disables the wallet account.
     *   3. The same wallet cannot open a new marketplace deal.
     *
     * Purpose: prove EntityRegistry account status changes affect marketplace
     *          eligibility after a wallet has already traded successfully.
     */
    function test_e2e_accountDisabled_afterSuccessfulTrade_blocksNewTrades() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT);
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL));

        vm.prank(_erAdmin);
        _er.setAccountStatus(_buyerWallet, AccountStatus.DISABLED, bytes("account-disabled"));
        assertFalse(_er.isAccountEnabled(_buyerWallet), "account still enabled");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
    }

    /**
     * Scenario:
     *   1. _buyerWallet completes one successful trade while its entity is enabled.
     *   2. EntityRegistry guard disables the owning entity.
     *   3. The wallet cannot open a new marketplace deal.
     *
     * Purpose: prove entity-level disablement blocks all linked account trading,
     *          even when the account record itself remains present.
     */
    function test_e2e_entityDisabled_afterSuccessfulTrade_blocksLinkedWalletTrades() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        bytes32 buyerEntityId = _er.getEntityId(_buyerWallet);
        vm.prank(_erAdmin);
        _er.setEntityStatus(buyerEntityId, EntityStatus.DISABLED, bytes("entity-disabled"));
        assertFalse(_er.isAccountEnabled(_buyerWallet), "linked wallet still enabled");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
    }

    /**
     * Scenario:
     *   1. _buyerWallet completes one trade under its original entity.
     *   2. A WALLET_TRANSFER actor relinks _buyerWallet to a new enabled entity.
     *   3. The original entity is disabled.
     *   4. _buyerWallet can still open and settle a new trade through its new entity.
     *
     * Purpose: prove administrative account relinking updates the marketplace
     *          eligibility source of truth instead of leaving the wallet tied to
     *          the old entity.
     */
    function test_e2e_accountTransferredToNewEntity_oldEntityDisabled_walletStillTrades() public {
        uint256 offerId = _registerOffer();
        uint256 firstDealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(firstDealId, true);
        _settleDeal(firstDealId);

        bytes32 oldEntityId = _er.getEntityId(_buyerWallet);
        bytes32 newEntityId = _registerEntity(_erAdmin, COMPANY_ENTITY);

        address walletTransferActor = makeAddr("walletTransferActor");
        _grantRoles(_erAddr, walletTransferActor, _er.WALLET_TRANSFER());

        vm.prank(walletTransferActor);
        _er.transferAccountToEntity(_buyerWallet, newEntityId);

        assertEq(_er.getEntityId(_buyerWallet), newEntityId, "wallet not transferred");

        vm.prank(_erAdmin);
        _er.setEntityStatus(oldEntityId, EntityStatus.DISABLED, bytes("old-entity-disabled"));

        assertTrue(_er.isAccountEnabled(_buyerWallet), "wallet should remain enabled under new entity");

        uint256 secondDealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(secondDealId, true);
        _settleDeal(secondDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT * 2);
        assertEq(uint8(_getDeal(secondDealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /**
     * Scenario:
     *   1. _buyerWallet completes one successful trade while registered.
     *   2. A WALLET_TRANSFER actor removes the account from EntityRegistry.
     *   3. The removed wallet cannot open another marketplace deal.
     *
     * Purpose: prove account removal immediately revokes marketplace eligibility
     *          even when the wallet previously traded successfully.
     */
    function test_e2e_accountRemoved_afterSuccessfulTrade_blocksNewTrades() public {
        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        address walletTransferActor = makeAddr("walletRemoveActor");
        _grantRoles(_erAddr, walletTransferActor, _er.WALLET_TRANSFER());

        vm.prank(walletTransferActor);
        _er.removeAccount(_buyerWallet, bytes("removed"));

        assertFalse(_er.doesAccountExist(_buyerWallet), "account still exists");
        assertFalse(_er.isAccountEnabled(_buyerWallet), "removed account still enabled");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
    }
}

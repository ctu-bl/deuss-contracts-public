// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Account as RegistryAccount, AccountStatus, EntityStatus} from "src/registry/EntityStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {DealStatus} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";

contract EntityRegistryOperationsE2ETest is SharedE2EFixture {
    uint256 private constant _TRADE_AMOUNT = 50;

    /*//////////////////////////////////////////////////////////////
      test_e2e_entityAndAccountStatus_gateWalletFactoryMarketplaceAndMetadata
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Registry admin updates buyer entity metadata and account role flags.
     *   2. Disabling the buyer account blocks marketplace acceptance and registry
     *      canTransfer validation; re-enabling restores a real settlement path.
     *   3. Disabling the buyer entity blocks both marketplace eligibility and
     *      wallet creation under that entity.
     *   4. Re-enabling the entity restores the same wallet's ability to trade.
     *
     * Purpose: prove live registry guard mutations affect downstream protocol
     *          modules instead of only changing isolated registry storage.
     */
    function test_e2e_entityAndAccountStatus_gateWalletFactoryMarketplaceAndMetadata() public {
        bytes32 buyerEntityId = _er.getEntityId(_buyerWallet);
        uint256 offerId = _registerOffer();

        vm.prank(_erAdmin);
        _er.setEntityMetadata(buyerEntityId, "ipfs://buyer-updated");
        assertEq(_er.getEntityMetadataRef(buyerEntityId), "ipfs://buyer-updated", "metadata");

        vm.prank(_erAdmin);
        _er.setAccountRoleFlags(_buyerWallet, ROLE_FLAGS_UPDATED);

        RegistryAccount memory account = _er.getAccount(_buyerWallet);
        assertEq(account.roleFlags, ROLE_FLAGS_UPDATED, "role flags");

        vm.prank(_erAdmin);
        _er.setAccountStatus(_buyerWallet, AccountStatus.DISABLED, bytes("KYC_EXPIRED"));

        assertFalse(_er.isAccountEnabled(_buyerWallet), "account enabled while disabled");
        assertFalse(
            _er.canTransfer(_issuerWallet, _buyerWallet, _issuerWallet, _bondFTId, _TRADE_AMOUNT),
            "disabled account transferable"
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);

        vm.prank(_erAdmin);
        _er.setAccountStatus(_buyerWallet, AccountStatus.ENABLED, "");

        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT, "first settlement");
        assertEq(uint8(_getDeal(dealId).status), uint8(DealStatus.SUCCESSFUL), "first deal");

        vm.prank(_erAdmin);
        _er.setEntityStatus(buyerEntityId, EntityStatus.DISABLED, bytes("ENTITY_REVIEW"));

        assertFalse(_er.isAccountEnabled(_buyerWallet), "entity-disabled account enabled");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);

        vm.expectRevert(abi.encodeWithSelector(Errors.WalletFactory__EntityNotEnabled.selector, buyerEntityId));
        _createCompanyWallet(buyerEntityId, makeAddr("blockedBuyerWalletOwner"), _erAdmin);

        vm.prank(_erAdmin);
        _er.setEntityStatus(buyerEntityId, EntityStatus.ENABLED, "");

        uint256 secondDealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(secondDealId, true);
        _settleDeal(secondDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT * 2, "second settlement");
        assertEq(uint8(_getDeal(secondDealId).status), uint8(DealStatus.SUCCESSFUL), "second deal");
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_accountMigrationAndRemoval_updatesEntityListsAndTradingEligibility
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. Registry admin migrates an active buyer wallet from its original
     *      entity to a new managed company entity.
     *   2. The migrated wallet remains marketplace-eligible and settles a sale.
     *   3. Removing the wallet from the registry immediately blocks acceptance.
     *   4. The new entity manager requests registration, the wallet accepts, and trading resumes.
     *
     * Purpose: prove account migration and offboarding update both entity account
     *          lists and live marketplace eligibility.
     */
    function test_e2e_accountMigrationAndRemoval_updatesEntityListsAndTradingEligibility() public {
        bytes32 sourceEntityId = _er.getEntityId(_buyerWallet);
        (bytes32 targetEntityId,, address targetManager) = _registerTargetEntity();

        vm.prank(_erAdmin);
        _er.transferAccountToEntity(_buyerWallet, targetEntityId);

        RegistryAccount memory migrated = _er.getAccount(_buyerWallet);
        assertEq(migrated.entityId, targetEntityId, "migrated entity");
        _assertDoesNotContain(_er.getEntityAccounts(sourceEntityId), _buyerWallet);
        _assertContains(_er.getEntityAccounts(targetEntityId), _buyerWallet);

        uint256 offerId = _registerOffer();
        uint256 dealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT, "migrated trade");

        vm.prank(_erAdmin);
        _er.removeAccount(_buyerWallet, bytes("OFFBOARD"));

        assertFalse(_er.isAccountRegistered(_buyerWallet), "removed account still registered");
        _assertDoesNotContain(_er.getEntityAccounts(targetEntityId), _buyerWallet);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.EntityEligibilityGuard__EntityWalletNotAllowed.selector, _buyerWallet)
        );
        _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);

        _requestAndAcceptWalletAccountRegistration(
            targetManager, _buyerWallet, targetEntityId, _buyerOwner, ROLE_FLAGS_UPDATED
        );

        RegistryAccount memory reRegistered = _er.getAccount(_buyerWallet);
        assertEq(reRegistered.entityId, targetEntityId, "re-registered entity");
        assertEq(reRegistered.roleFlags, ROLE_FLAGS_UPDATED, "re-registered flags");
        assertTrue(_er.isAccountEnabled(_buyerWallet), "re-registered account disabled");
        _assertContains(_er.getEntityAccounts(targetEntityId), _buyerWallet);

        uint256 secondDealId = _acceptOffer(offerId, _TRADE_AMOUNT, _buyerWallet);
        _resolvePayment(secondDealId, true);
        _settleDeal(secondDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _TRADE_AMOUNT * 2, "re-onboarded trade");
        assertEq(uint8(_getDeal(secondDealId).status), uint8(DealStatus.SUCCESSFUL), "re-onboarded deal");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerTargetEntity()
        private
        returns (bytes32 targetEntityId, address targetAuthority, address targetManager)
    {
        targetAuthority = makeAddr("migrationAuthority");
        targetManager = makeAddr("migrationManager");
        targetEntityId = keccak256(abi.encodePacked("migration-target", targetAuthority));

        address[] memory managers = new address[](1);
        managers[0] = targetManager;

        vm.prank(_erAdmin);
        _er.registerEntity(targetEntityId, COMPANY_ENTITY, "ipfs://migration-target", targetAuthority, managers);
    }

    function _assertContains(address[] memory accounts, address expected) private pure {
        bool found;
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == expected) {
                found = true;
                break;
            }
        }
        assertTrue(found, "account missing");
    }

    function _assertDoesNotContain(address[] memory accounts, address unexpected) private pure {
        for (uint256 i; i < accounts.length; ++i) {
            assertNotEq(accounts[i], unexpected, "account still linked");
        }
    }
}

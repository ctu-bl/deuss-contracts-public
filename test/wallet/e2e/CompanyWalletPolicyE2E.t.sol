// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings, function-max-lines */

import {SharedE2EFixture} from "test/fixtures/SharedE2EFixture.t.sol";
import {IMarketplace} from "src/marketplace/interfaces/IMarketplace.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {DealStatus, Deal, Offer, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {IDEUSSToken} from "src/token/fungible/IDEUSSToken.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";
import {Errors} from "src/libs/Errors.sol";
import {Vm} from "forge-std/Vm.sol";

contract CompanyWalletPolicyE2ETest is SharedE2EFixture {
    using StringExtensions for string;

    error CompanyWalletPolicyE2E__OfferRegisteredEventNotFound();
    error CompanyWalletPolicyE2E__DealCreatedEventNotFound();
    /*//////////////////////////////////////////////////////////////
                        POLICY ROLE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Role bit granted to the delegate for issueBond calls
    uint256 private constant _ROLE_ISSUE = 1;
    /// @notice Role bit granted to the delegate for registerOffer calls
    uint256 private constant _ROLE_OFFER = 2;
    /// @notice Combined role
    uint256 private constant _ROLE_ISSUE_AND_OFFER = _ROLE_ISSUE | _ROLE_OFFER;
    /// @notice Role bit granted to the delegate for accepting offers
    uint256 private constant _ROLE_BUY = 4;
    /// @notice Role bit granted to the delegate for enabling escrow token transfers
    uint256 private constant _ROLE_TOKEN_OPERATOR = 8;
    uint256 private constant _BROKER_ENTITY_TYPE = 77;
    uint256 private constant _DELEGATED_TRADE_AMOUNT = 100;
    uint8 private constant _BOND_VERSION = 1;

    /*//////////////////////////////////////////////////////////////
            test_e2e_delegate_with_policy_roles_issue_offer_and_sell
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerOwner grants a delegate the ISSUE + OFFER roles in PolicyRegistry.
     *   2. Delegate issues the bond via CompanyWallet.execute().
     *   3. Delegate registers an offer via CompanyWallet.execute().
     *   4. _buyerWallet accepts the offer directly (non-policy path).
     *   5. paymentProvider marks the deal paid.
     *   6. Deal is settled; _buyerWallet receives the bonds.
     *
     * Purpose: prove PolicyRegistry authorization gates real trade execution,
     *          and that the delegate path ends in the same settled state as
     *          the direct owner path.
     */
    function test_e2e_delegate_with_policy_roles_issue_offer_and_sell() public {
        address delegate = makeAddr("delegate");
        vm.label(delegate, "Delegate");

        string memory delegateBondIsin = "SK0001009999";

        vm.prank(_publisher);
        _br.publishBond(_createBond(delegateBondIsin, _issuerWallet));

        _grantWalletPolicyUserRoles(_issuerWallet, delegate, _ROLE_ISSUE_AND_OFFER);
        _grantWalletPolicyOperationRoles(_issuerWallet, _brAddr, IBondRegistry.issueBond.selector, _ROLE_ISSUE);
        _grantWalletPolicyOperationRoles(_issuerWallet, _marketplace, IMarketplace.registerOffer.selector, _ROLE_OFFER);

        _executeViaWallet(
            _issuerWallet,
            delegate,
            _brAddr,
            abi.encodeWithSelector(IBondRegistry.issueBond.selector, delegateBondIsin, _BOND_VERSION, BOND_ISSUE_COUNT)
        );

        bytes12 newIsinBytes = delegateBondIsin._isinToBytes12();
        uint256 newBondTokenId = uint256(keccak256(abi.encodePacked(newIsinBytes, _BOND_VERSION)));

        uint256 issuedSupply = IDEUSSToken(_tokenAddr).totalSupply(newBondTokenId);
        assertEq(issuedSupply, BOND_ISSUE_COUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, newBondTokenId), BOND_ISSUE_COUNT);

        OfferInput memory offerInput = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: newBondTokenId,
            totalAmount: BOND_ISSUE_COUNT,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });

        uint256 offerId = _executeViaWalletAndReadOfferId(
            _issuerWallet,
            delegate,
            _marketplace,
            abi.encodeWithSelector(IMarketplace.registerOffer.selector, offerInput)
        );

        Offer memory offer = _getOffer(offerId);
        assertEq(offer.owner, _issuerWallet);
        assertEq(offer.amounts.available, BOND_ISSUE_COUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, newBondTokenId), BOND_ISSUE_COUNT);

        uint256 dealId = _acceptOffer(offerId, BOND_ISSUE_COUNT, _buyerWallet);

        _resolvePayment(dealId, true);

        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, newBondTokenId), BOND_ISSUE_COUNT);
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_escrowManager, newBondTokenId), 0);

        Deal memory deal = _getDeal(dealId);
        assertEq(uint8(deal.status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
        test_e2e_policy_revocation_blocks_further_wallet_execution
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. issuerOwner grants delegate ISSUE + OFFER roles and matching operation roles.
     *   2. Delegate successfully issues a bond and registers an offer (proves access works).
     *   3. issuerOwner revokes the OFFER user-role and its operation-role mapping.
     *   4. Delegate can still issue but policy no longer authorizes registerOffer.
     *   5. issuerOwner registers the second offer and completes a full settlement.
     *
     * Purpose: prove that policy revocation is immediately effective and that a previously
     *          authorised delegate loses revoked capabilities while business flow continues.
     */
    function test_e2e_policy_revocation_blocks_further_wallet_execution() public {
        address delegate = makeAddr("revokeTestDelegate");
        vm.label(delegate, "RevokeTestDelegate");

        string memory bondA = "SK0001009901";
        string memory bondB = "SK0001009902";

        vm.prank(_publisher);
        _br.publishBond(_createBond(bondA, _issuerWallet));
        vm.prank(_publisher);
        _br.publishBond(_createBond(bondB, _issuerWallet));

        _grantWalletPolicyUserRoles(_issuerWallet, delegate, _ROLE_ISSUE_AND_OFFER);
        _grantWalletPolicyOperationRoles(_issuerWallet, _brAddr, IBondRegistry.issueBond.selector, _ROLE_ISSUE);
        _grantWalletPolicyOperationRoles(_issuerWallet, _marketplace, IMarketplace.registerOffer.selector, _ROLE_OFFER);

        _executeViaWallet(
            _issuerWallet,
            delegate,
            _brAddr,
            abi.encodeWithSelector(IBondRegistry.issueBond.selector, bondA, _BOND_VERSION, BOND_ISSUE_COUNT)
        );

        bytes12 isinA = bondA._isinToBytes12();
        uint256 tokenIdA = uint256(keccak256(abi.encodePacked(isinA, _BOND_VERSION)));
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, tokenIdA), BOND_ISSUE_COUNT);

        OfferInput memory offerA = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: tokenIdA,
            totalAmount: BOND_ISSUE_COUNT,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _executeViaWallet(
            _issuerWallet, delegate, _marketplace, abi.encodeWithSelector(IMarketplace.registerOffer.selector, offerA)
        );

        _revokeWalletPolicyUserRoles(_issuerWallet, delegate, _ROLE_OFFER);
        _revokeWalletPolicyOperationRoles(_issuerWallet, _marketplace, IMarketplace.registerOffer.selector, _ROLE_OFFER);
        assertEq(_policyRegistry.getUserRoles(_issuerWallet, delegate), _ROLE_ISSUE);
        assertEq(_policyRegistry.getOperationRoles(_issuerWallet, _marketplace, IMarketplace.registerOffer.selector), 0);

        bytes memory issueBondBData =
            abi.encodeWithSelector(IBondRegistry.issueBond.selector, bondB, _BOND_VERSION, BOND_ISSUE_COUNT);
        assertTrue(_policyRegistry.canExecute(_issuerWallet, delegate, _brAddr, 0, issueBondBData));
        _executeViaWallet(_issuerWallet, delegate, _brAddr, issueBondBData);
        bytes12 isinB = bondB._isinToBytes12();
        uint256 tokenIdB = uint256(keccak256(abi.encodePacked(isinB, _BOND_VERSION)));
        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_issuerWallet, tokenIdB), BOND_ISSUE_COUNT);

        OfferInput memory offerB = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: tokenIdB,
            totalAmount: BOND_ISSUE_COUNT,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        bytes memory registerOfferBData = abi.encodeWithSelector(IMarketplace.registerOffer.selector, offerB);
        assertFalse(_policyRegistry.canExecute(_issuerWallet, delegate, _marketplace, 0, registerOfferBData));

        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        _executeViaWallet(_issuerWallet, delegate, _marketplace, registerOfferBData);

        uint256 offerIdB =
            _executeViaWalletAndReadOfferId(_issuerWallet, _issuerOwner, _marketplace, registerOfferBData);
        Offer memory registeredOfferB = _getOffer(offerIdB);
        assertEq(registeredOfferB.owner, _issuerWallet);
        assertEq(registeredOfferB.tokenId, tokenIdB);
        assertEq(registeredOfferB.amounts.available, BOND_ISSUE_COUNT);

        uint256 dealIdB = _acceptOffer(offerIdB, BOND_ISSUE_COUNT, _buyerWallet);
        _resolvePayment(dealIdB, true);
        _settleDeal(dealIdB);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, tokenIdB), BOND_ISSUE_COUNT);
        assertEq(uint8(_getDeal(dealIdB).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
        test_e2e_selfManagedWallet_delegates_buy_and_sell_marketplace
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. A self-managed broker entity is registered with the same EOA as authority and manager.
     *   2. That company EOA creates and registers a CompanyWallet for a retail investor.
     *   3. A buy delegate is blocked from accepting an Marketplace offer before policy is granted.
     *   4. The wallet owner grants the buy delegate only the acceptOffer operation, and the delegate buys bonds.
     *   5. That buy delegate remains blocked from registering a sell offer.
     *   6. A sell delegate receives only the token operator + registerOffer operations and sells the acquired bonds.
     *   7. Revoking the buy role blocks the previously allowed acceptOffer operation.
     *
     * Purpose: prove that wallets onboarded through the self-managed company path can delegate real
     *          Marketplace buy/sell flows without giving delegates unrelated wallet powers.
     */
    function test_e2e_selfManagedWallet_delegates_buy_and_sell_marketplace() public {
        // Set up a self-managed company wallet that will trade through delegates.
        (address tradingWallet, address tradingWalletOwner) = _createSelfManagedBrokerWallet();
        address buyDelegate = makeAddr("self-managed-buy-delegate");
        address sellDelegate = makeAddr("self-managed-sell-delegate");
        // Declared at function scope because it is needed both at buy time and after revocation.
        bytes memory acceptData;

        // Buy delegate cannot accept marketplace offers before wallet policy grants the operation.
        uint256 issuerOfferId = _registerOffer();

        // @dev famous stack too deep error
        {
            acceptData =
                abi.encodeWithSelector(IMarketplace.acceptOffer.selector, issuerOfferId, _DELEGATED_TRADE_AMOUNT);

            vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
            _executeViaWallet(tradingWallet, buyDelegate, _marketplace, acceptData);

            // Grant the buy delegate only the Marketplace.acceptOffer operation.
            vm.startPrank(tradingWalletOwner);
            _policyRegistry.grantUserRoles(tradingWallet, buyDelegate, _ROLE_BUY);
            _policyRegistry.grantOperationRoles(
                tradingWallet, _marketplace, IMarketplace.acceptOffer.selector, _ROLE_BUY
            );
            vm.stopPrank();

            assertTrue(_policyRegistry.canExecute(tradingWallet, buyDelegate, _marketplace, 0, acceptData));
            uint256 buyDealId = _executeViaWalletAndReadDealId(tradingWallet, buyDelegate, _marketplace, acceptData);
            Deal memory buyDeal = _getDeal(buyDealId);
            assertEq(buyDeal.buyer, tradingWallet);
            assertEq(uint8(buyDeal.status), uint8(DealStatus.PENDING));

            _resolvePayment(buyDealId, true);
            _settleDeal(buyDealId);

            assertEq(IDEUSSToken(_tokenAddr).balanceOf(tradingWallet, _bondFTId), _DELEGATED_TRADE_AMOUNT);
        }

        // The buy delegate still cannot register a sell offer because registerOffer was not granted.
        // Sell delegate receives only the operations needed to approve escrow and register the resale offer.
        {
            OfferInput memory resaleOffer = _createDelegatedResaleOffer(_DELEGATED_TRADE_AMOUNT);
            bytes memory registerOfferData = abi.encodeWithSelector(IMarketplace.registerOffer.selector, resaleOffer);

            assertFalse(_policyRegistry.canExecute(tradingWallet, buyDelegate, _marketplace, 0, registerOfferData));
            vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
            _executeViaWallet(tradingWallet, buyDelegate, _marketplace, registerOfferData);

            bytes memory approveEscrowData = abi.encodeCall(IERC6909.setOperator, (_escrowManager, true));
            vm.startPrank(tradingWalletOwner);
            _policyRegistry.grantUserRoles(tradingWallet, sellDelegate, _ROLE_OFFER | _ROLE_TOKEN_OPERATOR);
            _policyRegistry.grantOperationRoles(
                tradingWallet, _marketplace, IMarketplace.registerOffer.selector, _ROLE_OFFER
            );
            _policyRegistry.grantOperationRoles(
                tradingWallet, _tokenAddr, IERC6909.setOperator.selector, _ROLE_TOKEN_OPERATOR
            );
            vm.stopPrank();

            assertTrue(_policyRegistry.canExecute(tradingWallet, sellDelegate, _tokenAddr, 0, approveEscrowData));
            _executeViaWallet(tradingWallet, sellDelegate, _tokenAddr, approveEscrowData);

            assertTrue(_policyRegistry.canExecute(tradingWallet, sellDelegate, _marketplace, 0, registerOfferData));
            uint256 resaleOfferId =
                _executeViaWalletAndReadOfferId(tradingWallet, sellDelegate, _marketplace, registerOfferData);
            Offer memory registeredResaleOffer = _getOffer(resaleOfferId);
            assertEq(registeredResaleOffer.owner, tradingWallet);
            assertEq(registeredResaleOffer.amounts.available, _DELEGATED_TRADE_AMOUNT);
            assertEq(IDEUSSToken(_tokenAddr).balanceOf(tradingWallet, _bondFTId), 0);

            uint256 resaleDealId = _acceptOffer(resaleOfferId, _DELEGATED_TRADE_AMOUNT, _secondBuyerWallet);
            _resolvePayment(resaleDealId, true);
            _settleDeal(resaleDealId);

            assertEq(IDEUSSToken(_tokenAddr).balanceOf(_secondBuyerWallet, _bondFTId), _DELEGATED_TRADE_AMOUNT);
            assertEq(uint8(_getDeal(resaleDealId).status), uint8(DealStatus.SUCCESSFUL));
        }

        // Revocation removes the buy delegate's previously valid wallet execution path.
        vm.prank(tradingWalletOwner);
        _policyRegistry.revokeUserRoles(tradingWallet, buyDelegate, _ROLE_BUY);

        _assertRevokedBuyRoleBlocksAccept(tradingWallet, buyDelegate, issuerOfferId);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_walletPolicyAdmin_grantsAndRevokes_realBuyExecution
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _buyerOwner grants a delegated policy admin for _buyerWallet.
     *   2. The policy admin grants a buy delegate the acceptOffer operation.
     *   3. The buy delegate accepts and settles a real Marketplace offer through CompanyWallet.execute.
     *   4. The policy admin revokes the user role.
     *   5. The same delegate can no longer accept from the still-open offer.
     *
     * Purpose: prove delegated policy admins can manage wallet permissions end-to-end
     *          and that their revocations affect real marketplace execution.
     */
    function test_e2e_walletPolicyAdmin_grantsAndRevokes_realBuyExecution() public {
        address policyAdmin = makeAddr("wallet-policy-admin");
        address buyDelegate = makeAddr("wallet-policy-admin-buy-delegate");
        uint256 offerId = _registerOffer();
        bytes memory acceptData =
            abi.encodeWithSelector(IMarketplace.acceptOffer.selector, offerId, _DELEGATED_TRADE_AMOUNT);

        vm.prank(_buyerOwner);
        _policyRegistry.grantWalletPolicyAdmin(_buyerWallet, policyAdmin);
        assertTrue(_policyRegistry.isWalletPolicyAdmin(_buyerWallet, policyAdmin), "policy admin not active");

        vm.startPrank(policyAdmin);
        _policyRegistry.grantUserRoles(_buyerWallet, buyDelegate, _ROLE_BUY);
        _policyRegistry.grantOperationRoles(_buyerWallet, _marketplace, IMarketplace.acceptOffer.selector, _ROLE_BUY);
        vm.stopPrank();

        assertTrue(_policyRegistry.canExecute(_buyerWallet, buyDelegate, _marketplace, 0, acceptData));
        uint256 dealId = _executeViaWalletAndReadDealId(_buyerWallet, buyDelegate, _marketplace, acceptData);
        _resolvePayment(dealId, true);
        _settleDeal(dealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _DELEGATED_TRADE_AMOUNT);

        vm.prank(policyAdmin);
        _policyRegistry.revokeUserRoles(_buyerWallet, buyDelegate, _ROLE_BUY);

        assertFalse(_policyRegistry.canExecute(_buyerWallet, buyDelegate, _marketplace, 0, acceptData));
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        _executeViaWallet(_buyerWallet, buyDelegate, _marketplace, acceptData);
    }

    /*//////////////////////////////////////////////////////////////
      test_e2e_walletOwnershipTransfer_invalidatesOldPolicyEpoch_thenNewOwnerRegrants
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. _buyerOwner grants a buy delegate the acceptOffer operation.
     *   2. The delegate buys once through _buyerWallet.
     *   3. _buyerOwner transfers wallet ownership, advancing the policy epoch.
     *   4. The old delegate grant is no longer effective.
     *   5. The new owner grants the same operation in the new epoch and the delegate can buy again.
     *
     * Purpose: prove CompanyWallet ownership changes invalidate previous
     *          PolicyRegistry permissions in real marketplace execution.
     */
    function test_e2e_walletOwnershipTransfer_invalidatesOldPolicyEpoch_thenNewOwnerRegrants() public {
        address buyDelegate = makeAddr("epoch-buy-delegate");
        address newBuyerOwner = makeAddr("new-buyer-wallet-owner");
        uint256 offerId = _registerOffer();
        bytes memory acceptData =
            abi.encodeWithSelector(IMarketplace.acceptOffer.selector, offerId, _DELEGATED_TRADE_AMOUNT);

        vm.startPrank(_buyerOwner);
        _policyRegistry.grantUserRoles(_buyerWallet, buyDelegate, _ROLE_BUY);
        _policyRegistry.grantOperationRoles(_buyerWallet, _marketplace, IMarketplace.acceptOffer.selector, _ROLE_BUY);
        vm.stopPrank();

        uint256 firstDealId = _executeViaWalletAndReadDealId(_buyerWallet, buyDelegate, _marketplace, acceptData);

        vm.prank(_buyerOwner);
        CompanyWallet(payable(_buyerWallet)).transferOwnership(newBuyerOwner);

        assertEq(CompanyWallet(payable(_buyerWallet)).owner(), newBuyerOwner, "owner not transferred");
        assertEq(CompanyWallet(payable(_buyerWallet)).ownershipEpoch(), 2, "epoch not advanced");
        assertEq(_policyRegistry.getUserRoles(_buyerWallet, buyDelegate), 0, "old user roles leaked");
        assertFalse(_policyRegistry.canExecute(_buyerWallet, buyDelegate, _marketplace, 0, acceptData));

        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        _executeViaWallet(_buyerWallet, buyDelegate, _marketplace, acceptData);

        vm.startPrank(newBuyerOwner);
        _policyRegistry.grantUserRoles(_buyerWallet, buyDelegate, _ROLE_BUY);
        _policyRegistry.grantOperationRoles(_buyerWallet, _marketplace, IMarketplace.acceptOffer.selector, _ROLE_BUY);
        vm.stopPrank();

        assertTrue(_policyRegistry.canExecute(_buyerWallet, buyDelegate, _marketplace, 0, acceptData));
        uint256 secondDealId = _executeViaWalletAndReadDealId(_buyerWallet, buyDelegate, _marketplace, acceptData);

        _resolvePayment(firstDealId, true);
        _settleDeal(firstDealId);
        _resolvePayment(secondDealId, true);
        _settleDeal(secondDealId);

        assertEq(IDEUSSToken(_tokenAddr).balanceOf(_buyerWallet, _bondFTId), _DELEGATED_TRADE_AMOUNT * 2);
        assertEq(uint8(_getDeal(firstDealId).status), uint8(DealStatus.SUCCESSFUL));
        assertEq(uint8(_getDeal(secondDealId).status), uint8(DealStatus.SUCCESSFUL));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createSelfManagedBrokerWallet() internal returns (address tradingWallet, address tradingWalletOwner) {
        vm.prank(_erAdmin);
        _er.defineEntityType(_BROKER_ENTITY_TYPE, bytes32("BROKER_E2E"), 0);

        vm.prank(_adminID);
        IMarketplace(_marketplace).setAllowedEntityType(_BROKER_ENTITY_TYPE, true);

        address companyEOA = makeAddr("self-managed-market-company");
        bytes32 entityId = keccak256(abi.encodePacked("self-managed-market", companyEOA));

        address[] memory managers = new address[](1);
        managers[0] = companyEOA;

        vm.prank(_erAdmin);
        _er.registerEntity(entityId, _BROKER_ENTITY_TYPE, "ipfs://self-managed-market", companyEOA, managers);

        tradingWalletOwner = makeAddr("self-managed-trading-wallet-owner");
        tradingWallet = _createCompanyWallet(entityId, tradingWalletOwner, companyEOA);

        _requestAndAcceptWalletAccountRegistration(
            companyEOA, tradingWallet, entityId, tradingWalletOwner, _ROLE_BUY | _ROLE_OFFER
        );
    }

    function _createDelegatedResaleOffer(uint256 amount) internal view returns (OfferInput memory) {
        return OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _bondFTId,
            totalAmount: amount,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: block.timestamp + OFFER_EXPIRY,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
    }

    function _encodeAcceptOfferData(uint256 offerId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IMarketplace.acceptOffer.selector, offerId, _DELEGATED_TRADE_AMOUNT);
    }

    function _assertRevokedBuyRoleBlocksAccept(address tradingWallet, address buyDelegate, uint256 issuerOfferId)
        internal
    {
        bytes memory acceptData = _encodeAcceptOfferData(issuerOfferId);

        assertFalse(_policyRegistry.canExecute(tradingWallet, buyDelegate, _marketplace, 0, acceptData));
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        _executeViaWallet(tradingWallet, buyDelegate, _marketplace, acceptData);
    }

    function _executeViaWalletAndReadOfferId(address wallet_, address caller_, address target_, bytes memory data_)
        internal
        returns (uint256 offerId)
    {
        vm.recordLogs();
        _executeViaWallet(wallet_, caller_, target_, data_);
        return _lastRegisteredOfferId();
    }

    function _executeViaWalletAndReadDealId(address wallet_, address caller_, address target_, bytes memory data_)
        internal
        returns (uint256 dealId)
    {
        vm.recordLogs();
        _executeViaWallet(wallet_, caller_, target_, data_);
        return _lastCreatedDealId();
    }

    function _lastRegisteredOfferId() internal returns (uint256 offerId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (logs[i - 1].topics[0] == IMarketplace.OfferRegistered.selector) {
                return uint256(logs[i - 1].topics[1]);
            }
        }
        revert CompanyWalletPolicyE2E__OfferRegisteredEventNotFound();
    }

    function _lastCreatedDealId() internal returns (uint256 dealId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (logs[i - 1].topics[0] == IMarketplace.DealCreated.selector) {
                return uint256(logs[i - 1].topics[2]);
            }
        }
        revert CompanyWalletPolicyE2E__DealCreatedEventNotFound();
    }
}

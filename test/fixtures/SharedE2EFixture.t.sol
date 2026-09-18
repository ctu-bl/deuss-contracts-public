// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {MarketplaceFixture} from "./MarketplaceFixture.t.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {
    CounterOfferInput,
    DealStatus,
    OfferInput,
    PaymentResolutionInput,
    SaleMode
} from "src/marketplace/MarketStructs.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";

/**
 * @title SharedE2EFixture
 * @notice Shared fixture for branch E2E tests, aligned with the current MarketplaceFixture setup.
 */
contract SharedE2EFixture is MarketplaceFixture {
    /*//////////////////////////////////////////////////////////////
                                ACTORS
    //////////////////////////////////////////////////////////////*/

    address internal _issuerOwner;
    address internal _issuerWallet;
    address internal _buyerOwner;
    address internal _buyerWallet;
    address internal _secondBuyerOwner;
    address internal _secondBuyerWallet;
    address internal _marketAdmin;

    /*//////////////////////////////////////////////////////////////
                            CONTRACT HANDLES
    //////////////////////////////////////////////////////////////*/

    PolicyRegistry internal _policyRegistry;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant OFFER_LOT = MIN_AMOUNT;
    uint256 public constant OFFER_UNIT_PRICE = UNIT_PRICE;
    bytes32 private constant _NO_PREDECESSOR = bytes32(0);

    /*//////////////////////////////////////////////////////////////
                              SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();

        _issuerWallet = _company;
        _issuerOwner = ICompanyWallet(_issuerWallet).owner();
        _buyerOwner = makeAddr("buyerOwner");
        _secondBuyerOwner = makeAddr("secondBuyerOwner");
        _marketAdmin = _adminID;
        _policyRegistry = PolicyRegistry(_suite.registries.walletPolicyRegistry);

        (_buyerWallet,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, _buyerOwner);
        (_secondBuyerWallet,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, _secondBuyerOwner);

        vm.label(_issuerWallet, "IssuerWallet");
        vm.label(_buyerWallet, "BuyerWallet");
        vm.label(_secondBuyerWallet, "SecondBuyerWallet");

        _approveEscrowOperator(_issuerWallet);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEREST DISCOVERY HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerOffer() internal returns (uint256 offerId) {
        offerId = _registerOfferAsCompany();
    }

    function _registerInterestDiscoveryOffer(uint256 minSaleUnits) internal returns (uint256 offerId) {
        OfferInput memory input = OfferInput({
            tokenAddress: _tokenAddr,
            tokenId: _bondFTId,
            totalAmount: BOND_ISSUE_COUNT,
            lot: OFFER_LOT,
            unitPrice: OFFER_UNIT_PRICE,
            currency: BOND_CURRENCY_BYTES3,
            expiry: block.timestamp + OFFER_EXPIRY,
            allowCounterOffers: false,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.INTEREST_DISCOVERY,
            minSaleUnits: minSaleUnits
        });

        vm.prank(_issuerWallet);
        offerId = Marketplace(_marketplace).registerOffer(input);
    }

    function _expressInterest(uint256 offerId, uint256 amount, address investor) internal returns (uint256 interestId) {
        vm.prank(investor);
        interestId = Marketplace(_marketplace).expressInterest(offerId, amount);
    }

    function _activateInterest(uint256 interestId, address caller) internal returns (uint256 dealId) {
        vm.prank(caller);
        dealId = Marketplace(_marketplace).activateInterest(interestId);
    }

    function _closeExpiredInterests(uint256 offerId, uint256[] memory interestIds, address caller) internal {
        vm.prank(caller);
        Marketplace(_marketplace).closeExpiredInterests(offerId, interestIds);
    }

    function _resolvePayment(uint256 dealId, bool paid) internal {
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayment(dealId, paid);
    }

    function _resolvePayments(PaymentResolutionInput[] memory resolutions) internal {
        vm.prank(_paymentProvider);
        Marketplace(_marketplace).resolvePayments(resolutions);
    }

    function _settleDeal(uint256 dealId) internal {
        Marketplace(_marketplace).settleDeal(dealId);
    }

    function _initiateDispute(uint256 dealId, address buyer) internal {
        vm.prank(buyer);
        Marketplace(_marketplace).initiateDispute(dealId);
    }

    function _resolveDisputeID(uint256 dealId, DealStatus status) internal {
        vm.prank(_arbitrator);
        Marketplace(_marketplace).resolveDispute(dealId, status);
    }

    function _cancelOffer(uint256 offerId, address seller) internal {
        vm.prank(seller);
        Marketplace(_marketplace).cancelOffer(offerId);
    }

    function _withdrawAvailable(uint256 offerId, address seller) internal {
        vm.prank(seller);
        Marketplace(_marketplace).withdrawAvailable(offerId);
    }

    function _approveEscrowOperator(address owner_) internal {
        _approveEscrowManagerAsOperator(owner_);
    }

    /*//////////////////////////////////////////////////////////////
                      ORDERBOOK MARKETPLACE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _placeSellOrder(bytes12 isin, uint256 amount, uint256 price, address seller)
        internal
        returns (uint256 orderId)
    {
        (isin);
        address[] memory noFilter = new address[](0);
        vm.prank(seller);
        orderId = OrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _bondFTId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: noFilter,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    function _placeBuyOrder(bytes12 isin, uint256 amount, uint256 price, address buyer)
        internal
        returns (uint256 orderId)
    {
        (isin);
        address[] memory noFilter = new address[](0);
        vm.prank(buyer);
        orderId = OrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _bondFTId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: noFilter,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function _markTradePaid(uint256 tradeId) internal {
        vm.prank(_paymentProvider);
        OrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
    }

    function _settleTrade(uint256 tradeId) internal {
        OrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPANY WALLET POLICY HELPERS
    //////////////////////////////////////////////////////////////*/

    function _grantWalletPolicyUserRoles(address wallet_, address delegate_, uint256 roles_) internal {
        vm.prank(ICompanyWallet(wallet_).owner());
        _policyRegistry.grantUserRoles(wallet_, delegate_, roles_);
    }

    function _grantWalletPolicyOperationRoles(address wallet_, address target_, bytes4 selector_, uint256 roles_)
        internal
    {
        vm.prank(ICompanyWallet(wallet_).owner());
        _policyRegistry.grantOperationRoles(wallet_, target_, selector_, roles_);
    }

    function _executeViaWallet(address wallet_, address caller_, address target_, bytes memory data_) internal {
        vm.prank(caller_);
        ICompanyWallet(wallet_).execute(target_, 0, data_);
    }

    function _revokeWalletPolicyUserRoles(address wallet_, address delegate_, uint256 roles_) internal {
        vm.prank(ICompanyWallet(wallet_).owner());
        _policyRegistry.revokeUserRoles(wallet_, delegate_, roles_);
    }

    function _revokeWalletPolicyOperationRoles(address wallet_, address target_, bytes4 selector_, uint256 roles_)
        internal
    {
        vm.prank(ICompanyWallet(wallet_).owner());
        _policyRegistry.revokeOperationRoles(wallet_, target_, selector_, roles_);
    }

    /*//////////////////////////////////////////////////////////////
                    COUNTER-OFFER HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createCounterOffer(uint256 offerId, uint256 amount, uint256 unitPrice, uint256 expiry, address buyer)
        internal
        returns (uint256 dealId)
    {
        CounterOfferInput memory input =
            CounterOfferInput({offerId: offerId, expiry: expiry, amount: amount, unitPrice: unitPrice});
        vm.prank(buyer);
        dealId = Marketplace(_marketplace).createCounterOffer(input);
    }

    function _resolveCounterOffer(uint256 dealId, bool accepted) internal {
        vm.prank(_issuerWallet);
        Marketplace(_marketplace).resolveCounterOffer(dealId, accepted);
    }

    function _cancelCounterOffer(uint256 dealId, address canceller) internal {
        vm.prank(canceller);
        Marketplace(_marketplace).cancelCounterOffer(dealId);
    }

    /*//////////////////////////////////////////////////////////////
                    ORDERBOOK EXTENDED HELPERS
    //////////////////////////////////////////////////////////////*/

    function _placeSellOrderWithMinMatch(bytes12 isin, uint256 amount, uint256 price, uint256 minMatch, address seller)
        internal
        returns (uint256 orderId)
    {
        (isin);
        address[] memory noFilter = new address[](0);
        vm.prank(seller);
        orderId = OrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _bondFTId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: minMatch,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: noFilter,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    function _markOrderbookTradeUnpaid(uint256 tradeId) internal {
        OrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                    GOVERNANCE / COMPLIANCE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setOfferFrozen(uint256 offerId, bool frozen) internal {
        vm.prank(_freezer);
        Marketplace(_marketplace).setOfferFrozen(offerId, frozen);
    }

    function _setDealFrozen(uint256 dealId, bool frozen) internal {
        vm.prank(_freezer);
        Marketplace(_marketplace).setDealFrozen(dealId, frozen);
    }

    function _seizeAvailable(uint256 offerId, address beneficiary, bytes32 reason) internal {
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeOfferEscrow(offerId, beneficiary, reason);
    }

    function _seizeDeal(uint256 dealId, address beneficiary, bytes32 reason) internal {
        vm.prank(_deployer);
        Marketplace(_marketplace).seizeDeal(dealId, beneficiary, reason);
    }

    /*//////////////////////////////////////////////////////////////
                            TIMELOCK HELPERS
    //////////////////////////////////////////////////////////////*/

    function _scheduleAndExecute(address target, bytes memory data, bytes32 salt)
        internal
        returns (bytes32 operationId)
    {
        TimelockController timelock = TimelockController(_timelockController);
        operationId = _schedule(target, data, salt);

        vm.warp(block.timestamp + timelock.getMinDelay());
        vm.prank(_timelockControllerActor);
        timelock.execute(target, 0, data, _NO_PREDECESSOR, salt);
    }

    function _schedule(address target, bytes memory data, bytes32 salt) internal returns (bytes32 operationId) {
        TimelockController timelock = TimelockController(_timelockController);
        operationId = timelock.hashOperation(target, 0, data, _NO_PREDECESSOR, salt);
        uint256 minDelay = timelock.getMinDelay();

        vm.prank(_timelockControllerActor);
        timelock.schedule(target, 0, data, _NO_PREDECESSOR, salt, minDelay);
    }

    function _grantCancellerRoleToTimelockActor() internal {
        TimelockController timelock = TimelockController(_timelockController);
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        vm.prank(_timelockControllerAdmin);
        timelock.grantRole(cancellerRole, _timelockControllerActor);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {
    BaseMockData,
    BaseMockData__InvalidBuyerIndex,
    BaseMockData__InvalidIssuerIndex,
    MockBondData,
    MockMarketData,
    MockMarketDeal
} from "./BaseMockData.s.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {Scoring} from "src/registry/BondStructs.sol";
import {DealStatus} from "src/marketplace/MarketStructs.sol";
import {EntityStatus} from "src/registry/EntityStructs.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DeployConstants as Constants} from "../DeployConstants.sol";

/**
 * @title SeedDemoData
 * @author DEUSS Team
 * @notice Single operator-facing entrypoint for seeding test data.
 *         All seed flow is implemented as internal helper methods in this script.
 */
contract SeedDemoData is BaseMockData {
    /**
     * @notice Shared context for the Orderbook seed flow, grouped into a single memory
     *         struct to keep each helper's stack frame small (coverage runs without viaIR).
     */
    struct OrderbookSeedContext {
        IOrderbookMarketplace ob;
        address token;
        uint256 tokenId;
        address sellerWallet;
        uint256 sellerKey;
        address buyerWallet;
        uint256 buyerKey;
        uint256 amount;
        uint256 price;
    }

    uint16 private constant _DEMO_SCORING_MAX_DEFAULT_PROBABILITY_BPS = 500;
    uint16 private constant _DEMO_SCORING_BASE_DEFAULT_PROBABILITY_BPS = 100;
    uint16 private constant _DEMO_SCORING_DEFAULT_PROBABILITY_STEP_BPS = 25;

    error SeedDemoData__OrderPlacedEventNotFound();

    /**
     * @notice Execute the full test seed sequence.
     */
    function run() public override {
        _ensureTestWallets();
        _ensureTestCurrencies();
        _publishTestBonds();
        _seedScoring();
        _issueTestBonds();
        _seedMarketplace();
        _seedOrderbook();
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 1 — COMPANY WALLETS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register test company entities and wallets for demo issuers and buyers.
     *         Safe to rerun — skips any entity/wallet that is already registered.
     */
    function _ensureTestWallets() internal {
        for (uint256 i; i < _bondIssuers.length; ++i) {
            _ensureEntityWallet(_bondIssuers[i].addr);
            _bondIssuerWallets.push(_getCompanyWallet(_bondIssuers[i].addr));
        }

        for (uint256 i; i < _bondBuyers.length; ++i) {
            _ensureEntityWallet(_bondBuyers[i].addr);
            _bondBuyerWallets.push(_getCompanyWallet(_bondBuyers[i].addr));
        }
    }

    /**
     * @notice Register a company entity and create a wallet for the given owner, if not
     *         already present.
     * @param owner Wallet owner address
     */
    function _ensureEntityWallet(address owner) internal {
        EntityRegistry er = EntityRegistry(_suite.registries.entityRegistry);
        IWalletFactory wf = IWalletFactory(_suite.registries.walletFactory);
        bytes32 entityId = keccak256(abi.encodePacked(owner, "company-entity"));
        bool walletExists;

        try er.getEntityAccounts(entityId) returns (address[] memory wallets) {
            walletExists = wallets.length > 0;
        } catch {
            walletExists = false;
        }

        if (walletExists) return;

        vm.startBroadcast(_admin.privateKey);
        er.registerEntity(entityId, Constants.COMPANY_ENTITY, "");
        er.setEntityStatus(entityId, EntityStatus.ENABLED, "");
        er.setEntityAuthority(entityId, _admin.addr);
        er.setEntityManager(entityId, _admin.addr, true);
        vm.stopBroadcast();

        vm.startBroadcast(_admin.privateKey);
        IWalletFactory.CreateWalletParams memory params = IWalletFactory.CreateWalletParams({
            entityId: entityId,
            walletType: Constants.COMPANY_WALLET_TYPE,
            initData: abi.encodeCall(ICompanyWallet.initialize, (owner, _suite.registries.walletPolicyRegistry))
        });
        address wallet = wf.createWallet(params);
        er.registerAccount(wallet, entityId, 0);
        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 2 — TEST CURRENCIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allowlist any currencies from the test bond dataset that are not already
     *         allowed in BondRegistry.
     */
    function _ensureTestCurrencies() internal {
        BondRegistry br = BondRegistry(_suite.registries.bondRegistry);

        vm.startBroadcast(_admin.privateKey);
        for (uint256 i; i < _bondsToDeploy.length; ++i) {
            string memory currency = _bondsToDeploy[i].bondInput.currency;
            if (!br.isCurrencyAllowed(currency)) {
                br.setAllowedCurrency(currency, true);
            }
        }
        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 3 — PUBLISH BONDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Publish all test bonds through BondRegistry using the admin operator role.
     */
    function _publishTestBonds() internal {
        BondRegistry br = BondRegistry(_suite.registries.bondRegistry);

        for (uint256 i; i < _bondsToDeploy.length; ++i) {
            MockBondData memory bond = _bondsToDeploy[i];
            uint256 issuerIndex = _issuerIndexForBond(bond);
            bond.bondInput.issuer = _bondIssuerWallets[issuerIndex];
            vm.startBroadcast(_admin.privateKey);
            br.publishBond(bond.bondInput);
            vm.stopBroadcast();
        }
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 4 — SCORING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Append one scoring record for each deployed test bond to that bond's issuer wallet.
     *         BondRegistry scoring is wallet-scoped, so each demo issuer gets its own scoring history.
     */
    function _seedScoring() internal {
        BondRegistry br = BondRegistry(_suite.registries.bondRegistry);

        vm.startBroadcast(_admin.privateKey);
        for (uint256 i; i < _bondsToDeploy.length; ++i) {
            uint256 issuerIndex = _issuerIndexForBond(_bondsToDeploy[i]);
            br.appendScoring(_bondIssuerWallets[issuerIndex], _buildScoring(i));
        }
        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 5 — ISSUE / CANCEL BONDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Issue or cancel each test bond according to its canceled flag.
     *         Admin must have CANCEL role (granted during bootstrap).
     */
    function _issueTestBonds() internal {
        BondRegistry br = BondRegistry(_suite.registries.bondRegistry);

        for (uint256 i; i < _bondsToDeploy.length; ++i) {
            MockBondData memory bond = _bondsToDeploy[i];
            uint256 issuerIndex = _issuerIndexForBond(bond);
            if (bond.canceled) {
                vm.startBroadcast(_admin.privateKey);
                br.cancelBond(bond.bondInput.isin, 1);
                vm.stopBroadcast();
            } else {
                vm.startBroadcast(_bondIssuers[issuerIndex].privateKey);
                CompanyWallet(payable(_bondIssuerWallets[issuerIndex]))
                    .execute(
                        address(br),
                        0,
                        abi.encodeWithSelector(
                            br.issueBond.selector, bond.bondInput.isin, uint8(1), bond.bondInput.maxSupply
                        )
                    );
                vm.stopBroadcast();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                       STEP 6 — OFFERS AND DEALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create test offers and deals in Marketplace.
     */
    function _seedMarketplace() internal {
        Marketplace id = Marketplace(_suite.core.marketplace);

        for (uint256 i = 0; i < _marketData.length; ++i) {
            MockMarketData memory data = _marketData[i];
            uint256 issuerIndex = _issuerIndexForMarketData(data);
            uint256 tokenId = BondRegistry(_suite.registries.bondRegistry).getTokenId(data.isin);
            data.offerInput.tokenId = tokenId;

            vm.startBroadcast(_bondIssuers[issuerIndex].privateKey);
            CompanyWallet(payable(_bondIssuerWallets[issuerIndex]))
                .execute(
                    _suite.multiToken.deussToken,
                    0,
                    abi.encodeWithSelector(
                        bytes4(keccak256("approve(address,uint256,uint256)")),
                        address(_suite.core.escrowManager),
                        tokenId,
                        data.offerInput.totalAmount
                    )
                );

            CompanyWallet(payable(_bondIssuerWallets[issuerIndex]))
                .execute(address(id), 0, abi.encodeWithSelector(id.registerOffer.selector, data.offerInput));
            vm.stopBroadcast();
            uint256 offerId = _latestMarketplaceOfferId(id);

            for (uint256 j; j < data.deals.length; ++j) {
                MockMarketDeal memory deal = data.deals[j];
                uint256 buyerIndex = _buyerIndexForDeal(deal);

                vm.startBroadcast(_bondBuyers[buyerIndex].privateKey);
                CompanyWallet(payable(_bondBuyerWallets[buyerIndex]))
                    .execute(address(id), 0, abi.encodeWithSelector(id.acceptOffer.selector, offerId, deal.amount));
                vm.stopBroadcast();
                uint256 dealId = _latestMarketplaceDealId(id);

                if (deal.targetStatus == DealStatus.PAID || deal.targetStatus == DealStatus.SUCCESSFUL) {
                    vm.startBroadcast(_admin.privateKey);
                    id.resolvePayment(dealId, true);
                    if (deal.targetStatus == DealStatus.SUCCESSFUL) {
                        id.settleDeal(dealId);
                    }
                    vm.stopBroadcast();
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            STEP 7 — ORDERBOOK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Seed a minimal Orderbook demo: one settled trade plus one cancelled order.
     */
    function _seedOrderbook() internal {
        MockBondData memory bond = _bondsToDeploy[2];
        uint256 issuerIndex = _issuerIndexForBond(bond);

        OrderbookSeedContext memory ctx = OrderbookSeedContext({
            ob: IOrderbookMarketplace(_suite.core.orderbookMarketplace),
            token: _suite.multiToken.deussToken,
            tokenId: BondRegistry(_suite.registries.bondRegistry).getTokenId(bond.bondInput.isin),
            sellerWallet: _bondIssuerWallets[issuerIndex],
            sellerKey: _bondIssuers[issuerIndex].privateKey,
            buyerWallet: _bondBuyerWallets[0],
            buyerKey: _bondBuyers[0].privateKey,
            amount: 100,
            price: 100
        });

        _seedOrderbookTrade(ctx);
        _seedOrderbookCancel(ctx);
    }

    /**
     * @notice Place crossing SELL/BUY orders, then mark the resulting trade paid and settle it.
     * @param ctx Shared orderbook seed context
     */
    function _seedOrderbookTrade(OrderbookSeedContext memory ctx) internal {
        // Seller places a SELL order; bonds are escrowed on placement.
        vm.startBroadcast(ctx.sellerKey);
        _approveBondsToEscrow(ctx.sellerWallet, ctx.token, ctx.tokenId, ctx.amount);
        uint256 sellOrderId = _placeOrder(
            ctx.ob,
            ctx.sellerWallet,
            ctx.token,
            ctx.tokenId,
            ctx.amount,
            ctx.price,
            IOrderbookMarketplace.OrderSide.SELL
        );
        vm.stopBroadcast();

        // Buyer places a crossing BUY order, which auto-creates a trade against the SELL order.
        vm.startBroadcast(ctx.buyerKey);
        _placeOrder(
            ctx.ob, ctx.buyerWallet, ctx.token, ctx.tokenId, ctx.amount, ctx.price, IOrderbookMarketplace.OrderSide.BUY
        );
        vm.stopBroadcast();
        uint256 tradeId = ctx.ob.getTradeIdsByOrderId(sellOrderId)[0];

        // Confirm the off-chain payment and settle, releasing the bonds to the buyer.
        vm.startBroadcast(_admin.privateKey);
        ctx.ob.markTradePaid(tradeId);
        ctx.ob.settleTrade(tradeId);
        vm.stopBroadcast();
    }

    /**
     * @notice Place a SELL order and cancel it to demonstrate the cancel path.
     * @param ctx Shared orderbook seed context
     */
    function _seedOrderbookCancel(OrderbookSeedContext memory ctx) internal {
        vm.startBroadcast(ctx.sellerKey);
        _approveBondsToEscrow(ctx.sellerWallet, ctx.token, ctx.tokenId, ctx.amount);
        uint256 cancelOrderId = _placeOrder(
            ctx.ob,
            ctx.sellerWallet,
            ctx.token,
            ctx.tokenId,
            ctx.amount,
            ctx.price,
            IOrderbookMarketplace.OrderSide.SELL
        );
        CompanyWallet(payable(ctx.sellerWallet))
            .execute(address(ctx.ob), 0, abi.encodeWithSelector(ctx.ob.cancelOrder.selector, cancelOrderId, address(0)));
        vm.stopBroadcast();
    }

    /**
     * @notice Approve the EscrowManager to pull bonds from a company wallet.
     * @param wallet Company wallet holding the bonds
     * @param token Multi-token contract address
     * @param tokenId Bond token id
     * @param amount Amount to approve
     */
    function _approveBondsToEscrow(address wallet, address token, uint256 tokenId, uint256 amount) internal {
        CompanyWallet(payable(wallet))
            .execute(
                token,
                0,
                abi.encodeWithSelector(
                    bytes4(keccak256("approve(address,uint256,uint256)")),
                    address(_suite.core.escrowManager),
                    tokenId,
                    amount
                )
            );
    }

    /**
     * @notice Place a fixed-price orderbook order on behalf of a company wallet.
     * @param ob Orderbook marketplace
     * @param wallet Company wallet placing the order
     * @param token Multi-token contract address
     * @param tokenId Bond token id
     * @param amount Order amount
     * @param price Fixed unit price
     * @param side BUY or SELL
     * @return orderId Id of the placed order, read from the OrderPlaced event
     */
    function _placeOrder(
        IOrderbookMarketplace ob,
        address wallet,
        address token,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        IOrderbookMarketplace.OrderSide side
    ) internal returns (uint256 orderId) {
        IOrderbookMarketplace.OrderInput memory input = IOrderbookMarketplace.OrderInput({
            tokenAddress: token,
            tokenId: tokenId,
            totalAmount: amount,
            minPrice: price,
            maxPrice: price,
            minMatchAmount: 0,
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
            traderFilterAddresses: new address[](0),
            side: side,
            expiry: 0
        });
        vm.recordLogs();
        CompanyWallet(payable(wallet))
            .execute(address(ob), 0, abi.encodeWithSelector(ob.placeOrder.selector, input, address(0)));
        orderId = _lastPlacedOrderId();
    }

    /**
     * @notice Read the order id from the most recent OrderPlaced event in the recorded logs.
     * @return orderId Id of the order that was just placed
     */
    function _lastPlacedOrderId() internal returns (uint256 orderId) {
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (logs[i - 1].topics[0] == IOrderbookMarketplace.OrderPlaced.selector) {
                return uint256(logs[i - 1].topics[1]);
            }
        }
        revert SeedDemoData__OrderPlacedEventNotFound();
    }

    /**
     * @notice Read the latest Marketplace offer id from the monotonic counter.
     * @param marketplace Marketplace instance
     * @return offerId Id of the offer that was just registered
     */
    function _latestMarketplaceOfferId(Marketplace marketplace) internal view returns (uint256 offerId) {
        (, MarketplaceStorage.Counters memory counters) = marketplace.getConfigAndCounters();
        return counters.offerCounter;
    }

    /**
     * @notice Read the latest Marketplace deal id from the monotonic counter.
     * @param marketplace Marketplace instance
     * @return dealId Id of the deal that was just created
     */
    function _latestMarketplaceDealId(Marketplace marketplace) internal view returns (uint256 dealId) {
        (, MarketplaceStorage.Counters memory counters) = marketplace.getConfigAndCounters();
        return counters.dealCounter;
    }

    /**
     * @notice Return the checked issuer index for a bond record.
     * @param bond Bond dataset entry
     * @return issuerIndex Valid issuer index
     */
    function _issuerIndexForBond(MockBondData memory bond) internal view returns (uint256 issuerIndex) {
        issuerIndex = bond.issuerIndex;
        if (
            _bondIssuerWallets.length == 0 || _bondIssuers.length == 0 || issuerIndex > _bondIssuerWallets.length - 1
                || issuerIndex > _bondIssuers.length - 1
        ) {
            revert BaseMockData__InvalidIssuerIndex(issuerIndex);
        }
    }

    /**
     * @notice Return the checked issuer index for a marketplace entry.
     * @param data Marketplace dataset entry
     * @return issuerIndex Valid issuer index
     */
    function _issuerIndexForMarketData(MockMarketData memory data) internal view returns (uint256 issuerIndex) {
        uint256 bondIndex = data.bondIndex;
        if (_bondsToDeploy.length == 0 || bondIndex > _bondsToDeploy.length - 1) {
            revert BaseMockData__InvalidIssuerIndex(bondIndex);
        }
        issuerIndex = _issuerIndexForBond(_bondsToDeploy[bondIndex]);
    }

    /**
     * @notice Return the checked buyer index for a deal record.
     * @param deal Deal dataset entry
     * @return buyerIndex Valid buyer index
     */
    function _buyerIndexForDeal(MockMarketDeal memory deal) internal view returns (uint256 buyerIndex) {
        buyerIndex = deal.buyerIndex;
        if (
            _bondBuyerWallets.length == 0 || _bondBuyers.length == 0 || buyerIndex > _bondBuyerWallets.length - 1
                || buyerIndex > _bondBuyers.length - 1
        ) {
            revert BaseMockData__InvalidBuyerIndex(buyerIndex);
        }
    }

    /**
     * @notice Build deterministic demo scoring data for a seeded bond index.
     * @param bondIndex Index in the mock bond dataset
     * @return Scoring record accepted by BondRegistry validation
     */
    function _buildScoring(uint256 bondIndex) internal view returns (Scoring memory) {
        uint64 issueDate = uint64(block.timestamp == 0 ? 1 : block.timestamp);
        uint64 expirationDate = issueDate + uint64(365 days);
        uint256 probabilityBps =
            _DEMO_SCORING_BASE_DEFAULT_PROBABILITY_BPS + (bondIndex * _DEMO_SCORING_DEFAULT_PROBABILITY_STEP_BPS);
        if (probabilityBps > _DEMO_SCORING_MAX_DEFAULT_PROBABILITY_BPS) {
            probabilityBps = _DEMO_SCORING_MAX_DEFAULT_PROBABILITY_BPS;
        }

        return Scoring({
            defaultProbabilityBps: uint16(probabilityBps),
            issueDate: issueDate,
            expirationDate: expirationDate,
            distributorId: keccak256(abi.encodePacked("DEUSS_DEMO_SCORING", bondIndex))
        });
    }
}

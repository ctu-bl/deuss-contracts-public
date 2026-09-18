// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {AssetType, OfferInput, Escrow} from "src/marketplace/MarketStructs.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {Errors} from "src/libs/Errors.sol";
import {MarketplaceFixture} from "test/fixtures/MarketplaceFixture.t.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {MockOrderbookMarketplace} from "test/mocks/MockContracts.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BondInput, CouponRateType, CouponFrequency, CouponRates} from "src/registry/BondStructs.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";
import {AccountStatus} from "src/registry/EntityStructs.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";

contract OrderbookMockERC6909 {
    mapping(address owner => mapping(uint256 tokenId => uint256 amount)) internal _balances;

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _balances[to][tokenId] += amount;
    }

    function balanceOf(address owner, uint256 tokenId) external view returns (uint256) {
        return _balances[owner][tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId, uint256 amount) external returns (bool) {
        uint256 balance = _balances[from][tokenId];
        if (balance < amount) {
            return false;
        }
        unchecked {
            _balances[from][tokenId] = balance - amount;
            _balances[to][tokenId] += amount;
        }
        return true;
    }
}

contract OrderbookMarketplaceStorageHarness is OrderbookMarketplace {
    function exposedOrderbookMarketplaceStorageLocation() external pure returns (bytes32) {
        return _ORDERBOOK_MARKETPLACE_STORAGE_LOCATION;
    }
}

contract OrderbookMarketplaceTest is MarketplaceFixture {
    using StringExtensions for string;

    // Shared batch-order test constants
    string internal constant _SECOND_ISIN = "SK0001002060";
    bytes3 internal constant _CURRENCY_USD = bytes3("USD");
    uint256 internal constant _SECOND_BOND_NOMINAL_VALUE = 2_000;
    uint256 internal constant _SECOND_COUPON_RATE = 700;
    bytes32 internal constant _ORDERBOOK_ESCROW_ID_BY_ORDER_ID_SLOT =
        0x79ea8b011a47713354185639eb0111ae61d66b4fa2e4fcda0a25dd7bc2691112;

    UpgradeableBeacon internal _orderbookMarketplaceBeacon;
    address internal _orderbookAdmin;
    address internal _buyer;
    address internal _seller;
    address internal _paymentHandler;
    uint256 internal _tokenId;

    function setUp() public override {
        super.setUp();

        _orderbookMarketplaceBeacon = UpgradeableBeacon(_suite.core.orderbookMarketplaceBeacon);
        _orderbookAdmin = makeAddr("orderbookAdmin");
        _tokenId = _bondFTId;

        (_buyer,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("buyer"), 0);
        (_seller,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("seller"), 0);

        uint256 adminRole = OrderbookMarketplace(_orderbookMarketplace).ADMIN();

        _grantRoles(_orderbookMarketplace, _orderbookAdmin, adminRole);

        _paymentHandler = makeAddr("paymentHandler");
        uint256 paymentHandlerRole = OrderbookMarketplace(_orderbookMarketplace).PAYMENT_HANDLER();

        _grantRoles(_orderbookMarketplace, _paymentHandler, paymentHandlerRole);
    }

    function _orderbookEscrowIdByOrderId(uint256 orderId) internal view returns (uint256 escrowId) {
        bytes32 slot = keccak256(abi.encode(orderId, _ORDERBOOK_ESCROW_ID_BY_ORDER_ID_SLOT));
        return _loadUint(_orderbookMarketplace, slot);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        OrderbookMarketplaceStorageHarness harness = new OrderbookMarketplaceStorageHarness();
        bytes32 storageLocation = harness.exposedOrderbookMarketplaceStorageLocation();

        // solhint-disable-next-line gas-small-strings
        assertEq(storageLocation, _erc7201Location("deuss.orderbookMarketplace.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    function test_namespacedState_success_usesErc7201Storage() public {
        // solhint-disable-next-line gas-small-strings
        bytes32 root = _erc7201Location("deuss.orderbookMarketplace.storage");
        OrderbookMarketplace ob = OrderbookMarketplace(_orderbookMarketplace);

        // Dependency scalars: assetManager (0), entityRegistry (1), escrowManager (2).
        assertEq(_loadAddress(_orderbookMarketplace, root), ob.assetManager());
        assertEq(_loadAddress(_orderbookMarketplace, _slotOffset(root, 1)), ob.entityRegistry());
        assertEq(_loadAddress(_orderbookMarketplace, _slotOffset(root, 2)), ob.escrowManager());

        // `delegations` is field offset 12; nested slot = keccak(delegate, keccak(trader, root + 12)).
        address trader = makeAddr("ob-trader");
        address delegate = makeAddr("ob-delegate");
        vm.prank(trader);
        ob.setDelegate(delegate, true);
        bytes32 entrySlot = keccak256(abi.encode(delegate, keccak256(abi.encode(trader, _slotOffset(root, 12)))));
        assertEq(uint256(vm.load(_orderbookMarketplace, entrySlot)), 1);

        // Isolation: the pre-namespace sequential slot (12) derivation for the same keys holds nothing.
        bytes32 legacySlot = keccak256(abi.encode(delegate, keccak256(abi.encode(trader, uint256(12)))));
        assertEq(vm.load(_orderbookMarketplace, legacySlot), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                                upgradeTo
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_success_beaconOwner() public {
        address newImpl = address(new MockOrderbookMarketplace());

        _timelockOp(
            address(_orderbookMarketplaceBeacon),
            abi.encodeWithSelector(_orderbookMarketplaceBeacon.upgradeTo.selector, newImpl)
        );

        assertEq(MockOrderbookMarketplace(_orderbookMarketplace).VERSION(), 2);
        assertTrue(MockOrderbookMarketplace(_orderbookMarketplace).isNewVersion());
    }

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockOrderbookMarketplace());
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, notOwner));
        _orderbookMarketplaceBeacon.upgradeTo(newImpl);
    }

    /*//////////////////////////////////////////////////////////////
                            setAssetManager
    //////////////////////////////////////////////////////////////*/

    function test_setAssetManager_success() public {
        address newAssetManager = makeAddr("newAssetManager");

        vm.expectEmit();
        emit IOrderbookMarketplace.AssetManagerSet(newAssetManager);

        vm.prank(_orderbookAdmin);
        IOrderbookMarketplace(_orderbookMarketplace).setAssetManager(newAssetManager);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).assetManager(), newAssetManager);
    }

    function test_setAssetManager_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        address newAssetManager = makeAddr("newAssetManager");

        vm.prank(notAdmin);
        vm.expectRevert();
        IOrderbookMarketplace(_orderbookMarketplace).setAssetManager(newAssetManager);
    }

    function test_setAssetManager_reverts_zeroAddress() public {
        vm.prank(_orderbookAdmin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setAssetManager(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        setEntityRegistry
    //////////////////////////////////////////////////////////////*/

    function test_setEntityRegistry_success() public {
        address newRegistry = makeAddr("newEntityRegistry");

        vm.expectEmit();
        emit IOrderbookMarketplace.EntityRegistrySet(newRegistry);

        vm.prank(_orderbookAdmin);
        IOrderbookMarketplace(_orderbookMarketplace).setEntityRegistry(newRegistry);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).entityRegistry(), newRegistry);
    }

    function test_setEntityRegistry_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        address newRegistry = makeAddr("newEntityRegistry");

        vm.prank(notAdmin);
        vm.expectRevert();
        IOrderbookMarketplace(_orderbookMarketplace).setEntityRegistry(newRegistry);
    }

    function test_setEntityRegistry_reverts_zeroAddress() public {
        vm.prank(_orderbookAdmin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setEntityRegistry(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            setEscrowManager
    //////////////////////////////////////////////////////////////*/

    function test_setEscrowManager_success() public {
        address newEscrowManager = makeAddr("newEscrowManager");

        vm.expectEmit();
        emit IOrderbookMarketplace.EscrowManagerSet(newEscrowManager);

        vm.prank(_orderbookAdmin);
        IOrderbookMarketplace(_orderbookMarketplace).setEscrowManager(newEscrowManager);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).escrowManager(), newEscrowManager);
    }

    function test_setEscrowManager_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        address newEscrowManager = makeAddr("newEscrowManager");

        vm.prank(notAdmin);
        vm.expectRevert();
        IOrderbookMarketplace(_orderbookMarketplace).setEscrowManager(newEscrowManager);
    }

    function test_setEscrowManager_reverts_zeroAddress() public {
        vm.prank(_orderbookAdmin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setEscrowManager(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                placeOrder
    //////////////////////////////////////////////////////////////*/

    function test_placeOrder_success_buyOrderNoMatch() public {
        uint256 buyOrderId;
        {
            // ACT
            vm.startPrank(_buyer);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                1,
                _tokenId,
                _buyer,
                _tokenAddr,
                1,
                1,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.BUY,
                0
            );
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 1,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(buyOrderId, 1);
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 1);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
            assertEq(tradeIds.length, 0);
        }
    }

    function test_placeOrder_success_buyOrderMatchPartial() public {
        // sellAmount=100, buyAmount=40, matchedAmount=40, unitPrice=1, expectedBuyOrderId=2
        uint256 sellOrderId;
        {
            // PREPARE: seller places SELL order first
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
            _approveEscrowManagerAsOperator(_seller);
            vm.prank(_seller);
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
        }

        uint256 buyOrderId;
        {
            // ACT: buyer places BUY order that partially consumes the SELL order
            vm.startPrank(_buyer);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(2, sellOrderId, _tokenId, _tokenAddr, _buyer, _seller, 40, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                2,
                _tokenId,
                _buyer,
                _tokenAddr,
                40,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.BUY,
                0
            );
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 40,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(buyOrderId, 2);
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 60); // 100 - 40
            assertEq(sellOrder.amounts.inDeals, 40);
        }
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 0);
            assertEq(buyOrder.amounts.inDeals, 40);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
            assertEq(tradeIds.length, 1);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 40);
        }
    }

    function test_placeOrder_success_buyOrderMatchExact() public {
        // sellAmount=100, buyAmount=100, matchedAmount=100, unitPrice=1, expectedBuyOrderId=2
        uint256 sellOrderId;
        {
            // PREPARE: seller places SELL order first
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
            _approveEscrowManagerAsOperator(_seller);
            vm.prank(_seller);
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
        }

        uint256 buyOrderId;
        {
            // ACT: buyer places BUY order that exactly matches the SELL order
            vm.startPrank(_buyer);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(2, sellOrderId, _tokenId, _tokenAddr, _buyer, _seller, 100, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                2,
                _tokenId,
                _buyer,
                _tokenAddr,
                100,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.BUY,
                0
            );
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(buyOrderId, 2);
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 0);
            assertEq(sellOrder.amounts.inDeals, 100);
        }
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 0);
            assertEq(buyOrder.amounts.inDeals, 100);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
            assertEq(tradeIds.length, 1);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 100);
        }
    }

    // solhint-disable function-max-lines
    function test_placeOrder_success_buyOrderMatchMultiple() public {
        // sellAmount=50, buyAmount=100, matchedAmount=100, unitPrice=1, expectedBuyOrderId=3
        uint256 sellOrderId;
        uint256 otherSellOrderId;
        {
            // PREPARE: seller places 2 SELL orders first
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100); // sellAmount * 2
            _approveEscrowManagerAsOperator(_seller);
            vm.startPrank(_seller);
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 50,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            otherSellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 50,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        uint256 buyOrderId;
        {
            // ACT: buyer places BUY order that exactly matches both SELL orders combined
            vm.startPrank(_buyer);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(3, sellOrderId, _tokenId, _tokenAddr, _buyer, _seller, 50, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(3, otherSellOrderId, _tokenId, _tokenAddr, _buyer, _seller, 50, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                3,
                _tokenId,
                _buyer,
                _tokenAddr,
                100,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.BUY,
                0
            );
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(buyOrderId, 3);
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 0);
            assertEq(sellOrder.amounts.inDeals, 50);
        }
        {
            IOrderbookMarketplace.Order memory otherSellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(otherSellOrderId);
            assertEq(otherSellOrder.amounts.available, 0);
            assertEq(otherSellOrder.amounts.inDeals, 50);
        }
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 0);
            assertEq(buyOrder.amounts.inDeals, 100);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
            assertEq(tradeIds.length, 2);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 50);
            IOrderbookMarketplace.Trade memory otherTrade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
            assertEq(otherTrade.tokenAddress, _tokenAddr);
            assertEq(otherTrade.amount, 50);
        }
    }
    // solhint-enable function-max-lines

    function test_placeOrder_success_sellOrderNoMatch() public {
        // PREPARE: transfer tokens to seller and approve EscrowManager
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 1);
        _approveEscrowManagerAsOperator(_seller);

        uint256 sellOrderId;
        {
            // ACT
            vm.startPrank(_seller);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                1,
                _tokenId,
                _seller,
                _tokenAddr,
                1,
                1,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.SELL,
                0
            );
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 1,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(sellOrderId, 1);
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 1);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
            assertEq(tradeIds.length, 0);
        }
    }

    function test_placeOrder_success_sellOrderMatchPartial() public {
        // buyAmount=100, sellAmount=40, matchedAmount=40, unitPrice=1, expectedSellOrderId=2
        uint256 buyOrderId;
        {
            // PREPARE: buyer places BUY order first
            vm.prank(_buyer);
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );

            // PREPARE: transfer tokens to seller and approve
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 40);
            _approveEscrowManagerAsOperator(_seller);
        }

        uint256 sellOrderId;
        {
            // ACT: seller places SELL order that partially consumes the BUY order
            vm.startPrank(_seller);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(buyOrderId, 2, _tokenId, _tokenAddr, _buyer, _seller, 40, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                2,
                _tokenId,
                _seller,
                _tokenAddr,
                40,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.SELL,
                0
            );
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 40,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(sellOrderId, 2);
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 60); // 100 - 40
            assertEq(buyOrder.amounts.inDeals, 40);
        }
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 0);
            assertEq(sellOrder.amounts.inDeals, 40);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
            assertEq(tradeIds.length, 1);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 40);
        }
    }

    function test_placeOrder_success_sellOrderMatchExact() public {
        // buyAmount=100, sellAmount=100, matchedAmount=100, unitPrice=1, expectedSellOrderId=2
        uint256 buyOrderId;
        {
            // PREPARE: buyer places BUY order first
            vm.prank(_buyer);
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );

            // PREPARE: transfer tokens to seller and approve
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
            _approveEscrowManagerAsOperator(_seller);
        }

        uint256 sellOrderId;
        {
            // ACT: seller places SELL order that exactly matches the BUY order
            vm.startPrank(_seller);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(buyOrderId, 2, _tokenId, _tokenAddr, _buyer, _seller, 100, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                2,
                _tokenId,
                _seller,
                _tokenAddr,
                100,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.SELL,
                0
            );
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(sellOrderId, 2);
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 0);
            assertEq(buyOrder.amounts.inDeals, 100);
        }
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 0);
            assertEq(sellOrder.amounts.inDeals, 100);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
            assertEq(tradeIds.length, 1);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 100);
        }
    }

    // solhint-disable function-max-lines
    function test_placeOrder_success_sellOrderMatchMultiple() public {
        // buyAmount=50, sellAmount=100, matchedAmount=100, unitPrice=1, expectedSellOrderId=3
        uint256 buyOrderId;
        uint256 otherBuyOrderId;
        {
            // PREPARE: buyer places 2 BUY orders first
            vm.startPrank(_buyer);
            buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 50,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            otherBuyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 50,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();

            // PREPARE: transfer tokens to seller and approve
            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
            _approveEscrowManagerAsOperator(_seller);
        }

        uint256 sellOrderId;
        {
            // ACT: seller places SELL order that exactly matches both BUY orders combined
            vm.startPrank(_seller);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(buyOrderId, 3, _tokenId, _tokenAddr, _buyer, _seller, 50, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.TradeExecuted(otherBuyOrderId, 3, _tokenId, _tokenAddr, _buyer, _seller, 50, 1);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                3,
                _tokenId,
                _seller,
                _tokenAddr,
                100,
                0,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.SELL,
                0
            );
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: 0
                }),
                    address(0)
                );
            vm.stopPrank();
        }

        // ASSERT
        assertEq(sellOrderId, 3);
        {
            IOrderbookMarketplace.Order memory buyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
            assertEq(buyOrder.amounts.available, 0);
            assertEq(buyOrder.amounts.inDeals, 50);
        }
        {
            IOrderbookMarketplace.Order memory otherBuyOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(otherBuyOrderId);
            assertEq(otherBuyOrder.amounts.available, 0);
            assertEq(otherBuyOrder.amounts.inDeals, 50);
        }
        {
            IOrderbookMarketplace.Order memory sellOrder =
                IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
            assertEq(sellOrder.amounts.available, 0);
            assertEq(sellOrder.amounts.inDeals, 100);
        }
        {
            uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
            assertEq(tradeIds.length, 2);
            IOrderbookMarketplace.Trade memory trade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
            assertEq(trade.tokenAddress, _tokenAddr);
            assertEq(trade.amount, 50);
            IOrderbookMarketplace.Trade memory otherTrade =
                IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
            assertEq(otherTrade.tokenAddress, _tokenAddr);
            assertEq(otherTrade.amount, 50);
        }
    }
    // solhint-enable function-max-lines

    function test_placeOrder_success_buyOrderSortedByPrice() public {
        // PREPARE: create 2 buy orders
        uint256 amount = 10;
        uint256 highPrice = 100;
        uint256 lowPrice = 50;
        vm.startPrank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT & ASSERT: orders are sorted
        (IOrderbookMarketplace.Order[] memory buyOrders,) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 2);
        assertEq(buyOrders[0].minPrice, highPrice);
        assertEq(buyOrders[1].minPrice, lowPrice);
    }

    function test_placeOrder_success_sellOrderSortedByPrice() public {
        // PREPARE: create 2 sell orders
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;
        uint256 highPrice = 100;
        uint256 lowPrice = 50;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.startPrank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT & ASSERT: orders are sorted
        (, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(sellOrders.length, 2);
        assertEq(sellOrders[0].minPrice, lowPrice);
        assertEq(sellOrders[1].minPrice, highPrice);
    }

    function test_placeOrder_samePriceOrdersMatchedFifo() public {
        // PREPARE: seller places two sell orders at the same price
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;
        uint256 unitPrice = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.startPrank(_seller);
        uint256 firstSellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        uint256 secondSellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT: buyer places a buy order that should match the oldest order first (FIFO)
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: oldest order should be matched first (FIFO)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.sellOrderId, firstSellOrderId);
        IOrderbookMarketplace.Order memory firstSellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(firstSellOrderId);
        IOrderbookMarketplace.Order memory secondSellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(secondSellOrderId);
        assertEq(firstSellOrder.amounts.available, 0);
        assertEq(secondSellOrder.amounts.available, amount);
    }

    function test_placeOrder_success_buyOrderNoMatchPriceTooLow() public {
        // PREPARE: seller places sell order
        uint256 amount = 10;
        uint256 sellPrice = 100;
        uint256 buyPrice = 50;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellPrice,
                maxPrice: sellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places buy order at lower price
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyPrice,
                maxPrice: buyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no trade, both orders remain
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 1);
        assertEq(sellOrders.length, 1);
        assertEq(buyOrders[0].amounts.available, amount);
        assertEq(sellOrders[0].amounts.available, amount);
    }

    function test_placeOrder_success_buyOrderSkipsZeroAvailableSellOrder() public {
        // PREPARE: seller creates two sell orders
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;
        uint256 lowPrice = 50;
        uint256 highPrice = 60;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.startPrank(_seller);
        uint256 sellOrderAtLow = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        uint256 sellOrderAtHigh = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT: buyer places two buy orders
        vm.prank(_buyer);
        uint256 buyOrder1 = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrder2 = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: two separate trades were created
        uint256[] memory tradeIds1 = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrder1);
        uint256[] memory tradeIds2 = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrder2);
        assertEq(tradeIds1.length, 1);
        assertEq(tradeIds2.length, 1);
        IOrderbookMarketplace.Order memory sellOrderLow =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderAtLow);
        assertEq(sellOrderLow.amounts.inDeals, amount);
        IOrderbookMarketplace.Order memory sellOrderHigh =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderAtHigh);
        assertEq(sellOrderHigh.amounts.inDeals, amount);
    }

    // solhint-disable-next-line function-max-lines
    function test_placeOrder_success_buyOrderSkipsZeroAvailableSellOrder_firstIteration() public {
        uint256 amount = 10;
        uint256 highPrice = 70;
        uint256 lowPrice = 60;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_buyer, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        _approveEscrowManagerAsOperator(_buyer);

        vm.prank(_seller);
        uint256 highSellOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 lowSellOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        (address initialBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("initialBuyer"), 0);
        vm.prank(initialBuyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondBuyer"), 0);
        vm.prank(secondBuyer);
        uint256 secondBuyOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory zeroAvailableLowOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(lowSellOrder);
        IOrderbookMarketplace.Order memory matchedHighOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(highSellOrder);
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondBuyOrder);

        assertEq(zeroAvailableLowOrder.amounts.available, 0);
        assertEq(zeroAvailableLowOrder.amounts.inDeals, amount);
        assertEq(matchedHighOrder.amounts.available, 0);
        assertEq(matchedHighOrder.amounts.inDeals, amount);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_buyOrderSkipsSelfMatch() public {
        // PREPARE: buyer creates sell order, seller creates sell order
        uint256 amount = 10;
        uint256 buyerSellPrice = 50;
        uint256 sellerSellPrice = 60;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_buyer, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_buyer);
        vm.prank(_buyer);
        uint256 buyerSellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyerSellPrice,
                maxPrice: buyerSellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellerSellPrice,
                maxPrice: sellerSellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer creates buy order
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellerSellPrice,
                maxPrice: sellerSellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: buyer's sell order was skipped
        IOrderbookMarketplace.Order memory buyerSellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyerSellOrderId);
        assertEq(buyerSellOrder.amounts.available, amount);
    }

    function test_placeOrder_success_buyOrderSkipsSelfMatch_firstIteration() public {
        uint256 amount = 10;
        uint256 selfSellPrice = 60;
        uint256 counterpartySellPrice = 70;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_buyer, _bondFTId, amount);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_buyer);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_buyer);
        uint256 buyerSelfSellOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: selfSellPrice,
                maxPrice: selfSellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_seller);
        uint256 sellerOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: counterpartySellPrice,
                maxPrice: counterpartySellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_buyer);
        uint256 buyerOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: selfSellPrice,
                maxPrice: counterpartySellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory selfOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyerSelfSellOrder);
        IOrderbookMarketplace.Order memory matchedSellerOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellerOrder);
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyerOrder);

        assertEq(selfOrder.amounts.available, amount);
        assertEq(selfOrder.amounts.inDeals, 0);
        assertEq(matchedSellerOrder.amounts.available, 0);
        assertEq(matchedSellerOrder.amounts.inDeals, amount);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_escrowIdsAreUniqueAcrossModules() public {
        // PREPARE: create Marketplace escrow with offerId = 1 (leave some tokens for orderbook)
        OfferInput memory offer = _createOfferInput();
        uint256 totalSupply = BOND_MAX_SUPPLY;
        offer.totalAmount = totalSupply - MIN_AMOUNT;
        _approveEscrowManager(_company, _bondFTId, offer.totalAmount);
        vm.prank(_company);
        uint256 offerId = Marketplace(_marketplace).registerOffer(offer);
        assertEq(offerId, 1);
        uint256 marketplaceEscrowId = _getEscrowIdByOfferId(offerId);

        // PREPARE: seller can create a sell order (orderId will also be 1)
        uint256 amount = MIN_AMOUNT;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: place a sell order (should not revert despite ID collision)
        vm.prank(_seller);
        uint256 orderPlacedId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: UNIT_PRICE,
                maxPrice: UNIT_PRICE,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: both escrows coexist with same numeric ID but different namespaces
        assertEq(orderPlacedId, 1);
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderPlacedId);
        assertEq(order.trader, _seller);
        assertEq(order.amounts.total, amount);
        assertEq(order.amounts.available, amount);

        // ASSERT: both escrows exist independently with distinct internal escrow IDs
        uint256 orderbookEscrowId = _orderbookEscrowIdByOrderId(orderPlacedId);
        Escrow memory marketplaceEscrow = EscrowManager(_escrowManager).getEscrow(marketplaceEscrowId);
        Escrow memory orderbookEscrow = EscrowManager(_escrowManager).getEscrow(orderbookEscrowId);
        assertEq(marketplaceEscrow.depositor, _company);
        assertEq(orderbookEscrow.depositor, _seller);
        assertNotEq(marketplaceEscrowId, orderbookEscrowId);
    }

    function test_placeOrder_success_sellOrderEscrowStoresAssetDetails() public {
        uint256 amount = MIN_AMOUNT;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _tokenId, amount);
        _approveEscrowManagerAsOperator(_seller);

        uint256 sellOrderId = _placeOrder(
            _seller, _tokenAddr, _tokenId, amount, UNIT_PRICE, UNIT_PRICE, IOrderbookMarketplace.OrderSide.SELL
        );

        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(escrowId);

        assertEq(escrow.depositor, _seller);
        assertEq(escrow.tokenAddress, _tokenAddr);
        assertEq(escrow.tokenId, _tokenId);
        assertEq(escrow.amount, amount);
    }

    function test_placeOrder_reverts_escrowIdMismatch() public {
        uint256 sellAmount = MIN_AMOUNT;
        uint256 expectedEscrowId = 1;
        uint256 actualEscrowId = 2;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);

        vm.mockCall(
            _escrowManager,
            abi.encodeWithSelector(EscrowManager.createEscrow.selector, sellAmount, _seller, _tokenAddr, _tokenId),
            abi.encode(actualEscrowId)
        );

        vm.prank(_seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__EscrowIdMismatch.selector, actualEscrowId, expectedEscrowId
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: UNIT_PRICE,
                maxPrice: UNIT_PRICE,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_sellOrderSkipsZeroAvailableBuyOrder() public {
        // PREPARE: buyer creates two buy orders
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;
        uint256 highPrice = 100;
        uint256 lowPrice = 90;
        vm.startPrank(_buyer);
        uint256 buyOrderAtHigh = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256 buyOrderAtLow = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: seller places two sell orders
        vm.prank(_seller);
        uint256 sellOrder1 = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_seller);
        uint256 sellOrder2 = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: two separate trades were created
        uint256[] memory tradeIds1 = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrder1);
        uint256[] memory tradeIds2 = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrder2);
        assertEq(tradeIds1.length, 1);
        assertEq(tradeIds2.length, 1);
        IOrderbookMarketplace.Order memory buyOrderHigh =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderAtHigh);
        assertEq(buyOrderHigh.amounts.inDeals, amount);
        IOrderbookMarketplace.Order memory buyOrderLow =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderAtLow);
        assertEq(buyOrderLow.amounts.inDeals, amount);
    }

    function test_placeOrder_success_sellOrderSkipsZeroAvailableBuyOrder_firstIteration() public {
        uint256 amount = 10;
        uint256 highPrice = 70;
        uint256 lowPrice = 60;

        vm.prank(_buyer);
        uint256 highBuyOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_seller);
        uint256 lowBuyOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        (address firstSeller,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("firstSeller"), 0);
        (address secondSeller,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondSeller"), 0);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(firstSeller, _bondFTId, amount);
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(secondSeller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(firstSeller);
        _approveEscrowManagerAsOperator(secondSeller);

        vm.prank(firstSeller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(secondSeller);
        uint256 secondSellOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory zeroAvailableHighOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(highBuyOrder);
        IOrderbookMarketplace.Order memory matchedLowOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(lowBuyOrder);
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondSellOrder);

        assertEq(zeroAvailableHighOrder.amounts.available, 0);
        assertEq(zeroAvailableHighOrder.amounts.inDeals, amount);
        assertEq(matchedLowOrder.amounts.available, 0);
        assertEq(matchedLowOrder.amounts.inDeals, amount);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_sellOrderSkipsSelfMatch() public {
        // PREPARE: seller creates buy order, buyer creates buy order
        uint256 amount = 10;
        uint256 sellerBuyPrice = 100;
        uint256 buyerBuyPrice = 90;
        vm.prank(_seller);
        uint256 sellerBuyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellerBuyPrice,
                maxPrice: sellerBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyerBuyPrice,
                maxPrice: buyerBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: seller creates sell order
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyerBuyPrice,
                maxPrice: buyerBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: seller's buy order was skipped
        IOrderbookMarketplace.Order memory sellerBuyOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellerBuyOrderId);
        assertEq(sellerBuyOrder.amounts.available, amount);
    }

    function test_placeOrder_success_sellOrderSkipsSelfMatch_firstIteration() public {
        uint256 amount = 10;
        uint256 selfBuyPrice = 70;
        uint256 counterpartyBuyPrice = 60;

        vm.prank(_buyer);
        uint256 buyerOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: selfBuyPrice,
                maxPrice: selfBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_seller);
        uint256 sellerOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: counterpartyBuyPrice,
                maxPrice: counterpartyBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_buyer, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_buyer);

        vm.prank(_buyer);
        uint256 sellOrder = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: counterpartyBuyPrice,
                maxPrice: selfBuyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory selfOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyerOrder);
        IOrderbookMarketplace.Order memory matchedCounterpartyOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellerOrder);
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrder);

        assertEq(selfOrder.amounts.available, amount);
        assertEq(selfOrder.amounts.inDeals, 0);
        assertEq(matchedCounterpartyOrder.amounts.available, 0);
        assertEq(matchedCounterpartyOrder.amounts.inDeals, amount);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_sellOrderStopsWhenAmountFilled() public {
        // @dev to test that _matchSellOrder early breaks when amount is filled, i.e.:
        // when 'newUnfilledAmount == 0'
        // ARRANGE: buyer places two BUY orders that are both matchable by price
        uint256 firstBuyAmount = 40;
        uint256 secondBuyAmount = 25;
        uint256 highPrice = 100;
        uint256 lowPrice = 90;
        vm.startPrank(_buyer);
        uint256 firstBuyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: firstBuyAmount,
                minPrice: lowPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256 secondBuyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: secondBuyAmount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ARRANGE: seller can fill only the first BUY order
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, firstBuyAmount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: firstBuyAmount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: only one trade is created and second BUY order remains untouched
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.buyOrderId, firstBuyOrderId);

        IOrderbookMarketplace.Order memory secondBuyOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(secondBuyOrderId);
        assertEq(secondBuyOrder.amounts.available, secondBuyAmount);
        assertEq(secondBuyOrder.amounts.inDeals, 0);
    }

    function test_placeOrder_reverts_zeroAmount() public {
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroAmount.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 0,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_zeroPrice() public {
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroPrice.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 0,
                maxPrice: 0,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_companyWalletNotAuthorized() public {
        // PREPARE
        address notAuthorized = makeAddr("notAuthorized");

        // ACT & ASSERT
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, notAuthorized));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_assetManagerNotSet() public {
        // PREPARE: deploy OrderbookMarketplace with address(0) for assetManager
        OrderbookMarketplace omImpl = new OrderbookMarketplace();
        UpgradeableBeacon omBeacon = new UpgradeableBeacon(address(omImpl), _deployer);
        address om = address(
            new BeaconProxy(
                address(omBeacon),
                abi.encodeWithSelector(
                    OrderbookMarketplace.initialize.selector,
                    _deployer,
                    address(0),
                    address(0),
                    address(0),
                    Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD,
                    Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD,
                    Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD,
                    address(1)
                )
            )
        );

        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__AssetManagerNotSet.selector);
        IOrderbookMarketplace(om)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_assetNotSupportedFromAssetManager() public {
        address unsupportedToken = makeAddr("unsupportedToken");
        uint256 tokenId = 42;

        vm.prank(_buyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AssetManager__AssetNotSupported.selector, unsupportedToken, tokenId)
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: unsupportedToken,
                tokenId: tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_tokenIdNotSupportedFromAssetManager() public {
        address allowlistedToken = makeAddr("allowlistedToken");
        uint256 tokenId = 42;

        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(allowlistedToken, AssetType.ERC1155, true, true);

        vm.prank(_buyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AssetManager__TokenIdNotSupported.selector, allowlistedToken, tokenId)
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: allowlistedToken,
                tokenId: tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_invalidTokenIdForERC20FromAssetManager() public {
        address erc20Token = makeAddr("erc20Token");
        uint256 invalidTokenId = 1;

        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(erc20Token, AssetType.ERC20, true, false);

        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidTokenId.selector, invalidTokenId));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: erc20Token,
                tokenId: invalidTokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_invalidAmountForERC721FromAssetManager() public {
        address erc721Token = makeAddr("erc721Token");
        uint256 invalidAmount = 2;

        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(erc721Token, AssetType.ERC721, true, false);

        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.AssetManager__InvalidAmountForERC721.selector, invalidAmount));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: erc721Token,
                tokenId: 1,
                totalAmount: invalidAmount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_storesExpiry() public {
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.expiry, expiry);
    }

    function test_placeOrder_reverts_invalidExpiryBelowThreshold() public {
        uint256 invalidExpiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold() - 1;

        vm.prank(_buyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__InvalidExpiry.selector, invalidExpiry, block.timestamp)
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: invalidExpiry
            }),
                address(0)
            );
    }

    function test_placeOrder_success_buyOrderSkipsExpiredSellOrder() public {
        uint256 amount = 100;
        uint256 price = 1;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: expiry
            }),
                address(0)
            );

        vm.warp(expiry + 1);

        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, amount);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId).length, 0);

        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, amount);
        assertEq(sellOrder.expiry, expiry);

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 1);
        assertEq(buyOrders[0].trader, _buyer);
        assertEq(sellOrders.length, 0);
    }

    function test_placeOrder_success_sellOrderSkipsExpiredBuyOrder() public {
        uint256 amount = 100;
        uint256 price = 1;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        vm.warp(expiry + 1);

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, amount);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId).length, 0);

        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, amount);
        assertEq(buyOrder.expiry, expiry);

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 1);
        assertEq(sellOrders[0].trader, _seller);
    }

    /*//////////////////////////////////////////////////////////////
                                cancelOrder
    //////////////////////////////////////////////////////////////*/

    function test_cancelOrder_success() public {
        // PREPARE
        uint256 totalAmount = 100;
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT
        vm.prank(_buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(orderId, _buyer, totalAmount);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));

        // ASSERT
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.available, 0);
    }

    function test_cancelOrder_success_removesFromMiddleOfArray() public {
        // PREPARE: buyer creates 3 orders at different prices
        uint256 amount = 10;
        uint256 lowPrice = 50;
        uint256 middlePrice = 70;
        uint256 highPrice = 90;
        vm.startPrank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: lowPrice,
                maxPrice: lowPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256 middleOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: middlePrice,
                maxPrice: middlePrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: highPrice,
                maxPrice: highPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: cancel the middle order
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(middleOrderId, address(0));
        vm.stopPrank();

        // ASSERT: only two orders remain
        (IOrderbookMarketplace.Order[] memory buyOrders,) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 2);
        assertEq(buyOrders[0].minPrice, highPrice);
        assertEq(buyOrders[1].minPrice, lowPrice);
    }

    function test_cancelOrder_success_sellOrderWithdrawsFromEscrow() public {
        // PREPARE: seller creates sell order (deposits to escrow)
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        // ACT: cancel the sell order
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));

        // ASSERT: tokens returned to seller
        uint256 sellerBalanceAfter = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        assertEq(sellerBalanceAfter, sellerBalanceBefore + amount);
    }

    function test_cancelOrder_success_partialMatch_keepsOrderWithInDeals() public {
        // ARRANGE: seller places sell order, buyer partially matches it
        uint256 totalAmount = 100;
        uint256 tradeAmount = 60;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: tradeAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        // ACT: cancel should withdraw only available amount, keeping inDeals
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(sellOrderId, address(0));

        // ASSERT: order still exists with inDeals and no available amount
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.trader, _seller);
        assertEq(order.amounts.available, 0);
        assertEq(order.amounts.inDeals, tradeAmount);
        uint256 sellerBalanceAfter = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        assertEq(sellerBalanceAfter, sellerBalanceBefore + (totalAmount - tradeAmount));
    }

    function test_cancelOrder_reverts_notAuthorized() public {
        // PREPARE
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        address notAuthorized = makeAddr("notAuthorized");

        // ACT & ASSERT
        vm.prank(notAuthorized);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, notAuthorized));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));
    }

    function test_cancelOrder_reverts_orderNotFound() public {
        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, uint256(999)));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(999, address(0));
    }

    function test_cancelOrder_reverts_noAvailableAmount() public {
        // PREPARE: create a fully matched order (available=0)
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT
        vm.prank(_seller);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NoAvailableAmount.selector, sellOrderId));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(sellOrderId, address(0));
    }

    function test_cancelOrder_reverts_onSyntheticOrder() public {
        _seedBatchSell(_seller, _bondFTId, 20, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(50, 1, 10));

        vm.prank(_buyer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__BatchOrderCannotBeCancelled.selector, orderId)
        );
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            cleanupExpiredOrder
    //////////////////////////////////////////////////////////////*/

    function test_cleanupExpiredOrder_reverts_orderNotExpired_atExactExpiry() public {
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        vm.warp(expiry);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__OrderNotExpired.selector, orderId, expiry, block.timestamp
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(orderId);
    }

    function test_cleanupExpiredOrder_reverts_orderNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, uint256(999)));
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(999);
    }

    function test_cleanupExpiredOrder_reverts_orderNotExpired_whenPerpetualOrder() public {
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__OrderNotExpired.selector, orderId, uint256(0), block.timestamp
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(orderId);
    }

    function test_cleanupExpiredOrder_success_buyOrderDeletesExpiredOrder() public {
        uint256 amount = 100;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        vm.warp(expiry + 1);

        address caller = makeAddr("cleanupCaller");
        vm.prank(caller);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(orderId, _buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(orderId, _buyer, amount);
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(orderId);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.trader, address(0));
        assertEq(order.amounts.available, 0);

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
    }

    function test_cleanupExpiredOrder_success_sellOrderWithdrawsEscrow() public {
        uint256 amount = 100;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: expiry
            }),
                address(0)
            );
        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        vm.warp(expiry + 1);

        address caller = makeAddr("cleanupCaller");
        vm.prank(caller);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(orderId, _seller);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(orderId, _seller, amount);
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(orderId);

        uint256 sellerBalanceAfter = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        assertEq(sellerBalanceAfter, sellerBalanceBefore + amount);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.trader, address(0));

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
    }

    function test_cleanupExpiredOrder_success_partialMatchKeepsOrderWithInDeals() public {
        // totalAmount=100, tradeAmount=60, unitPrice=1
        uint256 sellOrderId;
        uint256 expiry;
        {
            expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

            vm.prank(_company);
            DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
            _approveEscrowManagerAsOperator(_seller);

            vm.prank(_seller);
            sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 100,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.SELL,
                    expiry: expiry
                }),
                    address(0)
                );

            vm.prank(_buyer);
            IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 60,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    address(0)
                );
        }

        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        vm.warp(expiry + 1);

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(sellOrderId, _seller, 40); // 100 - 60
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(sellOrderId);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.trader, _seller);
        assertEq(order.amounts.available, 0);
        assertEq(order.amounts.inDeals, 60); // tradeAmount

        uint256 sellerBalanceAfter = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        assertEq(sellerBalanceAfter, sellerBalanceBefore + 40); // totalAmount - tradeAmount = 100 - 60

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
    }

    function test_cleanupExpiredOrder_reverts_noAvailableAmount() public {
        uint256 amount = 100;
        uint256 unitPrice = 1;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: expiry
            }),
                address(0)
            );

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NoAvailableAmount.selector, sellOrderId));
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(sellOrderId);
    }

    function test_cleanupExpiredOrder_reverts_orderFrozen() public {
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, bytes32("FROZEN"));

        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderFrozen.selector, orderId));
        IOrderbookMarketplace(_orderbookMarketplace).cleanupExpiredOrder(orderId);
    }

    function test_cancelOrder_success_expiredOrderMirrorsCleanup() public {
        uint256 amount = 100;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        vm.warp(expiry + 1);

        vm.prank(_buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(orderId, _buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(orderId, _buyer, amount);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.trader, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            markTradePaid
    //////////////////////////////////////////////////////////////*/

    function test_markTradePaid_success() public {
        // PREPARE: create a trade
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        // ACT
        vm.prank(_paymentHandler);
        vm.expectEmit();
        emit IOrderbookMarketplace.TradePaid(tradeId, _buyer, _seller);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        // ASSERT
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.PAID));
    }

    function test_markTradePaid_success_afterPaymentDeadlineWhileStillPending() public {
        (uint256 tradeId,,) = _createMatchedTrade(100, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);

        vm.warp(trade.paymentDeadline + 1);

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.PAID));
    }

    function test_markTradePaid_reverts_notPaymentHandler() public {
        // PREPARE: create a trade
        uint256 amount = 100;
        uint256 unitPrice = 1;
        address notAuthorized = makeAddr("notAuthorized");
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        // ACT
        vm.prank(notAuthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
    }

    function test_markTradePaid_reverts_tradeNotFound() public {
        vm.prank(_paymentHandler);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, uint256(0)));
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(999);
    }

    function test_markTradePaid_reverts_invalidTradeStatus() public {
        // PREPARE: create a trade and mark it as paid
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        // ACT: cannot mark it as paid again
        vm.prank(_paymentHandler);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidTradeStatus.selector, uint8(IOrderbookMarketplace.TradeStatus.PAID)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                            settleTrade
    //////////////////////////////////////////////////////////////*/

    function test_settleTrade_success() public {
        // PREPARE: create a trade and mark it as paid
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        // ACT
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeSettled(tradeId, _buyer, amount);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        // ASSERT
        uint256 buyerBalance = DEUSSToken(_tokenAddr).balanceOf(_buyer, _bondFTId);
        assertEq(buyerBalance, amount);
    }

    function test_settleTrade_success_deletesFullySettledOrders() public {
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256 tradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId)[0];

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(trade.tokenAddress, _tokenAddr);
        assertEq(trade.tokenId, _tokenId);
        assertEq(sellOrder.trader, address(0));
        assertEq(buyOrder.trader, address(0));
    }

    function test_settleTrade_success_partialMatch_updatesBuyOrderSold() public {
        uint256 buyAmount = 100;
        uint256 sellAmount = 40;
        uint256 unitPrice = 1;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: buyAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256 tradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId)[0];
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, buyAmount - sellAmount);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.sold, sellAmount);
    }

    function test_settleTrade_reverts_tradeNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, uint256(0)));
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(0);
    }

    function test_settleTrade_reverts_tradeNotSettleable_whenPending() public {
        // PREPARE: create a trade (status PENDING)
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        // ACT: cannot settle without marking as paid first
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__TradeNotSettleable.selector,
                uint8(IOrderbookMarketplace.TradeStatus.PENDING)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    function test_settleTrade_reverts_alreadySettledTrade() public {
        uint256 totalAmount = 200;
        uint256 unitPrice = 1;
        uint256 tradeAmount = 100;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: tradeAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ARRANGE: create a second buyer
        (address buyerTwo,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("buyerTwo"), 0);
        // ARRANGE: place a second buy order
        vm.prank(buyerTwo);
        uint256 secondBuyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: tradeAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: settle the first trade
        uint256 tradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId)[0];
        uint256 secondTradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondBuyOrderId)[0];

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(secondTradeId);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__TradeNotSettleable.selector,
                uint8(IOrderbookMarketplace.TradeStatus.SETTLED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(secondTradeId);
    }

    function test_settleTrade_success_onSyntheticBuyOrder() public {
        uint256 sellOrderId = _seedBatchSell(_seller, _bondFTId, 30, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(30, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        uint256 tradeId = tradeIds[0];

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        assertEq(
            uint8(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId).status),
            uint8(IOrderbookMarketplace.TradeStatus.SETTLED)
        );
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_buyer, _bondFTId), 30);

        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.trader, address(0), "deleted after settlement");
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_settleTrade_success_deletesSyntheticBuyAfterMixedPaidAndUnpaid() public {
        _seedBatchSell(_seller, _bondFTId, 30, 1);
        _seedBatchSell(_seller, _bondFTId, 30, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(60, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2);

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeIds[0]);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeIds[0]);

        IOrderbookMarketplace.Trade memory unpaid = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        vm.warp(unpaid.paymentDeadline + 1);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeIds[1]);
        unpaid = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        vm.warp(unpaid.disputeBuffer + 1);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeIds[1]);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_settleTrade_success_deletesSyntheticBuyAfterAllUnpaid() public {
        _seedBatchSell(_seller, _bondFTId, 30, 1);
        _seedBatchSell(_seller, _bondFTId, 30, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(60, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2);

        IOrderbookMarketplace.Trade memory first = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        vm.warp(first.paymentDeadline + 1);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeIds[0]);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeIds[1]);

        first = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        vm.warp(first.disputeBuffer + 1);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeIds[0]);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, _buyer);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeIds[1]);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            markTradeUnpaid
    //////////////////////////////////////////////////////////////*/

    function test_markTradeUnpaid_success() public {
        // PREPARE: create a trade
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(
            trade.disputeBuffer,
            trade.paymentDeadline + IOrderbookMarketplace(_orderbookMarketplace).disputeBufferPeriod()
        );
        vm.warp(trade.paymentDeadline + 1);

        // ACT
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeUnpaid(tradeId, _buyer, _seller);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);

        // ASSERT
        IOrderbookMarketplace.Trade memory updatedTrade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(updatedTrade.status), uint8(IOrderbookMarketplace.TradeStatus.UNPAID));
        assertEq(
            updatedTrade.disputeBuffer,
            trade.paymentDeadline + IOrderbookMarketplace(_orderbookMarketplace).disputeBufferPeriod()
        );
    }

    function test_markTradeUnpaid_reverts_tradeNotExpired() public {
        // PREPARE: create a trade
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        // ACT: try to mark as unpaid before deadline
        vm.expectRevert(Errors.OrderbookMarketplace__TradeNotExpired.selector);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    function test_markTradeUnpaid_reverts_tradeNotExpired_atDeadline() public {
        (uint256 tradeId,,) = _createMatchedTrade(100, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);

        vm.warp(trade.paymentDeadline);

        vm.expectRevert(Errors.OrderbookMarketplace__TradeNotExpired.selector);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    function test_markTradeUnpaid_reverts_tradeNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, uint256(0)));
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(999);
    }

    function test_markTradeUnpaid_reverts_invalidTradeStatus() public {
        // PREPARE: create a trade and mark it as paid
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.paymentDeadline + 1);

        // ACT: cannot mark as unpaid when already paid
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidTradeStatus.selector, uint8(IOrderbookMarketplace.TradeStatus.PAID)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    function test_markTradeUnpaid_reverts_whenFrozen() public {
        (uint256 tradeId,,) = _createMatchedTrade(100, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.warp(trade.paymentDeadline + 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, tradeId));
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                           initiateDispute
    //////////////////////////////////////////////////////////////*/

    function test_initiateDispute_success() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.prank(_buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeDisputed(tradeId, _buyer, _seller);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.IN_DISPUTE));
    }

    function test_initiateDispute_reverts_notBuyer() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);
        address notBuyer = makeAddr("notBuyer");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, notBuyer);

        vm.prank(notBuyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, notBuyer));
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);
    }

    function test_initiateDispute_reverts_invalidTradeStatus() public {
        (uint256 tradeId,,) = _createMatchedTrade(100, 1);

        vm.prank(_buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidTradeStatus.selector,
                uint8(IOrderbookMarketplace.TradeStatus.PENDING)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);
    }

    function test_initiateDispute_reverts_disputePeriodExpired() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.disputeBuffer + 1);

        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__DisputePeriodExpired.selector);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                           resolveDispute
    //////////////////////////////////////////////////////////////*/

    function test_resolveDispute_success_paid() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);

        vm.prank(_arbitrator);
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeDisputeResolved(tradeId, IOrderbookMarketplace.TradeStatus.PAID, _arbitrator);
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.PAID);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.PAID));
        assertEq(trade.disputeBuffer, 0);
    }

    function test_resolveDispute_success_unpaid() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);

        vm.prank(_arbitrator);
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.UNPAID);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.UNPAID));
        assertEq(trade.disputeBuffer, 0);
    }

    function test_resolveDispute_reverts_notArbitrator() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);
        address notArbitrator = makeAddr("notArbitrator");

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);

        vm.prank(notArbitrator);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.PAID);
    }

    function test_resolveDispute_reverts_tradeNotFound() public {
        vm.prank(_arbitrator);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, uint256(999)));
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(999, IOrderbookMarketplace.TradeStatus.PAID);
    }

    function test_resolveDispute_reverts_tradeNotInDispute() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.prank(_arbitrator);
        vm.expectRevert(Errors.OrderbookMarketplace__TradeNotInDispute.selector);
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.PAID);
    }

    function test_resolveDispute_reverts_invalidResolution() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);

        vm.prank(_arbitrator);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidDisputeResolution.selector,
                uint8(IOrderbookMarketplace.TradeStatus.CANCELLED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.CANCELLED);
    }

    /*//////////////////////////////////////////////////////////////
                    settleTrade (UNPAID / CANCELLED)
    //////////////////////////////////////////////////////////////*/

    function test_settleTrade_success_cancelledTrade() public {
        uint256 amount = 100;
        (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId) = _createUnpaidTrade(amount, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.disputeBuffer + 1);

        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        // ACT
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        // ASSERT: escrow stays intact (no withdraw on cancelled trade)
        uint256 sellerBalanceAfter = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);
        assertEq(sellerBalanceAfter, sellerBalanceBefore);

        // ASSERT: order amounts reverted to available
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, amount);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(sellOrder.amounts.sold, 0);

        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, amount);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.sold, 0);

        trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.CANCELLED));
    }

    function test_settleTrade_reverts_disputePeriodNotExpired_forUnpaidTrade() public {
        (uint256 tradeId,,) = _createUnpaidTrade(100, 1);

        vm.expectRevert(Errors.OrderbookMarketplace__DisputePeriodNotExpired.selector);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    function test_settleTrade_success_cancelledTrade_afterArbitration() public {
        uint256 amount = 100;
        (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId) = _createUnpaidTrade(amount, 1);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);
        vm.prank(_arbitrator);
        IOrderbookMarketplace(_orderbookMarketplace).resolveDispute(tradeId, IOrderbookMarketplace.TradeStatus.UNPAID);

        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);

        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.CANCELLED));
        assertEq(sellOrder.amounts.available, amount);
        assertEq(buyOrder.amounts.available, amount);
    }

    function test_settleTrade_success_cancelledTrade_deletesFullyResolvedOrders() public {
        // PREPARE: seller places sell order, buyer fully matches, seller cancels remaining (0 available)
        // Then trade is marked unpaid and settled
        uint256 totalAmount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256 tradeId = tradeIds[0];

        // Mark unpaid after deadline
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.paymentDeadline + 1);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
        trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.disputeBuffer + 1);

        // ACT: settle the cancelled trade
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        // ASSERT: orders get available restored, not deleted (available > 0 after restore)
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(trade.sellOrderId);
        assertEq(sellOrder.amounts.available, totalAmount);

        IOrderbookMarketplace.Order memory buyOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(trade.buyOrderId);
        assertEq(buyOrder.amounts.available, totalAmount);

        trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.CANCELLED));
    }

    /*//////////////////////////////////////////////////////////////
                        setPaymentExpiryThreshold
    //////////////////////////////////////////////////////////////*/

    function test_setPaymentExpiryThreshold_success() public {
        uint256 newThreshold = 2 days;
        vm.prank(_orderbookAdmin);
        vm.expectEmit();
        emit IOrderbookMarketplace.PaymentExpiryThresholdSet(newThreshold);
        IOrderbookMarketplace(_orderbookMarketplace).setPaymentExpiryThreshold(newThreshold);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).paymentExpiryThreshold(), newThreshold);
    }

    function test_setPaymentExpiryThreshold_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setPaymentExpiryThreshold(2 days);
    }

    function test_setPaymentExpiryThreshold_reverts_tooLow() public {
        uint256 invalidThreshold = OrderbookMarketplace(_orderbookMarketplace).MIN_PAYMENT_EXPIRY_THRESHOLD() - 1;

        vm.prank(_orderbookAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__PaymentExpiryThresholdTooLow.selector, invalidThreshold)
        );
        IOrderbookMarketplace(_orderbookMarketplace).setPaymentExpiryThreshold(invalidThreshold);
    }

    function test_setPaymentExpiryThreshold_reverts_tooHigh() public {
        uint256 invalidThreshold = OrderbookMarketplace(_orderbookMarketplace).MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;

        vm.prank(_orderbookAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__PaymentExpiryThresholdTooHigh.selector, invalidThreshold
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).setPaymentExpiryThreshold(invalidThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                        setMinExpiryThreshold
    //////////////////////////////////////////////////////////////*/

    function test_setMinExpiryThreshold_success() public {
        uint256 newThreshold = 2 days;
        vm.prank(_orderbookAdmin);
        vm.expectEmit();
        emit IOrderbookMarketplace.MinExpiryThresholdSet(newThreshold);
        IOrderbookMarketplace(_orderbookMarketplace).setMinExpiryThreshold(newThreshold);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold(), newThreshold);
    }

    function test_setMinExpiryThreshold_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setMinExpiryThreshold(2 days);
    }

    function test_setMinExpiryThreshold_reverts_tooLow() public {
        uint256 invalidThreshold = OrderbookMarketplace(_orderbookMarketplace).MIN_ORDER_EXPIRY_THRESHOLD() - 1;

        vm.prank(_orderbookAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__MinExpiryThresholdTooLow.selector, invalidThreshold)
        );
        IOrderbookMarketplace(_orderbookMarketplace).setMinExpiryThreshold(invalidThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                        setDisputeBufferPeriod
    //////////////////////////////////////////////////////////////*/

    function test_setDisputeBufferPeriod_success() public {
        uint256 newPeriod = 2 days;
        vm.prank(_orderbookAdmin);
        vm.expectEmit();
        emit IOrderbookMarketplace.DisputeBufferPeriodSet(newPeriod);
        IOrderbookMarketplace(_orderbookMarketplace).setDisputeBufferPeriod(newPeriod);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).disputeBufferPeriod(), newPeriod);
    }

    function test_setDisputeBufferPeriod_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setDisputeBufferPeriod(2 days);
    }

    function test_setDisputeBufferPeriod_reverts_tooLow() public {
        uint256 invalidPeriod = OrderbookMarketplace(_orderbookMarketplace).MIN_DISPUTE_BUFFER_PERIOD() - 1;

        vm.prank(_orderbookAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__DisputeBufferPeriodTooLow.selector, invalidPeriod)
        );
        IOrderbookMarketplace(_orderbookMarketplace).setDisputeBufferPeriod(invalidPeriod);
    }

    function test_setDisputeBufferPeriod_reverts_tooHigh() public {
        uint256 invalidPeriod = OrderbookMarketplace(_orderbookMarketplace).MAX_DISPUTE_BUFFER_PERIOD() + 1;

        vm.prank(_orderbookAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__DisputeBufferPeriodTooHigh.selector, invalidPeriod)
        );
        IOrderbookMarketplace(_orderbookMarketplace).setDisputeBufferPeriod(invalidPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                            setMarketFilter
    //////////////////////////////////////////////////////////////*/

    function test_setMarketFilter_success() public {
        address newFilter = makeAddr("newMarketFilter");

        vm.prank(_orderbookAdmin);
        vm.expectEmit();
        emit IOrderbookMarketplace.MarketFilterSet(newFilter);
        IOrderbookMarketplace(_orderbookMarketplace).setMarketFilter(newFilter);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).marketFilter(), newFilter);
    }

    function test_setMarketFilter_reverts_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setMarketFilter(makeAddr("anyFilter"));
    }

    function test_setMarketFilter_reverts_zeroAddress() public {
        vm.prank(_orderbookAdmin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setMarketFilter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_entityRegistry_success() public view {
        address retrieved = IOrderbookMarketplace(_orderbookMarketplace).entityRegistry();
        vm.assertEq(retrieved, _entityRegistry);
    }

    function test_escrowManager_success() public view {
        address retrieved = IOrderbookMarketplace(_orderbookMarketplace).escrowManager();
        vm.assertEq(retrieved, _escrowManager);
    }

    function test_paymentExpiryThreshold_success() public view {
        assertEq(
            IOrderbookMarketplace(_orderbookMarketplace).paymentExpiryThreshold(),
            Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD
        );
    }

    function test_minExpiryThreshold_success() public view {
        assertEq(
            IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold(), Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD
        );
    }

    function test_disputeBufferPeriod_success() public view {
        assertEq(
            IOrderbookMarketplace(_orderbookMarketplace).disputeBufferPeriod(),
            Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD
        );
    }

    function test_getEscrowIdByOrderId_success_sellOrderReturnsEscrowId() public {
        uint256 amount = MIN_AMOUNT;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _tokenId, amount);
        _approveEscrowManagerAsOperator(_seller);

        uint256 sellOrderId = _placeOrder(
            _seller, _tokenAddr, _tokenId, amount, UNIT_PRICE, UNIT_PRICE, IOrderbookMarketplace.OrderSide.SELL
        );

        uint256 escrowId = IOrderbookMarketplace(_orderbookMarketplace).getEscrowIdByOrderId(sellOrderId);
        Escrow memory escrow = EscrowManager(_escrowManager).getEscrow(escrowId);

        assertNotEq(escrowId, 0);
        assertEq(escrow.depositor, _seller);
        assertEq(escrow.tokenAddress, _tokenAddr);
        assertEq(escrow.tokenId, _tokenId);
        assertEq(escrow.amount, amount);
    }

    function test_getEscrowIdByOrderId_success_buyOrderReturnsZero() public {
        uint256 buyOrderId = _placeOrder(
            _buyer, _tokenAddr, _tokenId, MIN_AMOUNT, UNIT_PRICE, UNIT_PRICE, IOrderbookMarketplace.OrderSide.BUY
        );

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getEscrowIdByOrderId(buyOrderId), 0);
    }

    function test_getEscrowIdByOrderId_success_nonexistentOrderReturnsZero() public view {
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getEscrowIdByOrderId(type(uint256).max), 0);
    }

    function test_getOrderBook_success() public {
        // PREPARE: place one BUY order and one SELL order
        uint256 buyAmount = 100;
        uint256 buyPrice = 10;
        uint256 sellAmount = 50;
        uint256 sellPrice = 20;
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: buyAmount,
                minPrice: buyPrice,
                maxPrice: buyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: sellPrice,
                maxPrice: sellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);

        // ASSERT
        assertEq(buyOrders.length, 1);
        assertEq(buyOrders[0].tokenId, _tokenId);
        assertEq(buyOrders[0].trader, _buyer);
        assertEq(buyOrders[0].minPrice, buyPrice);
        assertEq(buyOrders[0].amounts.total, buyAmount);
        assertEq(buyOrders[0].amounts.available, buyAmount);
        assertEq(uint8(buyOrders[0].side), uint8(IOrderbookMarketplace.OrderSide.BUY));
        assertEq(sellOrders.length, 1);
        assertEq(sellOrders[0].tokenId, _tokenId);
        assertEq(sellOrders[0].trader, _seller);
        assertEq(sellOrders[0].minPrice, sellPrice);
        assertEq(sellOrders[0].amounts.total, sellAmount);
        assertEq(sellOrders[0].amounts.available, sellAmount);
        assertEq(uint8(sellOrders[0].side), uint8(IOrderbookMarketplace.OrderSide.SELL));
    }

    function test_getOrderBook_success_versionsAreSeparatedByTokenId() public {
        vm.prank(_publisher);
        _br.publishBond(_bondFT);

        uint256 successorTokenId = uint256(keccak256(abi.encodePacked(bytes12(bytes(_bondFT.isin)), uint8(2))));

        vm.prank(_company);
        _br.issueBond(_bondFT.isin, 2, BOND_MAX_SUPPLY);

        vm.startPrank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 10,
                maxPrice: 10,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: successorTokenId,
                totalAmount: 200,
                minPrice: 20,
                maxPrice: 20,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        (IOrderbookMarketplace.Order[] memory activeBuyOrders,) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        (IOrderbookMarketplace.Order[] memory successorBuyOrders,) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, successorTokenId);

        assertEq(activeBuyOrders.length, 1);
        assertEq(activeBuyOrders[0].tokenId, _tokenId);
        assertEq(activeBuyOrders[0].amounts.total, 100);

        assertEq(successorBuyOrders.length, 1);
        assertEq(successorBuyOrders[0].tokenId, successorTokenId);
        assertEq(successorBuyOrders[0].amounts.total, 200);
    }

    function test_getOrderBookAndMatching_success_marketsAreSeparatedByTokenAddress() public {
        OrderbookMockERC6909 secondToken = _setupSecondErc6909Asset();
        uint256 tokenId = _tokenId;
        uint256 amount = MIN_AMOUNT;
        uint256 unitPrice = 10;

        secondToken.mint(_seller, tokenId, amount);
        uint256 secondTokenSellOrderId = _placeFixedOrder(
            _seller, address(secondToken), tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.SELL
        );
        uint256 firstTokenBuyOrderId =
            _placeFixedOrder(_buyer, _tokenAddr, tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.BUY);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(firstTokenBuyOrderId).length, 0);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondTokenSellOrderId).length, 0);
        _assertSeparatedOrderBooks(address(secondToken), tokenId);
    }

    function test_matching_success_sameTokenIdDifferentTokenAddressTradesRemainDistinguishable() public {
        OrderbookMockERC6909 secondToken = _setupSecondErc6909Asset();
        uint256 tokenId = _tokenId;
        uint256 amount = MIN_AMOUNT;
        uint256 unitPrice = 10;

        secondToken.mint(_seller, tokenId, amount);
        uint256 secondTokenSellOrderId = _placeFixedOrder(
            _seller, address(secondToken), tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.SELL
        );
        uint256 firstTokenBuyOrderId =
            _placeFixedOrder(_buyer, _tokenAddr, tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.BUY);

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, tokenId, amount);
        _approveEscrowManagerAsOperator(_seller);

        uint256 expectedFirstTokenSellOrderId = firstTokenBuyOrderId + 1;
        _expectTradeExecuted(
            firstTokenBuyOrderId, expectedFirstTokenSellOrderId, tokenId, _tokenAddr, amount, unitPrice
        );
        uint256 firstTokenSellOrderId =
            _placeFixedOrder(_seller, _tokenAddr, tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.SELL);
        assertEq(firstTokenSellOrderId, expectedFirstTokenSellOrderId);

        uint256 expectedSecondTokenBuyOrderId = firstTokenSellOrderId + 1;
        _expectTradeExecuted(
            expectedSecondTokenBuyOrderId, secondTokenSellOrderId, tokenId, address(secondToken), amount, unitPrice
        );
        uint256 secondTokenBuyOrderId = _placeFixedOrder(
            _buyer, address(secondToken), tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.BUY
        );
        assertEq(secondTokenBuyOrderId, expectedSecondTokenBuyOrderId);

        uint256 firstTokenTradeId =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(firstTokenBuyOrderId)[0];
        uint256 secondTokenTradeId =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondTokenBuyOrderId)[0];
        assertNotEq(firstTokenTradeId, secondTokenTradeId);

        _markPaidAndSettleTrade(firstTokenTradeId);
        _markPaidAndSettleTrade(secondTokenTradeId);

        IOrderbookMarketplace.Trade memory firstTokenTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(firstTokenTradeId);
        IOrderbookMarketplace.Trade memory secondTokenTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(secondTokenTradeId);

        assertEq(firstTokenTrade.tokenAddress, _tokenAddr);
        assertEq(secondTokenTrade.tokenAddress, address(secondToken));
        assertEq(firstTokenTrade.tokenId, tokenId);
        assertEq(secondTokenTrade.tokenId, tokenId);
        assertEq(uint8(firstTokenTrade.status), uint8(IOrderbookMarketplace.TradeStatus.SETTLED));
        assertEq(uint8(secondTokenTrade.status), uint8(IOrderbookMarketplace.TradeStatus.SETTLED));
    }

    function test_getOrderBookAndMatching_success_sellTakerDoesNotCrossMatchDifferentTokenAddress() public {
        OrderbookMockERC6909 secondToken = _setupSecondErc6909Asset();
        uint256 tokenId = _tokenId;
        uint256 amount = MIN_AMOUNT;
        uint256 unitPrice = 10;

        uint256 firstTokenBuyOrderId =
            _placeFixedOrder(_buyer, _tokenAddr, tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.BUY);

        secondToken.mint(_seller, tokenId, amount);
        uint256 secondTokenSellOrderId = _placeFixedOrder(
            _seller, address(secondToken), tokenId, amount, unitPrice, IOrderbookMarketplace.OrderSide.SELL
        );

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(firstTokenBuyOrderId).length, 0);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondTokenSellOrderId).length, 0);
        _assertSeparatedOrderBooks(address(secondToken), tokenId);
    }

    function test_getOrderBook_success_excludesZeroAvailableOrders() public {
        // PREPARE: fully match buy and sell orders so available == 0 for both
        uint256 amount = 100;
        uint256 unitPrice = 1;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);

        // ASSERT: fully matched orders are filtered out (available == 0)
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
    }

    function test_getOrderBook_success_excludesExpiredOrders() public {
        uint256 amount = 100;
        uint256 price = 1;
        uint256 expiry = block.timestamp + IOrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: expiry
            }),
                address(0)
            );

        (address activeBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("activeBuyer"), 0);

        vm.prank(activeBuyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price + 1,
                maxPrice: price + 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.warp(expiry + 1);

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);

        assertEq(buyOrders.length, 1);
        assertEq(buyOrders[0].trader, activeBuyer);
        assertEq(sellOrders.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE RANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_placeOrder_success_buyRangeMatchesFixedSell() public {
        // PREPARE: seller places fixed-price sell order
        uint256 amount = 10;
        uint256 sellPrice = 95;
        uint256 buyMinPrice = 90;
        uint256 buyMaxPrice = 100;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellPrice,
                maxPrice: sellPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places range buy order that overlaps the sell price
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade at seller's minPrice (maker's best price for buyer)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.amount, amount);
        assertEq(trade.unitPrice, sellPrice);
    }

    function test_placeOrder_success_sellRangeMatchesFixedBuy() public {
        // PREPARE: buyer places fixed-price buy order
        uint256 amount = 10;
        uint256 buyPrice = 100;
        uint256 sellMinPrice = 90;
        uint256 sellMaxPrice = 110;

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyPrice,
                maxPrice: buyPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // PREPARE: transfer tokens to seller
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: seller places range sell order that overlaps the buy price
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade at buyer's maxPrice (maker's best price for seller)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.amount, amount);
        assertEq(trade.unitPrice, buyPrice);
    }

    function test_placeOrder_success_rangeOverlapExecutesAtMakerPrice() public {
        // PREPARE: seller places range sell order [95-110]
        uint256 amount = 10;
        uint256 sellMinPrice = 95;
        uint256 sellMaxPrice = 110;
        uint256 buyMinPrice = 90;
        uint256 buyMaxPrice = 100;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places range buy order [90-100], ranges overlap at [95-100]
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade at seller's minPrice (95), the maker's best price for buyer
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, sellMinPrice);
    }

    function test_placeOrder_success_rangeNoOverlap() public {
        // PREPARE: seller places range sell order [95-100]
        uint256 amount = 10;
        uint256 sellMinPrice = 95;
        uint256 sellMaxPrice = 100;
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 90;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places range buy order [80-90], no overlap with sell
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no trade, both orders remain in orderbook
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 1);
        assertEq(sellOrders.length, 1);
        assertEq(buyOrders[0].amounts.available, amount);
        assertEq(sellOrders[0].amounts.available, amount);
    }

    function test_placeOrder_success_sellTakerExecutesAtBuyerMaxPrice() public {
        // PREPARE: buyer places range buy order [90-100]
        uint256 amount = 10;
        uint256 buyMinPrice = 90;
        uint256 buyMaxPrice = 100;

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // PREPARE: transfer tokens to seller
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: seller places matching sell order
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade at buyer's maxPrice (maker's best price for seller)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, buyMaxPrice);
    }

    function test_placeOrder_success_sellTakerCapturesSellerMaxOnRange() public {
        // ARRANGE: buyer posts a wide range order [80-120]
        // buyer's economic incentive to buy at the lowest price
        uint256 amount = 10;
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 120;
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ARRANGE: seller can ask much lower and still get matched
        // seller's economic incentive to sell at the highest price
        uint256 sellMinPrice = 80;
        uint256 sellMaxPrice = 90;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT: seller takes the buy order
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: execution price is seller max, not buyer max
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, sellMaxPrice);
        assertLt(trade.unitPrice, buyMaxPrice);
    }

    function test_placeOrder_success_sellTakerMatchesWithoutFullRangeOverlap() public {
        // ARRANGE: buyer maker order is [80-120]
        uint256 amount = 10;
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 120;

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ARRANGE: seller taker order is [50-70]
        uint256 sellMinPrice = 50;
        uint256 sellMaxPrice = 70;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        // ACT
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no trade — ranges [80-120] and [50-70] do not overlap (sellMax 70 < buyMin 80)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(tradeIds.length, 0);
        assertEq(buyOrders.length, 1);
        assertEq(sellOrders.length, 1);
        assertEq(buyOrders[0].amounts.available, amount);
        assertEq(sellOrders[0].amounts.available, amount);
    }

    function test_placeOrder_success_buyTakerMatchesWithoutFullRangeOverlap() public {
        // ARRANGE: seller maker order is [50-70]
        uint256 amount = 10;
        uint256 sellMinPrice = 50;
        uint256 sellMaxPrice = 70;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer taker order is [80-120]
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 120;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no trade — ranges [50-70] and [80-120] do not overlap (sellMax 70 < buyMin 80)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(tradeIds.length, 0);
        assertEq(buyOrders.length, 1);
        assertEq(sellOrders.length, 1);
        assertEq(buyOrders[0].amounts.available, amount);
        assertEq(sellOrders[0].amounts.available, amount);
    }

    function test_placeOrder_success_buyTakerExecutesBelowBuyerMinPrice() public {
        // ARRANGE: seller maker order is [50-100]
        uint256 amount = 10;
        uint256 sellMinPrice = 50;
        uint256 sellMaxPrice = 100;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer taker order is [80-120]
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 120;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: taker-favorable — BUY taker executes at the lower bound of the overlap = max(sellMin, buyMin)
        // overlap is [80-100], so the buyer (taker) pays 80, the best price for them within the range
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertGe(trade.unitPrice, buyMinPrice);
        assertLe(trade.unitPrice, sellMaxPrice);
        assertEq(trade.unitPrice, buyMinPrice);
    }

    function test_placeOrder_success_rangeBoundaryOverlap_buyMaxEqualsSellMinExecutesAtBoundary() public {
        // ARRANGE: seller maker order [90-100]
        uint256 amount = 10;
        uint256 sellMinPrice = 90;
        uint256 sellMaxPrice = 100;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer taker order [80-90] creates a single-point overlap at 90
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 90;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade executes at the boundary price
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, buyMaxPrice);
        assertEq(trade.unitPrice, sellMinPrice);
    }

    function test_placeOrder_success_rangeBoundaryOverlap_sellMaxEqualsBuyMinExecutesAtBoundary() public {
        // ARRANGE: buyer maker order [80-120]
        uint256 amount = 10;
        uint256 buyMinPrice = 80;
        uint256 buyMaxPrice = 120;

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: buyMinPrice,
                maxPrice: buyMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: seller taker order [50-80] creates a single-point overlap at 80
        uint256 sellMinPrice = 50;
        uint256 sellMaxPrice = 80;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: sellMinPrice,
                maxPrice: sellMaxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: trade executes at the boundary price
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, sellMaxPrice);
        assertEq(trade.unitPrice, buyMinPrice);
    }

    function test_placeOrder_success_rangeSortingByBestPrice() public {
        // PREPARE: buyer places two range buy orders with different maxPrices
        uint256 amount = 10;

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 80,
                maxPrice: 90,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 85,
                maxPrice: 100,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT & ASSERT: orders sorted by maxPrice descending (best first)
        (IOrderbookMarketplace.Order[] memory buyOrders,) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 2);
        assertEq(buyOrders[0].maxPrice, 100);
        assertEq(buyOrders[1].maxPrice, 90);
    }

    function test_placeOrder_success_sellRangeSortingByMinPrice() public {
        // PREPARE: seller places two range sell orders with different minPrices
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);

        vm.startPrank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 100,
                maxPrice: 120,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 90,
                maxPrice: 110,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT & ASSERT: orders sorted by minPrice ascending (best first)
        (, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(sellOrders.length, 2);
        assertEq(sellOrders[0].minPrice, 90);
        assertEq(sellOrders[1].minPrice, 100);
    }

    function test_placeOrder_reverts_invalidPriceRange() public {
        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__InvalidPriceRange.selector, 100, 50));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 10,
                minPrice: 100,
                maxPrice: 50,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_buyRangeMatchesMultipleSellOrders() public {
        // PREPARE: seller places two fixed-price sell orders at 90 and 95
        uint256 amount = 10;
        uint256 totalAmount = amount * 2;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, totalAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.startPrank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 90,
                maxPrice: 90,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 95,
                maxPrice: 95,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
        vm.stopPrank();

        // ACT: buyer places range buy order [85-100] that matches both sells
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: totalAmount,
                minPrice: 85,
                maxPrice: 100,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: two trades, each at the respective seller's minPrice
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 2);
        IOrderbookMarketplace.Trade memory trade1 = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        IOrderbookMarketplace.Trade memory trade2 = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        assertEq(trade1.unitPrice, 90);
        assertEq(trade2.unitPrice, 95);
    }

    /*//////////////////////////////////////////////////////////////
                            MIN MATCH AMOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_placeOrder_reverts_minAmountExceedsTotal() public {
        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__MinAmountExceedsTotal.selector, 100, 50));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 50,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 100,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_minAmountZeroMatchesAnything() public {
        // PREPARE
        uint256 amount = 10;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.amount, amount);
    }

    function test_placeOrder_success_skipsCounterpartyBelowMinAmount() public {
        // PREPARE: seller places order with minMatchAmount=50
        uint256 sellAmount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order for 30 (below seller's minMatchAmount)
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 30,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, 30);
    }

    function test_placeOrder_success_skipsWhenNewOrderBelowMinAmount() public {
        // PREPARE: seller places order with no minMatchAmount
        uint256 sellAmount = 20;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order for 100 with minMatchAmount=50 (seller only has 20)
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match because potential match (20) < buyer's minMatchAmount (50)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, 100);
    }

    function test_placeOrder_success_exactMinAmountMatches() public {
        // PREPARE: seller places order with minMatchAmount=50
        uint256 amount = 50;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order for exactly 50 with minMatchAmount=50
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: exact match succeeds
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.amount, amount);
    }

    function test_placeOrder_success_bothSidesMinAmountRespected() public {
        // PREPARE: seller places order for 100 with minMatchAmount=40
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 40,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order for 30 with minMatchAmount=25
        // potential match = min(30, 100) = 30, buyer's min=25 OK, but seller's min=40 NOT OK
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 30,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 25,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match because 30 < seller's minMatchAmount (40)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_sellSideMinAmountSkipsSmallBuyOrder() public {
        // PREPARE: buyer places order for 20 with no minMatchAmount
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 20,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: seller places order for 100 with minMatchAmount=50 (buyer only has 20)
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match because potential match (20) < seller's minMatchAmount (50)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, 100);
    }

    function test_placeOrder_success_buySideMinAmountSkipsSmallSellOrder() public {
        // PREPARE: buyer places order for 100 with minMatchAmount=50
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 50,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: seller places order for 30 with no minMatchAmount (potential match is 30 < buyer min 50)
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 30);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 30,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match because 30 < buyOrder.minMatchAmount (50)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.amounts.available, 30);
    }

    function test_placeOrder_success_minAmountOrderPlacedEventIncludesMinAmount() public {
        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderPlaced(
            1,
            _tokenId,
            _buyer,
            _tokenAddr,
            100,
            100,
            1,
            1,
            25,
            IOrderbookMarketplace.TraderFilterMode.NONE,
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 25,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_minAmountStoredInOrder() public {
        // ACT
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 25,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.minMatchAmount, 25);
    }

    /*//////////////////////////////////////////////////////////////
                        TRADER FILTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_placeOrder_reverts_noneWithNonEmptyAddresses() public {
        // ACT & ASSERT
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__TradeFilterNotEmpty.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_whitelistWithEmptyAddresses() public {
        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__TradeFilterEmpty.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_blacklistWithEmptyAddresses() public {
        // ACT & ASSERT
        vm.prank(_buyer);
        vm.expectRevert(Errors.OrderbookMarketplace__TradeFilterEmpty.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.BLACKLIST,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_traderFilterTooLarge() public {
        // ACT & ASSERT
        address[] memory addrs = new address[](51);
        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TraderFilterTooLarge.selector, 51));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_reverts_zeroAddress() public {
        // ACT & ASSERT
        address[] memory addrs = new address[](1);
        addrs[0] = address(0);
        vm.prank(_buyer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function test_placeOrder_success_whitelistAllowsMatchWithAllowedTrader() public {
        // PREPARE: seller places order with no filter
        uint256 amount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with whitelist containing seller
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: match happens
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_whitelistSkipsNonAllowedTrader() public {
        // PREPARE: seller places order with no filter
        uint256 amount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with whitelist NOT containing seller
        address otherTrader = makeAddr("otherTrader");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, otherTrader);
        address[] memory addrs = new address[](1);
        addrs[0] = otherTrader;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_blacklistSkipsBlockedTrader() public {
        // PREPARE: seller places order with no filter
        uint256 amount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with blacklist containing seller
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.BLACKLIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match (seller is blacklisted)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_blacklistAllowsNonBlockedTrader() public {
        // PREPARE: seller places order with no filter
        uint256 amount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with blacklist NOT containing seller (blocks someone else)
        address otherTrader = makeAddr("otherTrader2");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, otherTrader);
        address[] memory addrs = new address[](1);
        addrs[0] = otherTrader;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.BLACKLIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: match happens (seller is not blacklisted)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_counterpartyFilterBlocksMatch() public {
        // PREPARE: seller places order with whitelist that does NOT include buyer
        uint256 amount = 100;
        address otherTrader = makeAddr("otherTrader3");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, otherTrader);
        address[] memory sellerWhitelist = new address[](1);
        sellerWhitelist[0] = otherTrader;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: sellerWhitelist,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with no filter
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match (seller's whitelist doesn't include buyer)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_bothSidesHaveFilter() public {
        // PREPARE: seller places order with whitelist containing buyer
        uint256 amount = 100;
        address[] memory sellerWhitelist = new address[](1);
        sellerWhitelist[0] = _buyer;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: sellerWhitelist,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with whitelist containing seller
        address[] memory buyerWhitelist = new address[](1);
        buyerWhitelist[0] = _seller;
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: buyerWhitelist,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: match happens (both sides allow each other)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_noneFilterMatchesAnyone() public {
        // PREPARE: seller places order with NONE filter
        uint256 amount = 100;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ACT: buyer places order with NONE filter
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: match happens
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
    }

    function test_placeOrder_success_traderFilterModeStoredInOrder() public {
        // ACT
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(uint8(order.traderFilterMode), uint8(IOrderbookMarketplace.TraderFilterMode.WHITELIST));
    }

    function test_isTraderAllowedForOrder_whitelist() public {
        // PREPARE
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        assertTrue(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _seller));
        assertFalse(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _buyer));
    }

    function test_isTraderAllowedForOrder_blacklist() public {
        // PREPARE
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.BLACKLIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        assertFalse(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _seller));
        assertTrue(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _buyer));
    }

    function test_isTraderAllowedForOrder_none() public {
        // PREPARE
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT
        assertTrue(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _seller));
        assertTrue(IOrderbookMarketplace(_orderbookMarketplace).isTraderAllowedForOrder(orderId, _buyer));
    }

    function test_placeOrder_success_sellSideFilterBlocksBuyer() public {
        // PREPARE: buyer places order with no filter
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: seller places order with blacklist containing buyer
        address[] memory addrs = new address[](1);
        addrs[0] = _buyer;
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.BLACKLIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match (seller blacklisted buyer)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_buySideFilterBlocksSeller() public {
        // PREPARE: buyer places order with whitelist not containing seller
        address otherTrader = makeAddr("otherTrader4");
        _createAndRegisterEntityWallet(_entityRegistryAdmin, otherTrader);
        address[] memory buyerWhitelist = new address[](1);
        buyerWhitelist[0] = otherTrader;
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: buyerWhitelist,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // ACT: seller places order with no filter
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);
        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // ASSERT: no match (buy maker whitelist does not include seller)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_success_orderPlacedEventIncludesFilterMode() public {
        // ACT & ASSERT
        address[] memory addrs = new address[](1);
        addrs[0] = _seller;
        vm.prank(_buyer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderPlaced(
            1,
            _tokenId,
            _buyer,
            _tokenAddr,
            100,
            100,
            1,
            1,
            0,
            IOrderbookMarketplace.TraderFilterMode.WHITELIST,
            IOrderbookMarketplace.OrderSide.BUY,
            0
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: addrs,
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function _emptyBondFilter() internal pure returns (BondMarketFilter.BondFilter memory) {
        return BondMarketFilter.BondFilter({
            maturityFrom: 0,
            maturityTo: 0,
            currencyWhitelist: new bytes3[](0),
            currencyBlacklist: new bytes3[](0),
            couponRateFrom: 0,
            couponRateTo: 0,
            couponRateTypes: new CouponRateType[](0),
            issuerWhitelist: new address[](0),
            issuerBlacklist: new address[](0),
            bondNominalValueFrom: 0,
            bondNominalValueTo: 0
        });
    }

    function _batchInput(uint256 total, uint256 minPrice, uint256 maxPrice)
        internal
        pure
        returns (IOrderbookMarketplace.BatchOrderInput memory)
    {
        return IOrderbookMarketplace.BatchOrderInput({
            totalAmount: total,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minMatchAmount: 0,
            filterData: abi.encode(_emptyBondFilter()),
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
            traderFilterAddresses: new address[](0)
        });
    }

    function _setupSecondErc6909Asset() internal returns (OrderbookMockERC6909 secondToken) {
        secondToken = new OrderbookMockERC6909();

        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(address(secondToken), AssetType.ERC6909, true, false);
    }

    function _placeFixedOrder(
        address trader,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 unitPrice,
        IOrderbookMarketplace.OrderSide side
    ) internal returns (uint256 orderId) {
        orderId = _placeOrder(trader, tokenAddress, tokenId, amount, unitPrice, unitPrice, side);
    }

    function _assertSeparatedOrderBooks(address secondToken, uint256 tokenId) internal {
        (IOrderbookMarketplace.Order[] memory firstTokenBuys, IOrderbookMarketplace.Order[] memory firstTokenSells) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, tokenId);
        (IOrderbookMarketplace.Order[] memory secondTokenBuys, IOrderbookMarketplace.Order[] memory secondTokenSells) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(secondToken, tokenId);

        assertEq(firstTokenBuys.length, 1);
        assertEq(firstTokenBuys[0].tokenAddress, _tokenAddr);
        assertEq(firstTokenSells.length, 0);
        assertEq(secondTokenBuys.length, 0);
        assertEq(secondTokenSells.length, 1);
        assertEq(secondTokenSells[0].tokenAddress, secondToken);
    }

    function _expectTradeExecuted(
        uint256 buyOrderId,
        uint256 sellOrderId,
        uint256 tokenId,
        address tokenAddress,
        uint256 amount,
        uint256 unitPrice
    ) internal {
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeExecuted(
            buyOrderId, sellOrderId, tokenId, tokenAddress, _buyer, _seller, amount, unitPrice
        );
    }

    function _markPaidAndSettleTrade(uint256 tradeId) internal {
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    function _placeOrder(
        address trader,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 minPrice,
        uint256 maxPrice,
        IOrderbookMarketplace.OrderSide side
    ) internal returns (uint256 orderId) {
        vm.prank(trader);
        orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: tokenAddress,
                tokenId: tokenId,
                totalAmount: amount,
                minPrice: minPrice,
                maxPrice: maxPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: side,
                expiry: 0
            }),
                address(0)
            );
    }

    function _placeBatchSellOrder(address seller, uint256 tokenId, uint256 amount, uint256 price)
        internal
        returns (uint256)
    {
        vm.prank(seller);
        return IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    function _seedBatchSell(address seller, uint256 tokenId, uint256 amount, uint256 price) internal returns (uint256) {
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(seller, tokenId, amount);
        _approveEscrowManagerAsOperator(seller);
        return _placeBatchSellOrder(seller, tokenId, amount, price);
    }

    function _seedBatchSellWithOptions(
        address seller,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 minMatchAmount,
        uint256 expiry,
        IOrderbookMarketplace.TraderFilterMode filterMode
    ) internal returns (uint256) {
        return _seedBatchSellWithOptions(
            seller, tokenId, amount, price, minMatchAmount, expiry, filterMode, new address[](0)
        );
    }

    function _seedBatchSellWithOptions(
        address seller,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 minMatchAmount,
        uint256 expiry,
        IOrderbookMarketplace.TraderFilterMode filterMode,
        address[] memory filterAddresses
    ) internal returns (uint256) {
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(seller, tokenId, amount);
        _approveEscrowManagerAsOperator(seller);

        vm.prank(seller);
        return IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: minMatchAmount,
                traderFilterMode: filterMode,
                traderFilterAddresses: filterAddresses,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: expiry
            }),
                address(0)
            );
    }

    function _createSecondBond(
        string memory isin,
        string memory currencyStr,
        CouponRateType couponRateType_,
        uint256 bondNominalValue,
        uint256 maturityOffsetDays,
        uint256 couponRate
    ) internal returns (uint256 tokenId) {
        vm.startPrank(_publisher);
        if (!_br.isCurrencyAllowed(currencyStr)) {
            _br.setAllowedCurrency(currencyStr, true);
        }
        vm.stopPrank();

        uint256 maturity = block.timestamp + (maturityOffsetDays * 1 days);

        CouponRates memory rates;
        if (couponRateType_ == CouponRateType.ZERO_COUPON) {
            rates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});
        } else {
            rates = _createCouponRatesFromOneRate(couponRate);
        }

        BondInput memory input = BondInput({
            isin: isin,
            issuer: _company,
            currency: currencyStr,
            bondNominalValue: bondNominalValue,
            maxSupply: BOND_MAX_SUPPLY,
            couponRateType: couponRateType_,
            couponRates: rates,
            couponFrequency: CouponFrequency.Annual,
            maturityDate: maturity,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });

        vm.prank(_publisher);
        _br.publishBond(input);

        vm.prank(_company);
        _br.issueBond(isin, 1, BOND_MAX_SUPPLY);

        bytes12 isinBytes = isin._isinToBytes12();
        tokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));
    }

    /*//////////////////////////////////////////////////////////////
                            placeBatchOrder
    //////////////////////////////////////////////////////////////*/

    function test_placeBatchOrder_noActiveMarkets() public {
        uint256 expectedOrderId = 1;

        vm.expectEmit();
        emit IOrderbookMarketplace.BatchOrderPlaced(
            expectedOrderId, _buyer, 100, 0, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE
        );
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(expectedOrderId, _buyer);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(100, 1, 10));

        assertEq(orderId, expectedOrderId);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_placeBatchOrder_fullyMatchesSingleMarket() public {
        uint256 sellAmount = 100;
        uint256 price = 5;

        uint256 sellOrderId = _seedBatchSell(_seller, _bondFTId, sellAmount, price);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(60, 1, 10));

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 60);
        assertEq(order.amounts.available, 0);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.amount, 60);
        assertEq(trade.buyOrderId, orderId);
        assertEq(trade.sellOrderId, sellOrderId);
        assertEq(trade.unitPrice, 5);
    }

    function test_placeBatchOrder_iocDiscardsRemainder() public {
        _seedBatchSell(_seller, _bondFTId, 30, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(100, 1, 10));

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.total, 100);
        assertEq(order.amounts.inDeals, 30);
        assertEq(order.amounts.available, 0, "synthetic order MUST remain IOC");
    }

    function test_placeBatchOrder_maxPriceBelowAsk_skipsMarket() public {
        _seedBatchSell(_seller, _bondFTId, 50, 100);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(50, 1, 10));

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    // solhint-disable-next-line function-max-lines
    function test_placeBatchOrder_crossMarketFill_presortPriority() public {
        _seedBatchSell(_seller, _bondFTId, 50, 10);

        uint256 secondTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, secondTokenId, 30, 2);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(60, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2, "should hit both markets");

        IOrderbookMarketplace.Trade memory firstTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(firstTrade.tokenId, secondTokenId);
        assertEq(firstTrade.amount, 30);
        assertEq(firstTrade.unitPrice, 2);

        IOrderbookMarketplace.Trade memory secondTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        assertEq(secondTrade.tokenId, _bondFTId);
        assertEq(secondTrade.amount, 30);
        assertEq(secondTrade.unitPrice, 10);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 60);
    }

    function test_placeBatchOrder_success_preservesGlobalPricePriorityAcrossMarkets() public {
        // Market A has the globally cheapest first ask, but its next ask is expensive.
        _seedBatchSell(_seller, _bondFTId, 10, 1);
        _seedBatchSell(_seller, _bondFTId, 10, 100);

        // Market B's best ask is more expensive than Market A's first ask, but cheaper than Market A's second ask.
        uint256 secondTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, secondTokenId, 10, 2);

        // Expected global cheapest-first fills for 20 units: Market A @ 1, then Market B @ 2.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(20, 1, 100));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2, "wrong global fill count");

        IOrderbookMarketplace.Trade memory firstTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(firstTrade.tokenId, _bondFTId);
        assertEq(firstTrade.amount, 10);
        assertEq(firstTrade.unitPrice, 1);

        IOrderbookMarketplace.Trade memory secondTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        assertEq(secondTrade.tokenId, secondTokenId);
        assertEq(secondTrade.amount, 10);
        assertEq(secondTrade.unitPrice, 2);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 20);
    }

    function test_placeBatchOrder_success_partialFillStaysOnCurrentBestMarket() public {
        // Market A: 100 @ 1 — globally cheapest, deep enough to fill the whole buy.
        uint256 sellOrderId = _seedBatchSell(_seller, _bondFTId, 100, 1);

        // Market B: 10 @ 2 — eligible, but more expensive than A.
        uint256 secondTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, secondTokenId, 10, 2);

        // Batch buy: 50 units. Should not hop to B while A's top-of-book still has liquidity.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(50, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1, "should stay on Market A");

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.tokenId, _bondFTId);
        assertEq(trade.sellOrderId, sellOrderId);
        assertEq(trade.amount, 50);
        assertEq(trade.unitPrice, 1);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 50);
    }

    // solhint-disable-next-line function-max-lines
    function test_placeBatchOrder_success_globalReprioritizationAcrossThreeMarkets() public {
        // Market A (EUR): 10 @ 1, 10 @ 7
        _seedBatchSell(_seller, _bondFTId, 10, 1);
        _seedBatchSell(_seller, _bondFTId, 10, 7);

        // Market B (USD): 10 @ 2, 10 @ 6
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 2);
        _seedBatchSell(_seller, marketB, 10, 6);

        // Market C (EUR, distinct ISIN): 10 @ 3
        uint256 marketC = _createSecondBond("SK0001002061", "EUR", CouponRateType.FIXED, 1_000, 400, 500);
        _seedBatchSell(_seller, marketC, 10, 3);

        // Batch buy: 50 units, max 10 — covers every ask. Globally cheapest-first must yield 1,2,3,6,7.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(50, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 5, "wrong three-market fill count");

        uint256[5] memory expectedPrices = [uint256(1), 2, 3, 6, 7];
        uint256[5] memory expectedTokenIds = [_bondFTId, marketB, marketC, marketB, _bondFTId];
        for (uint256 i; i < 5; ++i) {
            IOrderbookMarketplace.Trade memory t = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[i]);
            assertEq(t.unitPrice, expectedPrices[i]);
            assertEq(t.tokenId, expectedTokenIds[i]);
            assertEq(t.amount, 10);
        }

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 50);
    }

    function test_placeBatchOrder_success_priceCapBlocksDeeperExpensiveAsks() public {
        // Market A: 10 @ 1, 10 @ 100. The 100-ask must stay untouched once maxPrice is set to 2.
        _seedBatchSell(_seller, _bondFTId, 10, 1);
        uint256 untouchedSellOrderId = _seedBatchSell(_seller, _bondFTId, 10, 100);

        // Market B: 10 @ 2.
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 2);

        // Batch buy: 30 units, maxPrice 2. Should fill A@1 and B@2 (20 total) and IOC-discard the rest.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(30, 1, 2));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2, "crossed maxPrice cap");

        IOrderbookMarketplace.Trade memory firstTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(firstTrade.tokenId, _bondFTId);
        assertEq(firstTrade.amount, 10);
        assertEq(firstTrade.unitPrice, 1);

        IOrderbookMarketplace.Trade memory secondTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        assertEq(secondTrade.tokenId, marketB);
        assertEq(secondTrade.amount, 10);
        assertEq(secondTrade.unitPrice, 2);

        IOrderbookMarketplace.Order memory untouched =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(untouchedSellOrderId);
        assertEq(untouched.amounts.available, 10, "expensive ask touched");
        assertEq(untouched.amounts.inDeals, 0);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.total, 30);
        assertEq(order.amounts.inDeals, 20);
        assertEq(order.amounts.available, 0, "synthetic batch order is IOC");
    }

    function test_placeBatchOrder_success_cheaperMarketIgnoredWhenFilteredOut() public {
        // Market A (EUR): 10 @ 1 — globally cheapest, but excluded by the currency whitelist.
        uint256 cheaperUntouched = _seedBatchSell(_seller, _bondFTId, 10, 1);

        // Market B (USD): 10 @ 2 — passes the filter.
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 2);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(10, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.currencyWhitelist = new bytes3[](1);
        f.currencyWhitelist[0] = _CURRENCY_USD;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1, "filtered market matched");

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.tokenId, marketB);
        assertEq(trade.amount, 10);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory cheaper =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(cheaperUntouched);
        assertEq(cheaper.amounts.available, 10, "filtered ask touched");
        assertEq(cheaper.amounts.inDeals, 0);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 10);
    }

    function test_placeBatchOrder_success_skipsFrozenBestAskAndFillsNextMarket() public {
        // Market A: 10 @ 1 — globally cheapest, frozen post-seed.
        uint256 frozenSellOrderId = _seedBatchSell(_seller, _bondFTId, 10, 1);

        // Market B: 10 @ 2.
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 2);

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        _grantRoles(_orderbookMarketplace, _freezer, freezeRole);
        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(frozenSellOrderId, true, bytes32("FROZEN"));

        // Iter 0 picks A@1 → _matchBuyOrder skips frozen → no progress → floor=1.
        // Iter 1 skips A@1 (price ≤ floor) → picks B@2 → fills 10.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(10, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        // The cheapest top ask is frozen, so batch matching should skip it and still fill from the next eligible market.
        assertEq(tradeIds.length, 1, "frozen best ask not skipped");

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        // The single fill must be the valid second-market ask at price 2, not the frozen first-market ask at price 1.
        assertEq(trade.tokenId, marketB);
        assertEq(trade.amount, 10);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory frozenOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(frozenSellOrderId);
        assertEq(frozenOrder.amounts.available, 10, "frozen ask must remain untouched");
        assertEq(frozenOrder.amounts.inDeals, 0);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 10);
    }

    function test_placeBatchOrder_success_skipsBlacklistedBestAskAndFillsNextMarket() public {
        // Market A: 10 @ 1 — globally cheapest, but the buyer blacklists this seller.
        _seedBatchSell(_seller, _bondFTId, 10, 1);

        // Market B: 10 @ 2 — owned by a non-blacklisted seller.
        (address otherSeller,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("batchOtherSeller"), 0);
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        uint256 expectedSellOrderId = _seedBatchSell(otherSeller, marketB, 10, 2);

        address[] memory blockedTraders = new address[](1);
        blockedTraders[0] = _seller;

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(10, 1, 10);
        input.traderFilterMode = IOrderbookMarketplace.TraderFilterMode.BLACKLIST;
        input.traderFilterAddresses = blockedTraders;

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        // The cheapest top ask belongs to a blacklisted seller, so matching should continue to the next eligible seller.
        assertEq(tradeIds.length, 1, "blacklisted ask not skipped");

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        // The executed trade must come from the non-blacklisted seller in the second market at the next-best price.
        assertEq(trade.tokenId, marketB);
        assertEq(trade.sellOrderId, expectedSellOrderId);
        assertEq(trade.amount, 10);
        assertEq(trade.unitPrice, 2);
    }

    function test_placeBatchOrder_success_skipsMinMatchBlockedBestAskAndFillsNextMarket() public {
        // Market A: 5 @ 1 — globally cheapest, but its lot is below buyer's minMatchAmount of 10.
        uint256 smallSellOrderId = _seedBatchSell(_seller, _bondFTId, 5, 1);

        // Market B: 10 @ 2 — meets minMatchAmount of 10.
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 2);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(10, 1, 10);
        input.minMatchAmount = 10;

        // Iter 0 picks A@1 → _matchBuyOrder skips lot (5 < minMatch=10) → no progress → floor=1.
        // Iter 1 skips A@1 (price ≤ floor) → picks B@2 → fills 10.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        // The cheapest top ask is below the batch minMatchAmount, so matching should continue to a large enough ask.
        assertEq(tradeIds.length, 1, "small ask not skipped");

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        // The fill must use the second market because its available amount satisfies minMatchAmount at price 2.
        assertEq(trade.tokenId, marketB);
        assertEq(trade.amount, 10);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory smallOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(smallSellOrderId);
        assertEq(smallOrder.amounts.available, 5, "small ask touched");
        assertEq(smallOrder.amounts.inDeals, 0);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 10);
    }

    function test_placeBatchOrder_success_skipsAskBelowBatchMinPriceAndFillsNextAsk() public {
        uint256 cheapUnmatched = _seedBatchSell(_seller, _bondFTId, 10, 3);
        _seedBatchSell(_seller, _bondFTId, 10, 6);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(10, 5, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, 6);
        assertEq(trade.amount, 10);

        IOrderbookMarketplace.Order memory cheapOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(cheapUnmatched);
        assertEq(cheapOrder.amounts.available, 10);
        assertEq(cheapOrder.amounts.inDeals, 0);
    }

    function test_placeBatchOrder_success_skipsExpiredBestAskAndFillsNextAsk() public {
        uint256 expiry = block.timestamp + OrderbookMarketplace(_orderbookMarketplace).minExpiryThreshold();
        uint256 expiredSellOrderId = _seedBatchSellWithOptions(
            _seller, _bondFTId, 10, 1, 0, expiry, IOrderbookMarketplace.TraderFilterMode.NONE
        );
        _seedBatchSell(_seller, _bondFTId, 10, 2);

        vm.warp(expiry + 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(10, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory expiredOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(expiredSellOrderId);
        assertEq(expiredOrder.amounts.available, 10);
        assertEq(expiredOrder.amounts.inDeals, 0);
    }

    function test_placeBatchOrder_success_skipsSelfTradeBestAskAndFillsNextAsk() public {
        uint256 selfSellOrderId = _seedBatchSell(_buyer, _bondFTId, 10, 1);
        _seedBatchSell(_seller, _bondFTId, 10, 2);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(10, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.seller, _seller);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory selfOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(selfSellOrderId);
        assertEq(selfOrder.amounts.available, 10);
        assertEq(selfOrder.amounts.inDeals, 0);
    }

    function test_placeBatchOrder_success_skipsSellerFilteredBestAskAndFillsNextAsk() public {
        address[] memory blockedBuyer = new address[](1);
        blockedBuyer[0] = _buyer;
        uint256 filteredSellOrderId = _seedBatchSellWithOptions(
            _seller, _bondFTId, 10, 1, 0, 0, IOrderbookMarketplace.TraderFilterMode.BLACKLIST, blockedBuyer
        );
        _seedBatchSell(_seller, _bondFTId, 10, 2);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(10, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, 2);

        IOrderbookMarketplace.Order memory filteredOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(filteredSellOrderId);
        assertEq(filteredOrder.amounts.available, 10);
        assertEq(filteredOrder.amounts.inDeals, 0);
    }

    function test_placeBatchOrder_success_skipsSellerMinMatchBlockedBestAskAndFillsNextAsk() public {
        uint256 blockedSellOrderId =
            _seedBatchSellWithOptions(_seller, _bondFTId, 20, 1, 10, 0, IOrderbookMarketplace.TraderFilterMode.NONE);
        _seedBatchSell(_seller, _bondFTId, 5, 2);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(5, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.unitPrice, 2);
        assertEq(trade.amount, 5);

        IOrderbookMarketplace.Order memory blockedOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(blockedSellOrderId);
        assertEq(blockedOrder.amounts.available, 20);
        assertEq(blockedOrder.amounts.inDeals, 0);
    }

    function test_placeBatchOrder_success_samePriceDeterministicTieBreak() public {
        // Market A: 10 @ 5 — registered first in _activeSellMarkets.
        _seedBatchSell(_seller, _bondFTId, 10, 5);

        // Market B: 10 @ 5 — registered second.
        uint256 marketB = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, marketB, 10, 5);

        // Buy 20: both fills must execute at price 5. Tie-break is registration order: A first, then B.
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(20, 1, 10));

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 2);

        IOrderbookMarketplace.Trade memory firstTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(firstTrade.unitPrice, 5);
        assertEq(firstTrade.amount, 10);
        assertEq(firstTrade.tokenId, _bondFTId, "tie-break failed");

        IOrderbookMarketplace.Trade memory secondTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[1]);
        assertEq(secondTrade.unitPrice, 5);
        assertEq(secondTrade.amount, 10);
        assertEq(secondTrade.tokenId, marketB);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.amounts.inDeals, 20);
    }

    function test_placeBatchOrder_filter_currencyWhitelist() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);
        uint256 usdTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.currencyWhitelist = new bytes3[](1);
        f.currencyWhitelist[0] = _CURRENCY_USD;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, usdTokenId);
    }

    function test_placeBatchOrder_filter_currencyBlacklist() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);
        uint256 usdTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.currencyBlacklist = new bytes3[](1);
        f.currencyBlacklist[0] = BOND_CURRENCY_BYTES3;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, usdTokenId);
    }

    function test_placeBatchOrder_filter_maturityOutOfRange() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(50, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.maturityTo = block.timestamp + 10 days;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_placeBatchOrder_filter_bondNominalValueOutOfRange() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);
        uint256 usdTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.bondNominalValueFrom = 1_500;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, usdTokenId);
    }

    function test_placeBatchOrder_filter_couponRateTypeMismatch() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);
        uint256 zcTokenId =
            _createSecondBond(_SECOND_ISIN, "USD", CouponRateType.ZERO_COUPON, _SECOND_BOND_NOMINAL_VALUE, 400, 0);
        _seedBatchSell(_seller, zcTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.couponRateTypes = new CouponRateType[](1);
        f.couponRateTypes[0] = CouponRateType.ZERO_COUPON;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, zcTokenId);
    }

    function test_placeBatchOrder_filter_couponRateRange_fixed() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);
        uint256 usdTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.couponRateFrom = 600;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, usdTokenId);
    }

    // solhint-disable-next-line function-max-lines
    function test_placeBatchOrder_filter_issuerWhitelist() public {
        (address otherIssuer,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("otherIssuer"));
        vm.label(otherIssuer, "OtherIssuer");

        vm.prank(_publisher);
        _br.setAllowedCurrency("USD", true);

        uint256 maturity = block.timestamp + 400 days;
        BondInput memory input2 = BondInput({
            isin: _SECOND_ISIN,
            issuer: otherIssuer,
            currency: "USD",
            bondNominalValue: _SECOND_BOND_NOMINAL_VALUE,
            maxSupply: BOND_MAX_SUPPLY,
            couponRateType: CouponRateType.FIXED,
            couponRates: _createCouponRatesFromOneRate(_SECOND_COUPON_RATE),
            couponFrequency: CouponFrequency.Annual,
            maturityDate: maturity,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
        vm.prank(_publisher);
        _br.publishBond(input2);

        vm.prank(otherIssuer);
        _br.issueBond(_SECOND_ISIN, 1, BOND_MAX_SUPPLY);

        bytes12 isinBytes = _SECOND_ISIN._isinToBytes12();
        uint256 usdTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));

        _seedBatchSell(_seller, _bondFTId, 50, 1);

        vm.prank(otherIssuer);
        DEUSSToken(_tokenAddr).transfer(_seller, usdTokenId, 50);
        _approveEscrowManagerAsOperator(_seller);
        _placeBatchSellOrder(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory batch = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.issuerWhitelist = new address[](1);
        f.issuerWhitelist[0] = otherIssuer;
        batch.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(batch);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, usdTokenId);
    }

    // solhint-disable-next-line function-max-lines
    function test_placeBatchOrder_filter_issuerBlacklist() public {
        (address otherIssuer,) = _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("otherIssuer"));
        vm.label(otherIssuer, "OtherIssuer");

        vm.prank(_publisher);
        _br.setAllowedCurrency("USD", true);

        uint256 maturity = block.timestamp + 400 days;
        BondInput memory input2 = BondInput({
            isin: _SECOND_ISIN,
            issuer: otherIssuer,
            currency: "USD",
            bondNominalValue: _SECOND_BOND_NOMINAL_VALUE,
            maxSupply: BOND_MAX_SUPPLY,
            couponRateType: CouponRateType.FIXED,
            couponRates: _createCouponRatesFromOneRate(_SECOND_COUPON_RATE),
            couponFrequency: CouponFrequency.Annual,
            maturityDate: maturity,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
        vm.prank(_publisher);
        _br.publishBond(input2);

        vm.prank(otherIssuer);
        _br.issueBond(_SECOND_ISIN, 1, BOND_MAX_SUPPLY);

        bytes12 isinBytes = _SECOND_ISIN._isinToBytes12();
        uint256 usdTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));

        _seedBatchSell(_seller, _bondFTId, 50, 1);

        vm.prank(otherIssuer);
        DEUSSToken(_tokenAddr).transfer(_seller, usdTokenId, 50);
        _approveEscrowManagerAsOperator(_seller);
        _placeBatchSellOrder(_seller, usdTokenId, 50, 1);

        IOrderbookMarketplace.BatchOrderInput memory batch = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.issuerBlacklist = new address[](1);
        f.issuerBlacklist[0] = otherIssuer;
        batch.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(batch);

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(orderId);
        assertEq(tradeIds.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]).tokenId, _bondFTId);
    }

    // solhint-disable-next-line function-max-lines
    function test_placeBatchOrder_filter_couponRateRange_floating() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);

        vm.prank(_publisher);
        _br.setAllowedCurrency("USD", true);

        uint256 rateChangeTimestamp = block.timestamp + 720 days;
        uint256 maturityTimestamp = block.timestamp + 1800 days;
        // Final rate must be 0 per BondRegistry validation.
        uint256[] memory intervals = new uint256[](3);
        uint256[] memory rates = new uint256[](3);
        intervals[0] = block.timestamp;
        intervals[1] = rateChangeTimestamp;
        intervals[2] = maturityTimestamp;
        rates[0] = 300;
        rates[1] = 700;
        rates[2] = 0;

        BondInput memory input2 = BondInput({
            isin: _SECOND_ISIN,
            issuer: _company,
            currency: "USD",
            bondNominalValue: _SECOND_BOND_NOMINAL_VALUE,
            maxSupply: BOND_MAX_SUPPLY,
            couponRateType: CouponRateType.FLOATING,
            couponRates: CouponRates({paymentTimestamps: intervals, rates: rates}),
            couponFrequency: CouponFrequency.Annual,
            maturityDate: maturityTimestamp,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
        vm.prank(_publisher);
        _br.publishBond(input2);

        vm.prank(_company);
        _br.issueBond(_SECOND_ISIN, 1, BOND_MAX_SUPPLY);

        bytes12 isinBytes = _SECOND_ISIN._isinToBytes12();
        uint256 floatingTokenId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));

        _seedBatchSell(_seller, floatingTokenId, 50, 1);

        // At issuance (FLOATING rate = 300) filter [500, ∞) matches only the FIXED bond.
        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(200, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.couponRateFrom = 500;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        uint256 firstOrderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);
        uint256[] memory firstTrades = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(firstOrderId);
        assertEq(firstTrades.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(firstTrades[0]).tokenId, _bondFTId);

        // Warp to the explicit rate-change timestamp: FLOATING jumps to 700.
        vm.warp(rateChangeTimestamp);

        vm.prank(_buyer);
        uint256 secondOrderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);
        uint256[] memory secondTrades = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondOrderId);
        assertEq(secondTrades.length, 1);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(secondTrades[0]).tokenId, floatingTokenId);
    }

    function test_placeBatchOrder_skipsNonIssuedBond() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);

        uint256 suspendRole = _br.SUSPEND();
        _grantRoles(address(_br), _publisher, suspendRole);

        vm.prank(_publisher);
        _br.suspendBond(BOND_ISIN_ERC6909_FT, 1);

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(_batchInput(50, 1, 10));

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_placeBatchOrder_traderFilter_whitelist() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);

        address[] memory tf = new address[](1);
        tf[0] = _seller;

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(50, 1, 10);
        input.traderFilterMode = IOrderbookMarketplace.TraderFilterMode.WHITELIST;
        input.traderFilterAddresses = tf;

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).amounts.inDeals, 50);
    }

    function test_placeBatchOrder_traderFilter_blacklist_skipsAllLiquidity() public {
        _seedBatchSell(_seller, _bondFTId, 50, 1);

        address[] memory tf = new address[](1);
        tf[0] = _seller;

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(50, 1, 10);
        input.traderFilterMode = IOrderbookMarketplace.TraderFilterMode.BLACKLIST;
        input.traderFilterAddresses = tf;

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_placeBatchOrder_minMatchAmountSkipsSmallLot() public {
        _seedBatchSell(_seller, _bondFTId, 10, 1);
        _seedBatchSell(_seller, _bondFTId, 10, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(30, 1, 10);
        input.minMatchAmount = 15;

        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId).trader, address(0));
    }

    function test_placeBatchOrder_invalidFilterRange_maturity_revertsWhenMarketExists() public {
        _seedBatchSell(_seller, _bondFTId, 10, 1);

        IOrderbookMarketplace.BatchOrderInput memory input = _batchInput(50, 1, 10);
        BondMarketFilter.BondFilter memory f = _emptyBondFilter();
        f.maturityFrom = 200;
        f.maturityTo = 100;
        input.filterData = abi.encode(f);

        vm.prank(_buyer);
        vm.expectRevert(Errors.BondMarketFilter__InvalidFilterRange.selector);
        IOrderbookMarketplace(_orderbookMarketplace).placeBatchOrder(input);
    }

    /*//////////////////////////////////////////////////////////////
                            activeSellMarkets
    //////////////////////////////////////////////////////////////*/

    function test_activeSellMarkets_addOnFirstSell() public {
        IOrderbookMarketplace.Market[] memory pre = IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets();
        assertEq(pre.length, 0);

        _seedBatchSell(_seller, _bondFTId, 10, 1);

        IOrderbookMarketplace.Market[] memory post = IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets();
        assertEq(post.length, 1);
        assertEq(post[0].tokenAddress, _tokenAddr);
        assertEq(post[0].tokenId, _bondFTId);
    }

    function test_activeSellMarkets_sameMarketStaysOnce_onSecondSell() public {
        _seedBatchSell(_seller, _bondFTId, 10, 1);

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 10);
        _placeBatchSellOrder(_seller, _bondFTId, 10, 2);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets().length, 1);
    }

    function test_activeSellMarkets_sameTokenIdDifferentTokenAddressStaySeparate() public {
        OrderbookMockERC6909 secondToken = new OrderbookMockERC6909();
        uint256 tokenId = _tokenId;

        vm.prank(_adminID);
        AssetManager(_assetManager).setAsset(address(secondToken), AssetType.ERC6909, true, false);

        uint256 firstTokenSellOrderId = _seedBatchSell(_seller, tokenId, 10, 1);

        secondToken.mint(_seller, tokenId, 10);
        uint256 secondTokenSellOrderId =
            _placeOrder(_seller, address(secondToken), tokenId, 10, 1, 1, IOrderbookMarketplace.OrderSide.SELL);

        IOrderbookMarketplace.Market[] memory active = IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets();
        assertEq(active.length, 2);
        assertEq(active[0].tokenAddress, _tokenAddr);
        assertEq(active[0].tokenId, tokenId);
        assertEq(active[1].tokenAddress, address(secondToken));
        assertEq(active[1].tokenId, tokenId);

        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(firstTokenSellOrderId, address(0));

        IOrderbookMarketplace.Market[] memory postCancel =
            IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets();
        assertEq(postCancel.length, 1);
        assertEq(postCancel[0].tokenAddress, address(secondToken));
        assertEq(postCancel[0].tokenId, tokenId);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(secondTokenSellOrderId).length, 0);
    }

    function test_activeSellMarkets_removeOnLastOrderCancellation() public {
        uint256 sellOrderId = _seedBatchSell(_seller, _bondFTId, 10, 1);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets().length, 1);

        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(sellOrderId, address(0));

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets().length, 0);
    }

    function test_activeSellMarkets_swapPop_removeNonLast() public {
        // ARRANGE: two markets with active SELL liquidity
        uint256 sellOnFirst = _seedBatchSell(_seller, _bondFTId, 10, 1);
        uint256 secondTokenId = _createSecondBond(
            _SECOND_ISIN, "USD", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        _seedBatchSell(_seller, secondTokenId, 10, 1);

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets().length, 2);

        // ACT: cancel SELL on the first market (index 0, NOT last) → swap-pop
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(sellOnFirst, address(0));

        // ASSERT: array has 1 element, secondTokenId moved from index 1 to 0
        IOrderbookMarketplace.Market[] memory post = IOrderbookMarketplace(_orderbookMarketplace).activeSellMarkets();
        assertEq(post.length, 1);
        assertEq(post[0].tokenAddress, _tokenAddr);
        assertEq(post[0].tokenId, secondTokenId);
    }

    function test_activeSellMarkets_reverts_tooManyActiveSellMarkets() public {
        uint256 maxMarkets = OrderbookMarketplace(_orderbookMarketplace).MAX_ACTIVE_SELL_MARKETS();

        for (uint256 i; i < maxMarkets; ++i) {
            string memory isin = string.concat("SK0001002", vm.toString(100 + i));
            uint256 tokenId = _createSecondBond(
                isin, "EUR", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
            );
            _seedBatchSell(_seller, tokenId, 1, 1);
        }

        uint256 overflowTokenId = _createSecondBond(
            "SK0001002200", "EUR", CouponRateType.FIXED, _SECOND_BOND_NOMINAL_VALUE, 400, _SECOND_COUPON_RATE
        );
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, overflowTokenId, 1);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        vm.expectRevert(Errors.OrderbookMarketplace__TooManyActiveSellMarkets.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: overflowTokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    /*//////////////////////////////////////////////////////////////
                            setDelegate
    //////////////////////////////////////////////////////////////*/

    function test_setDelegate_success_authorize() public {
        address delegate = makeAddr("delegate");

        vm.expectEmit();
        emit IOrderbookMarketplace.DelegateSet(_buyer, delegate, true);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);
    }

    function test_setDelegate_success_revoke() public {
        address delegate = makeAddr("delegate");

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        vm.expectEmit();
        emit IOrderbookMarketplace.DelegateSet(_buyer, delegate, false);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, false);
    }

    function test_setDelegate_reverts_zeroDelegate() public {
        vm.prank(_buyer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(address(0), true);
    }

    /*//////////////////////////////////////////////////////////////
                        delegated placeOrder
    //////////////////////////////////////////////////////////////*/

    function test_placeOrder_delegated_buyOrder_storesTraderAsOnBehalfOf() public {
        // PREPARE
        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        uint256 orderId;
        {
            // ACT: delegate places BUY order on behalf of _buyer
            vm.startPrank(delegate);
            vm.expectEmit();
            emit IOrderbookMarketplace.OrderPlaced(
                1,
                _tokenId,
                _buyer,
                _tokenAddr,
                5,
                5,
                1,
                1,
                0,
                IOrderbookMarketplace.TraderFilterMode.NONE,
                IOrderbookMarketplace.OrderSide.BUY,
                0
            );
            orderId = IOrderbookMarketplace(_orderbookMarketplace)
                .placeOrder(
                    IOrderbookMarketplace.OrderInput({
                    tokenAddress: _tokenAddr,
                    tokenId: _tokenId,
                    totalAmount: 5,
                    minPrice: 1,
                    maxPrice: 1,
                    minMatchAmount: 0,
                    traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                    traderFilterAddresses: new address[](0),
                    side: IOrderbookMarketplace.OrderSide.BUY,
                    expiry: 0
                }),
                    _buyer
                );
            vm.stopPrank();
        }

        // ASSERT: order.trader == _buyer, not delegate
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.trader, _buyer);
    }

    function test_placeOrder_delegated_sellOrder_escrrowsFromTrader() public {
        uint256 sellAmount = 10;
        uint256 unitPrice = 1;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);

        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        uint256 sellerBalanceBefore = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        // ACT: delegate places SELL on behalf of _seller
        vm.prank(delegate);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                _seller
            );

        // ASSERT: tokens taken from _seller (not delegate); order.trader == _seller
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId), sellerBalanceBefore - sellAmount);
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(orderId);
        assertEq(order.trader, _seller);
    }

    function test_cancelOrder_delegated_sellOrder_returnsToTrader() public {
        uint256 sellAmount = 10;
        uint256 unitPrice = 1;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);

        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        vm.prank(delegate);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                _seller
            );

        uint256 sellerBalanceAfterEscrow = DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId);

        // ACT: delegate cancels on behalf of _seller → tokens return to _seller
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderCancelled(orderId, _seller, sellAmount);

        vm.prank(delegate);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, _seller);

        assertEq(DEUSSToken(_tokenAddr).balanceOf(_seller, _bondFTId), sellerBalanceAfterEscrow + sellAmount);
    }

    function test_placeOrder_reverts_delegateNotAuthorized() public {
        (address notDelegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("notDelegateOwner"), 0);

        vm.prank(notDelegate);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__DelegateNotAuthorized.selector, notDelegate, _buyer)
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                _buyer
            );
    }

    function test_placeOrder_reverts_delegateNotRegistered() public {
        address unregisteredDelegate = makeAddr("unregisteredDelegate");

        vm.prank(unregisteredDelegate);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, unregisteredDelegate)
        );
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                _buyer
            );
    }

    function test_placeOrder_reverts_traderNotRegistered() public {
        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        address unregisteredTrader = makeAddr("unregisteredTrader");

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, unregisteredTrader));
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 1,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                unregisteredTrader
            );
    }

    // solhint-disable function-max-lines
    function test_placeOrder_delegated_selfMatchPrevention() public {
        uint256 amount = 10;
        uint256 unitPrice = 1;

        // _buyer places a direct BUY order
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // Give _buyer tokens and set up delegate
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_buyer, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_buyer);

        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        // Delegate places SELL on behalf of _buyer → same effectiveTrader as the BUY order
        vm.prank(delegate);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                _buyer
            );

        // ASSERT: no match (self-match prevented)
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(buyOrder.amounts.available, amount);
    }

    // solhint-disable function-max-lines
    function test_placeOrder_delegated_traderFilterUsesEffectiveTrader() public {
        uint256 sellAmount = 10;
        uint256 unitPrice = 1;

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, sellAmount);
        _approveEscrowManagerAsOperator(_seller);

        // Seller whitelist contains _buyer but NOT the delegate
        address[] memory whitelist = new address[](1);
        whitelist[0] = _buyer;
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.WHITELIST,
                traderFilterAddresses: whitelist,
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        // Register a delegate (not in whitelist) and authorize it for _buyer
        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        // ACT: delegate places BUY on behalf of _buyer — filter must check _buyer, not delegate
        vm.prank(delegate);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: sellAmount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                _buyer
            );

        // ASSERT: trade was created with effectiveTrader identities
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 1);
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeIds[0]);
        assertEq(trade.buyer, _buyer);
        assertEq(trade.seller, _seller);
    }

    function test_cancelOrder_reverts_delegateRevoked() public {
        uint256 amount = 5;
        uint256 unitPrice = 1;

        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        // Delegate places a BUY on behalf of _buyer
        vm.prank(delegate);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                _buyer
            );

        // _buyer immediately revokes the delegation
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, false);

        // Revoked delegate tries to cancel — must revert
        vm.prank(delegate);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__DelegateNotAuthorized.selector, delegate, _buyer)
        );
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, _buyer);
    }

    function test_cancelOrder_reverts_delegated_orderNotOwnedByPrincipal() public {
        uint256 amount = 5;
        uint256 unitPrice = 1;

        // _buyer places an order directly
        vm.prank(_buyer);
        uint256 buyerOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        // _seller authorizes a delegate, but the order belongs to _buyer
        (address delegate,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("delegateOwner"), 0);
        vm.prank(_seller);
        IOrderbookMarketplace(_orderbookMarketplace).setDelegate(delegate, true);

        // Delegate tries to cancel _buyer's order on behalf of _seller — must revert
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__NotAuthorized.selector, delegate));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(buyerOrderId, _seller);
    }

    /*//////////////////////////////////////////////////////////////
                    setOrderFrozen / setTradeFrozen
    //////////////////////////////////////////////////////////////*/

    function test_setOrderFrozen_success() public {
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderFrozenSet(orderId, true, reason, freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, reason);

        vm.prank(freezer);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderFrozenSet(orderId, false, reason, freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, false, reason);
    }

    function test_setOrderFrozen_reverts_nonexistentOrder() public {
        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(999, true, reason);
    }

    function test_setOrderFrozen_reverts_notFreezeRole() public {
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        address notFreezer = makeAddr("notFreezer");
        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(notFreezer);
        vm.expectRevert();
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, reason);
    }

    function test_setTradeFrozen_success() public {
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        uint256 tradeId = tradeIds[0];

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeFrozenSet(tradeId, true, reason, freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.prank(freezer);
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeFrozenSet(tradeId, false, reason, freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, false, reason);
    }

    function test_setTradeFrozen_reverts_nonexistentTrade() public {
        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(999, true, reason);
    }

    function test_cancelOrder_reverts_whenFrozen() public {
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, reason);

        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderFrozen.selector, orderId));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));
    }

    function test_placeOrder_skips_frozenSellOrders() public {
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(sellOrderId, true, reason);

        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_placeOrder_skips_frozenBuyOrders() public {
        vm.prank(_buyer);
        uint256 buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(buyOrderId, true, reason);

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(tradeIds.length, 0);
    }

    function test_markTradePaid_reverts_whenFrozen() public {
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        uint256 tradeId = tradeIds[0];

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.prank(_paymentHandler);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, tradeId));
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
    }

    function test_settleTrade_reverts_whenFrozen() public {
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        uint256 tradeId = tradeIds[0];

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        bytes32 reason = bytes32(keccak256("SANCTIONS"));
        vm.prank(freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, tradeId));
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    function test_setOrderFrozen_reverts_zeroReason() public {
        vm.prank(_buyer);
        uint256 orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        vm.prank(freezer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroFreezeReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, bytes32(0));
    }

    function test_setTradeFrozen_reverts_zeroReason() public {
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, 100);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        uint256 sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: 100,
                minPrice: 1,
                maxPrice: 1,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        uint256 tradeId = tradeIds[0];

        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        address freezer = makeAddr("freezer");
        _grantRoles(_orderbookMarketplace, freezer, freezeRole);

        vm.prank(freezer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroFreezeReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, bytes32(0));
    }

    function _createMatchedTrade(uint256 amount, uint256 unitPrice)
        internal
        returns (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId)
    {
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(_seller, _bondFTId, amount);
        _approveEscrowManagerAsOperator(_seller);

        vm.prank(_seller);
        sellOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );

        vm.prank(_buyer);
        buyOrderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: unitPrice,
                maxPrice: unitPrice,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );

        tradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId)[0];
    }

    function _createUnpaidTrade(uint256 amount, uint256 unitPrice)
        internal
        returns (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId)
    {
        (tradeId, sellOrderId, buyOrderId) = _createMatchedTrade(amount, unitPrice);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.warp(trade.paymentDeadline + 1);
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                            freeze / seizure
    //////////////////////////////////////////////////////////////*/

    function test_deployment_grantsGovernanceOrderbookFreezeAndSeizureRoles() public view {
        uint256 freezeRole = OrderbookMarketplace(_orderbookMarketplace).FREEZE_ROLE();
        uint256 seizureRole = OrderbookMarketplace(_orderbookMarketplace).SEIZURE_ROLE();

        assertTrue(OrderbookMarketplace(_orderbookMarketplace).hasAnyRole(_governance, freezeRole));
        assertTrue(OrderbookMarketplace(_orderbookMarketplace).hasAnyRole(_governance, seizureRole));
    }

    function test_regression_TradeStatus_SEIZED_enumValue_isAppended() public pure {
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.NONE), 0);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.PENDING), 1);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.PAID), 2);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.UNPAID), 3);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.IN_DISPUTE), 4);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.CANCELLED), 5);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.SETTLED), 6);
        assertEq(uint8(IOrderbookMarketplace.TradeStatus.SEIZED), 7);
    }

    function test_setOrderFrozen_success_blocksCancelAndUnfreezeRestoresCancel() public {
        uint256 orderId = _placeBuyOrder(_buyer, 100, 1);
        bytes32 reason = keccak256("SANCTIONS");

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderFrozenSet(orderId, true, reason, _freezer);

        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, reason);

        vm.prank(_buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderFrozen.selector, orderId));
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderFrozenSet(orderId, false, reason, _freezer);

        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, false, reason);

        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).cancelOrder(orderId, address(0));
    }

    function test_setOrderFrozen_reverts_invalidInputsAndUnauthorized() public {
        uint256 orderId = _placeBuyOrder(_buyer, 100, 1);
        bytes32 reason = keccak256("SANCTIONS");

        vm.prank(makeAddr("notFreezer"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, reason);

        vm.prank(_freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(999, true, reason);

        vm.prank(_freezer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroFreezeReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, true, bytes32(0));
    }

    function test_setTradeFrozen_success_blocksPaymentAndUnfreezeRestoresPayment() public {
        (,, uint256 tradeId) = _createOrderbookTrade(100);
        bytes32 reason = keccak256("SANCTIONS");

        vm.expectEmit();
        emit IOrderbookMarketplace.TradeFrozenSet(tradeId, true, reason, _freezer);

        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.prank(_paymentHandler);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, tradeId));
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        vm.expectEmit();
        emit IOrderbookMarketplace.TradeFrozenSet(tradeId, false, reason, _freezer);

        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, false, reason);

        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
    }

    function test_setTradeFrozen_reverts_invalidInputsAndUnauthorized() public {
        (,, uint256 tradeId) = _createOrderbookTrade(100);
        bytes32 reason = keccak256("SANCTIONS");

        vm.prank(makeAddr("notFreezer"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, reason);

        vm.prank(_freezer);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(999, true, reason);

        vm.prank(_freezer);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroFreezeReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, true, bytes32(0));
    }

    function test_placeOrder_skipsFrozenBuyOrderAndMatchesNextExecutableOrder() public {
        uint256 frozenBuyOrderId = _placeBuyOrder(_buyer, 100, 1);
        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondBuyer"), 0);
        uint256 activeBuyOrderId = _placeBuyOrder(secondBuyer, 100, 1);
        _freezeOrder(frozenBuyOrderId, true);

        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);

        uint256[] memory sellTradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        uint256[] memory frozenBuyTradeIds =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(frozenBuyOrderId);
        uint256[] memory activeBuyTradeIds =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(activeBuyOrderId);

        assertEq(sellTradeIds.length, 1);
        assertEq(activeBuyTradeIds.length, 1);
        assertEq(frozenBuyTradeIds.length, 0);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(sellTradeIds[0]).buyOrderId, activeBuyOrderId);
    }

    function test_placeOrder_skipsFrozenSellOrderAndMatchesNextExecutableOrder() public {
        uint256 frozenSellOrderId = _placeSellOrder(_seller, 100, 1);
        (address secondSeller,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondSeller"), 0);
        uint256 activeSellOrderId = _placeSellOrder(secondSeller, 100, 1);
        _freezeOrder(frozenSellOrderId, true);

        uint256 buyOrderId = _placeBuyOrder(_buyer, 100, 1);

        uint256[] memory buyTradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(buyOrderId);
        uint256[] memory frozenSellTradeIds =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(frozenSellOrderId);
        uint256[] memory activeSellTradeIds =
            IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(activeSellOrderId);

        assertEq(buyTradeIds.length, 1);
        assertEq(activeSellTradeIds.length, 1);
        assertEq(frozenSellTradeIds.length, 0);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getTrade(buyTradeIds[0]).sellOrderId, activeSellOrderId);
    }

    function test_getOrderBook_excludesFrozenOrders() public {
        uint256 activeBuyOrderId = _placeBuyOrder(_buyer, 100, 1);
        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondBuyer2"), 0);
        uint256 frozenBuyOrderId = _placeBuyOrder(secondBuyer, 100, 1);
        uint256 activeSellOrderId = _placeSellOrder(_seller, 100, 10);
        (address secondSeller,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondSeller2"), 0);
        uint256 frozenSellOrderId = _placeSellOrder(secondSeller, 100, 11);

        _freezeOrder(frozenBuyOrderId, true);
        _freezeOrder(frozenSellOrderId, true);

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);

        assertEq(buyOrders.length, 1);
        assertEq(sellOrders.length, 1);
        assertEq(buyOrders[0].trader, _buyer);
        assertEq(sellOrders[0].trader, _seller);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(activeBuyOrderId).amounts.available, 100);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(activeSellOrderId).amounts.available, 100);

        // Frozen orders are still present in storage with their amounts intact — the view
        // just hides them to match the matchable state surfaced by _matchBuyOrder/_matchSellOrder.
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(frozenBuyOrderId).amounts.available, 100);
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(frozenSellOrderId).amounts.available, 100);
    }

    function test_frozenTrade_blocksUnpaidAndSettlement() public {
        (,, uint256 unpaidTradeId) = _createOrderbookTrade(100);
        _freezeTrade(unpaidTradeId, true);
        IOrderbookMarketplace.Trade memory unpaidTrade =
            IOrderbookMarketplace(_orderbookMarketplace).getTrade(unpaidTradeId);
        vm.warp(unpaidTrade.paymentDeadline + 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, unpaidTradeId));
        IOrderbookMarketplace(_orderbookMarketplace).markTradeUnpaid(unpaidTradeId);

        (,, uint256 completedTradeId) = _createOrderbookTrade(100);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(completedTradeId);
        _freezeTrade(completedTradeId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeFrozen.selector, completedTradeId));
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(completedTradeId);
    }

    function test_settleTrade_reverts_whenParentOrdersAreFrozen() public {
        (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId) = _createOrderbookTrade(100);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        _freezeOrder(sellOrderId, true);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderFrozen.selector, sellOrderId));
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
        _freezeOrder(sellOrderId, false);

        _freezeOrder(buyOrderId, true);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderFrozen.selector, buyOrderId));
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    function test_seizeOrder_success_emitsAndTransfersAvailableEscrow() public {
        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);
        _freezeOrder(sellOrderId, true);
        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderSeized(sellOrderId, _company, 100, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.amounts.available, 0);
        assertEq(order.amounts.inDeals, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeOrder_buyOrderEmitsSeizedWithoutEscrowTransfer() public {
        uint256 buyOrderId = _placeBuyOrder(_buyer, 100, 1);
        _freezeOrder(buyOrderId, true);
        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(buyOrderId, _buyer);
        vm.expectEmit();
        // @dev no tokens being actually transferred/seized
        emit IOrderbookMarketplace.OrderSeized(buyOrderId, _company, 0, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(buyOrderId, _company, reason);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);
        assertEq(order.trader, address(0));
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore);
    }

    function test_seizeOrder_reverts_invalidInputsAndUnauthorized() public {
        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);
        bytes32 reason = keccak256("JUDICIAL_ORDER");

        vm.prank(makeAddr("notSeizer"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);

        vm.prank(_governance);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(999, _company, reason);

        vm.prank(_governance);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__CannotSeizeUnfrozenOrder.selector, sellOrderId)
        );
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);

        _freezeOrder(sellOrderId, true);

        vm.prank(_governance);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, address(0), reason);

        vm.prank(_governance);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, bytes32(0));

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);

        // After a full seizure with no pending trades, the order is deleted, so the next
        // attempt surfaces OrderNotFound rather than NoAvailableAmountToSeize.
        vm.prank(_governance);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__OrderNotFound.selector, sellOrderId));
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);
    }

    /// @notice A seize on a partially-matched order leaves the order alive (inDeals > 0)
    /// and a second seize reverts with NoAvailableAmountToSeize.
    function test_seizeOrder_reverts_noAvailableAmountOnPartiallyMatchedOrder() public {
        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);
        // Match part of it so the sell order has inDeals > 0 and available > 0
        _placeBuyOrder(_buyer, 40, 1);
        _freezeOrder(sellOrderId, true);

        bytes32 reason = keccak256("JUDICIAL_ORDER");

        // First seize drains the remaining `available` (60) but leaves `inDeals` (40) intact,
        // so the order stays in storage.
        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.amounts.available, 0);
        assertEq(order.amounts.inDeals, 40);
        assertTrue(order.trader != address(0));

        vm.prank(_governance);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__NoAvailableAmountToSeize.selector, sellOrderId)
        );
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, reason);
    }

    /// @notice When a seized order has no pending trades (inDeals == 0), it must be removed
    /// from the sorted order arrays so it does not linger as a dead entry.
    function test_seizeOrder_deletesOrderWhenNoPendingTrades() public {
        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);
        _freezeOrder(sellOrderId, true);

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(sellOrderId, _seller);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, keccak256("JUDICIAL_ORDER"));

        // Order is fully removed from storage and from the sell-order array.
        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.trader, address(0));

        (, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(sellOrders.length, 0);
    }

    /// @notice A partially-matched sell order (inDeals > 0) must NOT be deleted on seize —
    /// its pending trades still need the escrow and order metadata to settle.
    function test_seizeOrder_keepsOrderWhenPendingTradesExist() public {
        uint256 sellOrderId = _placeSellOrder(_seller, 100, 1);
        _placeBuyOrder(_buyer, 30, 1);
        _freezeOrder(sellOrderId, true);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeOrder(sellOrderId, _company, keccak256("JUDICIAL_ORDER"));

        IOrderbookMarketplace.Order memory order = IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(order.trader, _seller);
        assertEq(order.amounts.available, 0);
        assertEq(order.amounts.inDeals, 30);
    }

    function test_seizeTrade_success_emitsTransfersEscrowToBeneficiaryAndClosesPendingTrade() public {
        (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId) = _createFrozenSeizableTrade(100);
        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        vm.expectEmit();
        emit IOrderbookMarketplace.TradeSeized(tradeId, sellOrderId, _company, 100, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);

        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.SEIZED));
        assertEq(sellOrder.amounts.available, 0);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.sold, 0);
        assertEq(buyOrder.amounts.available, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeTrade_postSeizureCannotResumeLifecycle() public {
        (,, uint256 tradeId) = _createFrozenSeizableTrade(100);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, keccak256("JUDICIAL_ORDER"));

        // The sell and buy orders are fully drained (available=0, inDeals=0 post-seize) and
        // deleted, so only the trade unfreeze matters here to probe the lifecycle transitions.
        _freezeTrade(tradeId, false);

        vm.prank(_paymentHandler);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidTradeStatus.selector,
                uint8(IOrderbookMarketplace.TradeStatus.SEIZED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__TradeNotSettleable.selector,
                uint8(IOrderbookMarketplace.TradeStatus.SEIZED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    /// @notice When a seized trade is the last inDeals amount on both orders and both have
    /// available == 0, both orders must be deleted from the sorted order arrays.
    function test_seizeTrade_deletesFullyDrainedOrders() public {
        (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId) = _createFrozenSeizableTrade(100);

        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(sellOrderId, _seller);
        vm.expectEmit();
        emit IOrderbookMarketplace.OrderDeleted(buyOrderId, _buyer);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, keccak256("JUDICIAL_ORDER"));

        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId).trader, address(0));
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId).trader, address(0));

        (IOrderbookMarketplace.Order[] memory buyOrders, IOrderbookMarketplace.Order[] memory sellOrders) =
            IOrderbookMarketplace(_orderbookMarketplace).getOrderBook(_tokenAddr, _tokenId);
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
    }

    /// @notice When a seized trade is only a fraction of an order's inDeals, the order must
    /// remain in storage to back any other pending trades tied to it.
    function test_seizeTrade_keepsOrdersWhenOtherPendingTradesRemain() public {
        // Place a larger sell order that will match two separate buy orders, producing two
        // pending trades on the same sell order.
        uint256 sellOrderId = _placeSellOrder(_seller, 200, 1);
        uint256 firstBuyOrderId = _placeBuyOrder(_buyer, 100, 1);
        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondBuyerSeizePartial"), 0);
        uint256 secondBuyOrderId = _placeBuyOrder(secondBuyer, 100, 1);

        uint256[] memory sellTradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        assertEq(sellTradeIds.length, 2);

        _freezeOrder(sellOrderId, true);
        _freezeTrade(sellTradeIds[0], true);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(sellTradeIds[0], _company, keccak256("JUDICIAL_ORDER"));

        // Sell order: still has the second pending trade, must survive
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        assertEq(sellOrder.trader, _seller);
        assertEq(sellOrder.amounts.available, 0);
        assertEq(sellOrder.amounts.inDeals, 100);

        // The first buy order (tied to the seized trade) had available=0 and inDeals=100
        // drained to 0 → deleted.
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(firstBuyOrderId).trader, address(0));
        // The second buy order is untouched by the seize.
        assertEq(IOrderbookMarketplace(_orderbookMarketplace).getOrder(secondBuyOrderId).trader, secondBuyer);
    }

    function test_seizeTrade_reverts_invalidInputsAndUnauthorized() public {
        (,, uint256 tradeId) = _createOrderbookTrade(100);
        bytes32 reason = keccak256("JUDICIAL_ORDER");

        vm.prank(makeAddr("notSeizer"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);

        vm.prank(_governance);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__TradeNotFound.selector, 999));
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(999, _company, reason);

        vm.prank(_governance);
        vm.expectRevert(abi.encodeWithSelector(Errors.OrderbookMarketplace__CannotSeizeUnfrozenTrade.selector, tradeId));
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);
    }

    function test_seizeTrade_reverts_whenParentOrderNotFrozen() public {
        (,, uint256 tradeId) = _createOrderbookTrade(100);
        _freezeTrade(tradeId, true);

        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        vm.prank(_governance);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__ParentOrderNotFrozen.selector, trade.sellOrderId)
        );
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, keccak256("JUDICIAL_ORDER"));
    }

    function test_seizeTrade_reverts_zeroBeneficiaryZeroReasonAndAlreadySeized() public {
        (,, uint256 zeroBeneficiaryTradeId) = _createFrozenSeizableTrade(100);

        vm.prank(_governance);
        vm.expectRevert(Errors.ZeroAddress.selector);
        IOrderbookMarketplace(_orderbookMarketplace)
            .seizeTrade(zeroBeneficiaryTradeId, address(0), keccak256("JUDICIAL_ORDER"));

        (,, uint256 zeroReasonTradeId) = _createFrozenSeizableTrade(100);
        vm.prank(_governance);
        vm.expectRevert(Errors.OrderbookMarketplace__ZeroReason.selector);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(zeroReasonTradeId, _company, bytes32(0));

        uint256 sellOrderId = _placeSellOrder(_seller, 200, 1);
        _placeBuyOrder(_buyer, 100, 1);
        (address secondBuyer,) =
            _createAndRegisterEntityWalletForCompany(_entityRegistryAdmin, makeAddr("secondBuyerSeizeReseize"), 0);
        _placeBuyOrder(secondBuyer, 100, 1);

        uint256 seizedTradeId = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId)[0];
        _freezeOrder(sellOrderId, true);
        _freezeTrade(seizedTradeId, true);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(seizedTradeId, _company, keccak256("JUDICIAL_ORDER"));

        vm.prank(_governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__InvalidTradeStatus.selector,
                uint8(IOrderbookMarketplace.TradeStatus.SEIZED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(seizedTradeId, _company, keccak256("JUDICIAL_ORDER"));
    }

    function test_seizeTrade_success_seizesPaidTradeAndTransfersEscrowToBeneficiary() public {
        // PREPARE: frozen PAID trade + balance snapshots
        (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId) = _createOrderbookTrade(100);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);
        _freezeOrder(sellOrderId, true);
        _freezeTrade(tradeId, true);

        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        // ACT: governance seizes the PAID trade
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeSeized(tradeId, sellOrderId, _company, 100, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);

        // ASSERT: trade SEIZED, orders zeroed, escrow drained, beneficiary credited
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);

        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.SEIZED));
        assertEq(sellOrder.amounts.available, 0);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.sold, 0);
        assertEq(buyOrder.amounts.available, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeTrade_success_seizesUnpaidTradeAndTransfersEscrowToBeneficiary() public {
        // PREPARE: expired trade marked UNPAID before compliance freeze
        (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId) = _createUnpaidTrade(100, 1);
        _freezeOrder(sellOrderId, true);
        _freezeTrade(tradeId, true);

        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        // ACT: governance seizes the UNPAID trade instead of requiring normal settlement
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeSeized(tradeId, sellOrderId, _company, 100, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);

        // ASSERT: trade SEIZED, orders drained, escrow recovered to beneficiary
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);

        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.SEIZED));
        assertEq(sellOrder.amounts.available, 0);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.available, 0);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeTrade_success_seizesInDisputeTradeAndTransfersEscrowToBeneficiary() public {
        // PREPARE: expired trade marked UNPAID and disputed before compliance freeze
        (uint256 tradeId, uint256 sellOrderId, uint256 buyOrderId) = _createUnpaidTrade(100, 1);
        vm.prank(_buyer);
        IOrderbookMarketplace(_orderbookMarketplace).initiateDispute(tradeId);
        _freezeOrder(sellOrderId, true);
        _freezeTrade(tradeId, true);

        bytes32 reason = keccak256("JUDICIAL_ORDER");
        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        // ACT: governance seizes the IN_DISPUTE trade as a compliance override
        vm.expectEmit();
        emit IOrderbookMarketplace.TradeSeized(tradeId, sellOrderId, _company, 100, reason, _governance);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, reason);

        // ASSERT: trade SEIZED, orders drained, escrow recovered to beneficiary
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        IOrderbookMarketplace.Order memory sellOrder =
            IOrderbookMarketplace(_orderbookMarketplace).getOrder(sellOrderId);
        IOrderbookMarketplace.Order memory buyOrder = IOrderbookMarketplace(_orderbookMarketplace).getOrder(buyOrderId);

        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.SEIZED));
        assertEq(sellOrder.amounts.available, 0);
        assertEq(sellOrder.amounts.inDeals, 0);
        assertEq(buyOrder.amounts.available, 0);
        assertEq(buyOrder.amounts.inDeals, 0);
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeTrade_recoverySucceedsForPaidTradeWhenBuyerDisabled() public {
        // PREPARE: PAID trade + buyer disabled (settle would otherwise revert)
        (, uint256 sellOrderId, uint256 tradeId) = _createOrderbookTrade(100);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        vm.prank(_entityRegistryAdmin);
        _er.setAccountStatus(_buyer, AccountStatus.DISABLED, "buyer disabled");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Token__TransferNotAllowed.selector, _escrowManager, _buyer, _bondFTId)
        );
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);

        _freezeOrder(sellOrderId, true);
        _freezeTrade(tradeId, true);

        uint256 escrowId = _orderbookEscrowIdByOrderId(sellOrderId);
        uint256 escrowBefore = EscrowManager(_escrowManager).getEscrow(escrowId).amount;
        uint256 beneficiaryBefore = DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId);

        // ACT: governance seizes the stuck PAID trade
        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, keccak256("JUDICIAL_ORDER"));

        // ASSERT: escrow recovered to beneficiary, trade SEIZED
        IOrderbookMarketplace.Trade memory trade = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(trade.status), uint8(IOrderbookMarketplace.TradeStatus.SEIZED));
        assertEq(EscrowManager(_escrowManager).getEscrow(escrowId).amount, escrowBefore - 100);
        assertEq(DEUSSToken(_tokenAddr).balanceOf(_company, _bondFTId), beneficiaryBefore + 100);
    }

    function test_seizeTrade_postSeizurePaidCannotBeSettled() public {
        // PREPARE: PAID trade seized, then unfrozen so the status guard is reachable
        (,, uint256 tradeId) = _createOrderbookTrade(100);
        vm.prank(_paymentHandler);
        IOrderbookMarketplace(_orderbookMarketplace).markTradePaid(tradeId);

        IOrderbookMarketplace.Trade memory tradeBefore = IOrderbookMarketplace(_orderbookMarketplace).getTrade(tradeId);
        assertEq(uint8(tradeBefore.status), uint8(IOrderbookMarketplace.TradeStatus.PAID));

        _freezeOrder(tradeBefore.sellOrderId, true);
        _freezeTrade(tradeId, true);

        vm.prank(_governance);
        IOrderbookMarketplace(_orderbookMarketplace).seizeTrade(tradeId, _company, keccak256("JUDICIAL_ORDER"));

        _freezeTrade(tradeId, false);

        // ACT: settle on the SEIZED-from-PAID trade reverts with TradeNotSettleable
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OrderbookMarketplace__TradeNotSettleable.selector,
                uint8(IOrderbookMarketplace.TradeStatus.SEIZED)
            )
        );
        IOrderbookMarketplace(_orderbookMarketplace).settleTrade(tradeId);
    }

    /*//////////////////////////////////////////////////////////////
                            private test helpers
    //////////////////////////////////////////////////////////////*/

    function _placeBuyOrder(address trader, uint256 amount, uint256 price) private returns (uint256 orderId) {
        vm.prank(trader);
        orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.BUY,
                expiry: 0
            }),
                address(0)
            );
    }

    function _placeSellOrder(address trader, uint256 amount, uint256 price) private returns (uint256 orderId) {
        vm.prank(_company);
        DEUSSToken(_tokenAddr).transfer(trader, _bondFTId, amount);
        _approveEscrowManagerAsOperator(trader);

        vm.prank(trader);
        orderId = IOrderbookMarketplace(_orderbookMarketplace)
            .placeOrder(
                IOrderbookMarketplace.OrderInput({
                tokenAddress: _tokenAddr,
                tokenId: _tokenId,
                totalAmount: amount,
                minPrice: price,
                maxPrice: price,
                minMatchAmount: 0,
                traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
                traderFilterAddresses: new address[](0),
                side: IOrderbookMarketplace.OrderSide.SELL,
                expiry: 0
            }),
                address(0)
            );
    }

    function _createOrderbookTrade(uint256 amount)
        private
        returns (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId)
    {
        buyOrderId = _placeBuyOrder(_buyer, amount, 1);
        sellOrderId = _placeSellOrder(_seller, amount, 1);
        uint256[] memory tradeIds = IOrderbookMarketplace(_orderbookMarketplace).getTradeIdsByOrderId(sellOrderId);
        tradeId = tradeIds[0];
    }

    function _createFrozenSeizableTrade(uint256 amount)
        private
        returns (uint256 buyOrderId, uint256 sellOrderId, uint256 tradeId)
    {
        (buyOrderId, sellOrderId, tradeId) = _createOrderbookTrade(amount);
        _freezeOrder(sellOrderId, true);
        _freezeTrade(tradeId, true);
    }

    function _freezeOrder(uint256 orderId, bool frozen) private {
        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setOrderFrozen(orderId, frozen, keccak256("SANCTIONS"));
    }

    function _freezeTrade(uint256 tradeId, bool frozen) private {
        vm.prank(_freezer);
        IOrderbookMarketplace(_orderbookMarketplace).setTradeFrozen(tradeId, frozen, keccak256("SANCTIONS"));
    }
}

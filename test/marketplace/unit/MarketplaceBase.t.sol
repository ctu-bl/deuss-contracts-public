// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "src/libs/Errors.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {DependenciesBase} from "src/base/DependenciesBase.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";
// test files
import {MockMarketplace} from "test/mocks/MockContracts.sol";
import {SharedUtilities} from "test/fixtures/SharedUtilities.t.sol";

contract MarketplaceNamespacedStorageHarness is Marketplace {
    function exposedMarketplaceStorageLocation() external pure returns (bytes32) {
        return _MARKETPLACE_STORAGE_LOCATION;
    }

    function exposedIncrementOfferCounter() external returns (uint256 offerCounter) {
        MarketplaceStorage.Counters storage counters = _marketplaceStorage().counters;
        offerCounter = ++counters.offerCounter;
    }

    function exposedIncrementDealCounter() external returns (uint256 dealCounter) {
        MarketplaceStorage.Counters storage counters = _marketplaceStorage().counters;
        dealCounter = ++counters.dealCounter;
    }

    function exposedIncrementInterestCounter() external returns (uint256 interestCounter) {
        MarketplaceStorage.Counters storage counters = _marketplaceStorage().counters;
        interestCounter = ++counters.interestCounter;
    }
}

contract MarketplaceBaseTest is SharedUtilities {
    event EntityTypeAllowed(uint256 indexed typeId, bool indexed allowed);
    event MaxCounterOffersPerUserSet(uint256 indexed maxCounterOffers);

    address internal _marketplace;
    UpgradeableBeacon internal _marketplaceBeacon;

    address internal _adminID;
    address internal _notGovernance;

    uint256 internal _expiryThreshold = 1 days;

    function _config() internal view returns (MarketplaceStorage.Config memory config) {
        (config,) = MarketplaceBase(_marketplace).getConfigAndCounters();
    }

    function setUp() public override {
        super.setUp();

        _adminID = makeAddr("adminID");
        _notGovernance = makeAddr("notGovernance");

        _marketplace = _suite.core.marketplace;
        _marketplaceBeacon = UpgradeableBeacon(_suite.core.marketplaceBeacon);

        uint256 adminRole = MarketplaceBase(_marketplace).ADMIN();
        _grantRoles(_marketplace, _adminID, adminRole);
    }

    /*//////////////////////////////////////////////////////////////
                             upgradeTo
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_reverts_notBeaconOwner() public {
        address newImpl = address(new MockMarketplace());
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, notOwner));
        _marketplaceBeacon.upgradeTo(newImpl);
    }

    function test_initialize_success_freshBeaconProxy() public {
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                _marketplaceAssetManager(_marketplace),
                _suite.core.escrowManager,
                _suite.registries.entityRegistry,
                5
            )
        );

        address freshMarketplace = address(new BeaconProxy(address(_marketplaceBeacon), initData));

        assertEq(_marketplaceAssetManager(freshMarketplace), _suite.core.assetManager);
        assertEq(MarketplaceBase(freshMarketplace).getEscrowManager(), _suite.core.escrowManager);
        assertEq(MarketplaceBase(freshMarketplace).getEntityRegistry(), _suite.registries.entityRegistry);
        assertEq(
            _configFor(freshMarketplace).redemptionPaymentExpiryThreshold,
            MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD()
        );
    }

    function test_initialize_reverts_maxOfferLifetimeAboveHardCap() public {
        uint256 aboveMax = MarketplaceBase(_marketplace).MAX_CONFIGURABLE_OFFER_LIFETIME() + 1;
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                aboveMax,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                _marketplaceAssetManager(_marketplace),
                _suite.core.escrowManager,
                _suite.registries.entityRegistry,
                5
            )
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__MaxOfferLifetimeTooHigh.selector, aboveMax));
        new BeaconProxy(address(_marketplaceBeacon), initData);
    }

    function test_initialize_reverts_maxOfferLifetimeBelowOfferExpiryThreshold() public {
        uint256 offerExpiryThreshold = MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD();
        uint256 maxOfferLifetime = offerExpiryThreshold - 1;
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                offerExpiryThreshold,
                maxOfferLifetime,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                _marketplaceAssetManager(_marketplace),
                _suite.core.escrowManager,
                _suite.registries.entityRegistry,
                5
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold.selector,
                maxOfferLifetime,
                offerExpiryThreshold
            )
        );
        new BeaconProxy(address(_marketplaceBeacon), initData);
    }

    function test_initialize_reverts_zeroMaxCounterOffers() public {
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                _marketplaceAssetManager(_marketplace),
                _suite.core.escrowManager,
                _suite.registries.entityRegistry,
                0
            )
        );

        vm.expectRevert(Errors.Marketplace__MaxCounterOffersPerUserZero.selector);
        new BeaconProxy(address(_marketplaceBeacon), initData);
    }

    function test_beaconDowngrade_success() public {
        address originalImpl = _marketplaceBeacon.implementation();

        address newImpl = address(new MockMarketplace());
        bytes memory upgradeData = abi.encodeWithSelector(_marketplaceBeacon.upgradeTo.selector, newImpl);
        _timelockOp(address(_marketplaceBeacon), upgradeData);
        assertEq(_marketplaceBeacon.implementation(), newImpl);

        bytes memory downgradeData = abi.encodeWithSelector(_marketplaceBeacon.upgradeTo.selector, originalImpl);
        _timelockOp(address(_marketplaceBeacon), downgradeData);

        assertEq(_marketplaceBeacon.implementation(), originalImpl);
    }

    /*//////////////////////////////////////////////////////////////
                             addCurrency
    //////////////////////////////////////////////////////////////*/
    function _addCurrency(bytes3 currency) internal {
        vm.prank(_adminID);
        MarketplaceBase(_marketplace).addCurrency(currency);
    }

    function test_addCurrency_success() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes3 currency = bytes3("USD");

        vm.expectEmit();
        emit MarketplaceBase.CurrencyAdded(currency);

        _addCurrency(currency);

        assertTrue(MarketplaceBase(_marketplace).isCurrencyAllowed(currency));
    }

    function test_addCurrency_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        MarketplaceBase(_marketplace).addCurrency(bytes3("USD"));
    }

    function test_addCurrency_reverts_alreadyExists() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes3 currency = bytes3("USD");

        _addCurrency(currency);

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CurrencyAlreadyExists.selector, currency));
        _addCurrency(currency);
    }

    /*//////////////////////////////////////////////////////////////
                            removeCurrency
    //////////////////////////////////////////////////////////////*/
    function _removeCurrency(bytes3 currency) internal {
        vm.prank(_adminID);
        MarketplaceBase(_marketplace).removeCurrency(currency);
    }

    function test_removeCurrency_success() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes3 currency = bytes3("USD");
        _addCurrency(currency);

        vm.expectEmit();
        emit MarketplaceBase.CurrencyRemoved(currency);

        _removeCurrency(currency);

        assertFalse(MarketplaceBase(_marketplace).isCurrencyAllowed(currency));
    }

    function test_removeCurrency_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        MarketplaceBase(_marketplace).removeCurrency(bytes3("USD"));
    }

    function test_removeCurrency_reverts_notExists() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes3 currency = bytes3("USD");

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__CurrencyDoesNotExist.selector, currency));
        _removeCurrency(currency);
    }

    /*//////////////////////////////////////////////////////////////
                            setAssetManager
    //////////////////////////////////////////////////////////////*/
    function test_setAssetManager_success() public {
        address newAssetManager = makeAddr("newAssetManager");

        vm.expectEmit();
        emit MarketplaceBase.AssetManagerSet(_suite.core.assetManager, newAssetManager);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setAssetManager(newAssetManager);

        assertEq(_marketplaceAssetManager(_marketplace), newAssetManager);
    }

    function test_setAssetManager_reverts_zeroAddress() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.ZeroAddress.selector);
        MarketplaceBase(_marketplace).setAssetManager(address(0));
    }

    function test_setAssetManager_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setAssetManager(makeAddr("newAssetManager"));
    }

    /*//////////////////////////////////////////////////////////////
                           setEscrowManager
    //////////////////////////////////////////////////////////////*/
    function test_setEscrowManager_success() public {
        address freshMarketplace = _deployUnwiredMarketplace();
        address newEscrowManager = makeAddr("newEscrowManager");

        vm.expectEmit();
        emit DependenciesBase.EscrowManagerSet(address(0), newEscrowManager);

        vm.prank(_adminID);
        MarketplaceBase(freshMarketplace).setEscrowManager(newEscrowManager);

        assertEq(MarketplaceBase(freshMarketplace).getEscrowManager(), newEscrowManager);
    }

    function test_setEscrowManager_reverts_alreadySet() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.DependenciesBase__EscrowManagerAlreadySet.selector);
        MarketplaceBase(_marketplace).setEscrowManager(makeAddr("newEscrowManager"));
    }

    function test_setEscrowManager_reverts_zeroAddress() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.ZeroAddress.selector);
        MarketplaceBase(_marketplace).setEscrowManager(address(0));
    }

    function test_setEscrowManager_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setEscrowManager(makeAddr("newEscrowManager"));
    }

    /*//////////////////////////////////////////////////////////////
                         setEntityRegistry
    //////////////////////////////////////////////////////////////*/
    function test_setEntityRegistry_reverts_alreadySet() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.DependenciesBase__EntityRegistryAlreadySet.selector);
        MarketplaceBase(_marketplace).setEntityRegistry(makeAddr("newEntityRegistry"));
    }

    function test_setEntityRegistry_reverts_zeroAddress() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.ZeroAddress.selector);
        MarketplaceBase(_marketplace).setEntityRegistry(address(0));
    }

    function test_setEntityRegistry_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setEntityRegistry(makeAddr("newEntityRegistry"));
    }

    /*//////////////////////////////////////////////////////////////
                          setAllowedEntityType
    //////////////////////////////////////////////////////////////*/
    function test_setAllowedEntityType_success() public {
        vm.expectEmit();
        emit EntityTypeAllowed(COMPANY_ENTITY, true);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, true);
    }

    function test_setAllowedEntityType_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        Marketplace(_marketplace).setAllowedEntityType(COMPANY_ENTITY, true);
    }

    function test_setAllowedEntityTypes_success() public {
        uint256[] memory typeIds = new uint256[](2);
        typeIds[0] = COMPANY_ENTITY;
        typeIds[1] = NATURAL_PERSON_ENTITY;

        vm.expectEmit();
        emit EntityTypeAllowed(COMPANY_ENTITY, true);
        vm.expectEmit();
        emit EntityTypeAllowed(NATURAL_PERSON_ENTITY, true);

        vm.prank(_adminID);
        Marketplace(_marketplace).setAllowedEntityTypes(typeIds, true);
    }

    /*//////////////////////////////////////////////////////////////
                setMarketplacePaymentExpiryThreshold
    //////////////////////////////////////////////////////////////*/
    function test_setMarketplacePaymentExpiryThreshold_success() public {
        uint256 newMarketplacePaymentExpiryThreshold =
            Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE;

        vm.expectEmit();
        emit MarketplaceBase.MarketplacePaymentExpiryThresholdSet(newMarketplacePaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(newMarketplacePaymentExpiryThreshold);

        assertEq(_config().marketplacePaymentExpiryThreshold, newMarketplacePaymentExpiryThreshold);
    }

    function test_setMarketplacePaymentExpiryThreshold_success_acceptsMaxThreshold() public {
        uint256 maxPaymentExpiryThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD();

        vm.expectEmit();
        emit MarketplaceBase.MarketplacePaymentExpiryThresholdSet(maxPaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(maxPaymentExpiryThreshold);

        assertEq(_config().marketplacePaymentExpiryThreshold, maxPaymentExpiryThreshold);
    }

    function test_setMarketplacePaymentExpiryThreshold_reverts_belowMinThreshold() public {
        uint256 minPaymentExpiryThreshold = MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD();
        uint256 belowMinThreshold = minPaymentExpiryThreshold - 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooLow.selector, belowMinThreshold)
        );
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(belowMinThreshold);
    }

    function test_setMarketplacePaymentExpiryThreshold_reverts_aboveMaxThreshold() public {
        uint256 aboveMaxThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMaxThreshold)
        );
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(aboveMaxThreshold);
    }

    function test_setMarketplacePaymentExpiryThreshold_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace)
            .setMarketplacePaymentExpiryThreshold(Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE);
    }

    /*//////////////////////////////////////////////////////////////
            setInterestDiscoveryPaymentExpiryThreshold
    //////////////////////////////////////////////////////////////*/
    function test_setInterestDiscoveryPaymentExpiryThreshold_success() public {
        uint256 newPaymentExpiryThreshold = Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE;

        vm.expectEmit();
        emit MarketplaceBase.InterestDiscoveryPaymentExpiryThresholdSet(newPaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(newPaymentExpiryThreshold);

        assertEq(_config().interestDiscoveryPaymentExpiryThreshold, newPaymentExpiryThreshold);
    }

    function test_setInterestDiscoveryPaymentExpiryThreshold_success_acceptsMaxThreshold() public {
        uint256 maxPaymentExpiryThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD();

        vm.expectEmit();
        emit MarketplaceBase.InterestDiscoveryPaymentExpiryThresholdSet(maxPaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(maxPaymentExpiryThreshold);

        assertEq(_config().interestDiscoveryPaymentExpiryThreshold, maxPaymentExpiryThreshold);
    }

    function test_setInterestDiscoveryPaymentExpiryThreshold_reverts_belowMinThreshold() public {
        uint256 minPaymentExpiryThreshold = MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD();
        uint256 belowMinThreshold = minPaymentExpiryThreshold - 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooLow.selector, belowMinThreshold)
        );
        MarketplaceBase(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(belowMinThreshold);
    }

    function test_setInterestDiscoveryPaymentExpiryThreshold_reverts_aboveMaxThreshold() public {
        uint256 aboveMaxThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMaxThreshold)
        );
        MarketplaceBase(_marketplace).setInterestDiscoveryPaymentExpiryThreshold(aboveMaxThreshold);
    }

    function test_setInterestDiscoveryPaymentExpiryThreshold_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace)
            .setInterestDiscoveryPaymentExpiryThreshold(
                Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE
            );
    }

    /*//////////////////////////////////////////////////////////////
                  setRedemptionPaymentExpiryThreshold
    //////////////////////////////////////////////////////////////*/
    function test_setRedemptionPaymentExpiryThreshold_success() public {
        uint256 newPaymentExpiryThreshold = Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE + 1 days;

        vm.expectEmit();
        emit MarketplaceBase.RedemptionPaymentExpiryThresholdSet(newPaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(newPaymentExpiryThreshold);

        assertEq(_config().redemptionPaymentExpiryThreshold, newPaymentExpiryThreshold);
    }

    function test_setRedemptionPaymentExpiryThreshold_success_acceptsMaxThreshold() public {
        uint256 maxPaymentExpiryThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD();

        vm.expectEmit();
        emit MarketplaceBase.RedemptionPaymentExpiryThresholdSet(maxPaymentExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(maxPaymentExpiryThreshold);

        assertEq(_config().redemptionPaymentExpiryThreshold, maxPaymentExpiryThreshold);
    }

    function test_setRedemptionPaymentExpiryThreshold_reverts_belowMinThreshold() public {
        uint256 minPaymentExpiryThreshold = MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD();
        uint256 belowMinThreshold = minPaymentExpiryThreshold - 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooLow.selector, belowMinThreshold)
        );
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(belowMinThreshold);
    }

    function test_setRedemptionPaymentExpiryThreshold_reverts_aboveMaxThreshold() public {
        uint256 aboveMaxThreshold = MarketplaceBase(_marketplace).MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMaxThreshold)
        );
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(aboveMaxThreshold);
    }

    function test_setRedemptionPaymentExpiryThreshold_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace)
            .setRedemptionPaymentExpiryThreshold(Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE);
    }

    /*//////////////////////////////////////////////////////////////
                     setOfferExpiryThreshold
    //////////////////////////////////////////////////////////////*/
    function test_setOfferExpiryThreshold_success() public {
        uint256 newOfferExpiryThreshold = 3 days;

        vm.expectEmit();
        emit MarketplaceBase.OfferExpiryThresholdSet(newOfferExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(newOfferExpiryThreshold);

        assertEq(_config().offerExpiryThreshold, newOfferExpiryThreshold);
    }

    function test_setOfferExpiryThreshold_success_acceptsMaxThreshold() public {
        uint256 maxOfferExpiryThreshold = MarketplaceBase(_marketplace).MAX_OFFER_EXPIRY_THRESHOLD();

        vm.expectEmit();
        emit MarketplaceBase.OfferExpiryThresholdSet(maxOfferExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(maxOfferExpiryThreshold);

        assertEq(_config().offerExpiryThreshold, maxOfferExpiryThreshold);
    }

    function test_setOfferExpiryThreshold_reverts_belowMinThreshold() public {
        uint256 minOfferExpiryThreshold = MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD();
        uint256 belowMinThreshold = minOfferExpiryThreshold - 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferExpiryThresholdTooLow.selector, belowMinThreshold)
        );
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(belowMinThreshold);
    }

    function test_setOfferExpiryThreshold_reverts_aboveMaxThreshold() public {
        uint256 aboveMaxThreshold = MarketplaceBase(_marketplace).MAX_OFFER_EXPIRY_THRESHOLD() + 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Marketplace__OfferExpiryThresholdTooHigh.selector, aboveMaxThreshold)
        );
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(aboveMaxThreshold);
    }

    function test_setOfferExpiryThreshold_reverts_aboveMaxOfferLifetime() public {
        uint256 newMaxOfferLifetime = 2 days;

        vm.startPrank(_adminID);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(newMaxOfferLifetime);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold.selector,
                newMaxOfferLifetime,
                newMaxOfferLifetime + 1
            )
        );
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(newMaxOfferLifetime + 1);
        vm.stopPrank();
    }

    function test_setOfferExpiryThreshold_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(Constants.MARKETPLACE_OFFER_EXPIRY_THRESHOLD);
    }

    /*//////////////////////////////////////////////////////////////
                         setMaxOfferLifetime
    //////////////////////////////////////////////////////////////*/
    function test_setMaxOfferLifetime_success() public {
        uint256 newMaxOfferLifetime = 180 days;

        vm.expectEmit();
        emit MarketplaceBase.MaxOfferLifetimeSet(newMaxOfferLifetime);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(newMaxOfferLifetime);

        assertEq(_config().maxOfferLifetime, newMaxOfferLifetime);
    }

    function test_setMaxOfferLifetime_success_acceptsHardCap() public {
        uint256 maxOfferLifetime = MarketplaceBase(_marketplace).MAX_CONFIGURABLE_OFFER_LIFETIME();

        vm.expectEmit();
        emit MarketplaceBase.MaxOfferLifetimeSet(maxOfferLifetime);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(maxOfferLifetime);

        assertEq(_config().maxOfferLifetime, maxOfferLifetime);
    }

    function test_setMaxOfferLifetime_success_acceptsOfferExpiryThreshold() public {
        uint256 offerExpiryThreshold = _config().offerExpiryThreshold;

        vm.expectEmit();
        emit MarketplaceBase.MaxOfferLifetimeSet(offerExpiryThreshold);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(offerExpiryThreshold);

        assertEq(_config().maxOfferLifetime, offerExpiryThreshold);
    }

    function test_setMaxOfferLifetime_reverts_aboveHardCap() public {
        uint256 aboveMax = MarketplaceBase(_marketplace).MAX_CONFIGURABLE_OFFER_LIFETIME() + 1;

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__MaxOfferLifetimeTooHigh.selector, aboveMax));
        MarketplaceBase(_marketplace).setMaxOfferLifetime(aboveMax);
    }

    function test_setMaxOfferLifetime_reverts_belowOfferExpiryThreshold() public {
        uint256 offerExpiryThreshold = _config().offerExpiryThreshold;
        uint256 belowThreshold = offerExpiryThreshold - 1;

        vm.prank(_adminID);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold.selector,
                belowThreshold,
                offerExpiryThreshold
            )
        );
        MarketplaceBase(_marketplace).setMaxOfferLifetime(belowThreshold);
    }

    function test_setMaxOfferLifetime_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(Constants.MARKETPLACE_MAX_OFFER_LIFETIME);
    }

    /*//////////////////////////////////////////////////////////////
                      setDisputeBufferPeriod
    //////////////////////////////////////////////////////////////*/
    function test_setDisputeBufferPeriod_success() public {
        uint256 newDisputeBufferPeriod = 1 days;

        vm.expectEmit();
        emit MarketplaceBase.DisputeBufferPeriodSet(newDisputeBufferPeriod);

        vm.prank(_adminID);
        MarketplaceBase(_marketplace).setDisputeBufferPeriod(newDisputeBufferPeriod);

        assertEq(_config().disputeBufferPeriod, newDisputeBufferPeriod);
    }

    function test_setDisputeBufferPeriod_reverts_belowMinPeriod() public {
        uint256 minDisputeBufferPeriod = MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD();
        uint256 belowMinPeriod = minDisputeBufferPeriod - 1;

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputeBufferPeriodTooLow.selector, belowMinPeriod));
        MarketplaceBase(_marketplace).setDisputeBufferPeriod(belowMinPeriod);
    }

    function test_setDisputeBufferPeriod_reverts_aboveMaxPeriod() public {
        uint256 maxDisputeBufferPeriod = MarketplaceBase(_marketplace).MAX_DISPUTE_BUFFER_PERIOD();
        uint256 aboveMaxPeriod = maxDisputeBufferPeriod + 1;

        vm.prank(_adminID);
        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputeBufferPeriodTooHigh.selector, aboveMaxPeriod));
        MarketplaceBase(_marketplace).setDisputeBufferPeriod(aboveMaxPeriod);
    }

    function test_setDisputeBufferPeriod_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setDisputeBufferPeriod(1 days);
    }

    /*//////////////////////////////////////////////////////////////
                    setMaxCounterOffersPerUser
    //////////////////////////////////////////////////////////////*/
    function test_setMaxCounterOffersPerUser_success() public {
        uint256 newMaxCounterOffers = 10;

        vm.prank(_adminID);
        vm.expectEmit(true, false, false, true);
        emit MaxCounterOffersPerUserSet(newMaxCounterOffers);
        MarketplaceBase(_marketplace).setMaxCounterOffersPerUser(newMaxCounterOffers);

        assertEq(_config().maxCounterOffersPerUser, newMaxCounterOffers);
    }

    function test_setMaxCounterOffersPerUser_reverts_zeroValue() public {
        vm.prank(_adminID);
        vm.expectRevert(Errors.Marketplace__MaxCounterOffersPerUserZero.selector);
        MarketplaceBase(_marketplace).setMaxCounterOffersPerUser(0);

        assertEq(_config().maxCounterOffersPerUser, 5);
    }

    function test_setMaxCounterOffersPerUser_reverts_notRoleAssigned() public {
        vm.prank(_notGovernance);
        vm.expectRevert(Ownable.Unauthorized.selector);
        MarketplaceBase(_marketplace).setMaxCounterOffersPerUser(10);
    }

    /*//////////////////////////////////////////////////////////////
                                getConfig
    //////////////////////////////////////////////////////////////*/
    function test_getConfig_success_returnsConfiguredValues() public view {
        MarketplaceStorage.Config memory config = _config();

        assertEq(config.maxCounterOffersPerUser, 5);
        assertEq(config.offerExpiryThreshold, _expiryThreshold);
        assertEq(config.maxOfferLifetime, Constants.MARKETPLACE_MAX_OFFER_LIFETIME);
        assertEq(
            config.redemptionPaymentExpiryThreshold, Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE
        );
        assertEq(
            config.interestDiscoveryPaymentExpiryThreshold,
            Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE
        );
    }

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public {
        address harness = _deployNamespacedStorageHarness();

        bytes32 marketplaceLocation = MarketplaceNamespacedStorageHarness(harness).exposedMarketplaceStorageLocation();

        assertEq(marketplaceLocation, _erc7201Location("deuss.marketplace.storage"));
        assertEq(uint256(marketplaceLocation) & 0xff, 0);
    }

    function test_getConfig_success_reflectsSetterUpdatesAfterNamespacedStorage() public {
        uint256 newOfferExpiryThreshold = 2 days;
        uint256 newMarketplacePaymentExpiryThreshold = 3 days;
        uint256 newRedemptionPaymentExpiryThreshold = 4 days;
        uint256 newInterestDiscoveryPaymentExpiryThreshold = 5 days;
        uint256 newDisputeBufferPeriod = 2 days;
        uint256 newMaxCounterOffers = 9;
        uint256 newMaxOfferLifetime = 180 days;

        vm.startPrank(_adminID);
        MarketplaceBase(_marketplace).setOfferExpiryThreshold(newOfferExpiryThreshold);
        MarketplaceBase(_marketplace).setMaxOfferLifetime(newMaxOfferLifetime);
        MarketplaceBase(_marketplace).setMarketplacePaymentExpiryThreshold(newMarketplacePaymentExpiryThreshold);
        MarketplaceBase(_marketplace).setRedemptionPaymentExpiryThreshold(newRedemptionPaymentExpiryThreshold);
        MarketplaceBase(_marketplace)
            .setInterestDiscoveryPaymentExpiryThreshold(newInterestDiscoveryPaymentExpiryThreshold);
        MarketplaceBase(_marketplace).setDisputeBufferPeriod(newDisputeBufferPeriod);
        MarketplaceBase(_marketplace).setMaxCounterOffersPerUser(newMaxCounterOffers);
        vm.stopPrank();

        MarketplaceStorage.Config memory config = _config();
        assertEq(config.offerExpiryThreshold, newOfferExpiryThreshold);
        assertEq(config.marketplacePaymentExpiryThreshold, newMarketplacePaymentExpiryThreshold);
        assertEq(config.redemptionPaymentExpiryThreshold, newRedemptionPaymentExpiryThreshold);
        assertEq(config.interestDiscoveryPaymentExpiryThreshold, newInterestDiscoveryPaymentExpiryThreshold);
        assertEq(config.disputeBufferPeriod, newDisputeBufferPeriod);
        assertEq(config.maxCounterOffersPerUser, newMaxCounterOffers);
        assertEq(config.maxOfferLifetime, newMaxOfferLifetime);
        bytes32 configLocation = _marketplaceConfigStorageLocation();
        assertEq(_loadUint(_marketplace, configLocation, 0), newOfferExpiryThreshold);
        assertEq(_loadUint(_marketplace, configLocation, 1), newMarketplacePaymentExpiryThreshold);
        assertEq(_loadUint(_marketplace, configLocation, 2), newRedemptionPaymentExpiryThreshold);
        assertEq(_loadUint(_marketplace, configLocation, 3), newInterestDiscoveryPaymentExpiryThreshold);
        assertEq(_loadUint(_marketplace, configLocation, 4), newDisputeBufferPeriod);
        assertEq(_loadUint(_marketplace, configLocation, 5), newMaxCounterOffers);
        assertEq(_loadUint(_marketplace, configLocation, 6), newMaxOfferLifetime);

        (MarketplaceStorage.Config memory mergedConfig, MarketplaceStorage.Counters memory mergedCounters) =
            MarketplaceBase(_marketplace).getConfigAndCounters();
        assertEq(mergedConfig.marketplacePaymentExpiryThreshold, newMarketplacePaymentExpiryThreshold);
        assertEq(mergedConfig.redemptionPaymentExpiryThreshold, newRedemptionPaymentExpiryThreshold);
        assertEq(mergedConfig.interestDiscoveryPaymentExpiryThreshold, newInterestDiscoveryPaymentExpiryThreshold);
        assertEq(mergedCounters.offerCounter, 0);
        assertEq(mergedCounters.dealCounter, 0);
        assertEq(mergedCounters.interestCounter, 0);
    }

    function test_namespacedCounters_success_reflectsMarketplaceOperationsAfterNamespacedStorage() public {
        address harness = _deployNamespacedStorageHarness();
        bytes32 countersLocation = _marketplaceCountersStorageLocation();

        (, MarketplaceStorage.Counters memory counters) = MarketplaceBase(harness).getConfigAndCounters();
        assertEq(counters.offerCounter, 0);
        assertEq(counters.dealCounter, 0);
        assertEq(counters.interestCounter, 0);

        assertEq(MarketplaceNamespacedStorageHarness(harness).exposedIncrementOfferCounter(), 1);
        assertEq(MarketplaceNamespacedStorageHarness(harness).exposedIncrementDealCounter(), 1);
        assertEq(MarketplaceNamespacedStorageHarness(harness).exposedIncrementInterestCounter(), 1);

        (, counters) = MarketplaceBase(harness).getConfigAndCounters();
        assertEq(counters.offerCounter, 1);
        assertEq(counters.dealCounter, 1);
        assertEq(counters.interestCounter, 1);
        assertEq(_loadUint(harness, countersLocation, 0), 1);
        assertEq(_loadUint(harness, countersLocation, 1), 1);
        assertEq(_loadUint(harness, countersLocation, 2), 1);
    }

    function test_namespacedStorage_doesNotOccupySequentialHeadSlots() public {
        // All marketplace state lives in the ERC-7201 namespace, so the sequential head slots are unused.
        for (uint256 slot = 0; slot < 12; ++slot) {
            assertEq(vm.load(_marketplace, bytes32(slot)), bytes32(0));
        }

        // assetManager lives at namespace offset 7, after the seven-slot Config struct.
        bytes32 root = _erc7201Location("deuss.marketplace.storage");
        assertEq(_loadUint(_marketplace, root, 7), uint256(uint160(_marketplaceAssetManager(_marketplace))));

        (MarketplaceStorage.Config memory config, MarketplaceStorage.Counters memory counters) =
            MarketplaceBase(_marketplace).getConfigAndCounters();
        assertEq(config.offerExpiryThreshold, _expiryThreshold);
        assertEq(config.maxCounterOffersPerUser, 5);
        assertEq(config.maxOfferLifetime, Constants.MARKETPLACE_MAX_OFFER_LIFETIME);
        bytes32 configLocation = _marketplaceConfigStorageLocation();
        assertEq(_loadUint(_marketplace, configLocation, 0), _expiryThreshold);
        assertEq(_loadUint(_marketplace, configLocation, 5), 5);
        assertEq(_loadUint(_marketplace, configLocation, 6), Constants.MARKETPLACE_MAX_OFFER_LIFETIME);
        bytes32 countersLocation = _marketplaceCountersStorageLocation();
        assertEq(_loadUint(_marketplace, countersLocation, 0), 0);
        assertEq(_loadUint(_marketplace, countersLocation, 1), 0);
        assertEq(_loadUint(_marketplace, countersLocation, 2), 0);
        assertEq(counters.offerCounter, 0);
        assertEq(counters.dealCounter, 0);
        assertEq(counters.interestCounter, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployUnwiredMarketplace() internal returns (address freshMarketplace) {
        Marketplace implementation = new Marketplace();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), _deployer);
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                address(0),
                address(0),
                _suite.registries.entityRegistry,
                5
            )
        );

        freshMarketplace = address(new BeaconProxy(address(beacon), initData));

        uint256 adminRole = MarketplaceBase(freshMarketplace).ADMIN();
        vm.prank(_deployer);
        MarketplaceBase(freshMarketplace).grantRoles(_adminID, adminRole);
    }

    function _deployNamespacedStorageHarness() internal returns (address harness) {
        MarketplaceNamespacedStorageHarness implementation = new MarketplaceNamespacedStorageHarness();
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                address(0),
                address(0),
                _suite.registries.entityRegistry,
                5
            )
        );

        harness = address(new ERC1967Proxy(address(implementation), initData));
    }

    function _marketplaceConfigStorageLocation() internal pure returns (bytes32) {
        // `config` is the first field of MarketplaceState, so it shares the namespace root slot.
        return _erc7201Location("deuss.marketplace.storage");
    }

    function _marketplaceCountersStorageLocation() internal pure returns (bytes32) {
        // `counters` follows the seven-slot `config` struct and `assetManager` at offset 8.
        return _slotOffset(_erc7201Location("deuss.marketplace.storage"), 8);
    }

    function _configFor(address marketplace_) internal view returns (MarketplaceStorage.Config memory config) {
        (config,) = MarketplaceBase(marketplace_).getConfigAndCounters();
    }

    function _marketplaceAssetManager(address marketplace_) internal view returns (address assetManager) {
        bytes32 assetManagerSlot = _slotOffset(_erc7201Location("deuss.marketplace.storage"), 7);
        assetManager = address(uint160(_loadUint(marketplace_, assetManagerSlot)));
    }

    function test_initialize_success_setsDependenciesWhenProvided() public {
        address assetManager = makeAddr("wiredAssetManager");
        address escrowManager = makeAddr("wiredEscrowManager");
        address entityRegistry = makeAddr("wiredEntityRegistry");
        Marketplace implementation = new Marketplace();

        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                assetManager,
                escrowManager,
                entityRegistry,
                5
            )
        );

        address freshMarketplace = address(new ERC1967Proxy(address(implementation), initData));

        assertEq(_marketplaceAssetManager(freshMarketplace), assetManager);
        assertEq(MarketplaceBase(freshMarketplace).getEscrowManager(), escrowManager);
        assertEq(MarketplaceBase(freshMarketplace).getEntityRegistry(), entityRegistry);
    }

    function test_initialize_reverts_zeroEntityRegistry() public {
        Marketplace implementation = new Marketplace();
        bytes memory initData = abi.encodeCall(
            Marketplace.initialize,
            (
                _deployer,
                MarketplaceBase(_marketplace).MIN_OFFER_EXPIRY_THRESHOLD(),
                Constants.MARKETPLACE_MAX_OFFER_LIFETIME,
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_PAYMENT_EXPIRY_THRESHOLD(),
                MarketplaceBase(_marketplace).MIN_DISPUTE_BUFFER_PERIOD(),
                address(0),
                address(0),
                address(0),
                5
            )
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(address(implementation), initData);
    }
}

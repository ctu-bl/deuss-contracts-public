// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {MarketplaceDeployer} from "src/deployer/marketplace/MarketplaceDeployer.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {MarketplaceBase} from "src/marketplace/MarketplaceBase.sol";
import {MarketplaceStorage} from "src/marketplace/MarketplaceStorage.sol";
import {Errors} from "src/libs/Errors.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";

contract MarketplaceDeployerTest is Test {
    uint256 private constant _MARKETPLACE_ASSET_MANAGER_SLOT =
        0xf7a56b15168bcb08515667a141d475c0860a6405d548a81fdf3dd5a1c8926a07;

    MarketplaceDeployer internal _marketplaceDeployer;
    Marketplace internal _marketplace;

    address internal _governance;
    address internal _assetManager;
    address internal _escrowManager;
    address internal _entityRegistry;
    uint256 internal _offerExpiryThreshold;
    uint256 internal _maxOfferLifetime;
    uint256 internal _paymentExpiryThreshold;
    uint256 internal _configuredRedemptionPaymentThreshold;
    uint256 internal _interestDiscoveryPaymentExpiryThreshold;
    uint256 internal _disputeBufferPeriod;
    uint256 internal _maxCounterOffers;

    function setUp() public {
        _governance = makeAddr("governance");
        _assetManager = makeAddr("assetManager");
        _escrowManager = makeAddr("escrowManager");
        _entityRegistry = makeAddr("entityRegistry");
        _offerExpiryThreshold = Constants.MARKETPLACE_OFFER_EXPIRY_THRESHOLD;
        _maxOfferLifetime = Constants.MARKETPLACE_MAX_OFFER_LIFETIME;
        _paymentExpiryThreshold = Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE;
        _configuredRedemptionPaymentThreshold = Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE;
        _interestDiscoveryPaymentExpiryThreshold =
        Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE;
        _disputeBufferPeriod = Constants.MARKETPLACE_DISPUTE_BUFFER_PERIOD;
        _maxCounterOffers = Constants.MAX_COUNTER_OFFERS_PER_USER;

        _marketplaceDeployer = _deployMarketplace("MarketplaceSalt");
        _marketplace = _marketplaceDeployer.marketplace();
    }

    function _defaultDeployParams(string memory salt)
        internal
        view
        returns (MarketplaceDeployer.MarketplaceDeployParams memory params)
    {
        params = MarketplaceDeployer.MarketplaceDeployParams({
            owner: _governance,
            offerExpiryThreshold: _offerExpiryThreshold,
            maxOfferLifetime: _maxOfferLifetime,
            marketplacePaymentExpiryThreshold: _paymentExpiryThreshold,
            redemptionPaymentExpiryThreshold: _configuredRedemptionPaymentThreshold,
            interestDiscoveryPaymentExpiryThreshold: _interestDiscoveryPaymentExpiryThreshold,
            disputeBufferPeriod: _disputeBufferPeriod,
            assetManager: _assetManager,
            escrowManager: _escrowManager,
            entityRegistry: _entityRegistry,
            maxCounterOffers: _maxCounterOffers,
            marketplaceSalt: salt
        });
    }

    function _deployMarketplace(string memory salt) internal returns (MarketplaceDeployer) {
        return new MarketplaceDeployer(_defaultDeployParams(salt));
    }

    function test_marketplaceOwner() public view {
        assertEq(_marketplace.owner(), _governance);
    }

    function test_marketplaceAssetManager() public view {
        assertEq(_marketplaceAssetManager(address(_marketplace)), _assetManager);
    }

    function test_marketplaceEscrowManager() public view {
        assertEq(_marketplace.getEscrowManager(), _escrowManager);
    }

    function test_marketplaceEntityRegistry() public view {
        assertEq(_marketplace.getEntityRegistry(), _entityRegistry);
    }

    function test_marketplaceMarketplacePaymentExpiryThreshold() public view {
        MarketplaceStorage.Config memory config = _marketplaceConfig(_marketplace);
        assertEq(config.marketplacePaymentExpiryThreshold, _paymentExpiryThreshold);
    }

    function test_marketplaceRedemptionPaymentExpiryThreshold() public view {
        MarketplaceStorage.Config memory config = _marketplaceConfig(_marketplace);
        assertEq(config.redemptionPaymentExpiryThreshold, _configuredRedemptionPaymentThreshold);
    }

    function test_marketplaceActivatedPaymentExpiryThreshold() public view {
        MarketplaceStorage.Config memory config = _marketplaceConfig(_marketplace);
        assertEq(config.interestDiscoveryPaymentExpiryThreshold, _interestDiscoveryPaymentExpiryThreshold);
    }

    function test_marketplaceOfferExpiryThreshold() public view {
        MarketplaceStorage.Config memory config = _marketplaceConfig(_marketplace);
        assertEq(config.offerExpiryThreshold, _offerExpiryThreshold);
    }

    function test_marketplaceMaxOfferLifetime() public view {
        MarketplaceStorage.Config memory config = _marketplaceConfig(_marketplace);
        assertEq(config.maxOfferLifetime, _maxOfferLifetime);
    }

    function test_marketplaceDisputeBufferPeriod() public view {
        uint256 disputeBufferPeriod = _marketplaceConfig(_marketplace).disputeBufferPeriod;

        assertTrue(!(disputeBufferPeriod < _marketplace.MIN_DISPUTE_BUFFER_PERIOD()));
        assertTrue(!(disputeBufferPeriod > _marketplace.MAX_DISPUTE_BUFFER_PERIOD()));
    }

    function test_marketplaceDisputeBufferPeriod_equalsConfiguredValue() public view {
        assertEq(_marketplaceConfig(_marketplace).disputeBufferPeriod, _disputeBufferPeriod);
    }

    function test_deployment_success_withEmptySalt() public {
        MarketplaceDeployer newDeployer = _deployMarketplace("");
        Marketplace newMarketplace = newDeployer.marketplace();

        assertNotEq(address(newMarketplace), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        MarketplaceDeployer deployer1 = _deployMarketplace("salt1");
        MarketplaceDeployer deployer2 = _deployMarketplace("salt2");

        assertNotEq(address(deployer1.marketplace()), address(deployer2.marketplace()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.owner = address(0);

        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withZeroOfferExpiryThreshold() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.offerExpiryThreshold = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferExpiryThresholdTooLow.selector, 0));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withOfferExpiryThresholdAboveMax() public {
        uint256 aboveMax = _marketplace.MAX_OFFER_EXPIRY_THRESHOLD() + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.offerExpiryThreshold = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__OfferExpiryThresholdTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withMaxOfferLifetimeAboveHardCap() public {
        uint256 aboveMax = _marketplace.MAX_CONFIGURABLE_OFFER_LIFETIME() + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.maxOfferLifetime = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__MaxOfferLifetimeTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withMaxOfferLifetimeBelowOfferExpiryThreshold() public {
        uint256 maxOfferLifetime = _offerExpiryThreshold - 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.maxOfferLifetime = maxOfferLifetime;

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Marketplace__MaxOfferLifetimeBelowOfferExpiryThreshold.selector,
                maxOfferLifetime,
                _offerExpiryThreshold
            )
        );
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withZeroPaymentExpiryThreshold() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.marketplacePaymentExpiryThreshold = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooLow.selector, 0));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withPaymentExpiryThresholdAboveMax() public {
        uint256 aboveMax = _marketplace.MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.marketplacePaymentExpiryThreshold = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withZeroRedemptionPaymentExpiryThreshold() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.redemptionPaymentExpiryThreshold = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooLow.selector, 0));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withRedemptionPaymentExpiryThresholdAboveMax() public {
        uint256 aboveMax = _marketplace.MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.redemptionPaymentExpiryThreshold = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withInterestDiscoveryPaymentExpiryThresholdAboveMax() public {
        uint256 aboveMax = _marketplace.MAX_PAYMENT_EXPIRY_THRESHOLD() + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.interestDiscoveryPaymentExpiryThreshold = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__PaymentExpiryThresholdTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withZeroDisputeBufferPeriod() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.disputeBufferPeriod = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputeBufferPeriodTooLow.selector, 0));
        new MarketplaceDeployer(params);
    }

    function test_deployment_reverts_withDisputeBufferPeriodAboveMax() public {
        uint256 maxDisputeBufferPeriod = MarketplaceBase(_marketplace).MAX_DISPUTE_BUFFER_PERIOD();
        uint256 aboveMax = maxDisputeBufferPeriod + 1;
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.disputeBufferPeriod = aboveMax;

        vm.expectRevert(abi.encodeWithSelector(Errors.Marketplace__DisputeBufferPeriodTooHigh.selector, aboveMax));
        new MarketplaceDeployer(params);
    }

    function test_deployment_success_withZeroAssetManager() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.assetManager = address(0);

        MarketplaceDeployer deployer = new MarketplaceDeployer(params);
        Marketplace marketplace = deployer.marketplace();

        assertEq(_marketplaceAssetManager(address(marketplace)), address(0));
    }

    function test_deployment_success_withZeroEscrowManager() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.escrowManager = address(0);

        MarketplaceDeployer deployer = new MarketplaceDeployer(params);
        Marketplace marketplace = deployer.marketplace();

        assertEq(marketplace.getEscrowManager(), address(0));
    }

    function test_deployment_reverts_withZeroEntityRegistry() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.entityRegistry = address(0);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new MarketplaceDeployer(params);
    }

    function test_deployment_success_withZeroAssetManagerAndEscrowManager() public {
        MarketplaceDeployer.MarketplaceDeployParams memory params = _defaultDeployParams("salt");
        params.assetManager = address(0);
        params.escrowManager = address(0);

        MarketplaceDeployer deployer = new MarketplaceDeployer(params);
        Marketplace marketplace = deployer.marketplace();

        assertEq(_marketplaceAssetManager(address(marketplace)), address(0));
        assertEq(marketplace.getEscrowManager(), address(0));
    }

    function _marketplaceConfig(Marketplace marketplace)
        internal
        view
        returns (MarketplaceStorage.Config memory config)
    {
        (config,) = marketplace.getConfigAndCounters();
    }

    function _marketplaceAssetManager(address marketplace) internal view returns (address assetManager) {
        assetManager = address(uint160(uint256(vm.load(marketplace, bytes32(_MARKETPLACE_ASSET_MANAGER_SLOT)))));
    }
}

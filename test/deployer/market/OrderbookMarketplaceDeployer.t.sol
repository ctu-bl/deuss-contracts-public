// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {OrderbookMarketplaceDeployer} from "src/deployer/marketplace/OrderbookMarketplaceDeployer.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {Errors} from "src/libs/Errors.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";

contract OrderbookMarketplaceDeployerTest is Test {
    OrderbookMarketplaceDeployer internal _omDeployer;
    OrderbookMarketplace internal _orderbookMarketplace;

    address internal _governance;
    address internal _assetManager;
    address internal _entityRegistry;
    address internal _escrowManager;
    address internal _marketFilter;
    uint256 internal _paymentExpiryThreshold = Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD;
    uint256 internal _minExpiryThreshold = Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD;
    uint256 internal _disputeBufferPeriod = Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD;

    function setUp() public {
        _governance = makeAddr("governance");
        _assetManager = makeAddr("assetManager");
        _entityRegistry = makeAddr("entityRegistry");
        _escrowManager = makeAddr("escrowManager");
        _marketFilter = makeAddr("marketFilter");

        _omDeployer = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "OrderbookMarketplaceSalt"
        );
        _orderbookMarketplace = _omDeployer.orderbookMarketplace();
    }

    function test_orderbookMarketplaceOwner() public view {
        assertEq(_orderbookMarketplace.owner(), _governance);
    }

    function test_orderbookMarketplaceEntityRegistry() public view {
        assertEq(_orderbookMarketplace.entityRegistry(), _entityRegistry);
    }

    function test_orderbookMarketplaceEscrowManager() public view {
        assertEq(_orderbookMarketplace.escrowManager(), _escrowManager);
    }

    function test_orderbookMarketplaceAssetManager() public view {
        assertEq(_orderbookMarketplace.assetManager(), _assetManager);
    }

    function test_orderbookMarketplaceMarketFilter() public view {
        assertEq(_orderbookMarketplace.marketFilter(), _marketFilter);
    }

    function test_orderbookMarketplaceDisputeBufferPeriod() public view {
        assertEq(_orderbookMarketplace.disputeBufferPeriod(), _disputeBufferPeriod);
    }

    function test_orderbookMarketplaceMinExpiryThreshold() public view {
        assertEq(_orderbookMarketplace.minExpiryThreshold(), _minExpiryThreshold);
    }

    function test_deployment_success_withEmptySalt() public {
        OrderbookMarketplaceDeployer newDeployer = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            ""
        );
        OrderbookMarketplace newOrderbookMarketplace = newDeployer.orderbookMarketplace();

        assertNotEq(address(newOrderbookMarketplace), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        OrderbookMarketplaceDeployer deployer1 = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt1"
        );
        OrderbookMarketplaceDeployer deployer2 = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt2"
        );

        assertNotEq(address(deployer1.orderbookMarketplace()), address(deployer2.orderbookMarketplace()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new OrderbookMarketplaceDeployer(
            address(0),
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt"
        );
    }

    function test_deployment_success_withZeroEntityRegistry() public {
        OrderbookMarketplaceDeployer deployer = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            address(0),
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt"
        );
        OrderbookMarketplace om = deployer.orderbookMarketplace();

        assertEq(om.entityRegistry(), address(0));
    }

    function test_deployment_success_withZeroEscrowManager() public {
        OrderbookMarketplaceDeployer deployer = new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            address(0),
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt"
        );
        OrderbookMarketplace om = deployer.orderbookMarketplace();

        assertEq(om.escrowManager(), address(0));
    }

    function test_deployment_success_withZeroAssetManager() public {
        OrderbookMarketplaceDeployer deployer = new OrderbookMarketplaceDeployer(
            _governance,
            address(0),
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "salt"
        );
        OrderbookMarketplace om = deployer.orderbookMarketplace();

        assertEq(om.assetManager(), address(0));
    }

    function test_deployment_reverts_paymentExpiryThresholdTooLow() public {
        uint256 invalidThreshold =
            OrderbookMarketplace(address(_orderbookMarketplace)).MIN_PAYMENT_EXPIRY_THRESHOLD() - 1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__PaymentExpiryThresholdTooLow.selector, invalidThreshold)
        );
        new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            invalidThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "payment-too-low"
        );
    }

    function test_deployment_reverts_minExpiryThresholdTooLow() public {
        uint256 invalidThreshold = OrderbookMarketplace(address(_orderbookMarketplace)).MIN_ORDER_EXPIRY_THRESHOLD() - 1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__MinExpiryThresholdTooLow.selector, invalidThreshold)
        );
        new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            invalidThreshold,
            _disputeBufferPeriod,
            _marketFilter,
            "expiry-too-low"
        );
    }

    function test_deployment_reverts_disputeBufferPeriodTooHigh() public {
        uint256 invalidPeriod = OrderbookMarketplace(address(_orderbookMarketplace)).MAX_DISPUTE_BUFFER_PERIOD() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.OrderbookMarketplace__DisputeBufferPeriodTooHigh.selector, invalidPeriod)
        );
        new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            invalidPeriod,
            _marketFilter,
            "dispute-too-high"
        );
    }

    function test_deployment_reverts_withZeroMarketFilter() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new OrderbookMarketplaceDeployer(
            _governance,
            _assetManager,
            _entityRegistry,
            _escrowManager,
            _paymentExpiryThreshold,
            _minExpiryThreshold,
            _disputeBufferPeriod,
            address(0),
            "salt"
        );
    }
}

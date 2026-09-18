// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {EscrowManagerDeployer} from "src/deployer/marketplace/EscrowManagerDeployer.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowManagerDeployerTest is Test {
    EscrowManagerDeployer internal _emDeployer;
    EscrowManager internal _escrowManager;

    address internal _governance;
    address internal _marketplace;
    address internal _orderbookMarketplace;

    function setUp() public {
        _governance = makeAddr("governance");
        _marketplace = makeAddr("marketplace");
        _orderbookMarketplace = makeAddr("orderbookMarketplace");

        _emDeployer = new EscrowManagerDeployer(_governance, _marketplace, _orderbookMarketplace, "EscrowManagerSalt");
        _escrowManager = _emDeployer.escrowManager();
    }

    function test_escrowManagerOwner() public view {
        assertEq(_escrowManager.owner(), _governance);
    }

    function test_escrowManagerMarketplaceRegistered() public view {
        bytes32 moduleType = _escrowManager.MARKETPLACE_MODULE();

        assertEq(_escrowManager.moduleTypeOf(_marketplace), moduleType);
        assertTrue(_escrowManager.isAuthorizedModule(moduleType, _marketplace));
    }

    function test_escrowManagerOrderbookMarketplaceRegistered() public view {
        bytes32 moduleType = _escrowManager.ORDERBOOK_MARKETPLACE_MODULE();

        assertEq(_escrowManager.moduleTypeOf(_orderbookMarketplace), moduleType);
        assertTrue(_escrowManager.isAuthorizedModule(moduleType, _orderbookMarketplace));
    }

    function test_deployment_success_withEmptySalt() public {
        EscrowManagerDeployer newDeployer =
            new EscrowManagerDeployer(_governance, _marketplace, _orderbookMarketplace, "");
        EscrowManager newEscrowManager = newDeployer.escrowManager();

        assertNotEq(address(newEscrowManager), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        EscrowManagerDeployer deployer1 =
            new EscrowManagerDeployer(_governance, _marketplace, _orderbookMarketplace, "salt1");
        EscrowManagerDeployer deployer2 =
            new EscrowManagerDeployer(_governance, _marketplace, _orderbookMarketplace, "salt2");

        assertNotEq(address(deployer1.escrowManager()), address(deployer2.escrowManager()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new EscrowManagerDeployer(address(0), _marketplace, _orderbookMarketplace, "salt");
    }

    function test_deployment_success_withZeroMarketplace() public {
        EscrowManagerDeployer newDeployer =
            new EscrowManagerDeployer(_governance, address(0), _orderbookMarketplace, "salt");
        EscrowManager newEscrowManager = newDeployer.escrowManager();

        bytes32 moduleType = newEscrowManager.MARKETPLACE_MODULE();
        assertNotEq(address(newEscrowManager), address(0));
        assertFalse(newEscrowManager.isAuthorizedModule(moduleType, address(0)));
    }

    function test_deployment_success_withZeroOrderbookMarketplace() public {
        EscrowManagerDeployer newDeployer = new EscrowManagerDeployer(_governance, _marketplace, address(0), "salt");
        EscrowManager newEscrowManager = newDeployer.escrowManager();

        bytes32 moduleType = newEscrowManager.ORDERBOOK_MARKETPLACE_MODULE();
        assertNotEq(address(newEscrowManager), address(0));
        assertFalse(newEscrowManager.isAuthorizedModule(moduleType, address(0)));
    }
}

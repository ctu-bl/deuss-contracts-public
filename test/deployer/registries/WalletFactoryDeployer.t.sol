// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {Errors} from "src/libs/Errors.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {WalletFactory} from "src/wallet/WalletFactory.sol";
import {WalletFactoryDeployer} from "src/deployer/registries/WalletFactoryDeployer.sol";

contract WalletFactoryDeployerTest is Test {
    WalletFactoryDeployer internal _walletFactoryDeployer;
    WalletFactory internal _walletFactory;

    address internal _governance;
    address internal _entityRegistry;

    function setUp() public {
        _governance = makeAddr("governance");
        _entityRegistry = address(new EntityRegistry());

        _walletFactoryDeployer = new WalletFactoryDeployer(_entityRegistry, _governance, "WalletFactorySalt");
        _walletFactory = _walletFactoryDeployer.walletFactory();
    }

    function test_owner() public view {
        assertEq(_walletFactory.owner(), _governance);
    }

    function test_entityRegistry() public view {
        assertEq(_walletFactory.entityRegistry(), _entityRegistry);
    }

    function test_deploymentWithEmptySalt_success() public {
        WalletFactoryDeployer newDeployer = new WalletFactoryDeployer(_entityRegistry, _governance, "");
        WalletFactory newWalletFactory = newDeployer.walletFactory();

        assertNotEq(address(newWalletFactory), address(0));
    }

    function test_deploymentAddressesAreUnique() public {
        WalletFactoryDeployer deployer1 = new WalletFactoryDeployer(_entityRegistry, _governance, "salt1");
        WalletFactoryDeployer deployer2 = new WalletFactoryDeployer(_entityRegistry, _governance, "salt2");

        assertNotEq(address(deployer1.walletFactory()), address(deployer2.walletFactory()));
    }

    function test_walletFactoryIsProxy() public view {
        bytes32 beaconSlot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address beacon = address(uint160(uint256(vm.load(address(_walletFactory), beaconSlot))));
        assertGt(address(_walletFactory).code.length, 0);
        assertNotEq(beacon, address(0));
        assertGt(beacon.code.length, 0);
    }

    function test_deployment_reverts_zeroEntityRegistry() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new WalletFactoryDeployer(address(0), _governance, "salt");
    }

    function test_deployment_reverts_zeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new WalletFactoryDeployer(_entityRegistry, address(0), "salt");
    }
}

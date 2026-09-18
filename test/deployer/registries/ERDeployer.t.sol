// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {ERDeployer} from "src/deployer/registries/ERDeployer.sol";

contract ERDeployerTest is Test {
    ERDeployer internal _entityRegistryDeployer;
    EntityRegistry internal _entityRegistry;

    address internal _governance;

    function setUp() public {
        _governance = makeAddr("governance");

        _entityRegistryDeployer = new ERDeployer(_governance, "EntityRegistrySalt");
        _entityRegistry = _entityRegistryDeployer.entityRegistry();
    }

    function test_owner() public view {
        assertEq(_entityRegistry.owner(), _governance);
    }

    function test_deploymentWithEmptySalt_success() public {
        ERDeployer newERDeployer = new ERDeployer(_governance, "");
        EntityRegistry newEntityRegistry = newERDeployer.entityRegistry();

        assertNotEq(newEntityRegistry.owner(), address(0));
    }

    function test_deploymentAddressesAreUnique() public {
        ERDeployer deployer1 = new ERDeployer(_governance, "salt1");
        ERDeployer deployer2 = new ERDeployer(_governance, "salt2");

        assertNotEq(address(deployer1.entityRegistry()), address(deployer2.entityRegistry()));
    }

    function test_deploymentWithZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new ERDeployer(address(0), "salt");
    }
}

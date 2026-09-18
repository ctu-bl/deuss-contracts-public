// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {PolicyRegistryDeployer} from "src/deployer/registries/PolicyRegistryDeployer.sol";

contract PolicyRegistryDeployerTest is Test {
    address internal _governance;

    function setUp() public {
        _governance = makeAddr("governance");
    }

    function test_owner() public {
        PolicyRegistryDeployer deployer = new PolicyRegistryDeployer(_governance, "policy-registry");
        PolicyRegistry registry = deployer.policyRegistry();

        assertEq(registry.owner(), _governance);
    }

    function test_policyRegistryIsProxy() public {
        PolicyRegistryDeployer deployer = new PolicyRegistryDeployer(_governance, "policy-registry");
        address registry = address(deployer.policyRegistry());

        bytes32 beaconSlot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address beacon = address(uint160(uint256(vm.load(registry, beaconSlot))));
        assertGt(registry.code.length, 0);
        assertNotEq(beacon, address(0));
        assertGt(beacon.code.length, 0);
    }

    function test_deploymentAddressesAreUnique() public {
        PolicyRegistryDeployer deployer1 = new PolicyRegistryDeployer(_governance, "salt1");
        PolicyRegistryDeployer deployer2 = new PolicyRegistryDeployer(_governance, "salt2");

        assertNotEq(address(deployer1.policyRegistry()), address(deployer2.policyRegistry()));
    }

    function test_deployment_reverts_zeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new PolicyRegistryDeployer(address(0), "policy-registry");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {BRDeployer} from "src/deployer/registries/BRDeployer.sol";

contract BRDeployerTest is Test {
    BRDeployer internal _brDeployer;
    BondRegistry internal _bondRegistry;

    address internal _governance;
    uint256 internal _validityPeriod;

    function setUp() public {
        _governance = makeAddr("governance");

        _brDeployer = new BRDeployer(_governance, "BondRegistrySalt");
        _bondRegistry = _brDeployer.bondRegistry();
    }

    function test_owner() public view {
        assertEq(_bondRegistry.owner(), _governance);
    }

    function test_deploymentWithEmptySalt_success() public {
        BRDeployer newbrDeployer = new BRDeployer(_governance, "");
        BondRegistry newBondRegistry = newbrDeployer.bondRegistry();

        assertNotEq(address(newBondRegistry), address(0));
    }

    function test_deploymentAddressesAreUnique() public {
        BRDeployer deployer1 = new BRDeployer(_governance, "salt1");
        BRDeployer deployer2 = new BRDeployer(_governance, "salt2");

        assertNotEq(address(deployer1.bondRegistry()), address(deployer2.bondRegistry()));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {AssetManagerDeployer} from "src/deployer/marketplace/AssetManagerDeployer.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";

contract AssetManagerDeployerTest is Test {
    AssetManagerDeployer internal _amDeployer;
    AssetManager internal _assetManager;

    address internal _governance;

    function setUp() public {
        _governance = makeAddr("governance");

        _amDeployer = new AssetManagerDeployer(_governance, "AssetManagerSalt");
        _assetManager = _amDeployer.assetManager();
    }

    function test_assetManagerOwner() public view {
        assertEq(_assetManager.owner(), _governance);
    }

    function test_assetManagerAdminRoleNotGrantedByDefault() public view {
        assertFalse(_assetManager.hasAnyRole(_governance, _assetManager.ADMIN()));
    }

    function test_deployment_success_withEmptySalt() public {
        AssetManagerDeployer newDeployer = new AssetManagerDeployer(_governance, "");
        AssetManager newAssetManager = newDeployer.assetManager();

        assertNotEq(address(newAssetManager), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        AssetManagerDeployer deployer1 = new AssetManagerDeployer(_governance, "salt1");
        AssetManagerDeployer deployer2 = new AssetManagerDeployer(_governance, "salt2");

        assertNotEq(address(deployer1.assetManager()), address(deployer2.assetManager()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new AssetManagerDeployer(address(0), "salt");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {BondMarketFilterDeployer} from "src/deployer/marketplace/BondMarketFilterDeployer.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";

contract BondMarketFilterDeployerTest is Test {
    BondMarketFilterDeployer internal _bmfDeployer;
    BondMarketFilter internal _bondMarketFilter;

    address internal _governance;

    function setUp() public {
        _governance = makeAddr("governance");

        _bmfDeployer = new BondMarketFilterDeployer(_governance, "BondMarketFilterSalt");
        _bondMarketFilter = _bmfDeployer.bondMarketFilter();
    }

    function test_bondMarketFilterOwner() public view {
        assertEq(_bondMarketFilter.owner(), _governance);
    }

    function test_bondMarketFilterAdminRoleNotGrantedByDefault() public view {
        assertFalse(_bondMarketFilter.hasAnyRole(_governance, _bondMarketFilter.ADMIN()));
    }

    function test_deployment_success_withEmptySalt() public {
        BondMarketFilterDeployer newDeployer = new BondMarketFilterDeployer(_governance, "");
        BondMarketFilter newFilter = newDeployer.bondMarketFilter();

        assertNotEq(address(newFilter), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        BondMarketFilterDeployer deployer1 = new BondMarketFilterDeployer(_governance, "salt1");
        BondMarketFilterDeployer deployer2 = new BondMarketFilterDeployer(_governance, "salt2");

        assertNotEq(address(deployer1.bondMarketFilter()), address(deployer2.bondMarketFilter()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new BondMarketFilterDeployer(address(0), "salt");
    }
}

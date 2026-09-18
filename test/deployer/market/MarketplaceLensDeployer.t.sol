// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MarketplaceLensDeployer} from "src/deployer/marketplace/MarketplaceLensDeployer.sol";
import {MarketplaceLens} from "src/marketplace/lens/MarketplaceLens.sol";
import {Errors} from "src/libs/Errors.sol";

contract MarketplaceLensDeployerTest is Test {
    MarketplaceLensDeployer internal _lensDeployer;
    MarketplaceLens internal _marketplaceLens;

    address internal _governance;
    address internal _marketplace;

    function setUp() public {
        _governance = makeAddr("governance");
        _marketplace = makeAddr("marketplace");

        _lensDeployer = new MarketplaceLensDeployer(_governance, _marketplace, "MarketplaceLensSalt");
        _marketplaceLens = _lensDeployer.marketplaceLens();
    }

    function test_marketplaceLensOwner() public view {
        assertEq(_marketplaceLens.owner(), _governance);
    }

    function test_marketplaceLensTarget() public view {
        assertEq(_marketplaceLens.marketplace(), _marketplace);
    }

    function test_deployment_success_withEmptySalt() public {
        MarketplaceLensDeployer newDeployer = new MarketplaceLensDeployer(_governance, _marketplace, "");
        MarketplaceLens newMarketplaceLens = newDeployer.marketplaceLens();

        assertNotEq(address(newMarketplaceLens), address(0));
    }

    function test_deployment_success_addressesAreUnique() public {
        MarketplaceLensDeployer deployer1 = new MarketplaceLensDeployer(_governance, _marketplace, "salt1");
        MarketplaceLensDeployer deployer2 = new MarketplaceLensDeployer(_governance, _marketplace, "salt2");

        assertNotEq(address(deployer1.marketplaceLens()), address(deployer2.marketplaceLens()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new MarketplaceLensDeployer(address(0), _marketplace, "salt");
    }

    function test_deployment_reverts_withZeroMarketplace() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new MarketplaceLensDeployer(_governance, address(0), "salt");
    }
}

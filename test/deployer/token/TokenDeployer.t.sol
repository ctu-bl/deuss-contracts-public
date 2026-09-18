// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {TokenDeployer} from "src/deployer/token/TokenDeployer.sol";
import {Errors} from "src/libs/Errors.sol";

contract TokenDeployerTest is Test {
    TokenDeployer internal _tokenDeployer;
    DEUSSToken internal _token;

    address internal _governance;
    address internal _bondRegistry;
    address internal _entityRegistry;
    address internal _escrowManager;

    function setUp() public {
        _governance = makeAddr("governance");
        _bondRegistry = makeAddr("bondRegistry");
        _entityRegistry = makeAddr("entityRegistry");
        _escrowManager = makeAddr("escrowManager");

        _tokenDeployer = new TokenDeployer(_governance, _bondRegistry, _entityRegistry, _escrowManager, "TokenSalt");
        _token = _tokenDeployer.token();
    }

    function test_owner() public view {
        assertEq(_token.owner(), _governance);
    }

    function test_bondRegistry() public view {
        assertEq(address(_token.bondRegistry()), _bondRegistry);
    }

    function test_entityRegistry() public view {
        assertEq(address(_token.entityRegistry()), _entityRegistry);
    }

    function test_escrowManagerProtected() public view {
        assertTrue(_token.isAddressProtected(_escrowManager));
    }

    function test_deploymentWithEmptySalt_success() public {
        TokenDeployer newDeployer = new TokenDeployer(_governance, _bondRegistry, _entityRegistry, _escrowManager, "");
        DEUSSToken newToken = newDeployer.token();

        assertNotEq(address(newToken), address(0));
        assertTrue(newToken.isAddressProtected(_escrowManager));
    }

    function test_deploymentAddressesAreUnique() public {
        TokenDeployer deployer1 =
            new TokenDeployer(_governance, _bondRegistry, _entityRegistry, _escrowManager, "salt1");
        TokenDeployer deployer2 =
            new TokenDeployer(_governance, _bondRegistry, _entityRegistry, _escrowManager, "salt2");

        assertNotEq(address(deployer1.token()), address(deployer2.token()));
    }

    function test_deployment_reverts_withZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableInvalidOwner.selector, address(0)));
        new TokenDeployer(address(0), _bondRegistry, _entityRegistry, _escrowManager, "salt");
    }

    function test_deployment_reverts_zeroBondRegistry() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenDeployer(_governance, address(0), _entityRegistry, _escrowManager, "salt");
    }

    function test_deployment_reverts_zeroEntityRegistry() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenDeployer(_governance, _bondRegistry, address(0), _escrowManager, "salt");
    }

    function test_deployment_reverts_zeroEscrowManager() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenDeployer(_governance, _bondRegistry, _entityRegistry, address(0), "salt");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TimelockControllerDeployer} from "src/deployer/governance/TimelockControllerDeployer.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";

contract TimelockControllerDeployerTest is Test {
    TimelockControllerDeployer internal _deployer;
    TimelockControllerUpgradeable internal _timelockController;

    address internal _initialAdmin;
    address internal _proposer;
    address internal _executor;

    uint256 internal _initialMinDelay;

    function setUp() public {
        _initialAdmin = makeAddr("initialAdmin");
        _proposer = makeAddr("proposer");
        _executor = makeAddr("executor");
        _initialMinDelay = 1 days;

        address[] memory proposers = new address[](1);
        proposers[0] = _proposer;

        address[] memory executors = new address[](1);
        executors[0] = _executor;

        _deployer = new TimelockControllerDeployer(
            _initialMinDelay, proposers, executors, _initialAdmin, "TimelockControllerSalt"
        );
        _timelockController = _deployer.timelockController();
    }

    function test_deploymentWithEmptySalt_success() public {
        address[] memory empty = new address[](0);
        TimelockControllerDeployer newDeployer =
            new TimelockControllerDeployer(_initialMinDelay, empty, empty, address(0), "");
        assertNotEq(address(newDeployer.timelockController()), address(0));
    }

    function test_deploymentAddressesAreUnique() public {
        address[] memory empty = new address[](0);
        TimelockControllerDeployer deployer1 =
            new TimelockControllerDeployer(_initialMinDelay, empty, empty, address(0), "salt1");
        TimelockControllerDeployer deployer2 =
            new TimelockControllerDeployer(_initialMinDelay, empty, empty, address(0), "salt2");
        assertNotEq(address(deployer1.timelockController()), address(deployer2.timelockController()));
    }

    function test_initialize_reverts_alreadyInitialized() public {
        address[] memory empty = new address[](0);
        TimelockControllerUpgradeable deployed =
            new TimelockControllerDeployer(_initialMinDelay, empty, empty, address(0), "").timelockController();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        deployed.initialize(_initialMinDelay, empty, empty, address(0));
    }

    function test_initialize_reverts_onImplementationDirectly() public {
        address[] memory empty = new address[](0);
        TimelockControllerDeployer newDeployer =
            new TimelockControllerDeployer(_initialMinDelay, empty, empty, address(0), "");

        address timelockProxy = address(newDeployer.timelockController());
        address beacon = address(uint160(uint256(vm.load(timelockProxy, Constants.BEACON_SLOT))));
        address payable impl = payable(IBeacon(beacon).implementation());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TimelockControllerUpgradeable(impl).initialize(_initialMinDelay, empty, empty, address(0));
    }
}

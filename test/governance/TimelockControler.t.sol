// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable as OwnableOZ} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockTargetContract, MockReentrantTarget} from "test/mocks/MockContracts.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {BaseFixture} from "../fixtures/BaseFixture.t.sol";

contract TimelockControllerTest is BaseFixture {
    uint256 internal constant _MIN_DELAY = 1 days;
    bytes32 internal constant _NO_PREDECESSOR = bytes32(0);
    bytes32 internal constant _SALT = bytes32("_SALT");

    address internal _canceller;

    // cached roles — avoid consuming vm.prank with external calls inside test arguments
    bytes32 internal _adminRole;
    bytes32 internal _proposerRole;
    bytes32 internal _executorRole;
    bytes32 internal _cancellerRole;

    TimelockController internal _timelock;
    MockTargetContract internal _target;

    function setUp() public override {
        super.setUp();
        _admin = _timelockControllerAdmin;
        _canceller = makeAddr("canceller");

        address[] memory proposers = new address[](1);
        proposers[0] = _proposer;

        address[] memory executors = new address[](1);
        executors[0] = _executor;

        _timelock = TimelockController(payable(_suite.governance.timelockController));

        _adminRole = _timelock.DEFAULT_ADMIN_ROLE();
        _proposerRole = _timelock.PROPOSER_ROLE();
        _executorRole = _timelock.EXECUTOR_ROLE();
        _cancellerRole = _timelock.CANCELLER_ROLE();

        vm.startPrank(_admin);
        _timelock.grantRole(_executorRole, _executor);
        _timelock.grantRole(_proposerRole, _proposer);
        _timelock.grantRole(_cancellerRole, _canceller);
        vm.stopPrank();

        _target = new MockTargetContract();
    }

    /*//////////////////////////////////////////////////////////////
                            initial state
    //////////////////////////////////////////////////////////////*/

    function test_initialState_minDelay() public {
        assertEq(_timelock.getMinDelay(), _MIN_DELAY);
    }

    function test_initialState_adminRole() public {
        assertTrue(_timelock.hasRole(_adminRole, _admin));
    }

    function test_initialState_proposerRole() public {
        assertTrue(_timelock.hasRole(_proposerRole, _proposer));
    }

    function test_initialState_executorRole() public {
        assertTrue(_timelock.hasRole(_executorRole, _executor));
    }

    function test_initialState_timelockIsSelfAdmin() public {
        assertTrue(_timelock.hasRole(_adminRole, address(_timelock)));
    }

    function test_initialState_beaconOwnedByTimelock() public {
        assertEq(UpgradeableBeacon(_suite.governance.timelockControllerBeacon).owner(), address(_timelock));
    }

    /*//////////////////////////////////////////////////////////////
                grantRole / revokeRole / renounceRole
    //////////////////////////////////////////////////////////////*/

    function test_grantRole_success_byAdmin() public {
        address newProposer = makeAddr("newProposer");
        vm.expectEmit(true, true, true, false);
        emit IAccessControl.RoleGranted(_proposerRole, newProposer, _admin);
        vm.startPrank(_admin);
        _timelock.grantRole(_proposerRole, newProposer);
        vm.stopPrank();
        assertTrue(_timelock.hasRole(_proposerRole, newProposer));
    }

    function test_grantRole_revert_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        address newProposer = makeAddr("newProposer");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, _adminRole)
        );
        vm.prank(notAdmin);
        _timelock.grantRole(_proposerRole, newProposer);
    }

    function test_revokeRole_success_byAdmin() public {
        vm.expectEmit(true, true, true, false);
        emit IAccessControl.RoleRevoked(_proposerRole, _proposer, _admin);
        vm.startPrank(_admin);
        _timelock.revokeRole(_proposerRole, _proposer);
        vm.stopPrank();
        assertFalse(_timelock.hasRole(_proposerRole, _proposer));
    }

    function test_revokeRole_revert_notAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, _adminRole)
        );
        vm.prank(notAdmin);
        _timelock.revokeRole(_proposerRole, _proposer);
    }

    function test_renounceRole_success() public {
        vm.expectEmit(true, true, true, false);
        emit IAccessControl.RoleRevoked(_proposerRole, _proposer, _proposer);
        vm.prank(_proposer);
        _timelock.renounceRole(_proposerRole, _proposer);
        assertFalse(_timelock.hasRole(_proposerRole, _proposer));
    }

    function test_renounceRole_revert_badConfirmation() public {
        address notProposer = makeAddr("notProposer");
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        vm.prank(notProposer);
        _timelock.renounceRole(_proposerRole, _proposer);
    }

    /*//////////////////////////////////////////////////////////////
                            schedule
    //////////////////////////////////////////////////////////////*/

    function test_schedule_success() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _timelock.hashOperation(address(_target), 0, data, _NO_PREDECESSOR, _SALT);

        vm.expectEmit(true, true, true, true);
        emit TimelockControllerUpgradeable.CallScheduled(id, 0, address(_target), 0, data, _NO_PREDECESSOR, _MIN_DELAY);
        vm.expectEmit(true, false, false, true);
        emit TimelockControllerUpgradeable.CallSalt(id, _SALT);
        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        assertTrue(_timelock.isOperationPending(id));
    }

    function test_schedule_revert_notProposer() public {
        address notProposer = makeAddr("notProposer");
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notProposer, _proposerRole)
        );
        vm.prank(notProposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
    }

    function test_schedule_revert_insufficientDelay() public {
        uint256 tooShort = _MIN_DELAY - 1;
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        vm.prank(_proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockInsufficientDelay.selector, tooShort, _MIN_DELAY
            )
        );
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, tooShort);
    }

    function test_schedule_revert_alreadyScheduled() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _timelock.hashOperation(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
        bytes32 expectedStates = bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Unset));

        vm.startPrank(_proposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, id, expectedStates
            )
        );
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            execute
    //////////////////////////////////////////////////////////////*/

    function test_execute_success() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _schedule(_proposer, address(_target), data);

        vm.expectEmit(true, true, true, true);
        emit TimelockControllerUpgradeable.CallExecuted(id, 0, address(_target), 0, data);
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);

        assertTrue(_timelock.isOperationDone(id));
        assertTrue(_target.state());
    }

    function test_execute_success_withPredecessor() public {
        bytes32 _salt2 = keccak256("_SALT2");
        bytes memory firstData = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 predecessorId = _schedule(_proposer, address(_target), firstData);

        bytes memory secondData = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 dependentId = _timelock.hashOperation(address(_target), 0, secondData, predecessorId, _salt2);
        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, secondData, predecessorId, _salt2, _MIN_DELAY);
        vm.warp(block.timestamp + _MIN_DELAY);

        vm.prank(_executor);
        _timelock.execute(address(_target), 0, firstData, _NO_PREDECESSOR, _SALT);

        vm.expectEmit(true, true, true, true);
        emit TimelockControllerUpgradeable.CallExecuted(dependentId, 0, address(_target), 0, secondData);
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, secondData, predecessorId, _salt2);

        assertTrue(_timelock.isOperationDone(dependentId));
    }

    function test_execute_revert_predecessorNotDone() public {
        bytes32 _salt2 = keccak256("_SALT2");
        bytes memory firstData = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 predecessorId = _timelock.hashOperation(address(_target), 0, firstData, _NO_PREDECESSOR, _SALT);

        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, firstData, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        bytes memory secondData = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, secondData, predecessorId, _salt2, _MIN_DELAY);

        vm.warp(block.timestamp + _MIN_DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockControllerUpgradeable.TimelockUnexecutedPredecessor.selector, predecessorId)
        );
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, secondData, predecessorId, _salt2);
    }

    function test_execute_revert_notExecutor() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        _schedule(_proposer, address(_target), data);

        address notExecutor = makeAddr("notExecutor");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notExecutor, _executorRole)
        );
        vm.prank(notExecutor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_execute_revert_notReady() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _timelock.hashOperation(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
        bytes32 expectedStates = bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Ready));

        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, id, expectedStates
            )
        );
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_execute_revert_alreadyDone() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _schedule(_proposer, address(_target), data);
        bytes32 expectedStates = bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Ready));

        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, id, expectedStates
            )
        );
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_execute_revert_callFailedWithReturnData() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateFailure, ());
        _schedule(_proposer, address(_target), data);

        vm.expectRevert(bytes("External call failed"));
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_execute_revert_callFailedNoReturnData() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSilentFailure, ());
        _schedule(_proposer, address(_target), data);

        vm.expectRevert(Errors.FailedCall.selector);
        vm.prank(_executor);
        _timelock.execute(address(_target), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_execute_revert_reentrancy() public {
        MockReentrantTarget reentrant = new MockReentrantTarget();
        bytes memory attackData = abi.encodeCall(MockReentrantTarget.attack, ());

        // configure re-entrant target to call execute again with the same operation
        reentrant.configure(address(_timelock), address(reentrant), attackData, _NO_PREDECESSOR, _SALT);

        // grant executor role to reentrant contract so the inner execute passes access control
        vm.prank(_admin);
        _timelock.grantRole(_executorRole, address(reentrant));

        bytes32 id = _schedule(_proposer, address(reentrant), attackData);

        // inner re-entrant execute succeeds and marks op as DONE;
        // outer _afterCall then finds id no longer Ready and reverts
        bytes32 expectedStates = bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Ready));
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, id, expectedStates
            )
        );
        vm.prank(_executor);
        _timelock.execute(address(reentrant), 0, attackData, _NO_PREDECESSOR, _SALT);
    }

    /*//////////////////////////////////////////////////////////////
                            cancel
    //////////////////////////////////////////////////////////////*/

    function test_cancel_success_byCanceller() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _timelock.hashOperation(address(_target), 0, data, _NO_PREDECESSOR, _SALT);

        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        vm.expectEmit(true, false, false, false);
        emit TimelockControllerUpgradeable.Cancelled(id);
        vm.prank(_canceller);
        _timelock.cancel(id);

        assertFalse(_timelock.isOperation(id));
    }

    function test_cancel_revert_notCanceller() public {
        bytes memory data = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        bytes32 id = _timelock.hashOperation(address(_target), 0, data, _NO_PREDECESSOR, _SALT);

        vm.prank(_proposer);
        _timelock.schedule(address(_target), 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        address notCanceller = makeAddr("notCanceller");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notCanceller, _cancellerRole
            )
        );
        vm.prank(notCanceller);
        _timelock.cancel(id);
    }

    function test_cancel_revert_invalidOperation() public {
        bytes32 invalidId = keccak256("nonexistent");
        bytes32 expectedStates = bytes32(
            (1 << uint8(TimelockControllerUpgradeable.OperationState.Waiting))
                | (1 << uint8(TimelockControllerUpgradeable.OperationState.Ready))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, invalidId, expectedStates
            )
        );
        vm.prank(_canceller);
        _timelock.cancel(invalidId);
    }

    /*//////////////////////////////////////////////////////////////
                            updateDelay
    //////////////////////////////////////////////////////////////*/

    function test_updateDelay_success_viaTimelock() public {
        uint256 newDelay = 2 days;
        bytes memory data = abi.encodeCall(TimelockControllerUpgradeable.updateDelay, (newDelay));

        bytes32 id = _schedule(_proposer, address(_timelock), data);
        vm.expectEmit(false, false, false, true);
        emit TimelockControllerUpgradeable.MinDelayChange(_MIN_DELAY, newDelay);
        vm.prank(_executor);
        _timelock.execute(address(_timelock), 0, data, _NO_PREDECESSOR, _SALT);

        assertTrue(_timelock.isOperationDone(id));
        assertEq(_timelock.getMinDelay(), newDelay);
    }

    function test_updateDelay_revert_directCall() public {
        vm.expectRevert(
            abi.encodeWithSelector(TimelockControllerUpgradeable.TimelockUnauthorizedCaller.selector, _admin)
        );
        vm.prank(_admin);
        _timelock.updateDelay(2 days);
    }

    /*//////////////////////////////////////////////////////////////
                        batch operations
    //////////////////////////////////////////////////////////////*/

    function test_scheduleBatch_and_executeBatch_success() public {
        address[] memory targets = new address[](2);
        targets[0] = address(_target);
        targets[1] = address(_target);

        uint256[] memory values = new uint256[](2);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(MockTargetContract.simulateSuccess, (true));
        payloads[1] = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        bytes32 id = _timelock.hashOperationBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);

        vm.prank(_proposer);
        _timelock.scheduleBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        vm.warp(block.timestamp + _MIN_DELAY);

        vm.prank(_executor);
        _timelock.executeBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);

        assertTrue(_timelock.isOperationDone(id));
        assertTrue(_target.state());
    }

    function test_scheduleBatch_revert_lengthMismatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](2);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockControllerUpgradeable.TimelockInvalidOperationLength.selector, 2, 2, 1)
        );
        vm.prank(_proposer);
        _timelock.scheduleBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
    }

    function test_scheduleBatch_revert_notProposer() public {
        address[] memory targets = new address[](1);
        targets[0] = address(_target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        address notProposer = makeAddr("notProposer");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notProposer, _proposerRole)
        );
        vm.prank(notProposer);
        _timelock.scheduleBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
    }

    function test_executeBatch_revert_notExecutor() public {
        address[] memory targets = new address[](1);
        targets[0] = address(_target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        vm.prank(_proposer);
        _timelock.scheduleBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
        vm.warp(block.timestamp + _MIN_DELAY);

        address notExecutor = makeAddr("notExecutor");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notExecutor, _executorRole)
        );
        vm.prank(notExecutor);
        _timelock.executeBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);
    }

    function test_executeBatch_revert_lengthMismatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](2);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockControllerUpgradeable.TimelockInvalidOperationLength.selector, 2, 2, 1)
        );
        vm.prank(_executor);
        _timelock.executeBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);
    }

    function test_executeBatch_revert_notReady() public {
        address[] memory targets = new address[](1);
        targets[0] = address(_target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeCall(MockTargetContract.simulateSuccess, (true));

        bytes32 id = _timelock.hashOperationBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);
        bytes32 expectedStates = bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Ready));

        vm.prank(_proposer);
        _timelock.scheduleBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT, _MIN_DELAY);

        // delay not elapsed — still Waiting
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector, id, expectedStates
            )
        );
        vm.prank(_executor);
        _timelock.executeBatch(targets, values, payloads, _NO_PREDECESSOR, _SALT);
    }

    /*//////////////////////////////////////////////////////////////
                        beacon upgrade
    //////////////////////////////////////////////////////////////*/

    function test_upgradeTo_success_viaTimelock() public {
        address newImpl = address(new TimelockController());
        UpgradeableBeacon beacon = UpgradeableBeacon(_suite.governance.timelockControllerBeacon);

        bytes memory data = abi.encodeCall(UpgradeableBeacon.upgradeTo, (newImpl));
        _schedule(_proposer, address(beacon), data);

        vm.prank(_executor);
        _timelock.execute(address(beacon), 0, data, _NO_PREDECESSOR, _SALT);

        assertEq(beacon.implementation(), newImpl);
    }

    function test_upgradeTo_revert_implNotContract() public {
        address notAContract = makeAddr("notAContract");
        UpgradeableBeacon beacon = UpgradeableBeacon(_suite.governance.timelockControllerBeacon);
        bytes memory data = abi.encodeCall(UpgradeableBeacon.upgradeTo, (notAContract));
        _schedule(_proposer, address(beacon), data);

        vm.expectRevert(abi.encodeWithSelector(UpgradeableBeacon.BeaconInvalidImplementation.selector, notAContract));
        vm.prank(_executor);
        _timelock.execute(address(beacon), 0, data, _NO_PREDECESSOR, _SALT);
    }

    function test_upgradeTo_revert_notTimelock() public {
        address newImpl = address(new TimelockController());
        address notOwner = makeAddr("notOwner");
        UpgradeableBeacon beacon = UpgradeableBeacon(_suite.governance.timelockControllerBeacon);

        vm.expectRevert(abi.encodeWithSelector(OwnableOZ.OwnableUnauthorizedAccount.selector, notOwner));
        vm.prank(notOwner);
        beacon.upgradeTo(newImpl);
    }

    /*//////////////////////////////////////////////////////////////
                        helpers
    //////////////////////////////////////////////////////////////*/

    function _schedule(address proposer, address target, bytes memory data) internal returns (bytes32 id) {
        id = _timelock.hashOperation(target, 0, data, _NO_PREDECESSOR, _SALT);
        vm.prank(proposer);
        _timelock.schedule(target, 0, data, _NO_PREDECESSOR, _SALT, _MIN_DELAY);
        vm.warp(block.timestamp + _MIN_DELAY);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";

import {Create2Deployer} from "src/deployer/base/Create2Deployer.sol";

/* solhint-disable foundry-test-functions */
// local mock, it is not test code
contract MockDeployer is Create2Deployer {
    function deployImplementation(string memory salt, bytes memory implementationBytecode, bytes memory initData)
        public
        returns (address)
    {
        return _deployImplementationViaCreate2(salt, implementationBytecode, initData);
    }

    function deployBeacon(string memory salt, address implementation, address beaconOwner) public returns (address) {
        return _deployBeaconViaCreate2(salt, implementation, beaconOwner);
    }

    function deployBeaconProxy(string memory salt, address beacon, bytes memory initData) public returns (address) {
        return _deployBeaconProxyViaCreate2(salt, beacon, initData);
    }
}
/* solhint-enable foundry-test-functions */

contract Create2DeployerTest is Test, Create2Deployer {
    bytes public constant ER_IMPL_CREATION_CODE = type(EntityRegistry).creationCode;
    string public constant ER_IMPL_SALT = "ER_IMPL_SALT";
    string public constant ER_BEACON_SALT = "ER_BEACON_SALT";
    string public constant ER_PROX_SALT = "ER_PROX_SALT";

    bytes public constant CW_IMPL_CREATION_CODE = type(CompanyWallet).creationCode;
    string public constant CW_IMPL_SALT = "CW_IMPL_SALT";
    string public constant CW_BEACON_SALT = "CW_BEACON_SALT";
    string public constant CW_PROX_SALT = "CW_PROX_SALT";

    bytes public constant NO_CONSTRUCTOR_DATA = bytes("");

    address public beaconOwner = makeAddr("beaconOwner");

    MockDeployer private _deployer;

    function setUp() public {
        _deployer = new MockDeployer();
    }

    /*//////////////////////////////////////////////////////////////
                     deployImplementationViaCreate2
    //////////////////////////////////////////////////////////////*/

    function test_deployImplementationViaCreate2_WithNoConstructorData() public {
        address erImplAddr = _deployImplementationViaCreate2(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        assertEq(erImplAddr, _computeAddress(ER_IMPL_SALT, ER_IMPL_CREATION_CODE));
    }

    /// @dev MockDeployer used instead, otherwise test fails due to "EvmError: CreateCollision"
    function test_deployImplementationViaCreate2_WithNoConstructorData_RevertsIfAlreadyDeployed() public {
        _deployer.deployImplementation(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployer.deployImplementation(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
    }

    function test_deployImplementationViaCreate2_WithConstructorData() public {
        address cwImplAddr = _deployImplementationViaCreate2(CW_IMPL_SALT, CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        assertEq(
            cwImplAddr,
            _computeAddress(
                CW_IMPL_SALT, _prepareImplementationCreationCode(CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA)
            )
        );
    }

    function test_deployImplementationViaCreate2_WithNoConstructorData_RevertsIfAlreadyDeployer_RevertsIfAlreadyDeployed()
        public
    {
        _deployer.deployImplementation(CW_IMPL_SALT, CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployer.deployImplementation(CW_IMPL_SALT, CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
    }

    /*//////////////////////////////////////////////////////////////
                         deployBeaconViaCreate2
    //////////////////////////////////////////////////////////////*/

    function test_deployBeaconViaCreate2() public {
        address erImplAddr = _deployImplementationViaCreate2(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        address erBeaconAddr = _deployBeaconViaCreate2(ER_BEACON_SALT, erImplAddr, beaconOwner);
        assertEq(erBeaconAddr, _computeAddress(ER_BEACON_SALT, _prepareBeaconCreationCode(erImplAddr, beaconOwner)));
        assertEq(IBeacon(erBeaconAddr).implementation(), erImplAddr);
    }

    /// @dev MockDeployer used instead, otherwise test fails due to "EvmError: CreateCollision"
    function test_deployBeaconViaCreate2_RevertsIfAlreadyDeployed() public {
        address erImplAddr = _deployer.deployImplementation(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        _deployer.deployBeacon(ER_BEACON_SALT, erImplAddr, beaconOwner);
        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployer.deployBeacon(ER_BEACON_SALT, erImplAddr, beaconOwner);
    }

    /*//////////////////////////////////////////////////////////////
                       deployBeaconProxyViaCreate2
    //////////////////////////////////////////////////////////////*/

    function test_deployBeaconProxyViaCreate2_WithNoConstructorData() public {
        address erImplAddr = _deployImplementationViaCreate2(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        address erBeaconAddr = _deployBeaconViaCreate2(ER_BEACON_SALT, erImplAddr, beaconOwner);
        address erProxyAddr = _deployBeaconProxyViaCreate2(ER_PROX_SALT, erBeaconAddr, NO_CONSTRUCTOR_DATA);
        assertEq(
            erProxyAddr,
            _computeAddress(ER_PROX_SALT, _prepareBeaconProxyCreationCode(erBeaconAddr, NO_CONSTRUCTOR_DATA))
        );
    }

    /// @dev MockDeployer used instead, otherwise test fails due to "EvmError: CreateCollision"
    function test_deployBeaconProxyViaCreate2_WithNoConstructorData_RevertsIfAlreadyDeployed() public {
        address erImplAddr = _deployer.deployImplementation(ER_IMPL_SALT, ER_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        address erBeaconAddr = _deployer.deployBeacon(ER_BEACON_SALT, erImplAddr, beaconOwner);
        _deployer.deployBeaconProxy(ER_PROX_SALT, erBeaconAddr, NO_CONSTRUCTOR_DATA);
        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployer.deployBeaconProxy(ER_PROX_SALT, erBeaconAddr, NO_CONSTRUCTOR_DATA);
    }

    function test_deployBeaconProxyViaCreate2_WithConstructorData() public {
        address cwImplAddr = _deployImplementationViaCreate2(CW_IMPL_SALT, CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        address cwBeaconAddr = _deployBeaconViaCreate2(CW_BEACON_SALT, cwImplAddr, beaconOwner);

        address user = makeAddr("user");
        address policyRegistry = address(_deployPolicyRegistry(user));
        bytes memory cwProxyInitData = abi.encodeWithSelector(ICompanyWallet.initialize.selector, user, policyRegistry);

        address cwProxAddr = _deployBeaconProxyViaCreate2(CW_PROX_SALT, cwBeaconAddr, cwProxyInitData);
        assertEq(
            cwProxAddr, _computeAddress(CW_PROX_SALT, _prepareBeaconProxyCreationCode(cwBeaconAddr, cwProxyInitData))
        );
    }

    function test_deployBeaconProxyViaCreate2_WithConstructorData_RevertsIfAlreadyDeployed() public {
        address cwImplAddr = _deployer.deployImplementation(CW_IMPL_SALT, CW_IMPL_CREATION_CODE, NO_CONSTRUCTOR_DATA);
        address cwBeaconAddr = _deployer.deployBeacon(CW_BEACON_SALT, cwImplAddr, beaconOwner);

        address user = makeAddr("user");
        address policyRegistry = address(_deployPolicyRegistry(user));
        bytes memory cwProxyInitData = abi.encodeWithSelector(ICompanyWallet.initialize.selector, user, policyRegistry);

        _deployer.deployBeaconProxy(CW_PROX_SALT, cwBeaconAddr, cwProxyInitData);
        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployer.deployBeaconProxy(CW_PROX_SALT, cwBeaconAddr, cwProxyInitData);
    }

    /// @notice Computes the address of a contract deployed via CREATE2
    /// @param salt A unique value to ensure unique contract addresses
    /// @param bytecode The bytecode of the contract to deploy
    /// @return predictedAddress The predicted address of the deployed contract
    function _computeAddress(string memory salt, bytes memory bytecode) private view returns (address) {
        bytes32 saltBytes = keccak256(abi.encodePacked(salt));
        return Create2.computeAddress(saltBytes, keccak256(bytecode), address(this));
    }

    function _deployPolicyRegistry(address owner_) private returns (PolicyRegistry registry) {
        address impl =
            _deployImplementationViaCreate2("PR_IMPL", type(PolicyRegistry).creationCode, NO_CONSTRUCTOR_DATA);
        address beacon = _deployBeaconViaCreate2("PR_BEACON", impl, beaconOwner);
        bytes memory initData = abi.encodeWithSelector(PolicyRegistry.initialize.selector, owner_);
        registry = PolicyRegistry(_deployBeaconProxyViaCreate2("PR_PROX", beacon, initData));
    }
}

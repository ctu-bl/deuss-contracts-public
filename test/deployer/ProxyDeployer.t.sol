// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.34;

import {console2} from "forge-std/console2.sol";

import {Errors} from "src/libs/Errors.sol";
import {IProxyDeployer} from "src/deployer/IProxyDeployer.sol";
import {IProxyFactory} from "ebsi/contract-factory/interfaces/IProxyFactory.sol";
import {IProxyTemplateRegistry} from "ebsi/contract-factory/interfaces/IProxyTemplateRegistry.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ProxyDeployer} from "src/deployer/ProxyDeployer.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {EBSIFixtures} from "test/fixtures/EBSIFixtures.t.sol";
import {MockInitializable} from "test/mocks/MockContracts.sol";

/* solhint-disable foundry-test-functions */
/**
 * @notice Test harness to expose ProxyDeployer's abstract functionality
 */
contract ProxyDeployerHarness is ProxyDeployer {
    constructor(address owner) {
        _initializeOwner(owner);
    }

    // Expose internal _deployProxy for testing
    function deployProxy(bytes32 templateId, bytes calldata initData) external returns (address) {
        return _deployProxy(templateId, initData);
    }

    // Expose internal _deployProxyWithSalt for testing
    function deployProxyWithSalt(bytes32 templateId, bytes calldata initData, bytes32 salt) external returns (address) {
        return _deployProxyWithSalt(templateId, initData, salt);
    }

    // Expose internal storage for testing
    function getTemplateFactory() external view returns (address) {
        return _proxyDeployerStorage().templateFactory;
    }

    function getTemplateRegistry() external view returns (address) {
        return _proxyDeployerStorage().templateRegistry;
    }

    function getTemplateConfigInternal(bytes32 templateId) external view returns (TemplateConfig memory) {
        return _proxyDeployerStorage().templateConfigs[templateId];
    }

    function proxyDeployerStorageLocation() external pure returns (bytes32) {
        return _PROXY_DEPLOYER_STORAGE_LOCATION;
    }
}
/* solhint-enable foundry-test-functions */

contract ProxyDeployerTest is EBSIFixtures {
    ProxyDeployerHarness internal _proxyDeployer;

    // Test data
    string internal constant _TEMPLATE_NAME = "TestTemplate";
    string internal constant _TEMPLATE_VERSION = "1.0.0";
    string internal constant _TEMPLATE_NAME_2 = "TestTemplate2";
    string internal constant _TEMPLATE_VERSION_2 = "2.0.0";
    string internal constant _ISSUER_DID = "did:ebsi:test123";

    address internal _deployerOwner;
    address internal _notOwner;
    address internal _testImplementation;
    address internal _testBeacon;

    bytes32 internal _templateId;
    bytes32 internal _templateId2;

    function setUp() public override {
        super.setUp();

        _notOwner = makeAddr("notOwner");
        _deployerOwner = makeAddr("_deployerOwner");

        // Deploy a mock implementation and beacon for testing
        _testImplementation = address(new MockInitializable());
        _testBeacon = address(new UpgradeableBeacon(_testImplementation, _deployerOwner));

        // Deploy harness
        _proxyDeployer = new ProxyDeployerHarness(_deployerOwner);

        vm.label(address(_proxyDeployer), "ProxyDeployer");
        vm.label(_deployerOwner, "DeployerOwner");
        vm.label(_notOwner, "NotOwner");
        vm.label(_testImplementation, "MockImplementation");
        vm.label(_testBeacon, "MockBeacon");
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupFactoryAndRegistry() internal {
        console2.log("Set factory + registry");
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setFactory(_proxyFactoryAddr);
        _proxyDeployer.setRegistry(_proxyTemplateRegistryAddr);
        vm.stopPrank();
    }

    function _createProxyTemplate(string memory name, string memory version)
        internal
        view
        returns (IProxyTemplateRegistry.ProxyTemplate memory)
    {
        console2.log("Creating proxy template");
        IProxyTemplateRegistry.ProxyTemplate memory template = IProxyTemplateRegistry.ProxyTemplate({
            name: name,
            version: version,
            beaconAddress: _testBeacon,
            repoURI: "https://github.com/test/repo",
            auditURI: "https://audit.test",
            contractHash: keccak256("test"),
            initSelector: MockInitializable.initialize.selector, // Use mock's initialize selector
            storageLayoutHash: keccak256("layout"),
            isActive: true
        });
        return template;
    }

    function _addTemplateToEBSIRegistry(string memory name, string memory version) internal {
        IProxyTemplateRegistry.ProxyTemplate memory template = _createProxyTemplate(name, version);

        console2.log("Add template to registry");
        // Use deployer for EBSI operations (EBSI contracts owned by deployer)
        vm.prank(getEbsiGovernance());
        _proxyTemplateRegistry.addTemplate(template);
    }

    function _addTestTemplate() internal returns (bytes32 templateId) {
        // Add template to EBSI registry first
        _addTemplateToEBSIRegistry(_TEMPLATE_NAME, _TEMPLATE_VERSION);

        // Add to ProxyDeployer (owned by deployerOwner)
        vm.prank(_deployerOwner);
        templateId = _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                        SET FACTORY
    //////////////////////////////////////////////////////////////*/

    function test_setFactory_success() public {
        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.FactorySet(_proxyFactoryAddr);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setFactory(_proxyFactoryAddr);

        assertEq(_proxyDeployer.getFactory(), _proxyFactoryAddr);
    }

    function test_setFactory_success_withRegistryAlreadySet() public {
        // Set registry first
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setRegistry(_proxyTemplateRegistryAddr);

        // Then set factory - should validate they're wired together
        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.FactorySet(_proxyFactoryAddr);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setFactory(_proxyFactoryAddr);

        assertEq(_proxyDeployer.getFactory(), _proxyFactoryAddr);
    }

    function test_setFactory_revert_notOwner() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _proxyDeployer.setFactory(_proxyFactoryAddr);
    }

    function test_setFactory_revert_zeroAddress() public {
        vm.startPrank(_deployerOwner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _proxyDeployer.setFactory(address(0));
    }

    function test_setFactory_revert_invalidRegistry() public {
        address wrongRegistry = makeAddr("wrongRegistry");

        // Set wrong registry first
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setRegistry(wrongRegistry);

        // Try to set factory - should fail because factory's registry doesn't match
        vm.startPrank(_deployerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ProxyDeployer__InvalidRegistry.selector, wrongRegistry, _proxyTemplateRegistryAddr
            )
        );
        _proxyDeployer.setFactory(_proxyFactoryAddr);
    }

    /*//////////////////////////////////////////////////////////////
                        SET REGISTRY
    //////////////////////////////////////////////////////////////*/

    function test_setRegistry_success() public {
        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.RegistrySet(_proxyTemplateRegistryAddr);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setRegistry(_proxyTemplateRegistryAddr);

        assertEq(_proxyDeployer.getRegistry(), _proxyTemplateRegistryAddr);
    }

    function test_setRegistry_success_withFactoryAlreadySet() public {
        // Set factory first
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setFactory(_proxyFactoryAddr);

        // Then set registry - should validate they're wired together
        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.RegistrySet(_proxyTemplateRegistryAddr);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setRegistry(_proxyTemplateRegistryAddr);

        assertEq(_proxyDeployer.getRegistry(), _proxyTemplateRegistryAddr);
    }

    function test_setRegistry_revert_notOwner() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _proxyDeployer.setRegistry(_proxyTemplateRegistryAddr);
    }

    function test_setRegistry_revert_zeroAddress() public {
        vm.startPrank(_deployerOwner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _proxyDeployer.setRegistry(address(0));
    }

    function test_setRegistry_revert_invalidRegistry() public {
        address wrongRegistry = makeAddr("wrongRegistry");

        // Set factory first
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setFactory(_proxyFactoryAddr);

        // Try to set wrong registry - should fail because factory is wired to different registry
        vm.startPrank(_deployerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ProxyDeployer__InvalidRegistry.selector, wrongRegistry, _proxyTemplateRegistryAddr
            )
        );
        _proxyDeployer.setRegistry(wrongRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                        DID SET/GET
    //////////////////////////////////////////////////////////////*/

    function test_setDid_and_getDid_success() public {
        string memory did = _ISSUER_DID;
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(did);
        assertEq(_proxyDeployer.getDid(), did);
    }

    function test_setDid_revert_notOwner() public {
        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _proxyDeployer.setDid(_ISSUER_DID);
    }

    function test_setDid_revert_empty() public {
        vm.startPrank(_deployerOwner);
        vm.expectRevert(Errors.EmptyString.selector);
        _proxyDeployer.setDid("");
    }

    /*//////////////////////////////////////////////////////////////
                        GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_getFactory_returnsZeroWhenNotSet() public view {
        assertEq(_proxyDeployer.getFactory(), address(0));
    }

    function test_getRegistry_returnsZeroWhenNotSet() public view {
        assertEq(_proxyDeployer.getRegistry(), address(0));
    }

    function test_namespacedStorageLocation_success_matchesErc7201Formula() public view {
        bytes32 storageLocation = _proxyDeployer.proxyDeployerStorageLocation();

        // solhint-disable-next-line gas-small-strings
        assertEq(storageLocation, _erc7201Location("deuss.deployer.proxydeployer.storage"));
        assertEq(uint256(storageLocation) & 0xff, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ADD TEMPLATE CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_addTemplateConfig_success() public {
        _setupFactoryAndRegistry();
        _addTemplateToEBSIRegistry(_TEMPLATE_NAME, _TEMPLATE_VERSION);

        bytes32 expectedTemplateId =
            IProxyTemplateRegistry(_proxyTemplateRegistryAddr).computeTemplateId(_TEMPLATE_NAME, _TEMPLATE_VERSION);

        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.TemplateConfigAdded(expectedTemplateId, _TEMPLATE_NAME, _TEMPLATE_VERSION);

        vm.startPrank(_deployerOwner);
        bytes32 templateId = _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);

        assertEq(templateId, expectedTemplateId);

        IProxyDeployer.TemplateConfig memory config = _proxyDeployer.getTemplateConfig(templateId);
        assertEq(config.name, _TEMPLATE_NAME);
        assertEq(config.version, _TEMPLATE_VERSION);
        assertTrue(config.isActive);
    }

    function test_addTemplateConfig_revert_notOwner() public {
        _setupFactoryAndRegistry();

        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);
    }

    function test_addTemplateConfig_revert_registryNotSet() public {
        // When registry is not set (address(0)), calling computeTemplateId will naturally revert
        vm.startPrank(_deployerOwner);
        vm.expectRevert();
        _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);
    }

    function test_addTemplateConfig_revert_emptyName() public {
        _setupFactoryAndRegistry();

        vm.startPrank(_deployerOwner);
        vm.expectRevert(Errors.EmptyString.selector);
        _proxyDeployer.addTemplateConfig("", _TEMPLATE_VERSION);
    }

    function test_addTemplateConfig_revert_emptyVersion() public {
        _setupFactoryAndRegistry();

        vm.startPrank(_deployerOwner);
        vm.expectRevert(Errors.EmptyString.selector);
        _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, "");
    }

    function test_addTemplateConfig_revert_alreadyExists() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ProxyDeployer__TemplateAlreadyExists.selector, _TEMPLATE_NAME, _TEMPLATE_VERSION
            )
        );
        _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);
    }

    function test_addTemplateConfig_revert_templateNotActive() public {
        _setupFactoryAndRegistry();

        // Add inactive template to EBSI registry
        IProxyTemplateRegistry.ProxyTemplate memory template = _createProxyTemplate(_TEMPLATE_NAME, _TEMPLATE_VERSION);
        template.isActive = false;

        // Use deployer for EBSI operations
        vm.prank(getEbsiGovernance());
        _proxyTemplateRegistry.addTemplate(template);

        // Deprecate it to make it inactive
        bytes32 templateId = _proxyTemplateRegistry.computeTemplateId(_TEMPLATE_NAME, _TEMPLATE_VERSION);
        vm.prank(getEbsiGovernance());
        _proxyTemplateRegistry.deprecateTemplate(templateId);

        vm.startPrank(_deployerOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotActive.selector, _TEMPLATE_NAME, _TEMPLATE_VERSION)
        );
        _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME, _TEMPLATE_VERSION);
    }

    function test_addTemplateConfig_multipleTemplates() public {
        _setupFactoryAndRegistry();

        // Add first template
        _templateId = _addTestTemplate();

        // Add second template
        _addTemplateToEBSIRegistry(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);
        vm.prank(_deployerOwner);
        _templateId2 = _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);

        // Verify both exist
        IProxyDeployer.TemplateConfig memory config1 = _proxyDeployer.getTemplateConfig(_templateId);
        assertEq(config1.name, _TEMPLATE_NAME);

        IProxyDeployer.TemplateConfig memory config2 = _proxyDeployer.getTemplateConfig(_templateId2);
        assertEq(config2.name, _TEMPLATE_NAME_2);
    }

    /*//////////////////////////////////////////////////////////////
                    DEACTIVATE TEMPLATE CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_deactivateTemplateConfig_success() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.expectEmit(true, false, false, true);
        emit IProxyDeployer.TemplateConfigDeactivated(_templateId, _TEMPLATE_NAME, _TEMPLATE_VERSION);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        assertFalse(_proxyDeployer.isTemplateActive(_templateId));
    }

    function test_deactivateTemplateConfig_revert_notOwner() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.prank(_notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _proxyDeployer.deactivateTemplateConfig(_templateId);
    }

    function test_deactivateTemplateConfig_revert_templateNotFound() public {
        _setupFactoryAndRegistry();
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.startPrank(_deployerOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, nonExistentId));
        _proxyDeployer.deactivateTemplateConfig(nonExistentId);
    }

    function test_deactivateTemplateConfig_revert_alreadyDeactivated() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        vm.startPrank(_deployerOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, _templateId));
        _proxyDeployer.deactivateTemplateConfig(_templateId);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPUTE TEMPLATE ID
    //////////////////////////////////////////////////////////////*/

    function test_computeTemplateId_success() public view {
        bytes32 expectedId = keccak256(abi.encode(_TEMPLATE_NAME, _TEMPLATE_VERSION));
        bytes32 computedId = _proxyDeployer.computeTemplateId(_TEMPLATE_NAME, _TEMPLATE_VERSION);
        assertEq(computedId, expectedId);
    }

    function test_computeTemplateId_matchesEBSI() public {
        _setupFactoryAndRegistry();

        bytes32 ebsiId =
            IProxyTemplateRegistry(_proxyTemplateRegistryAddr).computeTemplateId(_TEMPLATE_NAME, _TEMPLATE_VERSION);
        bytes32 deployerId = _proxyDeployer.computeTemplateId(_TEMPLATE_NAME, _TEMPLATE_VERSION);

        assertEq(deployerId, ebsiId);
    }

    function test_computeTemplateId_differentInputs() public view {
        bytes32 id1 = _proxyDeployer.computeTemplateId("Name1", "1.0.0");
        bytes32 id2 = _proxyDeployer.computeTemplateId("Name2", "1.0.0");
        bytes32 id3 = _proxyDeployer.computeTemplateId("Name1", "2.0.0");

        assertTrue(id1 != id2);
        assertTrue(id1 != id3);
        assertTrue(id2 != id3);
    }

    /*//////////////////////////////////////////////////////////////
                        GET TEMPLATE CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_getTemplateConfig_success() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        IProxyDeployer.TemplateConfig memory config = _proxyDeployer.getTemplateConfig(_templateId);
        assertEq(config.name, _TEMPLATE_NAME);
        assertEq(config.version, _TEMPLATE_VERSION);
        assertTrue(config.isActive);
    }

    function test_getTemplateConfig_revert_notFound() public {
        bytes32 nonExistentId = keccak256("nonexistent");

        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, nonExistentId));
        _proxyDeployer.getTemplateConfig(nonExistentId);
    }

    function test_getTemplateConfig_revert_deactivated() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, _templateId));
        _proxyDeployer.getTemplateConfig(_templateId);
    }

    /*//////////////////////////////////////////////////////////////
                        IS TEMPLATE ACTIVE
    //////////////////////////////////////////////////////////////*/

    function test_isTemplateActive_true() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        assertTrue(_proxyDeployer.isTemplateActive(_templateId));
    }

    function test_isTemplateActive_false_notAdded() public view {
        bytes32 nonExistentId = keccak256("nonexistent");
        assertFalse(_proxyDeployer.isTemplateActive(nonExistentId));
    }

    function test_isTemplateActive_false_deactivated() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        assertFalse(_proxyDeployer.isTemplateActive(_templateId));
    }

    /*//////////////////////////////////////////////////////////////
                        GET DEPLOYMENT INFO
    //////////////////////////////////////////////////////////////*/

    function test_getDeploymentInfo_revert_factoryNotSet() public {
        address someProxy = makeAddr("proxy");

        vm.expectRevert(Errors.ZeroAddress.selector);
        _proxyDeployer.getDeploymentInfo(someProxy);
    }

    function test_getDeploymentInfo_success() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        // Prepare init data for mock contract
        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        // Grant TRUSTED_ISSUER_ROLE to contract
        grantTrustedIssuerRole(address(_proxyDeployer));

        // Deploy a proxy
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy = _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();

        // Get deployment info
        IProxyFactory.DeploymentInfo memory info = _proxyDeployer.getDeploymentInfo(proxy);

        // Verify deployment info
        assertEq(info.templateId, _templateId, "Template ID should match");
        assertEq(info.deployer, address(_proxyDeployer), "Deployer should be proxy");
        assertEq(info.deployerDID, _ISSUER_DID, "Issuer DID should match");
        assertTrue(info.isActive, "Deployment should be active");
        assertTrue(info.deploymentTimestamp > 0, "Timestamp should be set");
        assertEq(info.deploymentTimestamp, block.timestamp, "Timestamp should match block");
    }

    function test_getDeploymentInfo_multipleProxies() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        // Grant TRUSTED_ISSUER_ROLE to contract
        grantTrustedIssuerRole(address(_proxyDeployer));

        // Prepare init data
        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        // Deploy first proxy
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy1 = _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();

        // Add another template
        _addTemplateToEBSIRegistry(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);
        vm.startPrank(_deployerOwner);
        _templateId2 = _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);

        // Deploy second proxy with different template
        string memory issuerDID2 = "did:ebsi:test456";
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(issuerDID2);
        address proxy2 = _proxyDeployer.deployProxy(_templateId2, initData);
        vm.stopPrank();

        // Get deployment info for both proxies
        IProxyFactory.DeploymentInfo memory info1 = _proxyDeployer.getDeploymentInfo(proxy1);
        IProxyFactory.DeploymentInfo memory info2 = _proxyDeployer.getDeploymentInfo(proxy2);

        // Verify first proxy info
        assertEq(info1.templateId, _templateId, "Proxy1 template matches");
        assertEq(info1.deployerDID, _ISSUER_DID, "Proxy 1: Issuer DID should match");
        assertTrue(info1.isActive, "Proxy 1: Should be active");

        // Verify second proxy info
        assertEq(info2.templateId, _templateId2, "Proxy2 template matches");
        assertEq(info2.deployerDID, issuerDID2, "Proxy 2: Issuer DID should match");
        assertTrue(info2.isActive, "Proxy 2: Should be active");

        // Verify they are different deployments
        assertTrue(info1.templateId != info2.templateId, "Template IDs should be different");
        assertTrue(
            keccak256(bytes(info1.deployerDID)) != keccak256(bytes(info2.deployerDID)),
            "Issuer DIDs should be different"
        );
    }

    function test_getDeploymentInfo_nonExistentProxy() public {
        _setupFactoryAndRegistry();

        // Try to get deployment info for a non-existent proxy
        address nonExistentProxy = makeAddr("nonExistentProxy");

        // Should return empty/default deployment info (not revert)
        IProxyFactory.DeploymentInfo memory info = _proxyDeployer.getDeploymentInfo(nonExistentProxy);

        // Verify it returns default values
        assertEq(info.templateId, bytes32(0), "Template ID zero for none");
        assertEq(info.deployer, address(0), "Deployer zero for none");
        assertEq(info.deploymentTimestamp, 0, "Timestamp zero for none");
        assertFalse(info.isActive, "Inactive for none");
        assertEq(info.deployerDID, "", "Issuer DID empty for none");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOY PROXY
    //////////////////////////////////////////////////////////////*/

    function test_deployProxy_success() public {
        _setupFactoryAndRegistry();

        _templateId = _addTestTemplate();

        // Prepare init data for mock contract
        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        // Grant to the contract a TRUSTED_ISSUER_ROLE in the EBSIFactory
        grantTrustedIssuerRole(address(_proxyDeployer));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);

        // Expect event (check all fields except proxy address which we don't know beforehand)
        vm.expectEmit(false, true, false, true);
        emit IProxyDeployer.ProxyDeployedViaTemplate(
            address(0), _templateId, _TEMPLATE_NAME, _TEMPLATE_VERSION, _ISSUER_DID
        );

        address proxy = _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();

        assertTrue(proxy != address(0));

        // Verify the proxy was initialized correctly
        MockInitializable mockProxy = MockInitializable(proxy);
        (address owner, uint256 value, bool initialized) = mockProxy.getData();
        assertEq(owner, testOwner);
        assertEq(value, testValue);
        assertTrue(initialized);
    }

    function test_deployProxy_revert_templateNotFound() public {
        _setupFactoryAndRegistry();
        bytes32 nonExistentId = keccak256("nonexistent");

        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, nonExistentId));
        _proxyDeployer.deployProxy(nonExistentId, initData);
        vm.stopPrank();
    }

    function test_deployProxy_revert_templateDeactivated() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, _templateId));
        _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOY PROXY WITH SALT
    //////////////////////////////////////////////////////////////*/

    function test_deployProxyWithSalt_success() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);
        bytes32 salt = keccak256("test-salt");

        grantTrustedIssuerRole(address(_proxyDeployer));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);

        vm.expectEmit(false, true, false, true);
        emit IProxyDeployer.ProxyDeployedViaTemplate(
            address(0), _templateId, _TEMPLATE_NAME, _TEMPLATE_VERSION, _ISSUER_DID
        );

        address proxy = _proxyDeployer.deployProxyWithSalt(_templateId, initData, salt);
        vm.stopPrank();

        assertTrue(proxy != address(0));

        MockInitializable mockProxy = MockInitializable(proxy);
        (address owner, uint256 value, bool initialized) = mockProxy.getData();
        assertEq(owner, testOwner);
        assertEq(value, testValue);
        assertTrue(initialized);
    }

    function test_deployProxyWithSalt_deterministicAddress() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        address testOwner = makeAddr("testOwner");
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, uint256(42));
        bytes32 salt = keccak256("deterministic-salt");

        grantTrustedIssuerRole(address(_proxyDeployer));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);

        address predicted = _proxyDeployer.computeProxyAddress(_templateId, initData, salt);
        address proxy = _proxyDeployer.deployProxyWithSalt(_templateId, initData, salt);
        vm.stopPrank();

        assertEq(proxy, predicted);
    }

    function test_deployProxyWithSalt_differentSaltsProduceDifferentAddresses() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        address testOwner = makeAddr("testOwner");
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, uint256(42));

        grantTrustedIssuerRole(address(_proxyDeployer));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy1 = _proxyDeployer.deployProxyWithSalt(_templateId, initData, keccak256("salt-1"));
        address proxy2 = _proxyDeployer.deployProxyWithSalt(_templateId, initData, keccak256("salt-2"));
        vm.stopPrank();

        assertTrue(proxy1 != proxy2);
    }

    function test_deployProxyWithSalt_revert_templateNotFound() public {
        _setupFactoryAndRegistry();
        bytes32 nonExistentId = keccak256("nonexistent");

        bytes memory initData =
            abi.encodeWithSelector(MockInitializable.initialize.selector, makeAddr("owner"), uint256(1));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, nonExistentId));
        _proxyDeployer.deployProxyWithSalt(nonExistentId, initData, keccak256("salt"));
        vm.stopPrank();
    }

    function test_computeProxyAddress_matchesDeployedAddress() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        address testOwner = makeAddr("testOwner");
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, uint256(42));
        bytes32 salt = keccak256("compute-salt");

        grantTrustedIssuerRole(address(_proxyDeployer));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);

        address predicted = _proxyDeployer.computeProxyAddress(_templateId, initData, salt);
        address deployed = _proxyDeployer.deployProxyWithSalt(_templateId, initData, salt);
        vm.stopPrank();

        assertEq(predicted, deployed);
    }

    function test_computeProxyAddress_revert_templateNotFound() public {
        _setupFactoryAndRegistry();
        bytes32 nonExistentId = keccak256("nonexistent");

        bytes memory initData =
            abi.encodeWithSelector(MockInitializable.initialize.selector, makeAddr("owner"), uint256(1));

        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, nonExistentId));
        _proxyDeployer.computeProxyAddress(nonExistentId, initData, keccak256("salt"));
    }

    function test_deployProxyWithSalt_revert_templateDeactivated() public {
        _setupFactoryAndRegistry();
        _templateId = _addTestTemplate();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);

        bytes memory initData =
            abi.encodeWithSelector(MockInitializable.initialize.selector, makeAddr("owner"), uint256(1));

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, _templateId));
        _proxyDeployer.deployProxyWithSalt(_templateId, initData, keccak256("salt"));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fullWorkflow_addDeployDeactivate() public {
        // 1. Setup factory and registry
        _setupFactoryAndRegistry();

        // Grant TRUSTED_ISSUER_ROLE to contract
        grantTrustedIssuerRole(address(_proxyDeployer));

        // 2. Add template
        _templateId = _addTestTemplate();
        assertTrue(_proxyDeployer.isTemplateActive(_templateId));

        // 3. Deploy proxy
        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy = _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();
        assertTrue(proxy != address(0));

        // 4. Deactivate template
        vm.startPrank(_deployerOwner);
        _proxyDeployer.deactivateTemplateConfig(_templateId);
        assertFalse(_proxyDeployer.isTemplateActive(_templateId));

        // 5. Cannot deploy with deactivated template
        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProxyDeployer__TemplateNotFound.selector, _templateId));
        _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();
    }

    function test_multipleTemplatesWorkflow() public {
        // 1. Setup factory and registry
        _setupFactoryAndRegistry();

        // Grant TRUSTED_ISSUER_ROLE to contract
        grantTrustedIssuerRole(address(_proxyDeployer));

        // Add multiple templates
        _templateId = _addTestTemplate();

        _addTemplateToEBSIRegistry(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);
        vm.startPrank(_deployerOwner);
        _templateId2 = _proxyDeployer.addTemplateConfig(_TEMPLATE_NAME_2, _TEMPLATE_VERSION_2);

        // Deploy with both templates
        address testOwner = makeAddr("testOwner");
        uint256 testValue = 42;
        bytes memory initData = abi.encodeWithSelector(MockInitializable.initialize.selector, testOwner, testValue);

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy1 = _proxyDeployer.deployProxy(_templateId, initData);
        vm.stopPrank();

        vm.startPrank(_deployerOwner);
        _proxyDeployer.setDid(_ISSUER_DID);
        address proxy2 = _proxyDeployer.deployProxy(_templateId2, initData);
        vm.stopPrank();

        assertTrue(proxy1 != proxy2);
        assertTrue(proxy1 != address(0));
        assertTrue(proxy2 != address(0));
    }
}

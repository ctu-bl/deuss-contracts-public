// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Test.sol";
import {DeploymentFixture} from "./DeploymentFixture.t.sol";

import {PolicyRegistry} from "ebsi/trusted-policies-registry/PolicyRegistry.sol";
import {DidRegistry} from "ebsi/did-registry/DidRegistry.sol";
import {Tir} from "ebsi/tir/Tir.sol";
import {ProxyTemplateRegistry} from "ebsi/contract-factory/ProxyTemplateRegistry.sol";
import {ProxyFactory} from "ebsi/contract-factory/ProxyFactory.sol";
import {IProxyTemplateRegistry} from "ebsi/contract-factory/interfaces/IProxyTemplateRegistry.sol";

error InvalidControlByte();
error InvalidPubKeyLength();

/**
 * @title EBSIFixtures
 * @notice Core EBSI Smart Contracts testing fixtures
 * @dev Provides complete EBSI infrastructure for testing
 * @dev Inherits from DeploymentFixture to get full suite deployment, then extracts EBSI contracts
 */
contract EBSIFixtures is DeploymentFixture {
    // Test user structure for DID testing
    struct User {
        address addr;
        bytes publicKey;
        uint256 privateKey;
    }

    // Test users mapping
    mapping(string name => User user) internal _testUsers;

    // Governance (use _governance from DeploymentFixture)

    // Core EBSI Contracts (for convenience - extracted from suite)
    PolicyRegistry internal _policyRegistry;
    DidRegistry internal _didRegistry;
    Tir internal _tir;

    // Contract Factory
    ProxyTemplateRegistry internal _proxyTemplateRegistry;
    ProxyFactory internal _proxyFactory;

    // Addresses (extracted from suite)
    address internal _policyRegistryAddr;
    address internal _didRegistryAddr;
    address internal _tirAddr;
    address internal _proxyTemplateRegistryAddr;
    address internal _proxyFactoryAddr;

    // EBSI-specific constants
    string internal constant _EBSI_DID_PREFIX = "did:ebsi:";

    function setUp() public virtual override {
        console2.log("EBSI Fixture: extract suite");

        // Deploy full suite (includes EBSI + all DEUSS contracts)
        super.setUp();

        // Extract EBSI contracts from suite (deployed by DeployDEUSSSuite)
        _policyRegistryAddr = _suite.ebsi.policyRegistry;
        _didRegistryAddr = _suite.ebsi.didRegistry;
        _proxyTemplateRegistryAddr = _suite.ebsi.proxyTemplateRegistry;
        _proxyFactoryAddr = _suite.ebsi.proxyFactory;
        _tirAddr = _suite.ebsi.tir;

        // Bind contract instances
        _policyRegistry = PolicyRegistry(_policyRegistryAddr);
        _didRegistry = DidRegistry(_didRegistryAddr);
        _proxyTemplateRegistry = ProxyTemplateRegistry(_proxyTemplateRegistryAddr);
        _proxyFactory = ProxyFactory(_proxyFactoryAddr);
        _tir = Tir(_tirAddr);

        // Labels
        vm.label(_policyRegistryAddr, "EBSI PolicyRegistry");
        vm.label(_didRegistryAddr, "EBSI DidRegistry");
        vm.label(_tirAddr, "EBSI Tir");
        vm.label(_proxyTemplateRegistryAddr, "EBSI ProxyTemplateRegistry");
        vm.label(_proxyFactoryAddr, "EBSI ProxyFactory");

        console2.log("EBSI contracts extracted");
        console2.log("PolicyRegistry:", _policyRegistryAddr);
        console2.log("DidRegistry:", _didRegistryAddr);
        console2.log("Tir:", _tirAddr);
        console2.log("ProxyTemplateRegistry:", _proxyTemplateRegistryAddr);
        console2.log("ProxyFactory:", _proxyFactoryAddr);

        // Setup test users for DID testing
        _setupTestUsers();
    }

    /**
     * @notice Setup test users with public keys and calculated addresses
     * @dev Creates alice, bob, and charlie users with proper cryptographic relationships
     */
    function _setupTestUsers() internal {
        // Alice: 65-byte public key (with 0x04 prefix)
        bytes memory alicePublicKey =
            hex"0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8";
        address aliceAddr = address(uint160(uint256(keccak256(_sanitizePublicKey(alicePublicKey)))));

        _testUsers["alice"] = User({
            addr: aliceAddr,
            publicKey: alicePublicKey,
            privateKey: 0x0000000000000000000000000000000000000000000000000000000000000001
        });

        // Bob: 64-byte public key (already sanitized)
        bytes memory bobPublicKey =
            hex"04c6047f9441ed7d6d3045406e95c07cd85a46e83744cafc81b5f1b92390a05c6b6b6eedd6b4891c1b5c9b36d6bba2eeb7b6a1883e43fce9c8f8f47b2a77a1b1";
        address bobAddr = address(uint160(uint256(keccak256(_sanitizePublicKey(bobPublicKey)))));

        _testUsers["bob"] = User({
            addr: bobAddr,
            publicKey: bobPublicKey,
            privateKey: 0x0000000000000000000000000000000000000000000000000000000000000002
        });

        // Charlie: 64-byte public key (already sanitized)
        bytes memory charliePublicKey =
            hex"04f9308a019258c3106ac18c0d6d950a0e7a5265b0b80a01e6fce1ce048a54ed7c0240f8a463a75ec2c53a041b98e18d21c0b6861c1b6855ce1e7be0a6e210c0";
        address charlieAddr = address(uint160(uint256(keccak256(_sanitizePublicKey(charliePublicKey)))));

        _testUsers["charlie"] = User({
            addr: charlieAddr,
            publicKey: charliePublicKey,
            privateKey: 0x0000000000000000000000000000000000000000000000000000000000000003
        });
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // Core EBSI Contract Getters
    function getPolicyRegistry() public view returns (PolicyRegistry) {
        return _policyRegistry;
    }

    function getDidRegistry() public view returns (DidRegistry) {
        return _didRegistry;
    }

    function getTir() public view returns (Tir) {
        return _tir;
    }

    // Contract Factory Getters
    function getProxyTemplateRegistry() public view returns (ProxyTemplateRegistry) {
        return _proxyTemplateRegistry;
    }

    function getProxyFactory() public view returns (ProxyFactory) {
        return _proxyFactory;
    }

    // Address Getters
    function getPolicyRegistryAddr() public view returns (address) {
        return _policyRegistryAddr;
    }

    function getDidRegistryAddr() public view returns (address) {
        return _didRegistryAddr;
    }

    function getTirAddr() public view returns (address) {
        return _tirAddr;
    }

    function getProxyTemplateRegistryAddr() public view returns (address) {
        return _proxyTemplateRegistryAddr;
    }

    function getProxyFactoryAddr() public view returns (address) {
        return _proxyFactoryAddr;
    }

    function getEbsiGovernance() public view returns (address) {
        // @dev EBSI contracts are owned by deployer, not governance
        return _deployer;
    }

    function getTestUser(string memory name) public view returns (User memory) {
        return _testUsers[name];
    }

    /*//////////////////////////////////////////////////////////////
                             FACTORY HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Helper to create a template struct for testing
     * @param name Template name
     * @param version Template version
     * @param beaconAddress Beacon contract address
     * @param initSelector Initialization function selector
     * @return ProxyTemplate struct
     */
    function createTemplate(string memory name, string memory version, address beaconAddress, bytes4 initSelector)
        public
        pure
        returns (IProxyTemplateRegistry.ProxyTemplate memory)
    {
        console2.log("--- Creating template ---");
        return IProxyTemplateRegistry.ProxyTemplate({
            name: name,
            version: version,
            beaconAddress: beaconAddress,
            repoURI: "repo://ebsi/contracts",
            auditURI: "audit://report",
            contractHash: keccak256("MOCK_CONTRACT_HASH"),
            initSelector: initSelector,
            storageLayoutHash: keccak256("MOCK_STORAGE_LAYOUT"),
            isActive: true
        });
    }

    /**
     * @notice Helper to register a template in the registry
     * @param template The template to register
     * @dev Uses _deployer because EBSI contracts are owned by deployer, not governance
     */
    function registerTemplate(IProxyTemplateRegistry.ProxyTemplate memory template) public {
        console2.log("Register template");
        vm.prank(_deployer);
        _proxyTemplateRegistry.addTemplate(template);
    }

    /**
     * @notice Helper to grant TRUSTED_ISSUER_ROLE to an address
     * @param issuer Address to grant the role to
     * @dev Uses _deployer because EBSI contracts are owned by deployer, not governance
     */
    function grantTrustedIssuerRole(address issuer) public {
        console2.log("--- grantTrustedIssuerRole ---");
        vm.startPrank(_deployer);
        _proxyFactory.grantRole(_proxyFactory.TRUSTED_ISSUER_ROLE(), issuer);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             DID REGISTRY HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Helper to insert a DID document with provided public key and DID
     * @param did The DID identifier to insert
     * @param publicKey The public key to use (64 or 65 bytes, with or without 0x04 prefix)
     * @return bool Success status
     * @dev Simple wrapper around DidRegistry.insertDidDocument with default test values
     */
    function insertDidDocument(string memory did, bytes memory publicKey) public returns (bool) {
        // Default test values based on TypeScript tests
        // solhint-disable-next-line quotes
        string memory baseDocument = "{\"context\":\"did\"}";
        string memory vMethodId = "vm1";

        bool isSecp256k1 = true;
        uint256 notBefore = block.timestamp > 0 ? block.timestamp - 1 : 0; // Start just before current time
        uint256 notAfter = block.timestamp + 3600; // Valid for 1 hour from now

        // Calculate the address that will be derived from this public key
        // MUST use the same logic as DidRegistry.getAddress() function (including sanitization)
        address keyAddress = address(uint160(uint256(keccak256(_sanitizePublicKey(publicKey)))));

        // Call the actual insertDidDocument function on DidRegistry using the derived address
        vm.prank(keyAddress);
        return _didRegistry.insertDidDocument(did, baseDocument, vMethodId, publicKey, isSecp256k1, notBefore, notAfter);
    }

    /**
     * @notice Sanitize public key by removing 0x04 prefix if present (matches DidRegistry logic)
     * @param publicKey The public key to sanitize
     * @return bytes The sanitized public key
     */
    function _sanitizePublicKey(bytes memory publicKey) internal pure returns (bytes memory) {
        if (publicKey.length == 65) {
            if (publicKey[0] != 0x04) {
                revert InvalidControlByte();
            }
            // Remove the 0x04 prefix
            bytes memory publicKeyWithoutPrefix = new bytes(publicKey.length - 1);
            for (uint256 i = 1; i < publicKey.length; ++i) {
                publicKeyWithoutPrefix[i - 1] = publicKey[i];
            }
            return publicKeyWithoutPrefix;
        } else if (publicKey.length == 64) {
            return publicKey;
        } else {
            revert InvalidPubKeyLength();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             DID REGISTRY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test DID Registry functionality with public key to address relationships
     * @dev Demonstrates the complete DID workflow: insert, check controllers, delegate control
     */
    function test_didRegistrySetup_insertAndCheckController() public {
        // Test DIDs
        string memory did1 = "did:ebsi:alice123";
        string memory did2 = "did:ebsi:bob456";
        string memory did3 = "did:ebsi:charlie789";

        // Insert DID documents using the wrapper helper
        assertTrue(insertDidDocument(did1, _testUsers["alice"].publicKey));
        assertTrue(insertDidDocument(did2, _testUsers["bob"].publicKey));
        assertTrue(insertDidDocument(did3, _testUsers["charlie"].publicKey));

        // Verify that checkController works correctly
        // Alice should be controller of her own DID
        assertTrue(getDidRegistry().checkController(did1, _testUsers["alice"].addr));

        // Alice should NOT be controller of Bob's DID
        assertFalse(getDidRegistry().checkController(did2, _testUsers["alice"].addr));

        // Bob should be controller of his own DID
        assertTrue(getDidRegistry().checkController(did2, _testUsers["bob"].addr));

        // Bob should NOT be controller of Charlie's DID
        assertFalse(getDidRegistry().checkController(did3, _testUsers["bob"].addr));

        // Charlie should be controller of his own DID
        assertTrue(getDidRegistry().checkController(did3, _testUsers["charlie"].addr));

        // Random address should not be controller of any DID
        address randomAddr = makeAddr("random");
        assertFalse(getDidRegistry().checkController(did1, randomAddr));
        assertFalse(getDidRegistry().checkController(did2, randomAddr));
        assertFalse(getDidRegistry().checkController(did3, randomAddr));

        // Test adding controller relationships
        // Alice (the owner of did1) adds Bob's DID as a controller
        vm.prank(_testUsers["alice"].addr);
        getDidRegistry().addController(did1, did2); // Bob becomes controller of Alice's DID

        // Now Bob should be controller of both his own DID and Alice's DID
        assertTrue(getDidRegistry().checkController(did1, _testUsers["bob"].addr));
        assertTrue(getDidRegistry().checkController(did2, _testUsers["bob"].addr));

        // Alice should still be controller of her own DID (original controller remains)
        assertTrue(getDidRegistry().checkController(did1, _testUsers["alice"].addr));

        // But Alice should still NOT be controller of Bob's DID
        assertFalse(getDidRegistry().checkController(did2, _testUsers["alice"].addr));
    }
}

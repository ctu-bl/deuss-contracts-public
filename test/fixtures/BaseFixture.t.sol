// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {console2} from "forge-std/Test.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {DeploymentFixture} from "./DeploymentFixture.t.sol";
// contracts
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
// structs
import {BondInput} from "src/registry/BondStructs.sol";
import {Deal, Interest, InterestDiscoveryState, Offer} from "src/marketplace/MarketStructs.sol";
import {IMarketplaceLens} from "src/marketplace/interfaces/IMarketplaceLens.sol";

// solhint-disable avoid-low-level-calls, gas-custom-errors
contract BaseFixture is DeploymentFixture {
    // Structs
    BondInput internal _bondFT;

    // Bond Token ID
    uint256 internal _bondFTId;

    // Wallets
    address internal _notGov;
    address internal _notOwner;

    // Registries
    BondRegistry internal _br;
    EntityRegistry internal _er;
    IWalletFactory internal _wf;

    // Registries addresses
    address internal _brAddr;
    address internal _erAddr;
    address internal _wfAddr;

    // Beacon addresses
    UpgradeableBeacon internal _brBeacon;
    UpgradeableBeacon internal _erBeacon;

    // token
    address internal _tokenAddr;
    UpgradeableBeacon internal _tokenBeacon;

    // Escrow manager
    address internal _escrowManager;
    address internal _marketplaceLens;

    // company wallet(issuer)
    address internal _cwAddr;

    // company entity id nonce
    uint256 internal _entityNonce;

    // entity registry admin
    address internal _erAdmin;

    // time controller
    address payable internal _timelockController;

    // timelock controller actors
    address internal _proposer;
    address internal _executor;

    function setUp() public virtual override {
        super.setUp();

        _notOwner = makeAddr("notOwner");
        _notGov = makeAddr("notGovernance");
        _proposer = makeAddr("proposer");
        _executor = makeAddr("executor");

        _brAddr = _suite.registries.bondRegistry;
        _erAddr = _suite.registries.entityRegistry;
        _wfAddr = _suite.registries.walletFactory;
        _brBeacon = UpgradeableBeacon(_suite.registries.bondRegistryBeacon);
        _erBeacon = UpgradeableBeacon(_suite.registries.entityRegistryBeacon);
        _tokenAddr = _suite.multiToken.deussToken;
        _tokenBeacon = UpgradeableBeacon(_suite.multiToken.deussTokenBeacon);
        _escrowManager = _suite.core.escrowManager;
        _marketplaceLens = _suite.utils.marketplaceLens;
        _timelockController = payable(_suite.governance.timelockController);

        console2.log("Fixture - setting up");

        // add labels
        vm.label(_deployer, "Deployer");
        vm.label(_proposer, "TimelockControllerProposer");
        vm.label(_executor, "TimelockControllerExecutor");
        vm.label(_brAddr, "BondRegistry");
        vm.label(_erAddr, "EntityRegistry");
        vm.label(_wfAddr, "WalletFactory");
        vm.label(_escrowManager, "EscrowManager");
        vm.label(_marketplaceLens, "MarketplaceLens");
        vm.label(_timelockController, "TimelockController");

        _wf = IWalletFactory(_wfAddr);

        /*//////////////////////////////////////////////////////////////
                            ENTITY REGISTRY SETUP
        //////////////////////////////////////////////////////////////*/

        // Create addresses using shared utilities
        _erAdmin = _admin;

        // registries initialization
        _er = EntityRegistry(_erAddr);

        vm.startPrank(_erAdmin);
        _er.defineEntityType(COMPANY_ENTITY, bytes32("COMPANY"), 0);
        _er.defineEntityType(NATURAL_PERSON_ENTITY, bytes32("NATURAL_PERSON"), 0);
        _er.defineEntityType(AGENT_ENTITY, bytes32("AGENT"), 0);
        _er.defineEntityType(DEUSS_GOVERNANCE_ENTITY, bytes32("DEUSS_GOVERNANCE_ENTITY"), 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create multiple addresses with a common prefix
     * @param prefix The prefix for the address names
     * @param count Number of addresses to create
     * @return addresses Array of created addresses
     */
    function _createAddresses(string memory prefix, uint256 count) internal returns (address[] memory addresses) {
        addresses = new address[](count);
        for (uint256 i; i < count; ++i) {
            addresses[i] = makeAddr(string(abi.encodePacked(prefix, _toString(i + 1))));
        }
    }

    /**
     * @notice Create a single address with a name
     * @param name The name for the address
     * @return addr The created address
     */
    function _createAddress(string memory name) internal returns (address addr) {
        return makeAddr(name);
    }

    /**
     * @notice Label multiple addresses with their names
     * @param addresses Array of addresses to label
     * @param names Array of names for the addresses
     */
    function _labelAddresses(address[] memory addresses, string[] memory names) internal {
        require(addresses.length == names.length, "Arrays length mismatch");
        for (uint256 i; i < addresses.length; ++i) {
            vm.label(addresses[i], names[i]);
        }
    }

    /**
     * @notice Label a single address
     * @param addr The address to label
     * @param name The name for the address
     */
    function _labelAddress(address addr, string memory name) internal {
        vm.label(addr, name);
    }

    /**
     * @notice Convert uint256 to string for dynamic naming
     * @param value Number to convert
     * @return str String representation
     */
    function _toString(uint256 value) internal pure returns (string memory str) {
        return LibString.toString(value);
    }

    function _getOffer(uint256 offerId) internal view returns (Offer memory offer) {
        return IMarketplaceLens(_marketplaceLens).getOffer(offerId);
    }

    function _getAllowedBuyers(uint256 offerId) internal view returns (address[] memory allowedBuyers) {
        return IMarketplaceLens(_marketplaceLens).getAllowedBuyers(offerId);
    }

    function _getDeal(uint256 dealId) internal view returns (Deal memory deal) {
        return IMarketplaceLens(_marketplaceLens).getDeal(dealId);
    }

    function _getInterest(uint256 interestId) internal view returns (Interest memory interest) {
        return IMarketplaceLens(_marketplaceLens).getInterest(interestId);
    }

    function _getInterestIdsByOfferId(uint256 offerId) internal view returns (uint256[] memory interestIds) {
        return IMarketplaceLens(_marketplaceLens).getInterestIdsByOfferId(offerId);
    }

    function _getInterestDiscoveryState(uint256 offerId) internal view returns (InterestDiscoveryState memory state) {
        return IMarketplaceLens(_marketplaceLens).getInterestDiscoveryState(offerId);
    }

    function _isOfferCancelled(uint256 offerId) internal view returns (bool cancelled) {
        return IMarketplaceLens(_marketplaceLens).isOfferCancelled(offerId);
    }

    function _isOfferFrozen(uint256 offerId) internal view returns (bool frozen) {
        return IMarketplaceLens(_marketplaceLens).isOfferFrozen(offerId);
    }

    function _isDealFrozen(uint256 dealId) internal view returns (bool frozen) {
        return IMarketplaceLens(_marketplaceLens).isDealFrozen(dealId);
    }

    function _getEscrowIdByOfferId(uint256 offerId) internal view returns (uint256 escrowId) {
        return IMarketplaceLens(_marketplaceLens).getEscrowIdByOfferId(offerId);
    }

    function _createWallet(bytes32 entityId, bytes32 walletType, bytes memory initData, address pranker)
        internal
        returns (address wallet)
    {
        IWalletFactory.CreateWalletParams memory params =
            IWalletFactory.CreateWalletParams({entityId: entityId, walletType: walletType, initData: initData});
        vm.prank(pranker);
        wallet = _wf.createWallet(params);
    }

    function _createCompanyWallet(bytes32 entityId, address owner, address pranker) internal returns (address wallet) {
        return _createWallet(
            entityId,
            COMPANY_WALLET_TYPE,
            abi.encodeCall(ICompanyWallet.initialize, (owner, _suite.registries.walletPolicyRegistry)),
            pranker
        );
    }

    function _requestAccountRegistration(address requester, address account, bytes32 entityId, uint256 roleFlags)
        internal
    {
        vm.prank(requester);
        _er.requestAccountRegistration(account, entityId, roleFlags);
    }

    function _acceptAccountRegistration(address account, bytes32 entityId) internal {
        vm.prank(account);
        _er.acceptAccountRegistration(entityId);
    }

    function _acceptWalletAccountRegistration(address wallet, bytes32 entityId, address owner) internal {
        vm.prank(owner);
        ICompanyWallet(wallet)
            .execute(_erAddr, 0, abi.encodeCall(IEntityRegistry.acceptAccountRegistration, (entityId)));
    }

    function _requestAndAcceptWalletAccountRegistration(
        address requester,
        address wallet,
        bytes32 entityId,
        address owner,
        uint256 roleFlags
    ) internal {
        _requestAccountRegistration(requester, wallet, entityId, roleFlags);
        _acceptWalletAccountRegistration(wallet, entityId, owner);
    }

    function _createAndRegisterEntityWalletForCompany(address admin, address owner)
        internal
        returns (address companyWallet, bytes32 entityId)
    {
        return _createAndRegisterEntityWalletForCompany(admin, owner, ROLE_FLAGS_EMPTY);
    }

    function _createAndRegisterEntityWalletForCompany(address admin, address owner, uint256 roleFlags)
        internal
        returns (address companyWallet, bytes32 entityId)
    {
        entityId = _registerEntity(admin, COMPANY_ENTITY);
        vm.prank(admin);
        _er.setEntityManager(entityId, admin, true);
        companyWallet = _createCompanyWallet(entityId, owner, admin);
        vm.prank(admin);
        _er.registerAccount(companyWallet, entityId, roleFlags);
    }

    function _createAndRegisterEntityWallet(address admin, address owner) internal returns (address, bytes32 entityId) {
        entityId = _registerEntity(admin, COMPANY_ENTITY);
        vm.prank(admin);
        _er.registerAccount(owner, entityId, ROLE_FLAGS_EMPTY);
    }

    function _createAndRegisterGovEntityWallet(address admin, address owner)
        internal
        returns (address, bytes32 entityId)
    {
        entityId = _registerEntity(admin, DEUSS_GOVERNANCE_ENTITY);
        vm.prank(admin);
        _er.registerAccount(owner, entityId, ROLE_FLAGS_EMPTY);
    }

    function _registerEntity(address admin, uint256 typeId) internal returns (bytes32 entityId) {
        entityId = keccak256(abi.encodePacked(admin, _entityNonce));
        ++_entityNonce;
        vm.prank(admin);
        _er.registerEntity(entityId, typeId, EMPTY_METADATA_REF);
    }
}

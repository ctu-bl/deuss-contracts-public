// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable gas-small-strings */

import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {Account as RegistryAccount} from "src/registry/EntityStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
import {MockExecutionTarget} from "test/mocks/MockContracts.sol";

/**
 * @title EntityOnboardingFlowsE2ETest
 * @notice E2E coverage for the three onboarding patterns
 */
contract EntityOnboardingFlowsE2ETest is CompanyFixture {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _BROKER_ENTITY_TYPE = 4;
    uint256 private constant _CUSTODIAN_ENTITY_TYPE = 99;
    bytes32 private constant _CUSTODIAN_ENTITY_NAME = bytes32("COMPANY_ISSUER_CUSTODIAN");
    uint256 private constant _ROLE_OPERATE = 1;

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    PolicyRegistry internal _policyRegistry;
    MockExecutionTarget internal _mockTarget;

    /*//////////////////////////////////////////////////////////////
                               SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        _policyRegistry = PolicyRegistry(_suite.registries.walletPolicyRegistry);
        _mockTarget = new MockExecutionTarget();
    }

    function _acceptRegistrationThroughWalletOwner(address ownerWallet, address targetWallet, bytes32 entityId)
        internal
    {
        bytes memory acceptRegistrationData = abi.encodeCall(IEntityRegistry.acceptAccountRegistration, (entityId));
        ICompanyWallet(ownerWallet)
            .execute(targetWallet, 0, abi.encodeCall(ICompanyWallet.execute, (address(_er), 0, acceptRegistrationData)));
    }

    /*//////////////////////////////////////////////////////////////
          SCENARIO 1 — SELF-MANAGED COMPANY (authority == manager)
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. ADMIN defines a BROKER entity type.
     *   2. ADMIN calls registerEntity v2 using the same EOA address as both
     *      authority and the sole manager — the company fully self-manages.
     *   3. The company EOA (acting as manager) creates a CompanyWallet for a
     *      retail investor via WalletFactory.
     *   4. The company EOA (acting as manager) requests wallet registration,
     *      and the wallet accepts through its owner.
     *   5. A non-owner delegate can execute only after the wallet owner grants
     *      matching PolicyRegistry user and operation roles.
     *   6. The delegate is still blocked from ungranted targets, and revocation
     *      blocks the previously allowed operation.
     *   7. The company EOA (acting as authority) adds a second manager.
     *   8. The new manager can also create wallets and request registration.
     *
     * Purpose: prove that the v2 registration path supports the self-managed
     *          broker model where a single company address carries both roles,
     *          and that wallets onboarded through that path use PolicyRegistry
     *          for delegated execution.
     */
    function test_e2e_scenario1_selfManagedCompany_authorityEqualsManager() public {
        vm.prank(_erAdmin);
        _er.defineEntityType(_BROKER_ENTITY_TYPE, bytes32("BROKER"), 0);

        address companyEOA = makeAddr("company-self-managed");
        bytes32 entityId = keccak256(abi.encodePacked("self-managed", companyEOA));

        address[] memory managers = new address[](1);
        managers[0] = companyEOA; // authority == manager

        vm.prank(_erAdmin);
        _er.registerEntity(entityId, _BROKER_ENTITY_TYPE, "ipfs://broker-meta", companyEOA, managers);

        assertEq(_er.getEntityAuthority(entityId), companyEOA, "authority mismatch");
        assertTrue(_er.isEntityManager(entityId, companyEOA), "company EOA should be manager");

        // Company EOA (as manager) creates a wallet for a retail investor
        address retailInvestor = makeAddr("retail-investor");
        address walletA = _createCompanyWallet(entityId, retailInvestor, companyEOA);

        // Company EOA (as manager) requests registration; wallet owner accepts.
        _requestAndAcceptWalletAccountRegistration(companyEOA, walletA, entityId, retailInvestor, _ROLE_OPERATE);

        RegistryAccount memory accountA = _er.getAccount(walletA);
        assertEq(accountA.entityId, entityId, "account entity mismatch");
        assertEq(accountA.roleFlags, _ROLE_OPERATE, "role flags mismatch");

        address[] memory accounts = _er.getEntityAccounts(entityId);
        assertEq(accounts.length, 1, "expected 1 registered account");
        assertEq(accounts[0], walletA, "unexpected account address");

        address delegate = makeAddr("self-managed-delegate");
        bytes memory operateData = abi.encodeCall(MockExecutionTarget.operate, ());

        vm.prank(delegate);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(walletA).execute(address(_mockTarget), 0, operateData);
        assertFalse(_mockTarget.invoked(), "target invoked before policy grant");

        vm.startPrank(retailInvestor);
        _policyRegistry.grantUserRoles(walletA, delegate, _ROLE_OPERATE);
        _policyRegistry.grantOperationRoles(
            walletA, address(_mockTarget), MockExecutionTarget.operate.selector, _ROLE_OPERATE
        );
        vm.stopPrank();

        assertTrue(
            _policyRegistry.canExecute(walletA, delegate, address(_mockTarget), 0, operateData),
            "canExecute false after grant"
        );

        vm.prank(delegate);
        ICompanyWallet(walletA).execute(address(_mockTarget), 0, operateData);
        assertTrue(_mockTarget.invoked(), "target not invoked after policy grant");

        MockExecutionTarget ungrantedTarget = new MockExecutionTarget();
        vm.prank(delegate);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(walletA).execute(address(ungrantedTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertFalse(ungrantedTarget.invoked(), "ungranted target invoked");

        vm.prank(retailInvestor);
        _policyRegistry.revokeUserRoles(walletA, delegate, _ROLE_OPERATE);

        assertFalse(
            _policyRegistry.canExecute(walletA, delegate, address(_mockTarget), 0, operateData),
            "canExecute true after revoke"
        );

        MockExecutionTarget revokedTarget = new MockExecutionTarget();
        vm.prank(delegate);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(walletA).execute(address(revokedTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertFalse(revokedTarget.invoked(), "target invoked after revoke");

        // Company EOA (as authority) delegates to a second manager
        address secondManager = makeAddr("second-manager");
        vm.prank(companyEOA);
        _er.setEntityManager(entityId, secondManager, true);
        assertTrue(_er.isEntityManager(entityId, secondManager), "second manager not registered");

        // Second manager can create and request registration for additional wallets.
        address retailInvestor2 = makeAddr("retail-investor-2");
        address walletB = _createCompanyWallet(entityId, retailInvestor2, secondManager);
        _requestAndAcceptWalletAccountRegistration(secondManager, walletB, entityId, retailInvestor2, _ROLE_OPERATE);

        address[] memory updatedAccounts = _er.getEntityAccounts(entityId);
        assertEq(updatedAccounts.length, 2, "expected 2 registered accounts");
    }

    /*//////////////////////////////////////////////////////////////
      SCENARIO 2B-i — CUSTODIAN ENTITY, COMPANY REP AS WALLET OWNER
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. ADMIN defines and registers a COMPANY_ISSUER_CUSTODIAN entity with a
     *      dedicated authority and manager (DEUSS backend EOA).
     *   2. The custodian manager creates a CompanyWallet for Company-A and sets
     *      the company rep's EOA as the wallet owner.
     *   3. The custodian manager requests wallet registration, and the wallet accepts.
     *   4. The company rep (wallet owner) can execute calls directly — the owner
     *      path in CompanyWallet bypasses PolicyRegistry completely.
     *   5. Negative check: a random EOA that is neither owner nor policy-authorised
     *      cannot execute calls through the wallet.
     *
     * Purpose: prove the custodian-managed onboarding path where the company
     *          receives full direct ownership of its wallet.
     */
    function test_e2e_scenario2B_i_custodianEntity_companyRepAsOwner() public {
        (bytes32 custodianEntityId,, address custodianManager) = _setupCustodianEntity();

        // Custodian manager creates a sub-company wallet; company rep is the owner
        address companyRepEOA = makeAddr("company-a-rep");
        address subCompanyWallet = _createCompanyWallet(custodianEntityId, companyRepEOA, custodianManager);

        // Request registration under the custodian entity; company rep accepts as wallet owner.
        _requestAndAcceptWalletAccountRegistration(
            custodianManager, subCompanyWallet, custodianEntityId, companyRepEOA, _ROLE_OPERATE
        );

        assertEq(ICompanyWallet(subCompanyWallet).owner(), companyRepEOA, "wrong wallet owner");
        assertTrue(_er.isAccountEnabled(subCompanyWallet), "account not enabled");

        RegistryAccount memory account = _er.getAccount(subCompanyWallet);
        assertEq(account.entityId, custodianEntityId, "acct entity mismatch");

        // Company rep (owner) can execute calls directly — no policy lookup
        vm.prank(companyRepEOA);
        ICompanyWallet(subCompanyWallet)
            .execute(address(_mockTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertTrue(_mockTarget.invoked(), "mock target was not invoked");

        // Negative check: a random EOA cannot execute
        MockExecutionTarget anotherTarget = new MockExecutionTarget();
        address randomEOA = makeAddr("random-eoa");
        vm.prank(randomEOA);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(subCompanyWallet)
            .execute(address(anotherTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertFalse(anotherTarget.invoked(), "target unexpectedly invoked");
    }

    /*//////////////////////////////////////////////////////////////
     SCENARIO 2B-ii — CUSTODIAN ENTITY, CUSTODIAN AS OWNER, POLICY DELEGATION
    //////////////////////////////////////////////////////////////*/

    /**
     * Scenario:
     *   1. ADMIN sets up a COMPANY_ISSUER_CUSTODIAN entity.
     *   2. Custodian manager creates the custodian's own CompanyWallet (owned by
     *      custodianAuthority).
     *   3. Custodian manager creates a sub-company wallet where the owner is the
     *      custodian's CompanyWallet — not the company rep.  The sub-company wallet
     *      accepts registration under the custodian entity.
     *   4. Negative check: company rep cannot execute without any policy grant.
     *   5. CustodianWallet owner (custodianAuthority) grants PolicyRegistry roles:
     *      - user-roles for company rep on the sub-company wallet
     *      - operation-roles for the target contract + selector
     *   6. PolicyRegistry.canExecute() confirms authorisation.
     *   7. Company rep successfully executes via the sub-company wallet.
     *   8. Revoking user-roles immediately blocks further execution.
     *
     * Purpose: prove the full custodian-as-owner delegation chain — including both
     *          the policy setup path and the immediate effect of policy revocation.
     */
    function test_e2e_scenario2B_ii_custodianEntity_custodianAsOwner_policyDelegation() public {
        (bytes32 custodianEntityId, address custodianAuthority, address custodianManager) = _setupCustodianEntity();

        address custodianWallet = _createCompanyWallet(custodianEntityId, custodianAuthority, custodianManager);
        _requestAndAcceptWalletAccountRegistration(
            custodianManager, custodianWallet, custodianEntityId, custodianAuthority, 0
        );

        // Create sub-company wallet — owned by the custodian wallet, not the company rep
        address companyRepEOA = makeAddr("company-b-rep");
        address subCompanyWallet = _createCompanyWallet(custodianEntityId, custodianWallet, custodianManager);
        vm.prank(custodianManager);
        _er.requestAccountRegistration(subCompanyWallet, custodianEntityId, _ROLE_OPERATE);

        vm.prank(custodianAuthority);
        _acceptRegistrationThroughWalletOwner(custodianWallet, subCompanyWallet, custodianEntityId);

        assertEq(ICompanyWallet(subCompanyWallet).owner(), custodianWallet, "owner should be custodian wallet");
        assertTrue(_er.isAccountEnabled(subCompanyWallet), "sub-company wallet not enabled");

        // Negative check: company rep has no access yet
        vm.prank(companyRepEOA);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(subCompanyWallet)
            .execute(address(_mockTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertFalse(_mockTarget.invoked(), "target invoked w/o policy");

        // Custodian authority grants permissions through the custodian wallet, which owns the sub-company wallet.
        bytes4 operateSelector = MockExecutionTarget.operate.selector;
        vm.startPrank(custodianAuthority);
        ICompanyWallet(custodianWallet)
            .execute(
                address(_policyRegistry),
                0,
                abi.encodeWithSignature(
                    "grantUserRoles(address,address,uint256)", subCompanyWallet, companyRepEOA, _ROLE_OPERATE
                )
            );
        ICompanyWallet(custodianWallet)
            .execute(
                address(_policyRegistry),
                0,
                abi.encodeWithSignature(
                    "grantOperationRoles(address,address,bytes4,uint256)",
                    subCompanyWallet,
                    address(_mockTarget),
                    operateSelector,
                    _ROLE_OPERATE
                )
            );
        vm.stopPrank();

        assertEq(_policyRegistry.getUserRoles(subCompanyWallet, companyRepEOA), _ROLE_OPERATE, "user roles not set");
        assertTrue(
            _policyRegistry.canExecute(
                subCompanyWallet,
                companyRepEOA,
                address(_mockTarget),
                0,
                abi.encodeCall(MockExecutionTarget.operate, ())
            ),
            "canExecute false post-grant"
        );

        // Company rep can now execute via the sub-company wallet
        vm.prank(companyRepEOA);
        ICompanyWallet(subCompanyWallet)
            .execute(address(_mockTarget), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertTrue(_mockTarget.invoked(), "target not invoked post-grant");

        // Revoke user-roles through the custodian wallet - execution must be blocked immediately
        vm.prank(custodianAuthority);
        ICompanyWallet(custodianWallet)
            .execute(
                address(_policyRegistry),
                0,
                abi.encodeWithSignature(
                    "revokeUserRoles(address,address,uint256)", subCompanyWallet, companyRepEOA, _ROLE_OPERATE
                )
            );

        assertEq(_policyRegistry.getUserRoles(subCompanyWallet, companyRepEOA), 0, "user roles should be cleared");
        assertFalse(
            _policyRegistry.canExecute(
                subCompanyWallet,
                companyRepEOA,
                address(_mockTarget),
                0,
                abi.encodeCall(MockExecutionTarget.operate, ())
            ),
            "canExecute true post-revoke"
        );

        MockExecutionTarget mockTarget2 = new MockExecutionTarget();
        vm.prank(companyRepEOA);
        vm.expectRevert(Errors.CompanyWallet__Unauthorized.selector);
        ICompanyWallet(subCompanyWallet)
            .execute(address(mockTarget2), 0, abi.encodeCall(MockExecutionTarget.operate, ()));
        assertFalse(mockTarget2.invoked(), "target invoked post-revoke");
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a COMPANY_ISSUER_CUSTODIAN entity type and register an instance.
     * @return custodianEntityId  EntityRegistry ID for the custodian entity.
     * @return custodianAuthority EOA that owns the entity (authority role).
     * @return custodianManager   EOA that can create and register wallets (manager role).
     */
    function _setupCustodianEntity()
        internal
        returns (bytes32 custodianEntityId, address custodianAuthority, address custodianManager)
    {
        vm.prank(_erAdmin);
        _er.defineEntityType(_CUSTODIAN_ENTITY_TYPE, _CUSTODIAN_ENTITY_NAME, 0);

        custodianAuthority = makeAddr("custodian-authority");
        custodianManager = makeAddr("custodian-manager");

        custodianEntityId = keccak256(abi.encodePacked("custodian-entity", custodianAuthority));
        address[] memory managers = new address[](1);
        managers[0] = custodianManager;

        vm.prank(_erAdmin);
        _er.registerEntity(
            custodianEntityId, _CUSTODIAN_ENTITY_TYPE, "ipfs://custodian-meta", custodianAuthority, managers
        );

        assertEq(_er.getEntityAuthority(custodianEntityId), custodianAuthority, "custodian authority mismatch");
        assertTrue(_er.isEntityManager(custodianEntityId, custodianManager), "custodian manager not registered");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-small-strings */

import {CouponRateType, CouponFrequency} from "src/registry/BondStructs.sol";
import {DeployConstants as Constants} from "script/DeployConstants.sol";

abstract contract FuzzConstants {
    bool internal constant VALIDATE_FUZZ_SETUP = true;

    address internal constant USER1 = address(0x10000);
    address internal constant USER2 = address(0x20000);
    address internal constant USER3 = address(0x30000);
    address[] internal users = [USER1, USER2, USER3];

    address internal constant FUZZ_WALLET_4 = address(0x40000);
    address internal constant FUZZ_WALLET_5 = address(0x50000);
    address internal constant FUZZ_WALLET_6 = address(0x60000);
    address internal constant FUZZ_WALLET_7 = address(0x70000);
    address internal constant FUZZ_WALLET_8 = address(0x80000);
    address[] internal fuzzWallets = [FUZZ_WALLET_4, FUZZ_WALLET_5, FUZZ_WALLET_6, FUZZ_WALLET_7, FUZZ_WALLET_8];

    address internal constant MANAGER1 = address(0x90000);
    address internal constant MANAGER2 = address(0xA0000);
    address internal constant MANAGER3 = address(0xB0000);
    address[] internal managers = [MANAGER1, MANAGER2, MANAGER3];

    address internal constant FUZZ_ESCROW_TEST_MODULE = address(0xC0000);
    bytes32 internal constant FUZZ_ESCROW_TEST_MODULE_TYPE = keccak256("FUZZ_ESCROW_TEST_MODULE");
    address internal constant FUZZ_ESCROW_UNAUTH_CALLER = address(0xD0000);
    address internal constant FUZZ_PAYMENT_UNAUTH_CALLER = address(0xE0000);
    address internal constant FUZZ_TOKEN_UNREGISTERED_OPERATOR = address(0xE1000);

    address internal constant POLICY_WALLET_OWNER_A = address(0xF0000);
    address internal constant POLICY_WALLET_OWNER_B = address(0xF1000);
    address internal constant POLICY_OUTSIDER = address(0xF2000);
    address internal constant POLICY_ADMIN_1 = address(0xF3000);
    address internal constant POLICY_ADMIN_2 = address(0xF4000);
    address internal constant POLICY_ADMIN_3 = address(0xF5000);
    address[] internal POLICY_ADMINS = [POLICY_ADMIN_1, POLICY_ADMIN_2, POLICY_ADMIN_3];

    // Owners for the dedicated policy-version (ownership-epoch) wallet. Ownership is rotated
    // between these two so the epoch can be advanced repeatedly without disturbing policyWalletA/B.
    address internal constant POLICY_EPOCH_WALLET_OWNER_A = address(0xF6000);
    address internal constant POLICY_EPOCH_WALLET_OWNER_B = address(0xF7000);

    // Owners for the dedicated CompanyWallet ownership-epoch (invariant I-3) wallet pair.
    address internal constant WALLET_EPOCH_OWNER_A = address(0xF8000);
    address internal constant WALLET_EPOCH_OWNER_B = address(0xF9000);

    uint8 internal constant BEFORE = 0;
    uint8 internal constant AFTER = 1;

    string internal constant FUZZ_BR_SALT = "fuzz-br";
    string internal constant FUZZ_ER_SALT = "fuzz-er";
    string internal constant FUZZ_TOKEN_SALT = "fuzz-token";
    string internal constant FUZZ_ASSET_MANAGER_SALT = "fuzz-asset-manager";
    string internal constant FUZZ_MARKETPLACE_SALT = "fuzz-id";
    string internal constant FUZZ_ESCROW_SALT = "fuzz-escrow";
    string internal constant FUZZ_ORDERBOOK_SALT = "fuzz-orderbook";
    string internal constant FUZZ_POLICY_REGISTRY_SALT = "fuzz-policy-registry";
    string internal constant FUZZ_BOND_MARKET_FILTER_SALT = "fuzz-bond-market-filter";
    string internal constant FUZZ_TIMELOCK_SALT = "fuzz-timelock";

    uint256 internal constant TL_INITIAL_MIN_DELAY = 2 days;

    string internal constant BOND_ISIN = "SK0001002059";
    bytes12 internal constant BOND_ISIN_BYTES12 = bytes12("SK0001002059");
    string internal constant BOND_ZERO_COUPON_ISIN = "SK0001002067";
    bytes12 internal constant BOND_ZERO_COUPON_ISIN_BYTES12 = bytes12("SK0001002067");
    string internal constant BOND_INVALID_INPUT_ISIN = "SK0001002075";
    address internal constant BOND_UNREGISTERED_ISSUER = address(0xE0000);
    string internal constant BOND_CURRENCY = "EUR";
    string internal constant EMPTY_METADATA_REF = "";

    uint256 internal constant BROKER_ENTITY = 1;
    uint256 internal constant NATURAL_PERSON_ENTITY = 2;
    uint256 internal constant DEUSS_PROTOCOL_ENTITY = 3;
    uint256 internal constant ROLE_FLAGS_EMPTY = 0;

    uint256 internal constant FUZZ_ER_COVERAGE_TYPE_ID = uint256(keccak256("FUZZ_ENTITY_REGISTRY_COVERAGE_TYPE"));
    uint256 internal constant FUZZ_ER_COVERAGE_TYPE_CAPS = 1;
    uint256 internal constant FUZZ_ER_USER_ROLE_FLAGS = 1;
    bytes32 internal constant FUZZ_ER_COVERAGE_TYPE_NAME = bytes32("FUZZ_ER_COVERAGE");
    bytes32 internal constant FUZZ_ER_ACCESS_ENTITY_ID = keccak256("FUZZ_ER_ACCESS_ENTITY");
    bytes32 internal constant FUZZ_ER_BATCH_ENTITY_ID_A = keccak256("FUZZ_ER_BATCH_ENTITY_A");
    bytes32 internal constant FUZZ_ER_BATCH_ENTITY_ID_B = keccak256("FUZZ_ER_BATCH_ENTITY_B");
    string internal constant FUZZ_ER_ACCESS_METADATA_REF = "ipfs://fuzz-er-access";
    string internal constant FUZZ_ER_BATCH_METADATA_REF_A = "ipfs://fuzz-er-batch-a";
    string internal constant FUZZ_ER_BATCH_METADATA_REF_B = "ipfs://fuzz-er-batch-b";
    address internal constant FUZZ_ER_AUTHORITY_A = address(0xC0A1);
    address internal constant FUZZ_ER_AUTHORITY_B = address(0xC0A2);
    address internal constant FUZZ_ER_AUTHORITY_C = address(0xC0A3);
    address internal constant FUZZ_ER_MANAGER_A = address(0xC0B1);
    address internal constant FUZZ_ER_MANAGER_B = address(0xC0B2);
    address internal constant FUZZ_ER_ACCOUNT_A = address(0xCA11A);
    address internal constant FUZZ_ER_ACCOUNT_B = address(0xCA11B);

    uint256 internal constant BOND_NOMINAL_VALUE = 1_000;
    uint256 internal constant BOND_ISSUE_COUNT = 10_000;
    uint256 internal constant BOND_COUPON_RATE = 500;
    uint16 internal constant BOND_ISSUANCE_COUNTRY = 703;

    CouponRateType internal constant BOND_COUPON_RATE_TYPE = CouponRateType.FIXED;
    CouponFrequency internal constant BOND_COUPON_FREQUENCY = CouponFrequency.Annual;

    uint256 internal constant MAX_TRACKED_ITEMS = 256;
    uint256 internal constant OFFER_EXPIRY_THRESHOLD = Constants.MARKETPLACE_OFFER_EXPIRY_THRESHOLD;
    uint256 internal constant FIXED_FUZZ_EXPIRY_DELTA = Constants.MARKETPLACE_MAX_OFFER_LIFETIME;
    uint256 internal constant MAX_OFFER_LIFETIME = Constants.MARKETPLACE_MAX_OFFER_LIFETIME;
    uint256 internal constant MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD =
        Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_MARKETPLACE_MODE;
    uint256 internal constant REDEMPTION_PAYMENT_EXPIRY_THRESHOLD =
        Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_REDEMPTION_MODE;
    uint256 internal constant INTEREST_DISCOVERY_PAYMENT_EXPIRY_THRESHOLD =
        Constants.MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD_FOR_INTEREST_DISCOVERY_MODE;
    uint256 internal constant MARKETPLACE_DISPUTE_BUFFER_PERIOD = Constants.MARKETPLACE_DISPUTE_BUFFER_PERIOD;
    uint256 internal constant ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD = Constants.ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD;
    uint256 internal constant ORDERBOOK_MIN_EXPIRY_THRESHOLD = Constants.ORDERBOOK_MIN_EXPIRY_THRESHOLD;
    uint256 internal constant ORDERBOOK_DISPUTE_BUFFER_PERIOD = Constants.ORDERBOOK_DISPUTE_BUFFER_PERIOD;
    uint256 internal constant MAX_COUNTER_OFFERS_PER_USER = Constants.MAX_COUNTER_OFFERS_PER_USER;
    uint256 internal constant PAYMENT_EXPIRY_THRESHOLD = 1 days;
    uint256 internal constant DISPUTE_BUFFER_PERIOD = 1 days;
    uint256 internal constant MAX_INTEREST_DISCOVERY_MIN_SALE_UNITS = 5;
    uint256 internal constant MIN_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE = 2;
    uint256 internal constant MAX_CLOSE_EXPIRED_INTERESTS_BATCH_SIZE = 3;
    uint256 internal constant DEFAULT_UNIT_PRICE = 1_000;

    // Dedicated pool of synthetic token addresses used only by the AssetManager harness.
    // Disjoint from address(token) so fuzzed reconfiguration cannot affect Marketplace.
    address internal constant FUZZ_ASSET_TOKEN_1 = address(0xA551);
    address internal constant FUZZ_ASSET_TOKEN_2 = address(0xA552);
    address internal constant FUZZ_ASSET_TOKEN_3 = address(0xA553);
    address internal constant FUZZ_ASSET_TOKEN_4 = address(0xA554);

    // Fixed bounded set of tokenIds probed against `isAssetSupported` / `isTokenIdAllowed`
    // for cross-view consistency invariants.
    uint256 internal constant FUZZ_ASSET_TOKEN_IDS_COUNT = 4;

    uint8 internal constant ASSET_TYPE_COUNT = 5;
    bytes4 internal constant ERC165_INVALID_INTERFACE_ID = bytes4(0xffffffff);

    // Dedicated pool of synthetic module addresses used only by the EscrowManager authorization
    // harness. Disjoint from the real Marketplace and OrderbookMarketplace so register /
    // deactivate fuzzing cannot touch real module registrations.
    address internal constant FUZZ_ESCROW_MODULE_1 = address(0xE551);
    address internal constant FUZZ_ESCROW_MODULE_2 = address(0xE552);
    address internal constant FUZZ_ESCROW_MODULE_3 = address(0xE553);
    address internal constant FUZZ_ESCROW_MODULE_4 = address(0xE554);

    // Synthetic module types used by the authorization harness. Deliberately distinct from the
    // real MARKETPLACE_MODULE / ORDERBOOK_MARKETPLACE_MODULE hashes so a fuzz-registered
    // module can never be authorized to act on a real escrow.
    bytes32 internal constant FUZZ_MODULE_TYPE_A = keccak256("FUZZ_MODULE_TYPE_A");
    bytes32 internal constant FUZZ_MODULE_TYPE_B = keccak256("FUZZ_MODULE_TYPE_B");
    bytes32 internal constant FUZZ_MODULE_TYPE_C = keccak256("FUZZ_MODULE_TYPE_C");

    uint256 internal constant POLICY_MAX_ROLE_BITMAP = 255;

    bytes4 internal constant _GRANT_USER_ROLES_SELECTOR = bytes4(keccak256("grantUserRoles(address,address,uint256)"));
    bytes4 internal constant _REVOKE_USER_ROLES_SELECTOR =
        bytes4(keccak256("revokeUserRoles(address,address,uint256)"));
    bytes4 internal constant _SET_USER_ROLES_SELECTOR = bytes4(keccak256("setUserRoles(address,address,uint256)"));
    bytes4 internal constant _GRANT_OPERATION_ROLES_SELECTOR =
        bytes4(keccak256("grantOperationRoles(address,address,bytes4,uint256)"));
    bytes4 internal constant _REVOKE_OPERATION_ROLES_SELECTOR =
        bytes4(keccak256("revokeOperationRoles(address,address,bytes4,uint256)"));
    bytes4 internal constant _SET_OPERATION_ROLES_SELECTOR =
        bytes4(keccak256("setOperationRoles(address,address,bytes4,uint256)"));
    bytes4 internal constant _SET_OPERATION_MODULE_SELECTOR =
        bytes4(keccak256("setOperationModule(address,address,bytes4,address)"));

    bytes4 internal constant _GRANT_USER_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("grantUserRoles(address,address[],uint256)"));
    bytes4 internal constant _REVOKE_USER_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("revokeUserRoles(address,address[],uint256)"));
    bytes4 internal constant _SET_USER_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("setUserRoles(address,address[],uint256[])"));
    bytes4 internal constant _GRANT_OPERATION_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("grantOperationRoles(address,(address,bytes4,uint256)[])"));
    bytes4 internal constant _REVOKE_OPERATION_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("revokeOperationRoles(address,(address,bytes4,uint256)[])"));
    bytes4 internal constant _SET_OPERATION_ROLES_BATCH_SELECTOR =
        bytes4(keccak256("setOperationRoles(address,(address,bytes4,uint256)[])"));
    bytes4 internal constant _SET_OPERATION_MODULE_BATCH_SELECTOR =
        bytes4(keccak256("setOperationModule(address,(address,bytes4,address)[])"));

    bytes4 internal constant _REGISTER_ENTITY_SELECTOR = 0x5a005374;
    bytes4 internal constant _REGISTER_ENTITY_WITH_ACCESS_SELECTOR =
        bytes4(keccak256("registerEntity(bytes32,uint256,string,address,address[])"));
    bytes4 internal constant _INVALID_INITIALIZATION_SELECTOR = bytes4(keccak256("InvalidInitialization()"));
}

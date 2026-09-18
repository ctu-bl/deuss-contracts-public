// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {CouponRateType} from "src/registry/BondStructs.sol";

contract Constants {
    /*//////////////////////////////////////////////////////////////
                                GENERAL
    //////////////////////////////////////////////////////////////*/

    address public constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    uint256 public constant VALIDITY_PERIOD = 72 hours;
    uint256 public constant COMPANY_ENTITY = 1;
    uint256 public constant NATURAL_PERSON_ENTITY = 2;
    uint256 public constant AGENT_ENTITY = 3;
    uint256 public constant DEUSS_GOVERNANCE_ENTITY = 4;
    bytes32 public constant COMPANY_WALLET_TYPE = keccak256("COMPANY_WALLET");
    uint256 public constant ROLE_FLAGS_EMPTY = 0;
    uint256 public constant ROLE_FLAGS_INITIAL = 1;
    uint256 public constant ROLE_FLAGS_UPDATED = 7;

    /*//////////////////////////////////////////////////////////////
                                  IDENTITY REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @dev 203 for Czechia according to ISO 3166: https://www.iso.org/obp/ui/#search
    uint16 public constant ISO_3166_CZECHIA = 203;
    uint16 public constant ISO_3166_SLOVAKIA = 703;
    uint16 public constant ISO_3166_HUNGARY = 348;

    /*//////////////////////////////////////////////////////////////
                               BOND DATA
    //////////////////////////////////////////////////////////////*/

    string public constant BOND_ISIN_ERC6909_FT = "SK0001002059";
    string public constant BOND_NAME = "SME Test Bond";
    string public constant BOND_SYMBOL = "SME";
    string public constant BOND_CURRENCY = "EUR";
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes3 public constant BOND_CURRENCY_BYTES3 = bytes3("EUR");
    string public constant BOND_V1 = "1.0.0";
    string public constant BOND_V2 = "2.0.0";
    uint256 public constant BOND_NOMINAL_VALUE = 1_000;
    uint256 public constant BOND_MAX_SUPPLY = 10_000;
    uint256 public constant BOND_ISSUANCE_NOMINAL_VALUE = BOND_MAX_SUPPLY * BOND_NOMINAL_VALUE;
    uint256 public constant BOND_ISSUE_COUNT = 10_000;
    uint256 public constant BOND_COUPON_RATE = 500; // 5% as basis points
    CouponRateType public constant BOND_COUPON_RATE_TYPE = CouponRateType.FIXED;
    uint16 public constant BOND_ISSUANCE_COUNTRY = ISO_3166_SLOVAKIA;
    string public constant EMPTY_METADATA_REF = "";

    string public constant URI = "ipfs://";
    string public constant NON_EXISTENT_ISIN = "SK0001999999";

    /*//////////////////////////////////////////////////////////////
                             COMMITMENT AGE
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MIN_COMMITMENT_AGE = 1;
    uint256 public constant MAX_COMMITMENT_AGE = 300;

    /*//////////////////////////////////////////////////////////////
                           INTEREST DISCOVERY
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_AMOUNT_TO_BUY = 5;
    // @todo Each `TimelockController.execute` operation increases the block time by one day.
    uint256 public constant OFFER_EXPIRY = 365 days;
    uint256 public constant COUNTER_OFFER_EXPIRY = 1 days;
    uint256 public constant MAX_OFFER_LIFETIME = 365 days;

    uint256 public constant POLICY_ID_1 = uint256(keccak256(abi.encode("POLICY_ID_1")));
    uint256 public constant POLICY_ID_2 = uint256(keccak256(abi.encode("POLICY_ID_2")));

    /*//////////////////////////////////////////////////////////////
                                FACTORY
    //////////////////////////////////////////////////////////////*/

    string public constant ESCROW_MANAGER_SALT = "escrowManagerSalt";
    string public constant FACTORY_SALT = "factorySalt";
    string public constant BOND_REGISTRY_SALT = "bondRegistrySalt";
    string public constant ENTITY_REGISTRY_SALT = "entityRegistrySalt";
    string public constant IDENTITY_FACTORY_SALT = "identityFactorySalt";
    string public constant MARKETPLACE_SALT = "marketplaceSalt";
    string public constant CLAIM_ISSUER_FACTORY_SALT = "claimIssuerFactorySalt";
    string public constant CTIR_SALT = "ctirSalt";
    string public constant IR_SALT = "irSalt";
    string public constant VERIFIER_SALT = "verifierSalt";

    /*//////////////////////////////////////////////////////////////
                                 CLAIMS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant KYC_CLAIM = 108137157962836418307292194945476710587398726536839190715934775571219101864675; // uint256(keccak256(abi.encode("KYC")));
    uint256 public constant AML_CLAIM = 24474565988312880094142471785028994269181852652050285977113542268824994266646; //uint256(keccak256(abi.encode("AML")));

    uint256 public constant CLAIM_KEY = 3;
    uint256 public constant ECDSA_TYPE = 1;

    uint256 public constant SIGNER_1_PK = 1;
    uint256 public constant SIGNER_2_PK = 2;
    uint256 public constant SIGNER_3_PK = 3;
    uint256 public constant IDENTITY_OWNER_PK = 999;
    uint256 public constant ISSUER_OWNER_PK = 998;
    uint256 public constant NOT_SIGNER_PK = 997;

    uint256 public constant REGISTRAR_1_PK = 1000;
    uint256 public constant REGISTRAR_2_PK = 1001;
    uint256 public constant REGISTRAR_3_PK = 1002;
    uint256 public constant IDENTITY_REGISTRY_OWNER_PK = 9999;
    uint256 public constant NOT_REGISTRAR_PK = 9998;

    uint256 public constant CLAIM_GROUP_ID = 1;
    uint256 public constant CLAIM_TOPIC = 1;
    uint256 public constant CLAIM_SCHEME = 1;
    uint256 public constant CLAIM_EXPIRY_THRESHOLD = 1 days;
    string public constant CLAIM_URI = "ipfs://claim";

    /*//////////////////////////////////////////////////////////////
                        TimelockController
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TIMELOCK_CONTROLLER_OP_SALT = bytes32("timelockControllerOpSalt");
    uint256 public constant TIMELOCK_CONTROLLER_MIN_DELAY = 1 days;
}

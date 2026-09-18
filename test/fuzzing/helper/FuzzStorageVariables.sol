// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, max-states-count */

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {FuzzConstants} from "../util/FuzzConstants.sol";
import {FuzzERC20, FuzzERC721, FuzzERC1155} from "../mocks/EscrowManagerFuzzMocks.sol";
import {
    FuzzBondMarketFilterCoverageHarness,
    FuzzBondMetadataAdapter,
    FuzzEscrowManagerCoverageHarness,
    FuzzMarketFilter,
    FuzzMarketplaceCoverageHarness,
    FuzzOrderbookCoverageHarness
} from "../mocks/OrderbookFuzzMocks.sol";
import {FuzzInvalidReturnPolicyModule, FuzzPolicyModule, FuzzPolicyTarget} from "../mocks/PolicyRegistryFuzzMocks.sol";
import {AssetManager} from "src/marketplace/AssetManager.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";

abstract contract FuzzStorageVariables is FuzzConstants {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct PendingRegistrationRef {
        address account;
        bytes32 entityId;
    }

    bool internal _setActor = true;
    bool internal _debug = false;
    address internal currentActor;

    BondRegistry internal bondRegistry;
    EntityRegistry internal entityRegistry;
    PolicyRegistry internal policyRegistry;
    DEUSSToken internal token;
    AssetManager internal assetManager;
    Marketplace internal marketplace;
    EscrowManager internal escrowManager;
    OrderbookMarketplace internal orderbookMarketplace;
    BondMarketFilter internal bondMarketFilter;
    CompanyWallet internal policyWalletA;
    CompanyWallet internal policyWalletB;
    CompanyWallet internal policyEpochWallet;
    CompanyWallet internal walletEpochA;
    CompanyWallet internal walletEpochB;
    FuzzPolicyTarget internal policyTarget;
    FuzzPolicyModule internal policyAllowModule;
    FuzzPolicyModule internal policyDenyModule;
    FuzzPolicyModule internal policyRevertingModule;
    FuzzInvalidReturnPolicyModule internal policyInvalidReturnModule;
    FuzzERC20 internal fuzzERC20;
    FuzzERC721 internal fuzzERC721;
    FuzzERC1155 internal fuzzERC1155;
    FuzzBondMetadataAdapter internal fuzzBondAdapter;
    FuzzMarketFilter internal fuzzMarketFilter;
    FuzzBondMarketFilterCoverageHarness internal bondMarketFilterCoverage;
    FuzzMarketplaceCoverageHarness internal marketplaceCoverage;
    FuzzEscrowManagerCoverageHarness internal escrowManagerCoverage;
    FuzzOrderbookCoverageHarness internal orderbookCoverage;
    TimelockControllerUpgradeable internal timelock;
    uint256 internal timelockOpNonce;
    bytes32[] internal trackedOpIds;
    mapping(bytes32 opId => bool tracked) internal trackedOp;
    mapping(bytes32 opId => address target) internal trackedOpTarget;
    mapping(bytes32 opId => uint256 value) internal trackedOpValue;
    mapping(bytes32 opId => bytes data) internal trackedOpData;
    mapping(bytes32 opId => bytes32 predecessor) internal trackedOpPredecessor;
    mapping(bytes32 opId => bytes32 salt) internal trackedOpSalt;
    mapping(bytes32 opId => uint256 scheduleTime) internal trackedOpScheduleTime;
    mapping(bytes32 opId => uint256 minDelay) internal trackedOpMinDelay;
    uint256 internal constant TL_MAX_EXTRA_DELAY = 30 days;
    uint256 internal constant TL_MAX_MIN_DELAY = 365 days;

    address internal governance;
    address internal publisher;
    address internal issuer;

    uint256 internal bondTokenId;
    uint256 internal initialIssuedSupply;
    uint256 internal fuzzERC721TokenCursor;
    uint256 internal orderbookTokenCursor;

    // Bounded sets of discovered IDs that the harness can later sample or scan.
    uint256[] internal knownOfferIds;
    uint256[] internal knownDealIds;
    uint256[] internal knownInterestIds;
    uint256[] internal knownEscrowIds;
    bytes32[] internal knownEntityIds;
    bytes32[] internal knownFuzzEntityIds;
    uint8[] internal knownBondVersions;
    uint256 internal trackedOfferCursor;
    uint256 internal trackedDealCursor;
    uint256 internal trackedInterestCursor;
    uint256 internal trackedEscrowCursor;
    uint256 internal trackedEntityCursor;
    uint256 internal trackedFuzzEntityCursor;
    uint256 internal trackedPendingRegistrationCursor;
    uint256 internal trackedBondVersionCursor;

    uint256 internal entityNonce;

    mapping(uint256 offerId => bool isTracked) internal trackedOffer;
    mapping(uint256 dealId => bool isTracked) internal trackedDeal;
    mapping(uint256 interestId => bool isTracked) internal trackedInterest;
    mapping(uint256 escrowId => bool isTracked) internal trackedEscrow;
    mapping(bytes32 entityId => bool isTracked) internal trackedEntity;
    mapping(bytes32 entityId => bool isFuzzEntity) internal trackedFuzzEntity;
    mapping(address account => bool isFuzzAccount) internal trackedFuzzAccount;
    mapping(bytes32 pendingKey => bool isTracked) internal trackedPendingRegistration;
    mapping(uint8 version => bool isTracked) internal trackedBondVersion;
    mapping(uint8 version => uint256 reclaimed) internal burnedReclaimed;
    mapping(uint8 version => uint256 settled) internal burnedSettled;

    mapping(uint256 bucketId => EnumerableSet.UintSet bucketSet) internal offerBuckets;
    mapping(uint256 bucketId => EnumerableSet.UintSet bucketSet) internal dealBuckets;
    mapping(uint256 bucketId => EnumerableSet.UintSet bucketSet) internal interestBuckets;
    mapping(uint256 bucketId => EnumerableSet.UintSet bucketSet) internal escrowBuckets;
    mapping(uint256 bucketId => EnumerableSet.Bytes32Set bucketSet) internal entityBuckets;
    mapping(uint256 bucketId => EnumerableSet.Bytes32Set bucketSet) internal fuzzEntityBuckets;
    mapping(uint256 bucketId => EnumerableSet.AddressSet bucketSet) internal fuzzAccountBuckets;

    // Fixed pool of synthetic token addresses fuzzed against AssetManager. Disjoint from
    // the real `token` wired into Marketplace so reconfiguration cannot affect it.
    address[] internal knownAssetTokens;

    // Fixed pool of tokenIds probed for per-(token,tokenId) allowlist invariants.
    uint256[] internal knownAssetTokenIds;

    // Fixed pool of synthetic module addresses fuzzed against EscrowManager register/deactivate.
    // Disjoint from the real Marketplace / OrderbookMarketplace addresses.
    address[] internal knownEscrowModules;

    // Fixed pool of synthetic module types. Index 0 is always `bytes32(0)` so the
    // `InvalidModuleType` revert branch is reachable from the same seed distribution.
    bytes32[] internal knownEscrowModuleTypes;

    // Bounded set of pending EntityRegistry account-registration requests. The key is
    // keccak256(account, entityId), while the ref array preserves selectable pair values.
    PendingRegistrationRef[] internal knownPendingRegistrations;
}

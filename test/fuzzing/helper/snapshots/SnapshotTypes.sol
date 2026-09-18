// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-struct-packing */

import {AssetType, DealStatus, DealType, SaleMode} from "src/marketplace/MarketStructs.sol";
import {BondStatus} from "src/registry/BondStructs.sol";
import {AccountStatus, EntityStatus} from "src/registry/EntityStructs.sol";
import {FuzzSetup} from "../../FuzzSetup.sol";

/// @notice Shared snapshot storage and type definitions used by all BeforeAfter verticals.
abstract contract SnapshotTypes is FuzzSetup {
    /*//////////////////////////////////////////////////////////////
                            SNAPSHOT STATE
    //////////////////////////////////////////////////////////////*/

    struct State {
        // Marketplace
        mapping(address actor => ActorState actorState) actorStates;
        mapping(uint256 offerId => OfferState offerState) offerStates;
        mapping(uint256 dealId => DealStateSnapshot dealState) dealStates;
        mapping(uint256 interestId => InterestStateSnapshot interestState) interestStates;
        mapping(uint256 escrowId => EscrowState escrowState) escrowStates;
        uint256 trackedBalanceSum;
        uint256 escrowBalance;
        uint256 trackedEscrowAmountSum;
        uint256 escrowReserved;
        uint256 escrowSweepable;
        uint256 nextEscrowId;
        uint256 totalSupply;
        uint256 totalSupplyAtCurrentBlock;
        uint256 bondNominalValue;
        uint256 trackedFaceValueSum;
        uint256 offerCounter;
        uint256 dealCounter;
        uint256 interestCounter;
        BondStatus bondStatus;
        bool tokenPaused;
        bool tokenIdPaused;
        bool allTrackedFrozenBalancesBounded;
        bool allTrackedOffersBounded;
        bool allTrackedEscrowsMatchOfferHoldings;
        // DEUSSToken
        mapping(address owner => mapping(address spender => TokenPairState pairState)) tokenPairStates;
        // Bond Registry
        mapping(uint8 version => BondVersionState bondVersionState) bondVersionStates;
        mapping(uint8 version => mapping(address account => uint256 balance)) bondVersionAccountBalances;
        uint8 latestBondVersion;
        uint8 activeBondVersion;
        bool allTrackedBondsConsistent;
        bool allTrackedBondSupplyConsistent;
        bool allTrackedBondCapacityConsistent;
        bool allTrackedBondPauseConsistent;
        bool allTrackedBondReverseMappingsConsistent;
        bool allTrackedBondTranchesConsistent;
        // Entity Registry
        mapping(bytes32 entityId => EntityState entityState) entityStates;
        mapping(address account => AccountState accountState) accountStates;
        bool allTrackedEntityAccountsConsistent;
        // Asset Manager
        mapping(address token => AssetManagerConfigState configState) assetConfigStates;
        mapping(address token => mapping(uint256 tokenId => bool allowed)) assetAllowedStates;
        // Policy Registry
        mapping(address wallet => PolicyWalletState walletState) policyWalletStates;
        mapping(address wallet => mapping(address admin => bool granted)) policyAdminStates;
        mapping(address wallet => mapping(address user => uint256 roles)) policyUserRoleStates;
        mapping(address wallet => mapping(bytes32 operationKey => PolicyOperationState operationState))
            policyOperationStates;
        mapping(address wallet => mapping(bytes32 executionKey => bool canExecute)) policyExecutionStates;
        // EscrowManager Authorization
        mapping(address moduleAddr => bytes32 moduleType) escrowModuleTypeStates;
        mapping(bytes32 moduleType => mapping(address moduleAddr => bool authorized)) escrowAuthStates;
        address escrowAssetManager;
        uint256 escrowNextId;
        // DependenciesBase
        address depBondRegistry;
        address depEscrowManager;
        address depEntityRegistry;
        // CompanyWallet ownership epoch (dedicated WALLET-vertical wallet pair)
        uint256 walletEpochAEpoch;
        uint256 walletEpochBEpoch;
        address walletEpochAOwner;
        address walletEpochBOwner;
        // TimelockController
        mapping(bytes32 opId => TimelockOpState timelockOpState) timelockOpStates;
        uint256 timelockMinDelay;
    }

    /*//////////////////////////////////////////////////////////////
                         MARKETPLACE SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    struct ActorState {
        uint256 balance;
        uint256 frozenBalance;
        uint256 balanceAtCurrentBlock;
        uint256 frozenBalanceAtCurrentBlock;
        uint256 availableBalanceAtCurrentBlock;
        bool escrowApproved;
    }

    struct TokenPairState {
        uint256 allowance;
        bool operatorApproved;
    }

    struct OfferState {
        address owner;
        uint256 escrowId;
        uint256 total;
        uint256 available;
        uint256 inDeals;
        uint256 sold;
        uint256 lot;
        uint256 unitPrice;
        uint256 expiry;
        bool cancelled;
        bool frozen;
        bool reservedInterestSeized;
        bool allowCounterOffers;
        SaleMode saleMode;
        uint256 minSaleUnits;
        uint256 interestedUnits;
        uint256 reservedInterestUnits;
        uint256 paymentExpiryThreshold;
        uint256 allowedBuyerCount;
        address[] allowedBuyers;
    }

    struct DealStateSnapshot {
        uint256 offerId;
        uint256 amount;
        address buyer;
        uint256 price;
        uint256 counterOfferExpiry;
        uint256 paymentDeadline;
        uint256 disputeBuffer;
        DealStatus status;
        DealType dealType;
        bool frozen;
    }

    struct InterestStateSnapshot {
        uint256 offerId;
        uint256 amount;
        address investor;
        uint256 price;
        uint8 status;
    }

    struct EscrowState {
        address depositor;
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                        BOND REGISTRY SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    struct BondVersionState {
        BondStatus status;
        bool issuanceClosed;
        bool isGuaranteed;
        bool tokenIdPaused;
        uint16 trancheCount;
        uint256 tokenId;
        address tokenAddress;
        uint256 mintedSupply;
        uint256 remainingIssuableSupply;
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 issuerBalance;
        address issuer;
        bytes3 currency;
        uint256 bondNominalValue;
        uint8 couponRateType;
        uint8 couponFrequency;
        uint16 issuanceCountry;
        uint256 maturityDate;
        bytes32 couponRatesHash;
    }

    /*//////////////////////////////////////////////////////////////
                       ENTITY REGISTRY SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    struct EntityState {
        EntityStatus status;
        uint256 typeId;
        uint256 accountCount;
    }

    struct AccountState {
        AccountStatus status;
        bytes32 entityId;
        uint256 roleFlags;
        bool registered;
    }

    struct TimelockOpState {
        uint8 opState;
        uint256 timestamp;
        bool ready;
        bool pending;
        bool done;
        bool predecessorDone;
    }

    /*//////////////////////////////////////////////////////////////
                         ASSET MANAGER SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    struct AssetManagerConfigState {
        AssetType assetType;
        bool enabled;
        bool enforceTokenId;
    }

    /*//////////////////////////////////////////////////////////////
                         POLICY REGISTRY SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    struct PolicyWalletState {
        uint256 ownershipEpoch;
        address owner;
    }

    struct PolicyOperationState {
        uint256 roles;
        address module;
    }

    mapping(uint8 snapshotId => State stateSnapshot) internal states;

    /*//////////////////////////////////////////////////////////////
                            SHARED HOOKS
    //////////////////////////////////////////////////////////////*/

    function _before(address[] memory actors, uint256[] memory offerIds, uint256[] memory dealIds) internal virtual;

    function _before(
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal virtual;

    function _after(address[] memory actors, uint256[] memory offerIds, uint256[] memory dealIds) internal virtual;

    function _after(
        address[] memory actors,
        uint256[] memory offerIds,
        uint256[] memory dealIds,
        uint256[] memory interestIds
    ) internal virtual;
}

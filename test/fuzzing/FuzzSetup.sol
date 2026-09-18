// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-small-strings */

import {vm} from "@perimetersec/fuzzlib/src/IHevm.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Bond, BondInput, CouponRates, BondStatus} from "src/registry/BondStructs.sol";
import {AssetType} from "src/marketplace/MarketStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {AccountStatus, EntityStatus, EntityTypeMeta} from "src/registry/EntityStructs.sol";
import {BRDeployer} from "src/deployer/registries/BRDeployer.sol";
import {ERDeployer} from "src/deployer/registries/ERDeployer.sol";
import {PolicyRegistryDeployer} from "src/deployer/registries/PolicyRegistryDeployer.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {TokenDeployer} from "src/deployer/token/TokenDeployer.sol";
import {AssetManagerDeployer} from "src/deployer/marketplace/AssetManagerDeployer.sol";
import {MarketplaceDeployer} from "src/deployer/marketplace/MarketplaceDeployer.sol";
import {EscrowManagerDeployer} from "src/deployer/marketplace/EscrowManagerDeployer.sol";
import {OrderbookMarketplaceDeployer} from "src/deployer/marketplace/OrderbookMarketplaceDeployer.sol";
import {BondMarketFilterDeployer} from "src/deployer/marketplace/BondMarketFilterDeployer.sol";
import {TimelockControllerDeployer} from "src/deployer/governance/TimelockControllerDeployer.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {IOrderbookMarketplace} from "src/marketplace/interfaces/IOrderbookMarketplace.sol";
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";

import {FuzzStateIndex} from "./helper/FuzzStateIndex.sol";
import {FuzzERC20, FuzzERC721, FuzzERC1155} from "./mocks/EscrowManagerFuzzMocks.sol";
import {
    FuzzBondMarketFilterCoverageHarness,
    FuzzBondMetadataAdapter,
    FuzzEscrowManagerCoverageHarness,
    FuzzMarketFilter,
    FuzzMarketplaceCoverageHarness,
    FuzzOrderbookCoverageHarness
} from "./mocks/OrderbookFuzzMocks.sol";
import {FuzzInvalidReturnPolicyModule, FuzzPolicyModule, FuzzPolicyTarget} from "./mocks/PolicyRegistryFuzzMocks.sol";

contract FuzzSetup is FuzzStateIndex {
    bytes4 private constant PANIC_SELECTOR = 0x4e487b71;

    function setup() internal {
        fl.log("Setting up core fuzz environment");

        governance = address(this);
        publisher = address(this);

        _deploySuite();
        _grantRoles();
        _defineEntityTypes();
        _configureCoreContracts();
        _registerCoreWallets();
    }

    function setupActors() internal {
        fl.log("Setting up fuzz users");

        _registerUsers();
        _initializeFuzzAccountBuckets();
        _setIssuer();
        _publishAndIssueBond();
        _approveEscrowForUsers();
        _seedAssetManagerPool();
        _warmEntityRegistry();
        _warmCoverageHarnesses();
    }

    function validateSetup() internal {
        fl.log("Validating setup");

        _validateProtocolAddresses();
        _validateOwnershipAndRoles();
        _validateCoreWiring();
        _validateEscrowModules();
        _validateMarketplaceConfiguration();
        _validateBondAndTokenState();
        _validateUserAndAccountState();
        _validateEntityRegistryWarmup();
        _validateEntityRegistrySameAuthorityReverts();
    }

    /*//////////////////////////////////////////////////////////////
                               CONTRACTS
    //////////////////////////////////////////////////////////////*/

    function _deploySuite() internal {
        fl.log("Deploying suite contracts");

        BRDeployer brd = new BRDeployer(governance, FUZZ_BR_SALT);
        bondRegistry = brd.bondRegistry();

        ERDeployer erd = new ERDeployer(governance, FUZZ_ER_SALT);
        entityRegistry = erd.entityRegistry();

        PolicyRegistryDeployer prd = new PolicyRegistryDeployer(governance, FUZZ_POLICY_REGISTRY_SALT);
        policyRegistry = prd.policyRegistry();

        AssetManagerDeployer amd = new AssetManagerDeployer(governance, FUZZ_ASSET_MANAGER_SALT);
        assetManager = amd.assetManager();

        MarketplaceDeployer.MarketplaceDeployParams memory marketplaceParams =
            MarketplaceDeployer.MarketplaceDeployParams({
                owner: governance,
                offerExpiryThreshold: OFFER_EXPIRY_THRESHOLD,
                maxOfferLifetime: MAX_OFFER_LIFETIME,
                marketplacePaymentExpiryThreshold: MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD,
                redemptionPaymentExpiryThreshold: REDEMPTION_PAYMENT_EXPIRY_THRESHOLD,
                interestDiscoveryPaymentExpiryThreshold: INTEREST_DISCOVERY_PAYMENT_EXPIRY_THRESHOLD,
                disputeBufferPeriod: MARKETPLACE_DISPUTE_BUFFER_PERIOD,
                assetManager: address(assetManager),
                escrowManager: address(0),
                entityRegistry: address(entityRegistry),
                maxCounterOffers: MAX_COUNTER_OFFERS_PER_USER,
                marketplaceSalt: FUZZ_MARKETPLACE_SALT
            });
        MarketplaceDeployer marketplaceDeployer = new MarketplaceDeployer(marketplaceParams);
        marketplace = marketplaceDeployer.marketplace();

        BondMarketFilterDeployer bmfd = new BondMarketFilterDeployer(governance, FUZZ_BOND_MARKET_FILTER_SALT);
        bondMarketFilter = bmfd.bondMarketFilter();

        OrderbookMarketplaceDeployer omd = new OrderbookMarketplaceDeployer(
            governance,
            address(assetManager),
            address(0),
            address(0),
            ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD,
            ORDERBOOK_MIN_EXPIRY_THRESHOLD,
            ORDERBOOK_DISPUTE_BUFFER_PERIOD,
            address(bondMarketFilter),
            FUZZ_ORDERBOOK_SALT
        );
        orderbookMarketplace = omd.orderbookMarketplace();

        EscrowManagerDeployer emd = new EscrowManagerDeployer(
            governance, address(marketplace), address(orderbookMarketplace), FUZZ_ESCROW_SALT
        );
        escrowManager = emd.escrowManager();

        TokenDeployer td = new TokenDeployer(
            governance, address(bondRegistry), address(entityRegistry), address(escrowManager), FUZZ_TOKEN_SALT
        );
        token = td.token();

        address[] memory tlProposers = new address[](1);
        tlProposers[0] = address(this);
        address[] memory tlExecutors = new address[](1);
        tlExecutors[0] = address(this);
        TimelockControllerDeployer tld = new TimelockControllerDeployer(
            TL_INITIAL_MIN_DELAY, tlProposers, tlExecutors, governance, FUZZ_TIMELOCK_SALT
        );
        timelock = tld.timelockController();

        _deployPolicyRegistryFuzzContracts();
        _deployEscrowManagerFuzzTokens();
    }

    function _grantRoles() internal {
        fl.log("Granting roles to core contracts");

        entityRegistry.grantRoles(address(this), entityRegistry.ALL_ROLES());
        bondRegistry.grantRoles(publisher, bondRegistry.ALL_BR_ROLES());
        token.grantRoles(address(this), token.ALL_ROLES());
        assetManager.grantRoles(address(this), assetManager.ADMIN());
        escrowManager.grantRoles(address(this), escrowManager.ADMIN());
        orderbookMarketplace.grantRoles(
            address(this),
            orderbookMarketplace.ADMIN() | orderbookMarketplace.PAYMENT_HANDLER() | orderbookMarketplace.ARBITRATOR()
                | orderbookMarketplace.SEIZURE_ROLE() | orderbookMarketplace.FREEZE_ROLE()
        );
        bondMarketFilter.grantRoles(address(this), bondMarketFilter.ADMIN());
        marketplace.grantRoles(
            address(this),
            marketplace.ADMIN() | marketplace.PAYMENT_HANDLER() | marketplace.ARBITRATOR() | marketplace.SEIZURE_ROLE()
                | marketplace.FREEZE_ROLE() | marketplace.INTEREST_DISCOVERY_OPERATOR()
        );
    }

    function _configureCoreContracts() internal {
        fl.log("Configuring core contracts");

        assetManager.setAsset(address(token), AssetType.ERC6909, true, false);
        assetManager.setAsset(address(fuzzERC20), AssetType.ERC20, true, false);
        assetManager.setAsset(address(fuzzERC721), AssetType.ERC721, true, false);
        assetManager.setAsset(address(fuzzERC1155), AssetType.ERC1155, true, false);
        escrowManager.setAssetManager(address(assetManager));
        escrowManager.registerModule(FUZZ_ESCROW_TEST_MODULE_TYPE, FUZZ_ESCROW_TEST_MODULE);

        marketplace.setEscrowManager(address(escrowManager));
        marketplace.setAllowedEntityType(BROKER_ENTITY, true);
        marketplace.setAllowedEntityType(NATURAL_PERSON_ENTITY, false);
        marketplace.setAllowedEntityType(DEUSS_PROTOCOL_ENTITY, false);
        // forge-lint: disable-next-line(unsafe-typecast)
        marketplace.addCurrency(bytes3(bytes(BOND_CURRENCY)));
        marketplace.setDisputeBufferPeriod(MARKETPLACE_DISPUTE_BUFFER_PERIOD);

        orderbookMarketplace.setEntityRegistry(address(entityRegistry));
        orderbookMarketplace.setEscrowManager(address(escrowManager));
        bondMarketFilter.setAdapter(address(fuzzERC1155), address(fuzzBondAdapter));

        policyRegistry.setPolicyModuleAllowed(address(policyAllowModule), true);
        policyRegistry.setPolicyModuleAllowed(address(policyDenyModule), true);
        policyRegistry.setPolicyModuleAllowed(address(policyRevertingModule), true);
        policyRegistry.setPolicyModuleAllowed(address(policyInvalidReturnModule), true);

        bondRegistry.setAllowedCurrency(BOND_CURRENCY, true);
        bondRegistry.setMultiToken(address(token));

        token.unpause();
    }

    function _deployPolicyRegistryFuzzContracts() internal {
        fl.log("Deploying PolicyRegistry fuzz contracts");

        CompanyWallet walletImplementation = new CompanyWallet();
        UpgradeableBeacon walletBeacon = new UpgradeableBeacon(address(walletImplementation), governance);

        policyWalletA = CompanyWallet(
            payable(address(
                    new BeaconProxy(
                        address(walletBeacon),
                        abi.encodeWithSelector(
                            CompanyWallet.initialize.selector, POLICY_WALLET_OWNER_A, address(policyRegistry)
                        )
                    )
                ))
        );
        policyWalletB = CompanyWallet(
            payable(address(
                    new BeaconProxy(
                        address(walletBeacon),
                        abi.encodeWithSelector(
                            CompanyWallet.initialize.selector, POLICY_WALLET_OWNER_B, address(policyRegistry)
                        )
                    )
                ))
        );
        // Dedicated wallet for the policy-version (ownership-epoch) invariants. Its ownership is
        // rotated by handler_advancePolicyVersionResetsState; keeping it separate from policyWalletA/B
        // ensures epoch advances do not wipe the epoch-scoped state the other PR handlers rely on.
        policyEpochWallet = CompanyWallet(
            payable(address(
                    new BeaconProxy(
                        address(walletBeacon),
                        abi.encodeWithSelector(
                            CompanyWallet.initialize.selector, POLICY_EPOCH_WALLET_OWNER_A, address(policyRegistry)
                        )
                    )
                ))
        );
        // Dedicated wallet pair for the CompanyWallet ownership-epoch vertical (invariant I-3). The
        // WALLET handlers bump the epoch via transferOwnership (and its restore) and grant wallet-scoped
        // roles.
        walletEpochA = CompanyWallet(
            payable(address(
                    new BeaconProxy(
                        address(walletBeacon),
                        abi.encodeWithSelector(
                            CompanyWallet.initialize.selector, WALLET_EPOCH_OWNER_A, address(policyRegistry)
                        )
                    )
                ))
        );
        walletEpochB = CompanyWallet(
            payable(address(
                    new BeaconProxy(
                        address(walletBeacon),
                        abi.encodeWithSelector(
                            CompanyWallet.initialize.selector, WALLET_EPOCH_OWNER_B, address(policyRegistry)
                        )
                    )
                ))
        );

        policyTarget = new FuzzPolicyTarget();
        policyAllowModule = new FuzzPolicyModule(true, false);
        policyDenyModule = new FuzzPolicyModule(false, false);
        policyRevertingModule = new FuzzPolicyModule(false, true);
        policyInvalidReturnModule = new FuzzInvalidReturnPolicyModule();
    }

    function _deployEscrowManagerFuzzTokens() internal {
        fl.log("Deploying EscrowManager fuzz tokens");

        fuzzERC20 = new FuzzERC20();
        fuzzERC721 = new FuzzERC721();
        fuzzERC1155 = new FuzzERC1155();
        fuzzBondAdapter = new FuzzBondMetadataAdapter();
        fuzzMarketFilter = new FuzzMarketFilter();
        bondMarketFilterCoverage = new FuzzBondMarketFilterCoverageHarness();
        FuzzMarketplaceCoverageHarness marketplaceCoverageImplementation = new FuzzMarketplaceCoverageHarness();
        UpgradeableBeacon marketplaceCoverageBeacon =
            new UpgradeableBeacon(address(marketplaceCoverageImplementation), governance);
        marketplaceCoverage = FuzzMarketplaceCoverageHarness(
            address(
                new BeaconProxy(
                    address(marketplaceCoverageBeacon),
                    abi.encodeWithSelector(
                        FuzzMarketplaceCoverageHarness.initializeCoverage.selector,
                        governance,
                        address(assetManager),
                        address(escrowManager),
                        address(entityRegistry)
                    )
                )
            )
        );
        escrowManagerCoverage = new FuzzEscrowManagerCoverageHarness();
        orderbookCoverage = new FuzzOrderbookCoverageHarness();
    }

    function _warmCoverageHarnesses() internal {
        fl.log("Warming directed coverage harnesses");

        uint256 baseTokenId = 9_000_000 + orderbookTokenCursor;
        orderbookTokenCursor += 100;

        bondMarketFilterCoverage.exerciseSurface(
            fuzzBondAdapter, address(fuzzERC1155), baseTokenId, bytes3(bytes(BOND_CURRENCY)), issuer, USER2
        );

        address[] memory emptyFilterAddresses = new address[](0);
        address[] memory filterAddresses = new address[](1);
        filterAddresses[0] = USER1;

        BondMarketFilter.BondFilter memory filter;
        IOrderbookMarketplace.BatchOrderInput memory batch = IOrderbookMarketplace.BatchOrderInput({
            totalAmount: 2,
            minPrice: 1,
            maxPrice: 10,
            minMatchAmount: 0,
            filterData: abi.encode(filter),
            traderFilterMode: IOrderbookMarketplace.TraderFilterMode.NONE,
            traderFilterAddresses: new address[](0)
        });

        orderbookCoverage.exerciseInternalSurface(
            address(entityRegistry),
            address(fuzzMarketFilter),
            USER1,
            USER2,
            emptyFilterAddresses,
            filterAddresses,
            batch
        );

        batch.filterData = hex"ff";
        orderbookCoverage.exerciseInternalSurface(
            address(entityRegistry),
            address(fuzzMarketFilter),
            USER1,
            USER2,
            emptyFilterAddresses,
            filterAddresses,
            batch
        );

        _warmOrderbookValidationResidualCoverage(emptyFilterAddresses, filterAddresses);
        _warmMarketplaceEscrowResidualCoverage();
    }

    function _warmOrderbookValidationResidualCoverage(
        address[] memory emptyFilterAddresses,
        address[] memory filterAddresses
    ) internal {
        address[] memory largeFilterAddresses = new address[](51);
        for (uint256 i; i < largeFilterAddresses.length; ++i) {
            largeFilterAddresses[i] = USER1;
        }
        address[] memory zeroFilterAddresses = new address[](1);

        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateZeroAmount.selector),
            Errors.OrderbookMarketplace__ZeroAmount.selector,
            "OB-COV-ZERO-AMOUNT"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateZeroPrice.selector),
            Errors.OrderbookMarketplace__ZeroPrice.selector,
            "OB-COV-ZERO-PRICE"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateInvalidPriceRange.selector),
            Errors.OrderbookMarketplace__InvalidPriceRange.selector,
            "OB-COV-PRICE-RANGE"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateMinMatchExceedsTotal.selector),
            Errors.OrderbookMarketplace__MinAmountExceedsTotal.selector,
            "OB-COV-MIN-MATCH"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateTraderFilterNotEmpty.selector, filterAddresses),
            Errors.OrderbookMarketplace__TradeFilterNotEmpty.selector,
            "OB-COV-FILTER-NOT-EMPTY"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedValidateTraderFilterEmpty.selector, emptyFilterAddresses),
            Errors.OrderbookMarketplace__TradeFilterEmpty.selector,
            "OB-COV-FILTER-EMPTY"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(
                orderbookCoverage.exposedValidateTraderFilterTooLarge.selector, largeFilterAddresses
            ),
            Errors.OrderbookMarketplace__TraderFilterTooLarge.selector,
            "OB-COV-FILTER-LARGE"
        );
        _expectCoverageRevert(
            address(orderbookCoverage),
            abi.encodeWithSelector(orderbookCoverage.exposedStoreZeroTraderFilter.selector, zeroFilterAddresses),
            Errors.ZeroAddress.selector,
            "OB-COV-FILTER-ZERO"
        );
        fl.eq(orderbookCoverage.exposedBlacklistTraderAllowed(USER2), true, "OB-COV-BLACKLIST-RETURN");
        fl.eq(orderbookCoverage.exposedMatchSellZeroBreak(USER1, USER2), 0, "OB-COV-MATCH-SELL-ZERO");
    }

    function _warmMarketplaceEscrowResidualCoverage() internal {
        uint256 erc721TokenId = ++fuzzERC721TokenCursor;
        fuzzERC721.mint(address(escrowManagerCoverage), erc721TokenId);
        fl.eq(
            escrowManagerCoverage.exposedBalanceHeldERC721(address(fuzzERC721), erc721TokenId),
            1,
            "ESCR-COV-ERC721-BALANCE"
        );
        escrowManagerCoverage.exposedTransferERC721(address(fuzzERC721), erc721TokenId, USER3);

        _expectCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidCancellationSaleMode.selector),
            PANIC_SELECTOR,
            "MKT-COV-CANCEL-SALEMODE"
        );
        _expectCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidPaymentExpirySaleMode.selector),
            Errors.Marketplace__InvalidSaleMode.selector,
            "MKT-COV-PAYMENT-SALEMODE"
        );
        _expectCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedInvalidInterestStatus.selector),
            Errors.Marketplace__InvalidInterestStatus.selector,
            "MKT-COV-INTEREST-STATUS"
        );
        _expectCoverageRevert(
            address(marketplaceCoverage),
            abi.encodeWithSelector(marketplaceCoverage.exposedValidateMarketplaceSaleMode.selector),
            Errors.Marketplace__NotMarketplaceOffer.selector,
            "MKT-COV-MARKETPLACE-MODE"
        );
        _expectCoverageRevert(
            address(escrowManagerCoverage),
            abi.encodeWithSelector(escrowManagerCoverage.exposedInvalidTransferAsset.selector, address(fuzzERC20)),
            Errors.EscrowManager__InvalidAssetType.selector,
            "ESCR-COV-INVALID-TRANSFER"
        );
        _expectCoverageRevert(
            address(escrowManagerCoverage),
            abi.encodeWithSelector(escrowManagerCoverage.exposedInvalidBalanceHeld.selector, address(fuzzERC20)),
            Errors.EscrowManager__InvalidAssetType.selector,
            "ESCR-COV-INVALID-BALANCE"
        );
    }

    /* solhint-disable avoid-low-level-calls */
    function _expectCoverageRevert(
        address target,
        bytes memory callData,
        bytes4 expectedSelector,
        string memory context
    ) internal {
        (bool success, bytes memory returnData) = target.call(callData);
        fl.eq(success, false, context);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(_coverageReturnSelector(returnData), allowedErrors, context);
    }
    /* solhint-enable avoid-low-level-calls */

    function _coverageReturnSelector(bytes memory returnData) internal pure returns (bytes4 errorSelector) {
        if (returnData.length > 3) {
            errorSelector = bytes4(returnData);
        }
    }

    function _defineEntityTypes() internal {
        fl.log("Defining entity types");

        // forge-lint: disable-next-line(unsafe-typecast)
        entityRegistry.defineEntityType(BROKER_ENTITY, bytes32("BROKER"), 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        entityRegistry.defineEntityType(NATURAL_PERSON_ENTITY, bytes32("NATURAL_PERSON"), 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        entityRegistry.defineEntityType(DEUSS_PROTOCOL_ENTITY, bytes32("DEUSS_PROTOCOL"), 0);
    }

    function _registerCoreWallets() internal {
        fl.log("Registering core wallets");

        _registerEntityAccount(address(this), DEUSS_PROTOCOL_ENTITY);
        _registerEntityAccount(address(escrowManager), DEUSS_PROTOCOL_ENTITY);
        _registerEntityAccount(FUZZ_WALLET_7, BROKER_ENTITY);
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTORS
    //////////////////////////////////////////////////////////////*/

    function _registerUsers() internal {
        fl.log("Registering users");

        for (uint256 i; i < users.length; ++i) {
            _registerEntityAccount(users[i], BROKER_ENTITY);
        }
    }

    function _setIssuer() internal {
        issuer = users[0];
    }

    function _publishAndIssueBond() internal {
        uint256[] memory paymentTimestamps = new uint256[](2);
        uint256[] memory rates = new uint256[](2);
        paymentTimestamps[0] = block.timestamp;
        paymentTimestamps[1] = block.timestamp + 365 days;
        rates[0] = BOND_COUPON_RATE;
        rates[1] = 0;

        BondInput memory bondInput = BondInput({
            isin: BOND_ISIN,
            issuer: issuer,
            currency: BOND_CURRENCY,
            bondNominalValue: BOND_NOMINAL_VALUE,
            maxSupply: BOND_ISSUE_COUNT,
            couponRates: CouponRates(paymentTimestamps, rates),
            couponRateType: BOND_COUPON_RATE_TYPE,
            maturityDate: block.timestamp + 365 days,
            couponFrequency: BOND_COUPON_FREQUENCY,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });

        bondRegistry.publishBond(bondInput);
        bondRegistry.issueBond(BOND_ISIN, 1, BOND_ISSUE_COUNT);
        _trackBondVersion(1);

        bondTokenId = bondRegistry.getTokenId(BOND_ISIN);
        initialIssuedSupply = token.totalSupply(bondTokenId);
    }

    function _approveEscrowForUsers() internal {
        for (uint256 i; i < users.length; ++i) {
            vm.prank(users[i]);
            bool success = token.setOperator(address(escrowManager), true);
            fl.eq(success, true, "Error approving escrow for user");
        }
    }

    function _seedAssetManagerPool() internal {
        fl.log("Seeding AssetManager fuzz token pool");

        // Synthetic addresses disjoint from `address(token)`. AssetManager never interacts
        // with the underlying tokens during setAsset/setAssetTokenId, so non-contract
        // addresses are fine. Keeping the real token out of this pool guarantees the
        // Marketplace slice remains stable under AssetManager fuzzing.
        knownAssetTokens.push(FUZZ_ASSET_TOKEN_1);
        knownAssetTokens.push(FUZZ_ASSET_TOKEN_2);
        knownAssetTokens.push(FUZZ_ASSET_TOKEN_3);
        knownAssetTokens.push(FUZZ_ASSET_TOKEN_4);

        for (uint256 i; i < FUZZ_ASSET_TOKEN_IDS_COUNT; ++i) {
            knownAssetTokenIds.push(i);
        }

        _seedEscrowAuthPool();
    }

    function _seedEscrowAuthPool() internal {
        fl.log("Seeding EscrowManager fuzz module pool");

        // Module address pool (disjoint from real Marketplace/OB addresses).
        knownEscrowModules.push(FUZZ_ESCROW_MODULE_1);
        knownEscrowModules.push(FUZZ_ESCROW_MODULE_2);
        knownEscrowModules.push(FUZZ_ESCROW_MODULE_3);
        knownEscrowModules.push(FUZZ_ESCROW_MODULE_4);

        // Module type pool. Index 0 is `bytes32(0)` so the InvalidModuleType branch is hit
        // naturally by the same modulo-based seed picker. The synthetic types are distinct
        // from the real MARKETPLACE_MODULE / ORDERBOOK_MARKETPLACE_MODULE hashes so
        // fuzz-registered modules can never be authorized for real escrows.
        knownEscrowModuleTypes.push(bytes32(0));
        knownEscrowModuleTypes.push(FUZZ_MODULE_TYPE_A);
        knownEscrowModuleTypes.push(FUZZ_MODULE_TYPE_B);
        knownEscrowModuleTypes.push(FUZZ_MODULE_TYPE_C);
    }

    function _registerEntityAccount(address wallet, uint256 typeId) internal {
        fl.log("Registering entity wallet");

        bytes32 entityId = keccak256(abi.encodePacked(wallet, entityNonce));
        ++entityNonce;

        entityRegistry.registerEntity(entityId, typeId, EMPTY_METADATA_REF);
        entityRegistry.registerAccount(wallet, entityId, ROLE_FLAGS_EMPTY);

        // Populate the ER tracking set so later fuzz handlers can discover and
        // target entities and accounts that were created during setup.
        _trackEntityId(entityId);
    }

    /*//////////////////////////////////////////////////////////////
                         ENTITY REGISTRY WARMUP
    //////////////////////////////////////////////////////////////*/

    function _warmEntityRegistry() internal {
        _warmEntityRegistryCoverageType();
        _warmEntityRegistryAccessEntity();
        _warmEntityRegistryBatchEntities();
        _warmEntityRegistryAuthorityAndMetadata();
        _warmEntityRegistryViewSurface();
        _warmEntityRegistryRolesAndAccounts();
    }

    function _warmEntityRegistryCoverageType() internal {
        entityRegistry.defineEntityType(
            FUZZ_ER_COVERAGE_TYPE_ID, FUZZ_ER_COVERAGE_TYPE_NAME, FUZZ_ER_COVERAGE_TYPE_CAPS
        );
        entityRegistry.getEntityTypeMeta(FUZZ_ER_COVERAGE_TYPE_ID);
        entityRegistry.freezeEntityType(FUZZ_ER_COVERAGE_TYPE_ID);
    }

    function _warmEntityRegistryAccessEntity() internal {
        entityRegistry.registerEntity(
            FUZZ_ER_ACCESS_ENTITY_ID, BROKER_ENTITY, EMPTY_METADATA_REF, FUZZ_ER_AUTHORITY_A, _entityRegistryManagers()
        );
    }

    function _warmEntityRegistryBatchEntities() internal {
        entityRegistry.registerEntityBatch(
            _entityRegistryBatchEntityIds(), _entityRegistryBatchTypeIds(), _entityRegistryBatchMetadataRefs()
        );
    }

    function _warmEntityRegistryAuthorityAndMetadata() internal {
        entityRegistry.setEntityMetadata(FUZZ_ER_ACCESS_ENTITY_ID, FUZZ_ER_ACCESS_METADATA_REF);
        entityRegistry.setEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID, FUZZ_ER_AUTHORITY_B);

        vm.prank(FUZZ_ER_AUTHORITY_B);
        entityRegistry.setEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID, FUZZ_ER_AUTHORITY_C);
    }

    function _warmEntityRegistryViewSurface() internal {
        entityRegistry.setAccountRoleFlags(USER1, FUZZ_ER_USER_ROLE_FLAGS);
        entityRegistry.getEntityMetadataRef(FUZZ_ER_ACCESS_ENTITY_ID);
        entityRegistry.getEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID);
        entityRegistry.getEntityTypeMeta(FUZZ_ER_COVERAGE_TYPE_ID);
        entityRegistry.getEntityTypeId(FUZZ_ER_ACCESS_ENTITY_ID);

        entityRegistry.supportsInterface(type(IEntityRegistry).interfaceId);
        entityRegistry.supportsInterface(type(IERC165).interfaceId);
        entityRegistry.supportsInterface(ERC165_INVALID_INTERFACE_ID);
        entityRegistry.canApprove(address(0), USER1, 0, 0);
        entityRegistry.canTransfer(USER1, address(0), USER1, 0, 0);
    }

    function _warmEntityRegistryRolesAndAccounts() internal {
        address[] memory roleGrantees = new address[](2);
        roleGrantees[0] = FUZZ_ER_AUTHORITY_C;
        roleGrantees[1] = FUZZ_ER_ACCOUNT_A;
        entityRegistry.grantRoles(roleGrantees, entityRegistry.GUARD());

        entityRegistry.registerAccount(FUZZ_ER_ACCOUNT_A, FUZZ_ER_BATCH_ENTITY_ID_A, ROLE_FLAGS_EMPTY);
        entityRegistry.registerAccount(FUZZ_ER_ACCOUNT_B, FUZZ_ER_BATCH_ENTITY_ID_A, ROLE_FLAGS_EMPTY);
        entityRegistry.transferAccountToEntity(FUZZ_ER_ACCOUNT_A, FUZZ_ER_BATCH_ENTITY_ID_B);
    }

    function _entityRegistryManagers() internal pure returns (address[] memory managers) {
        managers = new address[](2);
        managers[0] = FUZZ_ER_MANAGER_A;
        managers[1] = FUZZ_ER_MANAGER_B;
    }

    function _entityRegistryBatchEntityIds() internal pure returns (bytes32[] memory entityIds) {
        entityIds = new bytes32[](2);
        entityIds[0] = FUZZ_ER_BATCH_ENTITY_ID_A;
        entityIds[1] = FUZZ_ER_BATCH_ENTITY_ID_B;
    }

    function _entityRegistryBatchTypeIds() internal pure returns (uint256[] memory typeIds) {
        typeIds = new uint256[](2);
        typeIds[0] = NATURAL_PERSON_ENTITY;
        typeIds[1] = DEUSS_PROTOCOL_ENTITY;
    }

    function _entityRegistryBatchMetadataRefs() internal pure returns (string[] memory metadataRefs) {
        metadataRefs = new string[](2);
        metadataRefs[0] = FUZZ_ER_BATCH_METADATA_REF_A;
        metadataRefs[1] = FUZZ_ER_BATCH_METADATA_REF_B;
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateProtocolAddresses() internal {
        fl.log("Validating protocol addresses");

        fl.eq(address(bondRegistry) == address(0), false, "Error creating BondRegistry - address(0)");
        fl.eq(address(entityRegistry) == address(0), false, "Error creating EntityRegistry - address(0)");
        fl.eq(address(policyRegistry) == address(0), false, "Error creating PolicyRegistry - address(0)");
        fl.eq(address(token) == address(0), false, "Error creating DEUSSToken - address(0)");
        fl.eq(address(assetManager) == address(0), false, "Error creating AssetManager - address(0)");
        fl.eq(address(marketplace) == address(0), false, "Error creating Marketplace - address(0)");
        fl.eq(address(orderbookMarketplace) == address(0), false, "Error creating OrderbookMarketplace - address(0)");
        fl.eq(address(escrowManager) == address(0), false, "Error creating EscrowManager - address(0)");
        fl.eq(address(policyWalletA) == address(0), false, "Error creating PolicyWalletA - address(0)");
        fl.eq(address(policyWalletB) == address(0), false, "Error creating PolicyWalletB - address(0)");
        fl.eq(address(policyEpochWallet) == address(0), false, "Error creating PolicyEpochWallet - address(0)");
        fl.eq(address(walletEpochA) == address(0), false, "Error creating WalletEpochA - address(0)");
        fl.eq(address(walletEpochB) == address(0), false, "Error creating WalletEpochB - address(0)");
        fl.eq(address(policyTarget) == address(0), false, "Error creating PolicyTarget - address(0)");
        fl.eq(address(timelock) == address(0), false, "Error creating TimelockController - address(0)");
    }

    function _validateOwnershipAndRoles() internal {
        fl.log("Validating ownership and roles");

        fl.eq(bondRegistry.owner(), governance, "Error setting BondRegistry owner");
        fl.eq(entityRegistry.owner(), governance, "Error setting EntityRegistry owner");
        fl.eq(policyRegistry.owner(), governance, "Error setting PolicyRegistry owner");
        fl.eq(token.owner(), governance, "Error setting DEUSSToken owner");
        fl.eq(assetManager.owner(), governance, "Error setting AssetManager owner");
        fl.eq(marketplace.owner(), governance, "Error setting Marketplace owner");
        fl.eq(orderbookMarketplace.owner(), governance, "Error setting OrderbookMarketplace owner");
        fl.eq(escrowManager.owner(), governance, "Error setting EscrowManager owner");

        fl.eq(
            entityRegistry.hasAllRoles(address(this), entityRegistry.ALL_ROLES()),
            true,
            "Error granting EntityRegistry roles"
        );
        fl.eq(
            bondRegistry.hasAllRoles(address(this), bondRegistry.ALL_BR_ROLES()),
            true,
            "Error granting BondRegistry roles"
        );
        fl.eq(token.hasAllRoles(address(this), token.ALL_ROLES()), true, "Error granting token roles");
        fl.eq(assetManager.hasAllRoles(address(this), assetManager.ADMIN()), true, "Error granting AssetManager roles");
        fl.eq(
            escrowManager.hasAllRoles(address(this), escrowManager.ADMIN()),
            true,
            "Error granting EscrowManager admin role"
        );
        fl.eq(
            orderbookMarketplace.hasAllRoles(
                address(this),
                orderbookMarketplace.ADMIN() | orderbookMarketplace.PAYMENT_HANDLER()
                    | orderbookMarketplace.ARBITRATOR() | orderbookMarketplace.SEIZURE_ROLE()
                    | orderbookMarketplace.FREEZE_ROLE()
            ),
            true,
            "Error granting OrderbookMarketplace roles"
        );
        fl.eq(
            bondMarketFilter.hasAllRoles(address(this), bondMarketFilter.ADMIN()),
            true,
            "Error granting BondMarketFilter admin"
        );
        fl.eq(
            marketplace.hasAllRoles(
                address(this),
                marketplace.ADMIN() | marketplace.PAYMENT_HANDLER() | marketplace.ARBITRATOR()
                    | marketplace.SEIZURE_ROLE() | marketplace.FREEZE_ROLE() | marketplace.INTEREST_DISCOVERY_OPERATOR()
            ),
            true,
            "Error granting Marketplace roles"
        );
        fl.eq(
            marketplace.hasAllRoles(FUZZ_PAYMENT_UNAUTH_CALLER, marketplace.PAYMENT_HANDLER()),
            false,
            "Error keeping fuzz unauthorized payment caller unprivileged"
        );
        for (uint256 i; i < users.length; ++i) {
            fl.eq(
                marketplace.hasAllRoles(users[i], marketplace.PAYMENT_HANDLER()),
                false,
                "Error keeping fuzz users outside Marketplace payment handler role"
            );
        }
    }

    function _validateCoreWiring() internal {
        fl.log("Validating core wiring");

        fl.eq(address(token.bondRegistry()), address(bondRegistry), "Error wiring token to BondRegistry");
        fl.eq(address(token.entityRegistry()), address(entityRegistry), "Error wiring token to EntityRegistry");
        fl.eq(bondRegistry.getToken(), address(token), "Error wiring BondRegistry to token");
        fl.eq(escrowManager.assetManager(), address(assetManager), "Error wiring EscrowManager asset manager");
        fl.eq(marketplace.getEscrowManager(), address(escrowManager), "Error wiring Marketplace escrow");
        fl.eq(marketplace.getEntityRegistry(), address(entityRegistry), "Error wiring Marketplace entity registry");
        fl.eq(
            orderbookMarketplace.assetManager(),
            address(assetManager),
            "Error wiring OrderbookMarketplace asset manager"
        );
        fl.eq(
            orderbookMarketplace.entityRegistry(),
            address(entityRegistry),
            "Error wiring OrderbookMarketplace entity registry"
        );
        fl.eq(orderbookMarketplace.escrowManager(), address(escrowManager), "Error wiring OrderbookMarketplace escrow");
        fl.eq(policyWalletA.owner(), POLICY_WALLET_OWNER_A, "Error setting PolicyWalletA owner");
        fl.eq(policyWalletB.owner(), POLICY_WALLET_OWNER_B, "Error setting PolicyWalletB owner");
        fl.eq(policyWalletA.policyRegistry(), address(policyRegistry), "Error wiring PolicyWalletA policy registry");
        fl.eq(policyWalletB.policyRegistry(), address(policyRegistry), "Error wiring PolicyWalletB policy registry");
        fl.eq(policyEpochWallet.owner(), POLICY_EPOCH_WALLET_OWNER_A, "Error setting PolicyEpochWallet owner");
        fl.eq(
            policyEpochWallet.policyRegistry(),
            address(policyRegistry),
            "Error wiring PolicyEpochWallet policy registry"
        );
        fl.eq(policyEpochWallet.ownershipEpoch(), 1, "Error initializing PolicyEpochWallet epoch");
        fl.eq(walletEpochA.owner(), WALLET_EPOCH_OWNER_A, "Error setting WalletEpochA owner");
        fl.eq(walletEpochB.owner(), WALLET_EPOCH_OWNER_B, "Error setting WalletEpochB owner");
        fl.eq(walletEpochA.policyRegistry(), address(policyRegistry), "Error wiring WalletEpochA policy registry");
        fl.eq(walletEpochB.policyRegistry(), address(policyRegistry), "Error wiring WalletEpochB policy registry");
        fl.eq(walletEpochA.ownershipEpoch(), 1, "Error initializing WalletEpochA epoch");
        fl.eq(walletEpochB.ownershipEpoch(), 1, "Error initializing WalletEpochB epoch");

        fl.eq(
            policyRegistry.isPolicyModuleAllowed(address(policyAllowModule)), true, "Error allowing policy allow module"
        );
        fl.eq(
            policyRegistry.isPolicyModuleAllowed(address(policyDenyModule)), true, "Error allowing policy deny module"
        );
        fl.eq(
            policyRegistry.isPolicyModuleAllowed(address(policyRevertingModule)),
            true,
            "Error allowing policy reverting module"
        );
        fl.eq(
            policyRegistry.isPolicyModuleAllowed(address(policyInvalidReturnModule)),
            true,
            "Error allowing policy invalid-return module"
        );
    }

    function _validateEscrowModules() internal {
        fl.log("Validating escrow modules");

        fl.eq(
            escrowManager.moduleTypeOf(address(marketplace)) == escrowManager.MARKETPLACE_MODULE(),
            true,
            "Error authorizing Marketplace module"
        );
        fl.eq(
            escrowManager.isAuthorizedModule(escrowManager.MARKETPLACE_MODULE(), address(marketplace)),
            true,
            "Error marking Marketplace as authorized escrow module"
        );
        fl.eq(
            escrowManager.moduleTypeOf(address(orderbookMarketplace)) == escrowManager.ORDERBOOK_MARKETPLACE_MODULE(),
            true,
            "Error authorizing OrderbookMarketplace module"
        );
        fl.eq(
            escrowManager.isAuthorizedModule(
                escrowManager.ORDERBOOK_MARKETPLACE_MODULE(), address(orderbookMarketplace)
            ),
            true,
            "Error marking OrderbookMarketplace as authorized escrow module"
        );
        fl.eq(escrowManager.nextEscrowId(), 0, "Error initializing EscrowManager with empty escrow set");
        fl.eq(
            escrowManager.moduleTypeOf(FUZZ_ESCROW_TEST_MODULE) == FUZZ_ESCROW_TEST_MODULE_TYPE,
            true,
            "Error authorizing fuzz test escrow module"
        );
        fl.eq(
            escrowManager.isAuthorizedModule(FUZZ_ESCROW_TEST_MODULE_TYPE, FUZZ_ESCROW_TEST_MODULE),
            true,
            "Error marking fuzz test module as authorized"
        );
        fl.eq(
            escrowManager.moduleTypeOf(FUZZ_ESCROW_UNAUTH_CALLER) == bytes32(0),
            true,
            "Error unauth caller must not be registered"
        );
    }

    function _validateMarketplaceConfiguration() internal {
        fl.log("Validating marketplace configuration");

        fl.eq(
            orderbookMarketplace.paymentExpiryThreshold(),
            ORDERBOOK_PAYMENT_EXPIRY_THRESHOLD,
            "Error setting OrderbookMarketplace payment expiry threshold"
        );
        fl.eq(
            orderbookMarketplace.minExpiryThreshold(),
            ORDERBOOK_MIN_EXPIRY_THRESHOLD,
            "Error setting OrderbookMarketplace min expiry threshold"
        );
        fl.eq(
            orderbookMarketplace.disputeBufferPeriod(),
            ORDERBOOK_DISPUTE_BUFFER_PERIOD,
            "Error setting OrderbookMarketplace dispute buffer period"
        );
        fl.eq(assetManager.isAssetSupported(address(token), bondTokenId), true, "Error configuring AssetManager token");
        fl.eq(assetManager.isAssetSupported(address(fuzzERC20), 0), true, "Error configuring fuzz ERC20");
        fl.eq(assetManager.isAssetSupported(address(fuzzERC721), 1), true, "Error configuring fuzz ERC721");
        fl.eq(assetManager.isAssetSupported(address(fuzzERC1155), 1), true, "Error configuring fuzz ERC1155");
        fl.eq(_getOfferCounter(), 0, "Error initializing offer counter");
        fl.eq(_getDealCounter(), 0, "Error initializing deal counter");
        fl.eq(_getDisputeBufferPeriod(), MARKETPLACE_DISPUTE_BUFFER_PERIOD, "Error setting dispute buffer period");
        fl.eq(
            _getMarketplacePaymentExpiryThreshold(),
            MARKETPLACE_PAYMENT_EXPIRY_THRESHOLD,
            "Error setting Marketplace payment expiry threshold"
        );
        fl.eq(
            _getRedemptionPaymentThreshold(),
            REDEMPTION_PAYMENT_EXPIRY_THRESHOLD,
            "Error setting Marketplace redemption payment expiry threshold"
        );
        fl.eq(
            _getInterestDiscoveryPaymentExpiryThreshold(),
            INTEREST_DISCOVERY_PAYMENT_EXPIRY_THRESHOLD,
            "Error setting Marketplace interest-discovery payment expiry threshold"
        );
        fl.eq(_getMaxCounterOffersPerUser(), MAX_COUNTER_OFFERS_PER_USER, "Error setting counter-offer cap");

        fl.eq(
            // forge-lint: disable-next-line(unsafe-typecast)
            marketplace.isCurrencyAllowed(bytes3(bytes(BOND_CURRENCY))),
            true,
            "Error configuring Marketplace currency whitelist"
        );
    }

    function _validateBondAndTokenState() internal {
        fl.log("Validating bond and token state");

        Bond memory bond = bondRegistry.getBond(BOND_ISIN);

        fl.eq(bondRegistry.isCurrencyAllowed(BOND_CURRENCY), true, "Error allowing BondRegistry currency");
        fl.eq(uint256(bondRegistry.bondStatus(BOND_ISIN)), uint256(BondStatus.Issued), "Error issuing bond");
        fl.eq(bondRegistry.getTokenId(BOND_ISIN), bondTokenId, "Error recording bond token id");
        fl.eq(bondRegistry.getLatestCouponRate(BOND_ISIN), BOND_COUPON_RATE, "Error storing coupon rate");
        fl.eq(bond.bondNominalValue, BOND_NOMINAL_VALUE, "Error storing bondNominalValue");
        fl.eq(bond.maxSupply, BOND_ISSUE_COUNT, "Error storing max supply");
        fl.eq(bond.mintedSupply, BOND_ISSUE_COUNT, "Error storing minted supply");
        fl.eq(bond.remainingIssuableSupply, 0, "Error storing remaining issuable supply");
        fl.eq(bond.tokenId, bondTokenId, "Error storing bond token id");
        fl.eq(bond.tokenAddress, address(token), "Error storing bond token address");
        fl.eq(bond.trancheCount, 1, "Error recording first issuance tranche");

        fl.eq(token.paused(), false, "Error unpausing token");
        fl.eq(token.isTokenPaused(bondTokenId), false, "Error unpausing bond token id");
        fl.eq(token.totalSupply(bondTokenId), initialIssuedSupply, "Error recording initial supply");
        fl.eq(initialIssuedSupply, BOND_ISSUE_COUNT, "Error issuing expected bond count");
        fl.eq(token.balanceOf(issuer, bondTokenId), initialIssuedSupply, "Error assigning issuer balance");
        fl.eq(token.balanceOf(address(escrowManager), bondTokenId), 0, "Error initializing escrow bond balance");
    }

    function _validateUserAndAccountState() internal {
        fl.log("Validating users and accounts");

        fl.eq(issuer, users[0], "Error assigning issuer user");

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            bytes32 entityId = entityRegistry.getEntityId(user);
            AccountStatus accountStatus = entityRegistry.getAccount(user).status;

            fl.eq(entityId == bytes32(0), false, "Error registering user entity id");
            fl.eq(accountStatus == AccountStatus.ENABLED, true, "Error enabling user account");
            fl.eq(entityRegistry.getEntityStatus(entityId) == EntityStatus.ENABLED, true, "Error enabling user entity");
            fl.eq(entityRegistry.getEntityTypeIdByAccount(user), BROKER_ENTITY, "Error assigning user entity type");
            fl.eq(token.isOperator(user, address(escrowManager)), true, "Error approving escrow operator for user");
        }

        _validateRegisteredAccount(address(this), DEUSS_PROTOCOL_ENTITY, "harness");
        _validateRegisteredAccount(address(escrowManager), DEUSS_PROTOCOL_ENTITY, "escrow manager");
    }

    function _validateRegisteredAccount(address account, uint256 expectedType, string memory label) internal {
        fl.log("Validating registered account");

        bytes32 entityId = entityRegistry.getEntityId(account);
        AccountStatus accountStatus = entityRegistry.getAccount(account).status;

        fl.eq(entityId == bytes32(0), false, string.concat("Error registering ", label, " entity id"));
        fl.eq(accountStatus == AccountStatus.ENABLED, true, string.concat("Error enabling ", label, " account"));
        fl.eq(
            entityRegistry.getEntityTypeIdByAccount(account),
            expectedType,
            string.concat("Error assigning ", label, " entity type")
        );
    }

    function _validateEntityRegistryWarmup() internal {
        fl.log("Validating EntityRegistry warmup");

        _validateEntityRegistryCoverageTypeWarmup();
        _validateEntityRegistryAccessWarmup();
        _validateEntityRegistryBatchWarmup();
        _validateEntityRegistryAccountWarmup();
    }

    function _validateEntityRegistryCoverageTypeWarmup() internal {
        EntityTypeMeta memory coverageMeta = entityRegistry.getEntityTypeMeta(FUZZ_ER_COVERAGE_TYPE_ID);
        fl.eq(
            uint256(coverageMeta.name),
            uint256(FUZZ_ER_COVERAGE_TYPE_NAME),
            "Error warming EntityRegistry coverage type name"
        );
        fl.eq(coverageMeta.caps, FUZZ_ER_COVERAGE_TYPE_CAPS, "Error warming EntityRegistry coverage type caps");
        fl.eq(coverageMeta.frozen, true, "Error freezing EntityRegistry coverage type");
    }

    function _validateEntityRegistryAccessWarmup() internal {
        fl.eq(
            uint256(entityRegistry.getEntityStatus(FUZZ_ER_ACCESS_ENTITY_ID)),
            uint256(EntityStatus.ENABLED),
            "Error warming EntityRegistry access entity status"
        );
        fl.eq(
            entityRegistry.getEntityTypeId(FUZZ_ER_ACCESS_ENTITY_ID),
            BROKER_ENTITY,
            "Error warming EntityRegistry access entity type"
        );
        fl.eq(
            uint256(keccak256(bytes(entityRegistry.getEntityMetadataRef(FUZZ_ER_ACCESS_ENTITY_ID)))),
            uint256(keccak256(bytes(FUZZ_ER_ACCESS_METADATA_REF))),
            "Error warming EntityRegistry access metadata"
        );
        fl.eq(
            entityRegistry.getEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID),
            FUZZ_ER_AUTHORITY_C,
            "Error warming EntityRegistry access authority"
        );
        fl.eq(
            entityRegistry.isEntityManager(FUZZ_ER_ACCESS_ENTITY_ID, FUZZ_ER_MANAGER_A),
            true,
            "Error warming EntityRegistry manager A"
        );
        fl.eq(
            entityRegistry.isEntityManager(FUZZ_ER_ACCESS_ENTITY_ID, FUZZ_ER_MANAGER_B),
            true,
            "Error warming EntityRegistry manager B"
        );
    }

    function _validateEntityRegistryBatchWarmup() internal {
        fl.eq(
            entityRegistry.getEntityTypeId(FUZZ_ER_BATCH_ENTITY_ID_A),
            NATURAL_PERSON_ENTITY,
            "Error warming EntityRegistry batch entity A type"
        );
        fl.eq(
            entityRegistry.getEntityTypeId(FUZZ_ER_BATCH_ENTITY_ID_B),
            DEUSS_PROTOCOL_ENTITY,
            "Error warming EntityRegistry batch entity B type"
        );
        fl.eq(
            uint256(keccak256(bytes(entityRegistry.getEntityMetadataRef(FUZZ_ER_BATCH_ENTITY_ID_A)))),
            uint256(keccak256(bytes(FUZZ_ER_BATCH_METADATA_REF_A))),
            "Error warming EntityRegistry batch entity A metadata"
        );
        fl.eq(
            uint256(keccak256(bytes(entityRegistry.getEntityMetadataRef(FUZZ_ER_BATCH_ENTITY_ID_B)))),
            uint256(keccak256(bytes(FUZZ_ER_BATCH_METADATA_REF_B))),
            "Error warming EntityRegistry batch entity B metadata"
        );
    }

    function _validateEntityRegistryAccountWarmup() internal {
        fl.eq(
            entityRegistry.getEntityId(FUZZ_ER_ACCOUNT_A) == FUZZ_ER_BATCH_ENTITY_ID_B,
            true,
            "Error warming EntityRegistry account A transfer"
        );
        fl.eq(
            entityRegistry.getEntityId(FUZZ_ER_ACCOUNT_B) == FUZZ_ER_BATCH_ENTITY_ID_A,
            true,
            "Error warming EntityRegistry account B registration"
        );
        fl.eq(
            entityRegistry.getAccount(FUZZ_ER_ACCOUNT_A).status == AccountStatus.ENABLED,
            true,
            "Error warming EntityRegistry account A status"
        );
        fl.eq(
            entityRegistry.getAccount(FUZZ_ER_ACCOUNT_B).status == AccountStatus.ENABLED,
            true,
            "Error warming EntityRegistry account B status"
        );
        fl.eq(
            entityRegistry.getAccount(USER1).roleFlags,
            FUZZ_ER_USER_ROLE_FLAGS,
            "Error warming EntityRegistry role flags"
        );
        fl.eq(
            entityRegistry.hasAllRoles(FUZZ_ER_AUTHORITY_C, entityRegistry.GUARD()),
            true,
            "Error warming EntityRegistry authority guard role"
        );
        fl.eq(
            entityRegistry.hasAllRoles(FUZZ_ER_ACCOUNT_A, entityRegistry.GUARD()),
            true,
            "Error warming EntityRegistry account guard role"
        );
    }

    function _validateEntityRegistrySameAuthorityReverts() internal {
        address currentAuthority = entityRegistry.getEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID);
        bool revertedWithExpectedError;

        try entityRegistry.setEntityAuthority(FUZZ_ER_ACCESS_ENTITY_ID, currentAuthority) {
            revertedWithExpectedError = false;
        } catch (bytes memory returnData) {
            revertedWithExpectedError = bytes4(returnData) == Errors.ER__EntityAuthorityAlreadySet.selector;
        }

        fl.eq(revertedWithExpectedError, true, "Error validating EntityRegistry same authority revert");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Suite} from "../DeployTypes.sol";
import {DeploymentArtifacts} from "../lib/DeploymentArtifacts.s.sol";
import {BondInput, CouponFrequency, CouponRates, CouponRateType} from "src/registry/BondStructs.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {DealStatus, OfferInput, SaleMode} from "src/marketplace/MarketStructs.sol";
import {VmSafe} from "forge-std/Vm.sol";

struct MockBondData {
    BondInput bondInput;
    bool canceled;
    uint256 issuerIndex;
}

struct MockMarketDeal {
    uint256 amount;
    DealStatus targetStatus;
    uint256 buyerIndex;
}

struct MockMarketData {
    uint256 bondIndex;
    string isin;
    OfferInput offerInput;
    MockMarketDeal[] deals;
}

error BaseMockData__InvalidIssuerIndex(uint256 issuerIndex);
error BaseMockData__InvalidBuyerIndex(uint256 buyerIndex);

/**
 * @title BaseMockData
 * @author DEUSS Team
 * @notice Base script utilities and mock data for deployment/testing
 */
abstract contract BaseMockData is DeploymentArtifacts {
    uint16 internal constant _DEFAULT_ISSUANCE_COUNTRY = 703;
    uint256 internal constant _DEMO_BUYER_COUNT = 3;

    // solhint-disable function-max-lines
    VmSafe.Wallet[] internal _bondIssuers;
    VmSafe.Wallet[] internal _bondBuyers;
    VmSafe.Wallet internal _admin;

    MockBondData[] internal _bondsToDeploy;
    MockMarketData[] internal _marketData;
    Suite internal _suite;
    address[] internal _bondIssuerWallets;
    address[] internal _bondBuyerWallets;

    /**
     * @notice Initialize wallets and in-memory mock data
     */
    function setUp() public {
        _admin = vm.createWallet(_activeNetworkConfig.adminKey);
        _suite = _loadSuiteFromManifest();
        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "XS1234567890",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 1000000,
                    couponRates: _createCouponRates(2, 700),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Monthly,
                    isGuaranteed: true,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 0
            })
        );
        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "XS0987654321",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1000,
                    maxSupply: 2000,
                    couponRates: _createFloatingCouponRates(3, 800),
                    couponRateType: CouponRateType.FLOATING,
                    maturityDate: block.timestamp + 730 days,
                    couponFrequency: CouponFrequency.SemiAnnual,
                    isGuaranteed: true,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: true,
                issuerIndex: 1
            })
        );
        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "DE1234567891",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 3000000,
                    couponRates: _createCouponRates(2, 500),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Quarterly,
                    isGuaranteed: true,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 2
            })
        );
        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "CZ1234567892",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 500000,
                    couponRates: _createCouponRates(2, 900),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Annual,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 3
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "SK1234567893",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 600000,
                    couponRates: _createCouponRates(2, 1100),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Daily,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 4
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "FR1234567894",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 700000,
                    couponRates: _createCouponRates(2, 1200),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Monthly,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 5
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "XS1234567895",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 800000,
                    couponRates: _createCouponRates(2, 900),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.SemiAnnual,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 6
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "CZ1234567896",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 900000,
                    couponRates: _createCouponRates(2, 1000),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Monthly,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 7
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "PL1234567897",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 1000000,
                    couponRates: _createCouponRates(2, 1200),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Annual,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 8
            })
        );

        _bondsToDeploy.push(
            MockBondData({
                bondInput: BondInput({
                    isin: "SP1234567898",
                    issuer: address(0),
                    currency: "EUR",
                    bondNominalValue: 1,
                    maxSupply: 1100000,
                    couponRates: _createCouponRates(2, 850),
                    couponRateType: CouponRateType.FIXED,
                    maturityDate: block.timestamp + 365 days,
                    couponFrequency: CouponFrequency.Quarterly,
                    isGuaranteed: false,
                    issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
                }),
                canceled: false,
                issuerIndex: 9
            })
        );
        _setWallets();
        _fundWallets();
        _setLabels();
        _marketData.push();
        uint256 index = _marketData.length - 1;
        _marketData[index].bondIndex = 0;
        _marketData[index].isin = _bondsToDeploy[0].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 1000000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PENDING, buyerIndex: 0}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PAID, buyerIndex: 1}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.SUCCESSFUL, buyerIndex: 2}));
        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 2;
        _marketData[index].isin = _bondsToDeploy[2].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 1000000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PENDING, buyerIndex: 1}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PAID, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.SUCCESSFUL, buyerIndex: 0}));
        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 3;
        _marketData[index].isin = _bondsToDeploy[3].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 500000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PENDING, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 50, targetStatus: DealStatus.PAID, buyerIndex: 0}));
        _marketData[index].deals.push(MockMarketDeal({amount: 50, targetStatus: DealStatus.SUCCESSFUL, buyerIndex: 1}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 4;
        _marketData[index].isin = _bondsToDeploy[4].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 600000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 150, targetStatus: DealStatus.PENDING, buyerIndex: 0}));
        _marketData[index].deals.push(MockMarketDeal({amount: 150, targetStatus: DealStatus.PAID, buyerIndex: 1}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 5;
        _marketData[index].isin = _bondsToDeploy[5].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 700000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 200, targetStatus: DealStatus.PENDING, buyerIndex: 1}));
        _marketData[index].deals.push(MockMarketDeal({amount: 200, targetStatus: DealStatus.PAID, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 200, targetStatus: DealStatus.SUCCESSFUL, buyerIndex: 0}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 6;
        _marketData[index].isin = _bondsToDeploy[6].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 800000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 300, targetStatus: DealStatus.PENDING, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 300, targetStatus: DealStatus.PAID, buyerIndex: 0}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 7;
        _marketData[index].isin = _bondsToDeploy[7].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 900000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 400, targetStatus: DealStatus.PENDING, buyerIndex: 0}));
        _marketData[index].deals.push(MockMarketDeal({amount: 400, targetStatus: DealStatus.PAID, buyerIndex: 1}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 8;
        _marketData[index].isin = _bondsToDeploy[8].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 1000000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PENDING, buyerIndex: 1}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.PAID, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 100, targetStatus: DealStatus.SUCCESSFUL, buyerIndex: 0}));

        _marketData.push();
        index = _marketData.length - 1;
        _marketData[index].bondIndex = 9;
        _marketData[index].isin = _bondsToDeploy[9].bondInput.isin;
        _marketData[index].offerInput = OfferInput({
            tokenAddress: _suite.multiToken.deussToken,
            tokenId: 0,
            totalAmount: 1100000,
            lot: 10,
            unitPrice: 100,
            // forge-lint: disable-next-line(unsafe-typecast)
            currency: bytes3("EUR"),
            expiry: block.timestamp + 30 days,
            allowCounterOffers: true,
            allowedBuyers: new address[](0),
            saleMode: SaleMode.MARKETPLACE,
            minSaleUnits: 0
        });
        _marketData[index].deals.push(MockMarketDeal({amount: 600, targetStatus: DealStatus.PENDING, buyerIndex: 2}));
        _marketData[index].deals.push(MockMarketDeal({amount: 600, targetStatus: DealStatus.PAID, buyerIndex: 0}));
    }

    /**
     * @notice Execute the mock data script
     */
    function run() public virtual;

    /**
     * @notice Initialize deterministic issuer and buyer wallets for the active environment
     */
    function _setWallets() internal {
        string memory env = _walletEnvironmentPrefix();

        for (uint256 i; i < _bondsToDeploy.length; ++i) {
            _bondIssuers.push(
                vm.createWallet(uint256(keccak256(bytes(_indexedWalletSeed(env, "company-wallet-owner", i)))))
            );
        }

        for (uint256 i; i < _DEMO_BUYER_COUNT; ++i) {
            _bondBuyers.push(vm.createWallet(uint256(keccak256(bytes(_indexedWalletSeed(env, "bond-buyer", i))))));
        }
    }

    /**
     * @notice Fund issuer and buyer wallets with native gas token
     */
    function _fundWallets() internal {
        vm.startBroadcast(_admin.privateKey);
        for (uint256 i; i < _bondIssuers.length; ++i) {
            payable(_bondIssuers[i].addr).transfer(0.0001 ether);
        }
        for (uint256 i; i < _bondBuyers.length; ++i) {
            payable(_bondBuyers[i].addr).transfer(0.0001 ether);
        }
        vm.stopBroadcast();
    }

    /**
     * @notice Label key addresses to improve trace readability
     */
    function _setLabels() internal {
        for (uint256 i; i < _bondIssuers.length; ++i) {
            vm.label(_bondIssuers[i].addr, string.concat("CompanyWalletOwner", vm.toString(i)));
        }
        for (uint256 i; i < _bondBuyers.length; ++i) {
            vm.label(_bondBuyers[i].addr, string.concat("BondBuyer", vm.toString(i)));
        }
        vm.label(_suite.core.escrowManager, "EscrowManager");
        vm.label(_suite.core.marketplace, "Marketplace");
        vm.label(_suite.core.assetManager, "AssetManager");
        vm.label(_suite.registries.entityRegistry, "EntityRegistry");
        vm.label(_suite.registries.bondRegistry, "BondRegistry");
        vm.label(_suite.multiToken.deussToken, "DEUSSToken");
        vm.label(_suite.utils.multicall, "MultiCall");
        vm.label(_suite.utils.marketplaceLens, "MarketplaceLens");
    }

    /**
     * @notice Return the deterministic wallet seed prefix for the active deployment environment.
     * @return env Wallet seed environment prefix
     */
    function _walletEnvironmentPrefix() internal view returns (string memory env) {
        if (keccak256(bytes(_activeNetworkConfig.env)) == keccak256(bytes("dev"))) {
            return "dev";
        }
        if (keccak256(bytes(_activeNetworkConfig.env)) == keccak256(bytes("demo"))) {
            return "demo";
        }
        return "test";
    }

    /**
     * @notice Build a backwards-compatible deterministic seed for indexed mock wallets.
     * @param env Wallet seed environment prefix
     * @param label Wallet role label
     * @param index Wallet index
     * @return seed Deterministic seed string
     */
    function _indexedWalletSeed(string memory env, string memory label, uint256 index)
        internal
        view
        returns (string memory seed)
    {
        if (index == 0) {
            return string.concat(env, "-", label);
        }
        return string.concat(env, "-", label, "-", vm.toString(index));
    }

    /**
     * @notice Return the first company wallet linked to the owner's default mock entity
     * @param owner Wallet owner address
     * @return companyWallet Registered company wallet address
     */
    function _getCompanyWallet(address owner) internal view returns (address) {
        bytes32 entityId = keccak256(abi.encodePacked(owner, "company-entity"));
        address[] memory wallets = EntityRegistry(_suite.registries.entityRegistry).getEntityAccounts(entityId);
        return wallets[0];
    }

    /**
     * @notice Build coupon rates with a terminal zero-rate entry
     * @param length Number of timestamp checkpoints to generate
     * @param rate Coupon rate applied to all non-terminal intervals
     * @return couponRates Generated coupon rates struct
     */
    function _createCouponRates(uint256 length, uint256 rate) internal view returns (CouponRates memory) {
        uint256[] memory paymentTimestamps = new uint256[](length);
        uint256[] memory rates = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            paymentTimestamps[i] = block.timestamp + (i * 365 days);

            if (i == length - 1) {
                rates[i] = 0;
            } else {
                rates[i] = rate;
            }
        }

        return CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});
    }

    /**
     * @notice Build floating coupon rates with unique adjacent non-terminal entries and a terminal zero-rate entry
     * @param length Number of timestamp checkpoints to generate
     * @param initialRate Coupon rate applied to the first interval
     * @return couponRates Generated coupon rates struct
     */
    function _createFloatingCouponRates(uint256 length, uint256 initialRate)
        internal
        view
        returns (CouponRates memory)
    {
        uint256[] memory paymentTimestamps = new uint256[](length);
        uint256[] memory rates = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            paymentTimestamps[i] = block.timestamp + (i * 365 days);

            if (i == length - 1) {
                rates[i] = 0;
            } else {
                rates[i] = initialRate + i;
            }
        }

        return CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});
    }
}

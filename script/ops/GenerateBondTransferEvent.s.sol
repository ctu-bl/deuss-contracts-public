// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// solhint-disable gas-small-strings
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {console2} from "forge-std/console2.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {DeployConstants as Constants} from "../DeployConstants.sol";
import {Suite} from "../DeployTypes.sol";
import {DeploymentArtifacts} from "../lib/DeploymentArtifacts.s.sol";
import {Bond, BondInput, BondStatus, CouponFrequency, CouponRates, CouponRateType} from "src/registry/BondStructs.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {EntityStatus, AccountStatus} from "src/registry/EntityStructs.sol";
import {ICompanyWallet} from "src/wallet/ICompanyWallet.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";

/**
 * @title GenerateBondTransferEvent
 * @author DEUSS Team
 * @notice Idempotently prepares a local demo bond scenario and emits a wallet-to-wallet ERC6909 Transfer event.
 * @dev Intended for running against an already deployed and bootstrapped local Anvil network.
 */
contract GenerateBondTransferEvent is DeploymentArtifacts {
    using StringExtensions for string;

    // solhint-disable-next-line gas-struct-packing
    struct TransferPlan {
        uint256 fromOwnerKey;
        uint256 tokenId;
        uint256 availableBalance;
        uint256 amount;
        address fromWallet;
        address toWallet;
        bool issuedTopUp;
    }

    string internal constant _DEFAULT_ISIN = "XT0000000001";
    string internal constant _DEFAULT_CURRENCY = "EUR";
    uint256 internal constant _DEFAULT_MAX_SUPPLY = 1_000_000_000;
    uint256 internal constant _DEFAULT_ISSUE_AMOUNT = 1_000;
    uint256 internal constant _OWNER_A_KEY = 0x5e920d8e1ef2cc765510ec7d11f42aeeecff5a4ece6a7651e14323ecff6ddad3;
    uint256 internal constant _OWNER_B_KEY = 0xef4c3d3d59af9be4fba761d95295c3ebd0b052a2f437744d8012b8afb6170b1d;
    uint256 internal constant _MIN_OWNER_BALANCE = 0.01 ether;
    uint16 internal constant _DEFAULT_ISSUANCE_COUNTRY = 703;

    Suite internal _suite;
    VmSafe.Wallet internal _walletOwnerA;
    VmSafe.Wallet internal _walletOwnerB;
    VmSafe.Wallet internal _admin;

    error ExistingBondHasDifferentIssuer();
    error ExistingBondIsNotIssuable();
    error NoIssuableSupply();
    error TransferAmountExceedsBalance();
    error UnexpectedWalletOwner();
    error ZeroAvailableBalance();
    error ZeroIssueAmount();
    error ZeroMaxSupply();
    error ZeroTransferAmount();

    /**
     * @notice Run the idempotent scenario.
     */
    function run() public {
        _suite = _loadSuiteFromManifest();
        _walletOwnerA = vm.createWallet(vm.envOr("BOND_TRANSFER_EVENT_OWNER_A_KEY", _OWNER_A_KEY));
        _walletOwnerB = vm.createWallet(vm.envOr("BOND_TRANSFER_EVENT_OWNER_B_KEY", _OWNER_B_KEY));
        _admin = vm.createWallet(_activeNetworkConfig.adminKey);

        _fundWalletOwner(_walletOwnerA.addr);
        _fundWalletOwner(_walletOwnerB.addr);

        address walletA = _ensureCompanyWallet("bond-transfer-event-a", _walletOwnerA.addr);
        address walletB = _ensureCompanyWallet("bond-transfer-event-b", _walletOwnerB.addr);

        IBondRegistry bondRegistry = IBondRegistry(_suite.registries.bondRegistry);
        IERC6909 token = IERC6909(_suite.multiToken.deussToken);
        string memory isin = vm.envOr("BOND_TRANSFER_EVENT_ISIN", string(_DEFAULT_ISIN));
        string memory currency = vm.envOr("BOND_TRANSFER_EVENT_CURRENCY", string(_DEFAULT_CURRENCY));
        uint256 entropyBlock = vm.envOr("BOND_TRANSFER_EVENT_ENTROPY_BLOCK", block.number);

        _ensureCurrencyAllowed(bondRegistry, currency);
        Bond memory bond = _ensureBondIssued(bondRegistry, isin, currency, walletA, _walletOwnerA.privateKey);
        TransferPlan memory plan = _buildTransferPlan(token, bondRegistry, bond, walletA, walletB, entropyBlock);

        _executeTransfer(token, plan);

        console2.log("GenerateBondTransferEvent");
        console2.log("  isin", isin);
        console2.log("  tokenId", bond.tokenId);
        console2.log("  entropyBlock", entropyBlock);
        console2.log("  walletA", walletA);
        console2.log("  walletB", walletB);
        console2.log("  from", plan.fromWallet);
        console2.log("  to", plan.toWallet);
        console2.log("  amount", plan.amount);
        console2.log("  issuedTopUp", plan.issuedTopUp);
        console2.log("  fromBalanceAfter", token.balanceOf(plan.fromWallet, bond.tokenId));
        console2.log("  toBalanceAfter", token.balanceOf(plan.toWallet, bond.tokenId));
    }

    function _fundWalletOwner(address owner) internal {
        if (owner.balance > _MIN_OWNER_BALANCE || owner.balance == _MIN_OWNER_BALANCE) return;

        uint256 amount = _MIN_OWNER_BALANCE - owner.balance;
        vm.startBroadcast(_admin.privateKey);
        payable(owner).transfer(amount);
        vm.stopBroadcast();
    }

    function _ensureCompanyWallet(string memory label, address owner) internal returns (address wallet) {
        IEntityRegistry entityRegistry = IEntityRegistry(_suite.registries.entityRegistry);
        bytes32 entityId = keccak256(abi.encodePacked(label));

        bool entityExists = _entityExists(entityRegistry, entityId);
        if (!entityExists) {
            vm.startBroadcast(_admin.privateKey);
            entityRegistry.registerEntity(entityId, Constants.COMPANY_ENTITY, "");
            entityRegistry.setEntityStatus(entityId, EntityStatus.ENABLED, "");
            entityRegistry.setEntityAuthority(entityId, _admin.addr);
            entityRegistry.setEntityManager(entityId, _admin.addr, true);
            vm.stopBroadcast();
        } else if (entityRegistry.getEntityStatus(entityId) != EntityStatus.ENABLED) {
            vm.startBroadcast(_admin.privateKey);
            entityRegistry.setEntityStatus(entityId, EntityStatus.ENABLED, "");
            vm.stopBroadcast();
        }
        if (!entityRegistry.isEntityManager(entityId, _admin.addr)) {
            vm.startBroadcast(_admin.privateKey);
            entityRegistry.setEntityManager(entityId, _admin.addr, true);
            vm.stopBroadcast();
        }

        address[] memory wallets = entityRegistry.getEntityAccounts(entityId);
        if (wallets.length != 0) {
            wallet = wallets[0];
            if (ICompanyWallet(wallet).owner() != owner) revert UnexpectedWalletOwner();
            _ensureAccountEnabled(entityRegistry, wallet);
            return wallet;
        }

        IWalletFactory walletFactory = IWalletFactory(_suite.registries.walletFactory);
        IWalletFactory.CreateWalletParams memory params = IWalletFactory.CreateWalletParams({
            entityId: entityId,
            walletType: Constants.COMPANY_WALLET_TYPE,
            initData: abi.encodeCall(ICompanyWallet.initialize, (owner, _suite.registries.walletPolicyRegistry))
        });

        vm.startBroadcast(_admin.privateKey);
        wallet = walletFactory.createWallet(params);
        entityRegistry.registerAccount(wallet, entityId, 0);
        vm.stopBroadcast();
    }

    function _ensureAccountEnabled(IEntityRegistry entityRegistry, address account) internal {
        if (entityRegistry.isAccountEnabled(account)) return;

        vm.startBroadcast(_admin.privateKey);
        entityRegistry.setAccountStatus(account, AccountStatus.ENABLED, "");
        vm.stopBroadcast();
    }

    function _ensureCurrencyAllowed(IBondRegistry bondRegistry, string memory currency) internal {
        if (bondRegistry.isCurrencyAllowed(currency)) return;

        vm.startBroadcast(_admin.privateKey);
        bondRegistry.setAllowedCurrency(currency, true);
        vm.stopBroadcast();
    }

    function _ensureBondIssued(
        IBondRegistry bondRegistry,
        string memory isin,
        string memory currency,
        address issuerWallet,
        uint256 issuerOwnerKey
    ) internal returns (Bond memory bond) {
        bytes12 isinBytes = isin._isinToBytes12();
        uint8 latestVersion = bondRegistry.getLatestVersion(isinBytes);

        if (latestVersion == 0) {
            _publishBond(bondRegistry, isin, currency, issuerWallet);
            bond = bondRegistry.getBond(isin);
            uint256 amount = _min(_issueAmount(), bond.remainingIssuableSupply);
            if (amount == 0) revert NoIssuableSupply();
            _issueBond(bondRegistry, issuerWallet, issuerOwnerKey, isin, 1, amount);
            return bondRegistry.getBond(isin);
        }

        bond = bondRegistry.getBond(isin);
        if (bond.issuer != issuerWallet) revert ExistingBondHasDifferentIssuer();
        if (bond.status != BondStatus.Published && bond.status != BondStatus.Issued) {
            revert ExistingBondIsNotIssuable();
        }

        if (bond.status == BondStatus.Published) {
            uint256 amount = _min(_issueAmount(), bond.remainingIssuableSupply);
            if (amount == 0) revert NoIssuableSupply();
            _issueBond(
                bondRegistry, issuerWallet, issuerOwnerKey, isin, bondRegistry.getActiveVersion(isinBytes), amount
            );
            bond = bondRegistry.getBond(isin);
        }
    }

    function _buildTransferPlan(
        IERC6909 token,
        IBondRegistry bondRegistry,
        Bond memory bond,
        address walletA,
        address walletB,
        uint256 entropyBlock
    ) internal returns (TransferPlan memory plan) {
        uint256 balanceA = token.balanceOf(walletA, bond.tokenId);
        uint256 balanceB = token.balanceOf(walletB, bond.tokenId);

        if (balanceA == 0 && balanceB == 0) {
            uint256 amount = _min(_issueAmount(), bond.remainingIssuableSupply);
            if (amount == 0) revert NoIssuableSupply();
            _issueBond(
                bondRegistry,
                walletA,
                _walletOwnerA.privateKey,
                _isinToString(bond.isin),
                bondRegistry.getActiveVersion(bond.isin),
                amount
            );
            balanceA = token.balanceOf(walletA, bond.tokenId);
            plan.issuedTopUp = true;
        }

        if (balanceA != 0) {
            plan.fromWallet = walletA;
            plan.toWallet = walletB;
            plan.fromOwnerKey = _walletOwnerA.privateKey;
            plan.tokenId = bond.tokenId;
            plan.availableBalance = balanceA;
        } else {
            plan.fromWallet = walletB;
            plan.toWallet = walletA;
            plan.fromOwnerKey = _walletOwnerB.privateKey;
            plan.tokenId = bond.tokenId;
            plan.availableBalance = balanceB;
        }

        plan.amount = _entropyAmount(entropyBlock, bond.tokenId, plan.fromWallet, plan.toWallet, plan.availableBalance);
    }

    function _publishBond(IBondRegistry bondRegistry, string memory isin, string memory currency, address issuerWallet)
        internal
    {
        BondInput memory input = BondInput({
            isin: isin,
            issuer: issuerWallet,
            currency: currency,
            bondNominalValue: 1,
            maxSupply: _maxSupply(),
            couponRates: _couponRates(),
            couponRateType: CouponRateType.FIXED,
            maturityDate: block.timestamp + 365 days,
            couponFrequency: CouponFrequency.Monthly,
            isGuaranteed: false,
            issuanceCountry: _DEFAULT_ISSUANCE_COUNTRY
        });

        vm.startBroadcast(_admin.privateKey);
        bondRegistry.publishBond(input);
        vm.stopBroadcast();
    }

    function _issueBond(
        IBondRegistry bondRegistry,
        address issuerWallet,
        uint256 issuerOwnerKey,
        string memory isin,
        uint8 version,
        uint256 amount
    ) internal {
        vm.startBroadcast(issuerOwnerKey);
        ICompanyWallet(issuerWallet)
            .execute(address(bondRegistry), 0, abi.encodeCall(IBondRegistry.issueBond, (isin, version, amount)));
        vm.stopBroadcast();
    }

    function _executeTransfer(IERC6909 token, TransferPlan memory plan) internal {
        if (plan.amount == 0) revert ZeroTransferAmount();
        if (plan.amount > plan.availableBalance) revert TransferAmountExceedsBalance();

        vm.startBroadcast(plan.fromOwnerKey);
        ICompanyWallet(plan.fromWallet)
            .execute(address(token), 0, abi.encodeCall(IERC6909.transfer, (plan.toWallet, plan.tokenId, plan.amount)));
        vm.stopBroadcast();
    }

    function _couponRates() internal view returns (CouponRates memory rates) {
        rates.paymentTimestamps = new uint256[](2);
        rates.rates = new uint256[](2);
        rates.paymentTimestamps[0] = block.timestamp + 30 days;
        rates.paymentTimestamps[1] = block.timestamp + 365 days;
        rates.rates[0] = 500;
        rates.rates[1] = 0;
    }

    function _issueAmount() internal view returns (uint256) {
        uint256 amount = vm.envOr("BOND_TRANSFER_EVENT_ISSUE_AMOUNT", _DEFAULT_ISSUE_AMOUNT);
        if (amount == 0) revert ZeroIssueAmount();
        return amount;
    }

    function _maxSupply() internal view returns (uint256) {
        uint256 maxSupply = vm.envOr("BOND_TRANSFER_EVENT_MAX_SUPPLY", _DEFAULT_MAX_SUPPLY);
        if (maxSupply == 0) revert ZeroMaxSupply();
        return maxSupply;
    }

    function _entityExists(IEntityRegistry entityRegistry, bytes32 entityId) internal view returns (bool) {
        try entityRegistry.getEntityStatus(entityId) returns (EntityStatus) {
            return true;
        } catch {
            return false;
        }
    }

    function _entropyAmount(uint256 entropyBlock, uint256 tokenId, address from, address to, uint256 availableBalance)
        internal
        pure
        returns (uint256)
    {
        if (availableBalance == 0) revert ZeroAvailableBalance();
        uint256 raw = uint256(keccak256(abi.encodePacked(entropyBlock, tokenId, from, to)));
        return (raw % availableBalance) + 1;
    }

    function _isinToString(bytes12 isin) internal pure returns (string memory) {
        bytes memory output = new bytes(12);
        for (uint256 i; i < 12; ++i) {
            output[i] = isin[i];
        }
        return string(output);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

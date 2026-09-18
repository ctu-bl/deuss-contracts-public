// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {DeployConfig} from "../DeployConfig.s.sol";
import {Suite} from "../DeployTypes.sol";
import {Errors} from "src/libs/Errors.sol";
import {VmSafe} from "forge-std/Vm.sol";

/**
 * @title DeploymentArtifacts
 * @author DEUSS Team
 * @notice Centralised manifest resolution and Suite loading for all post-deploy scripts.
 *
 *         Manifest resolution order (first usable wins):
 *           1. Stable file:  deployments/<chainId>_<env>_latest.json
 *           2. Newest snapshot: deployments/<chainId>_<env>_<block>.json
 *
 *         A manifest is "usable" when its core/registry addresses contain bytecode on
 *         the connected chain.
 */
abstract contract DeploymentArtifacts is DeployConfig {
    /*//////////////////////////////////////////////////////////////
                          MANIFEST RESOLUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Resolve the best deployment manifest for the active network.
     * @return path Absolute path to the selected JSON file
     */
    function _resolveManifest() internal returns (string memory path) {
        string memory chainStr = vm.toString(block.chainid);
        string memory env = _activeNetworkConfig.env;

        // 1) Stable file.
        string memory dir = _deploymentDirPath();
        string memory stableFile = string.concat(chainStr, "_", env, "_latest.json");
        string memory legacyStable = string.concat(dir, stableFile);
        if (_fileExists(legacyStable) && _isManifestUsable(legacyStable)) {
            return legacyStable;
        }

        // 2) Newest block-numbered snapshot.
        string memory prefix = string.concat(chainStr, "_", env, "_");
        string memory bestLegacy = _findNewestSnapshot(dir, prefix);
        if (bytes(bestLegacy).length != 0 && _isManifestUsable(bestLegacy)) {
            return bestLegacy;
        }

        revert Errors.DeploymentFileNotFound();
    }

    /**
     * @notice Read the raw JSON from the best available manifest.
     * @return json Raw deployment manifest JSON string
     */
    function _readManifest() internal returns (string memory json) {
        return vm.readFile(_resolveManifest());
    }

    /**
     * @notice Load a Suite struct from the best available manifest.
     * @return suite Populated Suite with all deployed contract addresses
     */
    function _loadSuiteFromManifest() internal returns (Suite memory suite) {
        return _parseSuiteFromJson(_readManifest());
    }

    /*//////////////////////////////////////////////////////////////
                           MANIFEST PARSING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Parse a Suite struct from a deployment JSON string.
     * @param json Raw deployment manifest JSON
     * @return suite Populated Suite
     */
    // solhint-disable-next-line function-max-lines
    function _parseSuiteFromJson(string memory json) internal returns (Suite memory suite) {
        // solhint-disable gas-small-strings
        // Core
        suite.core.escrowManager = abi.decode(vm.parseJson(json, ".core.EscrowManager.contractAddress"), (address));
        suite.core.escrowManagerBeacon = abi.decode(vm.parseJson(json, ".core.EscrowManager.beaconAddress"), (address));
        suite.core.escrowManagerImpl =
            abi.decode(vm.parseJson(json, ".core.EscrowManager.implementationAddress"), (address));
        suite.core.marketplace = abi.decode(vm.parseJson(json, ".core.Marketplace.contractAddress"), (address));
        suite.core.marketplaceBeacon = abi.decode(vm.parseJson(json, ".core.Marketplace.beaconAddress"), (address));
        suite.core.marketplaceImpl =
            abi.decode(vm.parseJson(json, ".core.Marketplace.implementationAddress"), (address));
        suite.core.assetManager = abi.decode(vm.parseJson(json, ".core.AssetManager.contractAddress"), (address));
        suite.core.assetManagerBeacon = abi.decode(vm.parseJson(json, ".core.AssetManager.beaconAddress"), (address));
        suite.core.assetManagerImpl =
            abi.decode(vm.parseJson(json, ".core.AssetManager.implementationAddress"), (address));
        suite.core.orderbookMarketplace =
            abi.decode(vm.parseJson(json, ".core.OrderbookMarketplace.contractAddress"), (address));
        suite.core.orderbookMarketplaceBeacon =
            abi.decode(vm.parseJson(json, ".core.OrderbookMarketplace.beaconAddress"), (address));
        suite.core.orderbookMarketplaceImpl =
            abi.decode(vm.parseJson(json, ".core.OrderbookMarketplace.implementationAddress"), (address));
        suite.core.bondMarketFilter =
            abi.decode(vm.parseJson(json, ".core.BondMarketFilter.contractAddress"), (address));
        suite.core.bondMarketFilterBeacon =
            abi.decode(vm.parseJson(json, ".core.BondMarketFilter.beaconAddress"), (address));
        suite.core.bondMarketFilterImpl =
            abi.decode(vm.parseJson(json, ".core.BondMarketFilter.implementationAddress"), (address));
        // Registries
        suite.registries.bondRegistry =
            abi.decode(vm.parseJson(json, ".registries.BondRegistry.contractAddress"), (address));
        suite.registries.bondRegistryBeacon =
            abi.decode(vm.parseJson(json, ".registries.BondRegistry.beaconAddress"), (address));
        suite.registries.bondRegistryImpl =
            abi.decode(vm.parseJson(json, ".registries.BondRegistry.implementationAddress"), (address));
        suite.registries.entityRegistry =
            abi.decode(vm.parseJson(json, ".registries.EntityRegistry.contractAddress"), (address));
        suite.registries.entityRegistryBeacon =
            abi.decode(vm.parseJson(json, ".registries.EntityRegistry.beaconAddress"), (address));
        suite.registries.entityRegistryImpl =
            abi.decode(vm.parseJson(json, ".registries.EntityRegistry.implementationAddress"), (address));
        suite.registries.walletPolicyRegistry =
            abi.decode(vm.parseJson(json, ".registries.PolicyRegistry.contractAddress"), (address));
        suite.registries.walletPolicyRegistryBeacon =
            abi.decode(vm.parseJson(json, ".registries.PolicyRegistry.beaconAddress"), (address));
        suite.registries.walletPolicyRegistryImpl =
            abi.decode(vm.parseJson(json, ".registries.PolicyRegistry.implementationAddress"), (address));
        suite.registries.walletFactory =
            abi.decode(vm.parseJson(json, ".registries.WalletFactory.contractAddress"), (address));
        suite.registries.walletFactoryBeacon =
            abi.decode(vm.parseJson(json, ".registries.WalletFactory.beaconAddress"), (address));
        // Token
        suite.multiToken.deussToken =
            abi.decode(vm.parseJson(json, ".multiToken.deussToken.contractAddress"), (address));
        suite.multiToken.deussTokenBeacon =
            abi.decode(vm.parseJson(json, ".multiToken.deussToken.beaconAddress"), (address));
        suite.multiToken.deussTokenImpl =
            abi.decode(vm.parseJson(json, ".multiToken.deussToken.implementationAddress"), (address));
        // Utils
        suite.utils.multicall = abi.decode(vm.parseJson(json, ".utils.Multicall3.contractAddress"), (address));
        suite.utils.marketplaceLens =
            abi.decode(vm.parseJson(json, ".utils.MarketplaceLens.contractAddress"), (address));
        suite.utils.marketplaceLensBeacon =
            abi.decode(vm.parseJson(json, ".utils.MarketplaceLens.beaconAddress"), (address));
        suite.utils.marketplaceLensImpl =
            abi.decode(vm.parseJson(json, ".utils.MarketplaceLens.implementationAddress"), (address));
        // Wallet
        suite.wallet.companyWalletBeacon =
            abi.decode(vm.parseJson(json, ".wallet.CompanyWallet.beaconAddress"), (address));
        suite.wallet.companyWalletImpl =
            abi.decode(vm.parseJson(json, ".wallet.CompanyWallet.implementationAddress"), (address));
        // Governance
        suite.governance.timelockController =
            abi.decode(vm.parseJson(json, ".governance.TimelockController.contractAddress"), (address));
        suite.governance.timelockControllerBeacon =
            abi.decode(vm.parseJson(json, ".governance.TimelockController.beaconAddress"), (address));
        suite.governance.timelockControllerImpl =
            abi.decode(vm.parseJson(json, ".governance.TimelockController.implementationAddress"), (address));
        // EBSI
        suite.ebsi.didRegistry = abi.decode(vm.parseJson(json, ".ebsi.DidRegistry.contractAddress"), (address));
        suite.ebsi.proxyTemplateRegistry =
            abi.decode(vm.parseJson(json, ".ebsi.ProxyTemplateRegistry.contractAddress"), (address));
        suite.ebsi.proxyFactory = abi.decode(vm.parseJson(json, ".ebsi.ProxyFactory.contractAddress"), (address));
        // solhint-enable gas-small-strings
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Scan a directory for block-numbered JSON snapshots and return the path
     *         of the one with the highest block number.
     * @dev Files are expected to be named `<prefix><block>.json`.
     * @param dir   Directory path (must end with `/`)
     * @param prefix Expected filename prefix
     * @return path Absolute path to the newest snapshot, or empty string if none found
     */
    function _findNewestSnapshot(string memory dir, string memory prefix) internal returns (string memory path) {
        VmSafe.DirEntry[] memory files = vm.readDir(dir);
        uint256 latestBlock;

        for (uint256 i = 0; i < files.length; ++i) {
            if (files[i].isDir || files[i].isSymlink) continue;

            string memory file = vm.replace(files[i].path, dir, "");
            (bool matched, uint256 blockNum) = _tryParseDeploymentBlockNumber(file, prefix);
            if (matched && blockNum > latestBlock) {
                latestBlock = blockNum;
                path = files[i].path;
            }
        }
    }

    /**
     * @notice Return true when the manifest points to live contracts on the connected chain.
     * @param path Absolute path to deployment JSON
     * @return usable True when required core/registry addresses contain bytecode
     */
    function _isManifestUsable(string memory path) internal view returns (bool usable) {
        string memory json = vm.readFile(path);

        // solhint-disable gas-small-strings
        address entityRegistry = abi.decode(vm.parseJson(json, ".registries.EntityRegistry.contractAddress"), (address));
        address bondRegistry = abi.decode(vm.parseJson(json, ".registries.BondRegistry.contractAddress"), (address));
        address marketplace = abi.decode(vm.parseJson(json, ".core.Marketplace.contractAddress"), (address));
        address escrowManager = abi.decode(vm.parseJson(json, ".core.EscrowManager.contractAddress"), (address));
        // solhint-enable gas-small-strings

        return entityRegistry.code.length > 0 && bondRegistry.code.length > 0 && marketplace.code.length > 0
            && escrowManager.code.length > 0;
    }

    /**
     * @notice Return true when the given absolute file path exists and is readable.
     * @dev Uses a try/catch around vm.readFile as a presence check.
     * @param path Absolute file path to check
     * @return exists True when the file can be read successfully
     */
    function _fileExists(string memory path) internal view returns (bool exists) {
        try vm.readFile(path) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }
}

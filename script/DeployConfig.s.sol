// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Errors} from "../src/libs/Errors.sol";
import {NetworkConfig} from "./DeployTypes.sol";
import {DeployConstants as Constants} from "./DeployConstants.sol";

/**
 * @title DeployConfig
 * @author DEUSS Team
 * @notice Configuration script for deployment
 */
contract DeployConfig is Script {
    /// @notice Active network configuration
    NetworkConfig internal _activeNetworkConfig;

    constructor() {
        _activeNetworkConfig = getNetworkConfig(block.chainid);
    }

    /**
     * @notice Get network configuration from environment variables
     * @param chainId Chain ID
     * @return NetworkConfig struct with deployment settings
     */
    function getNetworkConfig(uint256 chainId) public view returns (NetworkConfig memory) {
        if (chainId == _besuChainId()) return _getBesuNetworkConfig();
        if (chainId == Constants.DEFAULT_ANVIL_NETWORK_ID) return _getAnvilNetworkConfig();

        revert Errors.DeployConfig__NetworkNotConfigured(chainId);
    }

    /**
     * @notice Get the active network configuration
     * @return NetworkConfig struct with deployment settings
     */
    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return _activeNetworkConfig;
    }

    /**
     * @notice Parse block number from a deployment snapshot filename
     * @dev Supports `<chainId>_<env>_<block>.json`
     * @param file Candidate file name
     * @param prefix Expected prefix `<chainId>_<env>_`
     * @return matched Whether the file is a block-numbered deployment snapshot
     * @return blockNum Parsed block number when `matched` is true
     */
    function _tryParseDeploymentBlockNumber(string memory file, string memory prefix)
        internal
        returns (bool matched, uint256 blockNum)
    {
        if (!(vm.contains(file, prefix) && vm.contains(file, ".json"))) {
            return (false, 0);
        }

        string memory blockStr = vm.replace(file, prefix, "");
        if (vm.contains(blockStr, "_latest.json")) {
            blockStr = vm.replace(blockStr, "_latest.json", "");
        } else {
            blockStr = vm.replace(blockStr, ".json", "");
        }

        if (!_isNumericString(blockStr)) {
            return (false, 0);
        }

        return (true, vm.parseUint(blockStr));
    }

    /**
     * @notice Get Besu deployment configuration from environment variables
     * @return NetworkConfig struct with Besu deployment settings
     */
    function _getBesuNetworkConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("BESU_DEPLOYER_PRIVATE_KEY"),
            timelockControllerAdminKey: vm.envUint("BESU_TIMELOCK_ADMIN_PRIVATE_KEY"),
            timelockControllerActorKey: vm.envUint("BESU_TIMELOCK_ACTOR_PRIVATE_KEY"),
            adminKey: vm.envUint("BESU_ADMIN_PRIVATE_KEY"),
            env: vm.envString("BESU_DEPLOY_ENV")
        });
    }

    /**
     * @notice Get Anvil deployment configuration from local constants
     * @return NetworkConfig struct with Anvil deployment settings
     */
    function _getAnvilNetworkConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: Constants.DEFAULT_ANVIL_DEPLOYER_PRIVATE_KEY,
            timelockControllerAdminKey: Constants.DEFAULT_ANVIL_TIMELOCK_CONTROLLER_ADMIN_PRIVATE_KEY,
            timelockControllerActorKey: Constants.DEFAULT_ANVIL_TIMELOCK_CONTROLLER_ACTOR_PRIVATE_KEY,
            adminKey: Constants.DEFAULT_ANVIL_ADMIN_PRIVATE_KEY,
            env: vm.envOr("ANVIL_DEPLOY_ENV", string("anvil"))
        });
    }

    /**
     * @notice Read the configured Besu chain ID
     * @return chainId Besu chain ID, or max uint256 when not configured
     */
    function _besuChainId() internal view returns (uint256 chainId) {
        return vm.envOr("BESU_NETWORK_ID", type(uint256).max);
    }

    /**
     * @notice Get the deployment directory path
     * @return dirPath Absolute path to the `deployments/` directory
     */
    function _deploymentDirPath() internal view returns (string memory dirPath) {
        return string.concat(vm.projectRoot(), "/deployments/");
    }

    /**
     * @notice Get the deployment filename prefix for the active network
     * @return prefix Prefix in the form `<chainId>_<env>_`
     */
    function _deploymentFilePrefix() internal view returns (string memory prefix) {
        return string.concat(vm.toString(block.chainid), "_", _activeNetworkConfig.env, "_");
    }

    /**
     * @notice Get the stable deployment filename for the active network
     * @return fileName Stable file name in the form `<chainId>_<env>_latest.json`
     */
    function _stableDeploymentFileName() internal view returns (string memory fileName) {
        return string.concat(vm.toString(block.chainid), "_", _activeNetworkConfig.env, "_latest.json");
    }

    /**
     * @notice Read the implementation address from a BeaconProxy
     * @param proxy BeaconProxy contract address
     * @return implementation Implementation contract address
     */
    function _getBeaconImplementation(address proxy) internal view returns (address implementation) {
        address beacon = _getBeacon(proxy);
        return IBeacon(beacon).implementation();
    }

    /**
     * @notice Read the beacon address from a proxy
     * @param proxy BeaconProxy contract address
     * @return beacon UpgradeableBeacon contract address
     */
    function _getBeacon(address proxy) internal view returns (address beacon) {
        return address(uint160(uint256(vm.load(proxy, Constants.BEACON_SLOT))));
    }

    /**
     * @notice Check whether a string consists only of decimal digits
     * @param value Input string
     * @return isNumeric True when every character is between `0` and `9`
     */
    function _isNumericString(string memory value) internal pure returns (bool isNumeric) {
        bytes memory valueBytes = bytes(value);
        if (valueBytes.length == 0) return false;

        for (uint256 i = 0; i < valueBytes.length; ++i) {
            bytes1 char = valueBytes[i];
            if (char < 0x30 || char > 0x39) return false;
        }

        return true;
    }
}

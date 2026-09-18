// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title Create2Deployer
 * @author DEUSS Team
 * @notice Can be used to deploy contracts with CREATE2 Factory.
 */
abstract contract Create2Deployer {
    /**
     * @notice Emitted when a contract is deployed via CREATE2
     * @param addr The address of the deployed contract
     */
    event Deployed(address indexed addr);

    /**
     * @notice Deploys an implementation contract using CREATE2
     * @param salt A unique value to ensure unique contract addresses
     * @param implementationBytecode The creation code of the implementation contract
     * @param initData Initialization data to call the implementation contract's constructor with
     * @return implementationAddress The address of the deployed implementation contract
     */
    function _deployImplementationViaCreate2(
        string memory salt,
        bytes memory implementationBytecode,
        bytes memory initData
    ) internal returns (address implementationAddress) {
        bytes memory bytecode = _prepareImplementationCreationCode(implementationBytecode, initData);
        return _deploy(salt, bytecode);
    }

    /**
     * @notice Deploys an UpgradeableBeacon using CREATE2
     * @param salt A unique value to ensure unique contract addresses
     * @param implementation The address of the initial implementation contract
     * @param beaconOwner The address that will own and be able to upgrade the beacon
     * @return beaconAddress The address of the deployed beacon contract
     */
    function _deployBeaconViaCreate2(string memory salt, address implementation, address beaconOwner)
        internal
        returns (address beaconAddress)
    {
        bytes memory beaconBytecode = _prepareBeaconCreationCode(implementation, beaconOwner);
        return _deploy(salt, beaconBytecode);
    }

    /**
     * @notice Deploys a BeaconProxy using CREATE2
     * @param salt A unique value to ensure unique contract addresses
     * @param beacon The address of the beacon contract
     * @param initData Initialization data to call the implementation contract with
     * @return proxyAddress The address of the deployed proxy contract
     */
    function _deployBeaconProxyViaCreate2(string memory salt, address beacon, bytes memory initData)
        internal
        returns (address proxyAddress)
    {
        bytes memory proxyBytecode = _prepareBeaconProxyCreationCode(beacon, initData);
        return _deploy(salt, proxyBytecode);
    }

    /**
     * @notice Generates the creation code for the implementation contract
     * @param implementationBytecode The bytecode of the implementation contract
     * @param initData Initialization data for the implementation contract's constructor
     * @return The creation code for deploying the implementation contract
     */
    function _prepareImplementationCreationCode(bytes memory implementationBytecode, bytes memory initData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(implementationBytecode, initData);
    }

    /**
     * @notice Generates the creation code for the UpgradeableBeacon
     * @param implementation The address of the initial implementation contract
     * @param beaconOwner The address that will own the beacon
     * @return The creation code for deploying the beacon contract
     */
    function _prepareBeaconCreationCode(address implementation, address beaconOwner)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(type(UpgradeableBeacon).creationCode, abi.encode(implementation, beaconOwner));
    }

    /**
     * @notice Generates the creation code for the BeaconProxy
     * @param beacon The address of the beacon contract
     * @param initData Initialization data to call the implementation contract with (if no data, pass 'bytes("")')
     * @return proxyBytecode The bytecode for deploying the proxy contract
     */
    function _prepareBeaconProxyCreationCode(address beacon, bytes memory initData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon, initData));
    }

    /**
     * @notice Deploys a contract using CREATE2
     * @param salt A unique value to ensure unique contract addresses
     * @param bytecode The creation code of the contract
     * @return addr The address of the deployed contract
     */
    function _deploy(string memory salt, bytes memory bytecode) private returns (address) {
        bytes32 saltBytes = keccak256(abi.encodePacked(salt));
        address addr = Create2.deploy(0, saltBytes, bytecode);
        emit Deployed(addr);
        return addr;
    }
}

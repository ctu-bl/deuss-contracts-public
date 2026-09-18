// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

/**
 * @title StorageLayoutHelpers
 * @notice Shared helpers for tests that assert ERC-7201 namespaced storage locations and raw slot values.
 */
abstract contract StorageLayoutHelpers is Test {
    /**
     * @notice Computes the ERC-7201 root storage slot for a namespace identifier.
     * @param namespaceId The fully qualified storage namespace identifier.
     * @return The aligned ERC-7201 storage location for the namespace.
     */
    function _erc7201Location(string memory namespaceId) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(namespaceId))) - 1)) & ~bytes32(uint256(0xff));
    }

    /**
     * @notice Computes the absolute storage slot at an offset from a base slot.
     * @param slot The base storage slot.
     * @param offset The slot offset to add to the base slot.
     * @return The storage slot located `offset` positions after `slot`.
     */
    function _slotOffset(bytes32 slot, uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(slot) + offset);
    }

    /**
     * @notice Loads a raw storage slot and decodes it as an unsigned integer.
     * @param target The contract address to inspect.
     * @param slot The storage slot to load.
     * @return The decoded unsigned integer stored at `slot`.
     */
    function _loadUint(address target, bytes32 slot) internal view returns (uint256) {
        return uint256(vm.load(target, slot));
    }

    /**
     * @notice Loads a raw storage slot at an offset from a base slot and decodes it as an unsigned integer.
     * @param target The contract address to inspect.
     * @param slot The base storage slot.
     * @param offset The slot offset to add to the base slot before loading.
     * @return The decoded unsigned integer stored at the offset slot.
     */
    function _loadUint(address target, bytes32 slot, uint256 offset) internal view returns (uint256) {
        return _loadUint(target, _slotOffset(slot, offset));
    }

    /**
     * @notice Loads a raw storage slot and decodes it as an address.
     * @param target The contract address to inspect.
     * @param slot The storage slot to load.
     * @return The decoded address stored at `slot`.
     */
    function _loadAddress(address target, bytes32 slot) internal view returns (address) {
        return address(uint160(_loadUint(target, slot)));
    }
}

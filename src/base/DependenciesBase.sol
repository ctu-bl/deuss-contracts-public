// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {OwnableRolesExtension} from "../utils/OwnableRolesExtension.sol";
import {Errors} from "../libs/Errors.sol";

/**
 * @title DependenciesBase
 * @author DEUSS Team
 * @notice Shared dependency storage and admin setters/getters for protocol modules.
 * @dev Each of `_bondRegistry`, `_escrowManager`, and `_entityRegistry` may be set at most once
 *      (`*_AlreadySet` errors). Intended for one-shot wiring during deployment, not rotating addresses.
 *      Configuration uses role `ADMIN` (`_ROLE_0`).
 */
contract DependenciesBase is OwnableRolesExtension {
    /**
     * @notice Shared dependency addresses for protocol modules.
     * @custom:storage-location erc7201:deuss.base.dependencies.storage
     */
    struct DependenciesStorage {
        address bondRegistry;
        address escrowManager;
        address entityRegistry;
    }

    /**
     * @notice Role id allowed to configure module dependencies.
     */
    uint256 public constant ADMIN = _ROLE_0;

    /**
     * @notice ERC-7201 storage location for shared dependency addresses.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.base.dependencies.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _DEPENDENCIES_STORAGE_LOCATION =
        0x6ba34783cb4a25c3b0ae39f0782ba928fcc8c247146e532ae3e002c19848c100;

    /**
     * @notice Returns dependency namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _dependenciesStorage() internal pure returns (DependenciesStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _DEPENDENCIES_STORAGE_LOCATION
        }
    }

    /**
     * @notice Emitted when BondRegistry dependency is updated with previous and new addresses.
     * @param previousBondRegistry Previous BondRegistry dependency address.
     * @param bondRegistry New BondRegistry dependency address.
     */
    event BondRegistrySet(address indexed previousBondRegistry, address indexed bondRegistry);

    /**
     * @notice Emitted when EscrowManager dependency is updated with previous and new addresses.
     * @param previousEscrowManager Previous EscrowManager dependency address.
     * @param escrowManager New EscrowManager dependency address.
     */
    event EscrowManagerSet(address indexed previousEscrowManager, address indexed escrowManager);

    /**
     * @notice Emitted when EntityRegistry dependency is updated with previous and new addresses.
     * @param previousEntityRegistry Previous EntityRegistry dependency address.
     * @param entityRegistry New EntityRegistry dependency address.
     */
    event EntityRegistrySet(address indexed previousEntityRegistry, address indexed entityRegistry);

    /**
     * @notice Sets BondRegistry dependency.
     * @param bondRegistry Address of the BondRegistry contract.
     */
    function setBondRegistry(address bondRegistry) public virtual onlyRoles(ADMIN) {
        _setBondRegistry(bondRegistry);
    }

    /**
     * @notice Sets EscrowManager dependency.
     * @param escrowManager Address of the EscrowManager contract.
     */
    function setEscrowManager(address escrowManager) public virtual onlyRoles(ADMIN) {
        _setEscrowManager(escrowManager);
    }

    /**
     * @notice Sets EntityRegistry dependency.
     * @param entityRegistry Address of the EntityRegistry contract.
     */
    function setEntityRegistry(address entityRegistry) public virtual onlyRoles(ADMIN) {
        _setEntityRegistry(entityRegistry);
    }

    /**
     * @notice Returns configured BondRegistry address.
     * @return bondRegistry Configured BondRegistry dependency address.
     */
    function getBondRegistry() public view virtual returns (address bondRegistry) {
        return _dependenciesStorage().bondRegistry;
    }

    /**
     * @notice Returns configured EscrowManager address.
     * @return escrowManager Configured EscrowManager dependency address.
     */
    function getEscrowManager() public view virtual returns (address escrowManager) {
        return _dependenciesStorage().escrowManager;
    }

    /**
     * @notice Returns configured EntityRegistry address.
     * @return entityRegistry Configured EntityRegistry dependency address.
     */
    function getEntityRegistry() public view virtual returns (address entityRegistry) {
        return _dependenciesStorage().entityRegistry;
    }

    /**
     * @notice Stores BondRegistry dependency.
     * @param bondRegistry Address of the BondRegistry contract.
     */
    function _setBondRegistry(address bondRegistry) internal virtual {
        require(bondRegistry != address(0), Errors.ZeroAddress());
        DependenciesStorage storage $ = _dependenciesStorage();
        require($.bondRegistry == address(0), Errors.DependenciesBase__BondRegistryAlreadySet());
        address previousBondRegistry = $.bondRegistry;
        $.bondRegistry = bondRegistry;
        emit BondRegistrySet(previousBondRegistry, bondRegistry);
    }

    /**
     * @notice Stores EscrowManager dependency.
     * @param escrowManager Address of the EscrowManager contract.
     */
    function _setEscrowManager(address escrowManager) internal virtual {
        require(escrowManager != address(0), Errors.ZeroAddress());
        DependenciesStorage storage $ = _dependenciesStorage();
        require($.escrowManager == address(0), Errors.DependenciesBase__EscrowManagerAlreadySet());
        address previousEscrowManager = $.escrowManager;
        $.escrowManager = escrowManager;
        emit EscrowManagerSet(previousEscrowManager, escrowManager);
    }

    /**
     * @notice Stores EntityRegistry dependency.
     * @param entityRegistry Address of the EntityRegistry contract.
     */
    function _setEntityRegistry(address entityRegistry) internal virtual {
        require(entityRegistry != address(0), Errors.ZeroAddress());
        DependenciesStorage storage $ = _dependenciesStorage();
        require($.entityRegistry == address(0), Errors.DependenciesBase__EntityRegistryAlreadySet());
        address previousEntityRegistry = $.entityRegistry;
        $.entityRegistry = entityRegistry;
        emit EntityRegistrySet(previousEntityRegistry, entityRegistry);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Errors} from "../libs/Errors.sol";
import {IEntityRegistry} from "./interfaces/IEntityRegistry.sol";
import {DependenciesBase} from "../base/DependenciesBase.sol";

/**
 * @title EntityEligibilityGuard
 * @author DEUSS Team
 * @notice Reusable mixin for entity-type allowlist and entity-registry eligibility validations
 */
abstract contract EntityEligibilityGuard is DependenciesBase {
    /**
     * @notice Entity type allowlist storage.
     * @custom:storage-location erc7201:deuss.registry.entityeligibilityguard.storage
     */
    struct EntityEligibilityStorage {
        /// @notice Mapping of entity type id to allowed state
        mapping(uint256 entityId => bool allowed) allowedEntityTypes;
    }

    /**
     * @notice ERC-7201 storage location for entity eligibility state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.registry.entityeligibilityguard.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _ENTITY_ELIGIBILITY_STORAGE_LOCATION =
        0x1e8d49406242ce25abe87042959059df080d978423ec45227ef520f1cc16df00;

    /**
     * @notice Returns entity eligibility namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-start uninitialized-storage
    // slither-disable-next-line assembly
    function _entityEligibilityStorage() internal pure returns (EntityEligibilityStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _ENTITY_ELIGIBILITY_STORAGE_LOCATION
        }
    }
    // slither-disable-end uninitialized-storage

    /**
     * @notice Emitted when an entity type is enabled or disabled in the allowlist
     * @param typeId Entity type identifier
     * @param allowed Whether the type is allowed
     */
    event EntityTypeAllowed(uint256 indexed typeId, bool indexed allowed);

    /**
     * @notice Sets allowlist status for a single entity type id
     * @param typeId Entity type identifier
     * @param allowed Allowlist status
     */
    function _setAllowedEntityType(uint256 typeId, bool allowed) internal {
        _entityEligibilityStorage().allowedEntityTypes[typeId] = allowed;
        emit EntityTypeAllowed(typeId, allowed);
    }

    /**
     * @notice Sets allowlist status for multiple entity type ids
     * @param typeIds Entity type identifiers
     * @param allowed Allowlist status
     */
    function _setAllowedEntityTypes(uint256[] calldata typeIds, bool allowed) internal {
        for (uint256 i; i < typeIds.length; ++i) {
            _setAllowedEntityType(typeIds[i], allowed);
        }
    }

    /**
     * @notice Validates that wallet and linked entity are enabled
     * @param wallet Wallet to validate
     * @dev If the entity registry is not configured, the function returns without reverting
     */
    function _validateEntityWalletEnabled(address wallet) internal view {
        address entityRegistry = _dependenciesStorage().entityRegistry;
        if (entityRegistry == address(0)) {
            return;
        }
        require(
            IEntityRegistry(entityRegistry).isAccountEnabled(wallet),
            Errors.EntityEligibilityGuard__EntityWalletNotAllowed(wallet)
        );
    }

    /**
     * @notice Validates that wallet's entity type id is allowlisted
     * @param wallet Wallet to validate
     * @dev If the entity registry is not configured, the function returns without reverting
     */
    function _validateEntityTypeAllowed(address wallet) internal view {
        address entityRegistry = _dependenciesStorage().entityRegistry;
        if (entityRegistry == address(0)) {
            return;
        }

        uint256 typeId = IEntityRegistry(entityRegistry).getEntityTypeIdByAccount(wallet);
        require(
            _entityEligibilityStorage().allowedEntityTypes[typeId],
            Errors.EntityEligibilityGuard__EntityTypeNotAllowed(typeId)
        );
    }

    /**
     * @notice Validates wallet enabled state and allowlisted entity type for one wallet
     * @param wallet Wallet to validate
     * @dev Validation order is wallet-enabled first, then entity-type allowlist
     */
    function _validateEntityWalletAndTypeAllowed(address wallet) internal view {
        _validateEntityWalletEnabled(wallet);
        _validateEntityTypeAllowed(wallet);
    }

    /**
     * @notice Validates wallet enabled state and allowlisted entity type for multiple wallets
     * @param wallets Wallets to validate
     */
    function _validateEntityWalletsAndTypesAllowed(address[] memory wallets) internal view {
        for (uint256 i; i < wallets.length; ++i) {
            _validateEntityWalletAndTypeAllowed(wallets[i]);
        }
    }
}

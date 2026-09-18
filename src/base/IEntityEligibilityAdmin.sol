// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title IEntityEligibilityAdmin
 * @author DEUSS Team
 * @notice Interface for admin functions that manage allowed entity types.
 * @dev Implementations such as `EligibilityModuleBase` restrict these functions to `DependenciesBase.ADMIN`.
 */
interface IEntityEligibilityAdmin {
    /**
     * @notice Sets allowlist status for one entity type.
     * @param typeId Entity type identifier.
     * @param allowed Allowlist status.
     */
    function setAllowedEntityType(uint256 typeId, bool allowed) external;

    /**
     * @notice Sets allowlist status for multiple entity types.
     * @param typeIds Entity type identifiers.
     * @param allowed Allowlist status.
     */
    function setAllowedEntityTypes(uint256[] calldata typeIds, bool allowed) external;
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Initializable} from "solady/src/utils/Initializable.sol";
import {EntityEligibilityGuard} from "../registry/EntityEligibilityGuard.sol";
import {IEntityEligibilityAdmin} from "../base/IEntityEligibilityAdmin.sol";

/**
 * @title EligibilityModuleBase
 * @author DEUSS Team
 * @notice Shared module base for contracts that use entity eligibility checks.
 * @dev Inherits `EntityEligibilityGuard` (entity registry + type allowlist) and Solady `Initializable`.
 *      The implementation constructor calls `_disableInitializers()` so only proxy instances run `initialize`.
 *      Admin entry points use `DependenciesBase.ADMIN` (`onlyRoles(ADMIN)`).
 */
abstract contract EligibilityModuleBase is IEntityEligibilityAdmin, EntityEligibilityGuard, Initializable {
    /**
     * @notice Disables direct initialization on the implementation contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IEntityEligibilityAdmin
     */
    function setAllowedEntityType(uint256 typeId, bool allowed) public virtual override onlyRoles(ADMIN) {
        _setAllowedEntityType(typeId, allowed);
    }

    /**
     * @inheritdoc IEntityEligibilityAdmin
     */
    function setAllowedEntityTypes(uint256[] calldata typeIds, bool allowed) public virtual override onlyRoles(ADMIN) {
        _setAllowedEntityTypes(typeIds, allowed);
    }
}

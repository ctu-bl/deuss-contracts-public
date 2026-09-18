// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";
import {EntityStatus, AccountStatus, EntityTypeMeta, PendingAccountRegistration} from "src/registry/EntityStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_ER is PropertiesBase {
    function invariant_ER_01() internal {
        fl.eq(states[AFTER].allTrackedEntityAccountsConsistent, true, ER_01);
    }

    function invariant_ER_10(bytes32 entityId, uint256 expectedTypeId) internal {
        fl.eq(uint256(states[AFTER].entityStates[entityId].status), uint256(EntityStatus.ENABLED), ER_10_STATUS);
        fl.eq(states[AFTER].entityStates[entityId].typeId, expectedTypeId, ER_10_TYPE_ID);
    }

    function invariant_ER_11(bytes32 entityId) internal {
        fl.eq(states[AFTER].entityStates[entityId].accountCount, 0, ER_11);
    }

    function invariant_ER_12(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_12);
    }

    function invariant_ER_20(bytes32 entityId, EntityStatus expectedStatus) internal {
        fl.eq(uint256(states[AFTER].entityStates[entityId].status), uint256(expectedStatus), ER_20);
    }

    function invariant_ER_21(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_21);
    }

    function invariant_ER_30(address account, bytes32 entityId) internal {
        fl.eq(uint256(states[AFTER].accountStates[account].status), uint256(AccountStatus.ENABLED), ER_30_STATUS);
        fl.t(states[AFTER].accountStates[account].entityId == entityId, ER_30_ENTITY_ID);
        fl.eq(states[AFTER].accountStates[account].registered, true, ER_30_REGISTERED);
    }

    function invariant_ER_31(bytes32 entityId) internal {
        fl.eq(
            states[AFTER].entityStates[entityId].accountCount,
            states[BEFORE].entityStates[entityId].accountCount + 1,
            ER_31
        );
    }

    function invariant_ER_32(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_32);
    }

    function invariant_ER_33(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.ER__NotEntityManagerOrAdmin.selector;
        fl.errAllow(errorSelector, allowedErrors, ER_33);
    }

    function invariant_ER_33(bool managerAuthorized) internal {
        fl.eq(managerAuthorized, true, ER_33);
    }

    function invariant_ER_92(address account, bytes32 entityId, uint256 expectedRoleFlags, address expectedRequester)
        internal
    {
        PendingAccountRegistration memory pending = entityRegistry.getPendingAccountRegistration(account, entityId);
        fl.eq(pending.roleFlags, expectedRoleFlags, ER_92);
        fl.eq(pending.requester, expectedRequester, ER_92);
    }

    function invariant_ER_93(address account, bytes32 entityId) internal {
        fl.eq(states[AFTER].accountStates[account].registered, false, ER_93);
        fl.eq(
            states[AFTER].entityStates[entityId].accountCount, states[BEFORE].entityStates[entityId].accountCount, ER_93
        );
    }

    function invariant_ER_94(address account, bytes32 entityId, uint256 expectedRoleFlags, address expectedRequester)
        internal
    {
        PendingAccountRegistration memory pending = entityRegistry.getPendingAccountRegistration(account, entityId);
        fl.eq(pending.roleFlags, expectedRoleFlags, ER_94);
        fl.eq(pending.requester, expectedRequester, ER_94);
    }

    function invariant_ER_95(
        address account,
        bytes32 entityIdA,
        bytes32 entityIdB,
        uint256 expectedRoleFlagsA,
        uint256 expectedRoleFlagsB,
        address expectedRequester
    ) internal {
        PendingAccountRegistration memory pendingA = entityRegistry.getPendingAccountRegistration(account, entityIdA);
        PendingAccountRegistration memory pendingB = entityRegistry.getPendingAccountRegistration(account, entityIdB);
        fl.eq(pendingA.roleFlags, expectedRoleFlagsA, ER_95);
        fl.eq(pendingB.roleFlags, expectedRoleFlagsB, ER_95);
        fl.eq(pendingA.requester, expectedRequester, ER_95);
        fl.eq(pendingB.requester, expectedRequester, ER_95);
    }

    function invariant_ER_96(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__NotEntityManagerOrAdmin.selector, ER_96);
    }

    function invariant_ER_97(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ZeroAddress.selector, ER_97);
    }

    function invariant_ER_98(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertERError(errorSelector, expectedSelector, ER_98);
    }

    function invariant_ER_99(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__AccountAlreadyRegistered.selector, ER_99);
    }

    function invariant_ER_100(address account, bytes32 entityId, uint256 expectedRoleFlags) internal {
        fl.eq(uint256(states[AFTER].accountStates[account].status), uint256(AccountStatus.ENABLED), ER_100);
        fl.t(states[AFTER].accountStates[account].entityId == entityId, ER_100);
        fl.eq(states[AFTER].accountStates[account].registered, true, ER_100);
        fl.eq(states[AFTER].accountStates[account].roleFlags, expectedRoleFlags, ER_100);
    }

    function invariant_ER_101(bytes32 entityId) internal {
        fl.eq(
            states[AFTER].entityStates[entityId].accountCount,
            states[BEFORE].entityStates[entityId].accountCount + 1,
            ER_101
        );
    }

    function invariant_ER_102(address account, bytes32 entityId) internal {
        PendingAccountRegistration memory pending = entityRegistry.getPendingAccountRegistration(account, entityId);
        fl.eq(pending.requester, address(0), ER_102);
        fl.eq(pending.roleFlags, 0, ER_102);
    }

    function invariant_ER_103(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__AccountRegistrationNotPending.selector, ER_103);
    }

    function invariant_ER_104(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__AccountAlreadyRegistered.selector, ER_104);
    }

    function invariant_ER_105(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__NotEntityManagerOrAdmin.selector, ER_105);
    }

    function invariant_ER_106(address account, bytes32 entityId, uint256 expectedRoleFlags, address expectedRequester)
        internal
    {
        PendingAccountRegistration memory pending = entityRegistry.getPendingAccountRegistration(account, entityId);
        fl.eq(pending.roleFlags, expectedRoleFlags, ER_106);
        fl.eq(pending.requester, expectedRequester, ER_106);
    }

    function invariant_ER_107(address account, bytes32 entityId, uint256 expectedRoleFlags, address expectedRequester)
        internal
    {
        PendingAccountRegistration memory pending = entityRegistry.getPendingAccountRegistration(account, entityId);
        fl.eq(entityRegistry.isAccountRegistered(account), false, ER_107);
        fl.eq(pending.roleFlags, expectedRoleFlags, ER_107);
        fl.eq(pending.requester, expectedRequester, ER_107);
    }

    function invariant_ER_40(address account, AccountStatus expectedStatus) internal {
        fl.eq(uint256(states[AFTER].accountStates[account].status), uint256(expectedStatus), ER_40);
    }

    function invariant_ER_41(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_41);
    }

    function invariant_ER_50(address account) internal {
        fl.eq(states[AFTER].accountStates[account].registered, false, ER_50);
    }

    function invariant_ER_51(bytes32 entityId) internal {
        fl.eq(
            states[AFTER].entityStates[entityId].accountCount + 1,
            states[BEFORE].entityStates[entityId].accountCount,
            ER_51
        );
    }

    function invariant_ER_52(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_52);
    }

    function invariant_ER_60(address account, bytes32 newEntityId) internal {
        fl.t(states[AFTER].accountStates[account].entityId == newEntityId, ER_60);
        fl.eq(states[AFTER].accountStates[account].registered, true, ER_60);
    }

    function invariant_ER_61(bytes32 oldEntityId) internal {
        fl.eq(
            states[AFTER].entityStates[oldEntityId].accountCount + 1,
            states[BEFORE].entityStates[oldEntityId].accountCount,
            ER_61
        );
    }

    function invariant_ER_62(bytes32 newEntityId) internal {
        fl.eq(
            states[AFTER].entityStates[newEntityId].accountCount,
            states[BEFORE].entityStates[newEntityId].accountCount + 1,
            ER_62
        );
    }

    function invariant_ER_63(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_63);
    }

    function invariant_ER_70(bytes32 entityId, address manager, bool expectedEnabled) internal {
        fl.eq(entityRegistry.isEntityManager(entityId, manager), expectedEnabled, ER_70);
    }

    function invariant_ER_71(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, ER_71);
    }

    function invariant_ER_80(bytes32 entityId, address authority, address managerA, address managerB) internal {
        fl.eq(entityRegistry.getEntityAuthority(entityId), authority, ER_80);
        fl.eq(entityRegistry.isEntityManager(entityId, managerA), true, ER_80);
        fl.eq(entityRegistry.isEntityManager(entityId, managerB), true, ER_80);
    }

    function invariant_ER_81(bytes32 entityId, string memory expectedMetadataRef) internal {
        fl.eq(
            uint256(keccak256(bytes(entityRegistry.getEntityMetadataRef(entityId)))),
            uint256(keccak256(bytes(expectedMetadataRef))),
            ER_81
        );
    }

    function invariant_ER_82(bytes32 entityId, address expectedAuthority) internal {
        fl.eq(entityRegistry.getEntityAuthority(entityId), expectedAuthority, ER_82);
    }

    function invariant_ER_83(address account, uint256 expectedRoleFlags) internal {
        fl.eq(entityRegistry.getAccount(account).roleFlags, expectedRoleFlags, ER_83);
    }

    function invariant_ER_84(address registeredAccount, address missingAccount) internal {
        fl.eq(entityRegistry.doesAccountExist(registeredAccount), true, ER_84);
        fl.eq(entityRegistry.doesAccountExist(missingAccount), false, ER_84);
        fl.eq(entityRegistry.isAccountRegistered(registeredAccount), true, ER_84);
        fl.eq(entityRegistry.isAccountEnabled(registeredAccount), true, ER_84);
        fl.eq(entityRegistry.canTransfer(registeredAccount, registeredAccount, registeredAccount, 0, 0), true, ER_84);
        fl.eq(entityRegistry.canApprove(registeredAccount, registeredAccount, 0, 0), true, ER_84);
        fl.eq(entityRegistry.canTransfer(address(0), registeredAccount, registeredAccount, 0, 0), true, ER_84);
        fl.eq(entityRegistry.canTransfer(registeredAccount, address(0), registeredAccount, 0, 0), true, ER_84);
        fl.eq(entityRegistry.canTransfer(registeredAccount, registeredAccount, address(0), 0, 0), true, ER_84);
        fl.eq(entityRegistry.canApprove(address(0), registeredAccount, 0, 0), true, ER_84);
        fl.eq(entityRegistry.canApprove(registeredAccount, address(0), 0, 0), true, ER_84);
    }

    function invariant_ER_85(address account) internal {
        fl.eq(entityRegistry.isAccountEnabled(account), false, ER_85);
        fl.eq(entityRegistry.canApprove(account, account, 0, 0), false, ER_85);
    }

    function invariant_ER_86(address account) internal {
        fl.eq(entityRegistry.isAccountEnabled(account), false, ER_86);
        fl.eq(entityRegistry.canTransfer(account, account, account, 0, 0), false, ER_86);
    }

    function invariant_ER_87(uint256 typeId, bytes32 name, uint256 caps) internal {
        EntityTypeMeta memory meta = entityRegistry.getEntityTypeMeta(typeId);
        fl.eq(uint256(meta.name), uint256(name), ER_87);
        fl.eq(meta.caps, caps, ER_87);
        fl.eq(meta.frozen, false, ER_87);
    }

    function invariant_ER_88(uint256 typeId) internal {
        EntityTypeMeta memory meta = entityRegistry.getEntityTypeMeta(typeId);
        fl.eq(meta.frozen, true, ER_88);
    }

    function invariant_ER_89(address singleGrantee, address[] memory grantees, uint256 role) internal {
        fl.eq(entityRegistry.hasAnyRole(singleGrantee, role), true, ER_89);
        for (uint256 i; i < grantees.length; ++i) {
            fl.eq(entityRegistry.hasAnyRole(grantees[i], role), true, ER_89);
        }
    }

    function invariant_ER_90(IERC165 registry) internal {
        fl.eq(registry.supportsInterface(type(IEntityRegistry).interfaceId), true, ER_90);
        fl.eq(registry.supportsInterface(type(IERC165).interfaceId), true, ER_90);
        fl.eq(registry.supportsInterface(ERC165_INVALID_INTERFACE_ID), false, ER_90);
    }

    function invariant_ER_91(bytes32 sourceEntityId, bytes32 targetEntityId, address walletA, address walletB)
        internal
    {
        fl.eq(uint256(entityRegistry.getEntityId(walletA)), uint256(targetEntityId), ER_91);
        fl.eq(entityRegistry.isAccountRegistered(walletB), false, ER_91);
        fl.eq(entityRegistry.getEntityAccounts(sourceEntityId).length, 0, ER_91);
        fl.eq(entityRegistry.getEntityAccounts(targetEntityId).length, 1, ER_91);
    }

    function invariant_ER_110(address account, bytes32 entityId, uint256 expectedRoleFlags) internal {
        fl.eq(uint256(states[AFTER].accountStates[account].status), uint256(AccountStatus.ENABLED), ER_110);
        fl.t(states[AFTER].accountStates[account].entityId == entityId, ER_110);
        fl.eq(states[AFTER].accountStates[account].registered, true, ER_110);
        fl.eq(states[AFTER].accountStates[account].roleFlags, expectedRoleFlags, ER_110);
    }

    function invariant_ER_111(bytes32 entityId) internal {
        fl.eq(
            states[AFTER].entityStates[entityId].accountCount,
            states[BEFORE].entityStates[entityId].accountCount + 1,
            ER_111
        );
    }

    function invariant_ER_112(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Ownable.Unauthorized.selector, ER_112);
    }

    function invariant_ER_113(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ZeroAddress.selector, ER_113);
    }

    function invariant_ER_114(bytes4 errorSelector, bytes4 expectedSelector) internal {
        _assertERError(errorSelector, expectedSelector, ER_114);
    }

    function invariant_ER_115(bytes4 errorSelector) internal {
        _assertERError(errorSelector, Errors.ER__AccountAlreadyRegistered.selector, ER_115);
    }

    function _assertERError(bytes4 errorSelector, bytes4 expectedSelector, string memory label) private {
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedSelector;
        fl.errAllow(errorSelector, allowedErrors, label);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore */

import {PreconditionsEntityRegistry} from "../preconditions/PreconditionsEntityRegistry.sol";
import {PostconditionsBase} from "./PostconditionsBase.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Errors} from "src/libs/Errors.sol";

abstract contract PostconditionsEntityRegistry is PostconditionsBase {
    function registerEntityPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RegisterEntityParams memory params
    ) internal {
        if (success) {
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            _afterER(entityIds, _emptyAddressArray());
            invariant_ER_10(params.entityId, params.typeId);
            invariant_ER_11(params.entityId);
            invariant_ER_01();
        } else {
            invariant_ER_12(_returnSelectorER(returnData));
        }
    }

    function setEntityStatusPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.SetEntityStatusParams memory params
    ) internal {
        if (success) {
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            _afterER(entityIds, _emptyAddressArray());
            invariant_ER_20(params.entityId, params.status);
            invariant_ER_01();
        } else {
            invariant_ER_21(_returnSelectorER(returnData));
        }
    }

    function registerAccountPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RegisterAccountParams memory params
    ) internal {
        if (success) {
            invariant_ER_33(params.managerAuthorized);
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_30(params.wallet, params.entityId);
            invariant_ER_31(params.entityId);
            invariant_ER_01();
        } else {
            if (params.managerAuthorized) {
                invariant_ER_32(_returnSelectorER(returnData));
            } else {
                invariant_ER_33(_returnSelectorER(returnData));
            }
        }
    }

    function requestAccountRegistrationPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RequestAccountRegistrationParams memory params
    ) internal {
        if (success) {
            _trackPendingRegistration(params.wallet, params.entityId);
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_92(params.wallet, params.entityId, params.roleFlags, params.requester);
            invariant_ER_93(params.wallet, params.entityId);
            invariant_ER_01();
        } else if (params.requesterAuthorized) {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-PREQ: auth request reverted");
        } else {
            invariant_ER_96(_returnSelectorER(returnData));
        }
    }

    function acceptAccountRegistrationPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.AcceptAccountRegistrationParams memory params
    ) internal {
        if (success) {
            _clearPendingRegistration(params.wallet, params.entityId);
            _setFuzzAccountRegistered(params.wallet, true);
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_100(params.wallet, params.entityId, params.roleFlags);
            invariant_ER_101(params.entityId);
            invariant_ER_102(params.wallet, params.entityId);
            invariant_ER_01();
        } else if (!params.entityEnabled) {
            invariant_ER_98(_returnSelectorER(returnData), Errors.ER__EntityNotEnabled.selector);
        } else if (params.accountRegistered) {
            invariant_ER_104(_returnSelectorER(returnData));
        } else if (params.requester == address(0)) {
            invariant_ER_103(_returnSelectorER(returnData));
        } else if (!params.requesterAuthorized) {
            invariant_ER_105(_returnSelectorER(returnData));
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-PACC: valid accept reverted");
        }
    }

    function adminRegisterAccountPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.AdminRegisterAccountParams memory params
    ) internal {
        if (success) {
            _setFuzzAccountRegistered(params.wallet, true);
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_110(params.wallet, params.entityId, params.roleFlags);
            invariant_ER_111(params.entityId);
            invariant_ER_01();
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-AREG: admin register reverted");
        }
    }

    function setAccountStatusPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.SetAccountStatusParams memory params
    ) internal {
        if (success) {
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(_emptyBytes32Array(), accounts);
            invariant_ER_40(params.wallet, params.status);
            invariant_ER_01();
        } else {
            invariant_ER_41(_returnSelectorER(returnData));
        }
    }

    function removeAccountPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RemoveAccountParams memory params
    ) internal {
        if (success) {
            bytes32[] memory entityIds = _singleBytes32Array(params.entityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_50(params.wallet);
            invariant_ER_51(params.entityId);
            invariant_ER_01();
        } else {
            invariant_ER_52(_returnSelectorER(returnData));
        }
    }

    function transferAccountPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.TransferAccountParams memory params
    ) internal {
        if (success) {
            bytes32[] memory entityIds = _twoBytes32Array(params.oldEntityId, params.newEntityId);
            address[] memory accounts = _singleActorArray(params.wallet);
            _afterER(entityIds, accounts);
            invariant_ER_60(params.wallet, params.newEntityId);
            invariant_ER_61(params.oldEntityId);
            invariant_ER_62(params.newEntityId);
            invariant_ER_01();
        } else {
            invariant_ER_63(_returnSelectorER(returnData));
        }
    }

    function setEntityManagerPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.SetEntityManagerParams memory params
    ) internal {
        if (success) {
            // Manager flag changes are live-read; no snapshot delta needed.
            _afterER(_emptyBytes32Array(), _emptyAddressArray());
            invariant_ER_70(params.entityId, params.manager, params.enabled);
            invariant_ER_01();
        } else {
            invariant_ER_71(_returnSelectorER(returnData));
        }
    }

    function requestAccountRegistrationOverwritePostconditions(
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        address requester
    ) internal {
        _afterER(_singleBytes32Array(entityId), _singleActorArray(wallet));
        invariant_ER_94(wallet, entityId, roleFlags, requester);
        invariant_ER_93(wallet, entityId);
        invariant_ER_01();
    }

    function requestAccountRegistrationMultipleEntitiesPostconditions(
        address wallet,
        bytes32 entityIdA,
        bytes32 entityIdB,
        uint256 roleFlagsA,
        uint256 roleFlagsB,
        address requester
    ) internal {
        _afterER(_twoBytes32Array(entityIdA, entityIdB), _singleActorArray(wallet));
        invariant_ER_95(wallet, entityIdA, entityIdB, roleFlagsA, roleFlagsB, requester);
        invariant_ER_93(wallet, entityIdA);
        invariant_ER_93(wallet, entityIdB);
        invariant_ER_01();
    }

    function registerAccountUnauthorizedPostconditions(bool success, bytes memory returnData) internal {
        fl.eq(success, false, ER_112);
        invariant_ER_112(_returnSelectorER(returnData));
    }

    function registerAccountInvalidInputPostconditions(
        bool success,
        bytes memory returnData,
        bytes4 expectedSelector,
        string memory invariantLabel
    ) internal {
        fl.eq(success, false, invariantLabel);
        bytes4 errorSelector = _returnSelectorER(returnData);
        if (expectedSelector == Errors.ZeroAddress.selector) {
            invariant_ER_113(errorSelector);
        } else if (expectedSelector == Errors.ER__AccountAlreadyRegistered.selector) {
            invariant_ER_115(errorSelector);
        } else {
            invariant_ER_114(errorSelector, expectedSelector);
        }
    }

    function requestAccountRegistrationInvalidInputPostconditions(
        bool success,
        bytes memory returnData,
        bytes4 expectedSelector,
        string memory invariantLabel
    ) internal {
        fl.eq(success, false, invariantLabel);
        bytes4 errorSelector = _returnSelectorER(returnData);
        if (expectedSelector == Errors.ZeroAddress.selector) {
            invariant_ER_97(errorSelector);
        } else if (expectedSelector == Errors.ER__AccountAlreadyRegistered.selector) {
            invariant_ER_99(errorSelector);
        } else {
            invariant_ER_98(errorSelector, expectedSelector);
        }
    }

    function acceptRegistrationMissingPendingPostconditions(bool success, bytes memory returnData) internal {
        fl.eq(success, false, ER_103);
        invariant_ER_103(_returnSelectorER(returnData));
    }

    function acceptRegistrationAlreadyRegisteredPostconditions(bool success, bytes memory returnData) internal {
        fl.eq(success, false, ER_104);
        invariant_ER_104(_returnSelectorER(returnData));
    }

    function requesterRevocationBeforeAcceptancePostconditions(
        bool success,
        bytes memory returnData,
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        address requester
    ) internal {
        fl.eq(success, false, ER_105);
        invariant_ER_105(_returnSelectorER(returnData));
        invariant_ER_106(wallet, entityId, roleFlags, requester);
    }

    function stalePendingRegistrationPostconditions(
        address wallet,
        bytes32 entityId,
        uint256 roleFlags,
        address requester
    ) internal {
        invariant_ER_107(wallet, entityId, roleFlags, requester);
    }

    function registerEntityWithAccessPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RegisterEntityParams memory params,
        address authority,
        address managerA,
        address managerB
    ) internal {
        if (success) {
            _afterER(_singleBytes32Array(params.entityId), _emptyAddressArray());
            invariant_ER_10(params.entityId, params.typeId);
            invariant_ER_11(params.entityId);
            invariant_ER_01();
            invariant_ER_80(params.entityId, authority, managerA, managerB);
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-ACCESS-UNEXPECTED");
        }
    }

    function registerEntityBatchPostconditions(
        bool success,
        bytes memory returnData,
        PreconditionsEntityRegistry.RegisterEntityParams memory paramsA,
        PreconditionsEntityRegistry.RegisterEntityParams memory paramsB,
        bytes32[] memory entityIds,
        string[] memory metadataRefs
    ) internal {
        if (success) {
            _afterER(entityIds, _emptyAddressArray());
            invariant_ER_10(paramsA.entityId, paramsA.typeId);
            invariant_ER_11(paramsA.entityId);
            invariant_ER_10(paramsB.entityId, paramsB.typeId);
            invariant_ER_11(paramsB.entityId);
            invariant_ER_01();
            invariant_ER_81(paramsA.entityId, metadataRefs[0]);
            invariant_ER_81(paramsB.entityId, metadataRefs[1]);
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-BATCH-UNEXPECTED");
        }
    }

    function setEntityMetadataPostconditions(
        bool success,
        bytes memory returnData,
        bytes32 entityId,
        string memory metadataRef
    ) internal {
        if (success) {
            _afterER(_singleBytes32Array(entityId), _emptyAddressArray());
            invariant_ER_01();
            invariant_ER_81(entityId, metadataRef);
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-METADATA-UNEXPECTED");
        }
    }

    function setEntityAuthorityPostconditions(
        bool success,
        bytes memory returnData,
        bytes32 entityId,
        address expectedAuthority
    ) internal {
        if (success) {
            _afterER(_singleBytes32Array(entityId), _emptyAddressArray());
            invariant_ER_01();
            invariant_ER_82(entityId, expectedAuthority);
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-AUTHORITY-UNEXPECTED");
        }
    }

    function setAccountRoleFlagsPostconditions(
        bool success,
        bytes memory returnData,
        bytes32 entityId,
        address account,
        uint256 roleFlags
    ) internal {
        if (success) {
            _afterER(_singleBytes32Array(entityId), _singleActorArray(account));
            invariant_ER_01();
            invariant_ER_83(account, roleFlags);
        } else {
            entityRegistryUnexpectedRevertPostconditions(success, returnData, "ER-ROLE-FLAGS-UNEXPECTED");
        }
    }

    function entityRegistryViewSurfaceInitialPostconditions(address registeredAccount, address missingAccount)
        internal
    {
        invariant_ER_84(registeredAccount, missingAccount);
        invariant_ER_90(entityRegistry);
    }

    function entityRegistryDisabledAccountPostconditions(address account) internal {
        invariant_ER_85(account);
    }

    function entityRegistryDisabledEntityPostconditions(address account) internal {
        invariant_ER_86(account);
    }

    function entityRegistryViewSurfacePostconditions(bytes32 entityId, address account) internal {
        _afterER(_singleBytes32Array(entityId), _singleActorArray(account));
        invariant_ER_01();
    }

    function entityTypeDefinedPostconditions(uint256 typeId, bytes32 name, uint256 caps) internal {
        invariant_ER_87(typeId, name, caps);
    }

    function entityTypeFrozenPostconditions(uint256 typeId) internal {
        invariant_ER_88(typeId);
    }

    function entityRegistryAdminGrantPostconditions(address singleGrantee, address[] memory grantees, uint256 role)
        internal
    {
        invariant_ER_89(singleGrantee, grantees, role);
    }

    function entityRegistryFreshDeploymentPostconditions(IERC165 registry) internal {
        invariant_ER_90(registry);
    }

    function entityAccountSwapAndPopPostconditions(
        bytes32 sourceEntityId,
        bytes32 targetEntityId,
        address walletA,
        address walletB
    ) internal {
        _afterER(_twoBytes32Array(sourceEntityId, targetEntityId), _twoActorArray(walletA, walletB));
        invariant_ER_01();
        invariant_ER_91(sourceEntityId, targetEntityId, walletA, walletB);
    }

    function _returnSelectorER(bytes memory returnData) internal pure returns (bytes4 errorSelector) {
        if (returnData.length > 3) {
            errorSelector = bytes4(returnData);
        }
    }

    function entityRegistryUnexpectedRevertPostconditions(bool success, bytes memory returnData, string memory reason)
        internal
    {
        if (!success) {
            bytes4[] memory allowedErrors = new bytes4[](0);
            fl.errAllow(_returnSelectorER(returnData), allowedErrors, reason);
        }
    }

    function entityRegistryExpectedRevertPostconditions(
        bool success,
        bytes memory returnData,
        bytes4 expectedError,
        string memory reason
    ) internal {
        fl.eq(success, false, reason);

        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedError;
        fl.errAllow(_returnSelectorER(returnData), allowedErrors, reason);
    }
}

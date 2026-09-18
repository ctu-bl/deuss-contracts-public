// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerDEUSSToken} from "./helper/handlers/HandlerDEUSSToken.sol";

/**
 * @title FuzzDEUSSTokenIntegrity
 * @notice Checks handler integrity for the issued bond DEUSSToken fuzz harness
 */
contract FuzzDEUSSTokenIntegrity is HandlerDEUSSToken, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_approve`
     * @param spenderSeed Seed used to pick the approval spender
     * @param amountSeed Seed used to derive the allowance amount
     */
    function fuzz_approve(uint256 spenderSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_approve.selector, spenderSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-APPROVE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_approveOverwriteExisting`
     * @param spenderSeed Seed used to pick a spender with existing allowance
     * @param amountSeed Seed used to derive the new allowance amount
     */
    function fuzz_approveOverwriteExisting(uint256 spenderSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_approveOverwriteExisting.selector, spenderSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-APPROVE-OVERWRITE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_grantRolesBatchInvalidRoles`
     * @param userSeed Seed used to pick the first batch role recipient
     * @param roleBitSeed Seed used to pick an invalid role bit
     */
    function fuzz_grantRolesBatchInvalidRoles(uint256 userSeed, uint256 roleBitSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_grantRolesBatchInvalidRoles.selector, userSeed, roleBitSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-GRANT-ROLES-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_transfer`
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_transfer(uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_transfer.selector, receiverSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-TRANSFER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_transferFromAllowance`
     * @param ownerSeed Seed used to select an owner with allowance
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_transferFromAllowance(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_transferFromAllowance.selector, ownerSeed, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-TRANSFER-ALLOWANCE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setOperator`
     * @param operatorSeed Seed used to pick the operator
     * @param approved Whether the operator should be approved
     */
    function fuzz_setOperator(uint256 operatorSeed, bool approved) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_setOperator.selector, operatorSeed, approved);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-OPERATOR");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setOperatorUnregistered`
     */
    function fuzz_setOperatorUnregistered() public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEUSSToken.handler_setOperatorUnregistered.selector);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-OPERATOR-UNREGISTERED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_transferFromOperator`
     * @param ownerSeed Seed used to select an owner that approved the current actor
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_transferFromOperator(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_transferFromOperator.selector, ownerSeed, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-TRANSFER-OPERATOR");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchTransferFromSingleReceiver`
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_batchTransferFromSingleReceiver(uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchTransferFromSingleReceiver.selector, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TKN-BATCH-TRANSFER-1");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchTransferFromMultipleReceivers`
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_batchTransferFromMultipleReceivers(uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchTransferFromMultipleReceivers.selector, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TKN-BATCH-TRANSFER-N");
        }
    }

    /**
     * @notice Checks the integrity of `handler_freezePartialTokens`
     * @param accountSeed Seed used to pick an account with free balance
     * @param amountSeed Seed used to derive the frozen amount
     */
    function fuzz_freezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_freezePartialTokens.selector, accountSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-FREEZE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchFreezePartialTokens`
     * @param accountSeed Seed used to pick an account with free balance
     * @param amountSeed Seed used to derive the frozen amount
     */
    function fuzz_batchFreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchFreezePartialTokens.selector, accountSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BATCH-FREEZE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_unfreezePartialTokens`
     * @param accountSeed Seed used to pick an account with frozen balance
     * @param amountSeed Seed used to derive the unfrozen amount
     */
    function fuzz_unfreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_unfreezePartialTokens.selector, accountSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-UNFREEZE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchUnfreezePartialTokens`
     * @param accountSeed Seed used to pick an account with frozen balance
     * @param amountSeed Seed used to derive the unfrozen amount
     */
    function fuzz_batchUnfreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchUnfreezePartialTokens.selector, accountSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BATCH-UNFREEZE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_forcedTransfer`
     * @param fromSeed Seed used to pick a source account with balance
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_forcedTransfer(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_forcedTransfer.selector, fromSeed, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-FORCED-TRANSFER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchForcedTransfer`
     * @param fromSeed Seed used to pick a source account with balance
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_batchForcedTransfer(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchForcedTransfer.selector, fromSeed, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BATCH-FORCED-TRANSFER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_forcedTransferToProtectedReceiver`
     * @param fromSeed Seed used to pick a source account with balance
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_forcedTransferToProtectedReceiver(uint256 fromSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_forcedTransferToProtectedReceiver.selector, fromSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TKN-FORCE-PROTECTED");
        }
    }

    /**
     * @notice Checks the integrity of `handler_batchForcedTransferToProtectedReceiver`
     * @param fromSeed Seed used to pick a source account with balance
     * @param amountSeed Seed used to derive the transfer amount
     */
    function fuzz_batchForcedTransferToProtectedReceiver(uint256 fromSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_batchForcedTransferToProtectedReceiver.selector, fromSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TKN-BATCH-FORCE-PROT");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burn`
     * @param fromSeed Seed used to pick a source account with balance
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burn(uint256 fromSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEUSSToken.handler_burn.selector, fromSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BURN");
        }
    }

    /**
     * @notice Checks the integrity of `handler_burnBatch`
     * @param fromSeed Seed used to pick a source account with balance
     * @param amountSeed Seed used to derive the burned amount
     */
    function fuzz_burnBatch(uint256 fromSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_burnBatch.selector, fromSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BURN-BATCH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_protectAddress`
     * @param accountSeed Seed used to pick an unprotected address
     */
    function fuzz_protectAddress(uint256 accountSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEUSSToken.handler_protectAddress.selector, accountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-PROTECT-ADDRESS");
        }
    }

    /**
     * @notice Checks protected receiver transfer rejection
     * @param senderSeed Seed used to pick a source account
     * @param amountSeed Seed used to derive the attempted amount
     */
    function fuzz_protectedReceiverTransfer(uint256 senderSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_protectedReceiverTransfer.selector, senderSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-PROTECTED-RECEIVER");
        }
    }

    /**
     * @notice Checks the integrity of `handler_checkpointFutureReverts`
     * @param accountSeed Seed used to pick a tracked account
     */
    function fuzz_checkpointFutureReverts(uint256 accountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_checkpointFutureReverts.selector, accountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-CHECKPOINT-FUTURE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setContractPause`
     * @param paused True to pause the token contract
     */
    function fuzz_setContractPause(bool paused) public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEUSSToken.handler_setContractPause.selector, paused);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-CONTRACT-PAUSE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_setBondSuspended`
     * @param suspended True to suspend the issued bond token ID
     */
    function fuzz_setBondSuspended(bool suspended) public {
        bytes memory callData = abi.encodeWithSelector(HandlerDEUSSToken.handler_setBondSuspended.selector, suspended);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-BOND-SUSPEND");
        }
    }

    /**
     * @notice Checks the integrity of `handler_contractPauseBlocksAction`
     * @param spenderSeed Seed used to pick the approval spender
     */
    function fuzz_contractPauseBlocksAction(uint256 spenderSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerDEUSSToken.handler_contractPauseBlocksAction.selector, spenderSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-CONTRACT-PAUSE-BLOCKS");
        }
    }

    /**
     * @notice Checks the integrity of `handler_tokenIdPauseBlocksTransfer`
     * @param senderSeed Seed used to pick a source account with free balance
     * @param receiverSeed Seed used to pick the transfer receiver
     * @param amountSeed Seed used to derive the attempted transfer amount
     */
    function fuzz_tokenIdPauseBlocksTransfer(uint256 senderSeed, uint256 receiverSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerDEUSSToken.handler_tokenIdPauseBlocksTransfer.selector, senderSeed, receiverSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-TOKEN-ID-PAUSE-BLOCKS");
        }
    }
}

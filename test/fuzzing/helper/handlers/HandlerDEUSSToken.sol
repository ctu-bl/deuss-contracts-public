// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {PreconditionsDEUSSToken} from "../preconditions/PreconditionsDEUSSToken.sol";
import {PostconditionsDEUSSToken} from "../postconditions/PostconditionsDEUSSToken.sol";

/// @title HandlerDEUSSToken
/// @notice Stateful fuzz handlers for the issued bond DEUSSToken vertical slice.
abstract contract HandlerDEUSSToken is PreconditionsDEUSSToken, PostconditionsDEUSSToken {
    bytes4 private constant _BATCH_TRANSFER_SINGLE_RECEIVER_SELECTOR = 0x17fad7fc;
    bytes4 private constant _BATCH_TRANSFER_MULTIPLE_RECEIVERS_SELECTOR = 0x80883397;
    bytes4 private constant _GRANT_ROLES_BATCH_SELECTOR = bytes4(keccak256("grantRoles(address[],uint256)"));

    /// @notice Attempts to write an ERC-6909 allowance for the current actor.
    /// @param spenderSeed Seed used to pick the spender from USERS.
    /// @param amountSeed Seed used to derive the allowance amount.
    function handler_approve(uint256 spenderSeed, uint256 amountSeed) public setCurrentActor {
        ApproveParams memory params = approvePreconditions(spenderSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.spender);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.spender);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.approve.selector, params.spender, bondTokenId, params.amount),
            params.owner
        );

        approvePostconditions(success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate, params);
    }

    /// @notice Attempts to overwrite an existing nonzero allowance with another nonzero allowance.
    /// @param spenderSeed Seed used to pick a spender with an existing allowance from the current actor.
    /// @param amountSeed Seed used to derive the new nonzero allowance.
    function handler_approveOverwriteExisting(uint256 spenderSeed, uint256 amountSeed) public setCurrentActor {
        ApproveParams memory params = approveOverwriteExistingPreconditions(spenderSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.spender);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.spender);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.approve.selector, params.spender, bondTokenId, params.amount),
            params.owner
        );

        approveOverwriteExistingPostconditions(
            success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate, params
        );
    }

    /// @notice Attempts to batch-grant an out-of-range BaseToken role bitmap through the owner.
    /// @param userSeed Seed used to pick the first batch user from USERS.
    /// @param roleBitSeed Seed used to pick an invalid role bit outside BaseToken.ALL_ROLES.
    function handler_grantRolesBatchInvalidRoles(uint256 userSeed, uint256 roleBitSeed) public {
        GrantRolesBatchParams memory params = grantRolesBatchInvalidRolesPreconditions(userSeed, roleBitSeed);

        _beforeToken(params.users, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token), abi.encodeWithSelector(_GRANT_ROLES_BATCH_SELECTOR, params.users, params.roles)
        );

        grantRolesBatchInvalidRolesPostconditions(success, returnData, params);
    }

    /// @notice Attempts a normal transfer from the current actor.
    /// @param receiverSeed Seed used to pick a receiver from USERS.
    /// @param amountSeed Seed used to derive the transfer amount.
    function handler_transfer(uint256 receiverSeed, uint256 amountSeed) public setCurrentActor {
        TransferParams memory params = transferPreconditions(receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, params.to, bondTokenId, params.amount),
            params.from
        );

        transferPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Attempts transferFrom through an existing allowance to the current actor.
    /// @param ownerSeed Seed used to select an owner with allowance to the current actor.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the transferred amount.
    function handler_transferFromAllowance(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed)
        public
        setCurrentActor
    {
        AllowanceTransferParams memory params = transferFromAllowancePreconditions(ownerSeed, receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.receiver);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.spender);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(
                token.transferFrom.selector, params.owner, params.receiver, bondTokenId, params.amount
            ),
            params.spender
        );

        transferFromAllowancePostconditions(
            success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate, params
        );
    }

    /// @notice Enables or revokes an operator for the current actor.
    /// @param operatorSeed Seed used to pick an enabled operator from USERS.
    /// @param approved Whether to grant or revoke operator approval.
    function handler_setOperator(uint256 operatorSeed, bool approved) public setCurrentActor {
        OperatorParams memory params = setOperatorPreconditions(operatorSeed, approved);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.operator);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.operator);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.setOperator.selector, params.operator, params.approved),
            params.owner
        );

        setOperatorPostconditions(success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate, params);
    }

    /// @notice Attempts to enable an operator that is not registered/enabled in EntityRegistry.
    function handler_setOperatorUnregistered() public setCurrentActor {
        OperatorParams memory params = setOperatorUnregisteredPreconditions();

        address[] memory actorsToUpdate = _singleActorArray(params.owner);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.operator);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token), abi.encodeWithSelector(token.setOperator.selector, params.operator, true), params.owner
        );

        setOperatorUnregisteredPostconditions(success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate);
    }

    /// @notice Attempts transferFrom through an existing operator approval to the current actor.
    /// @param ownerSeed Seed used to select an owner that approved the current actor as operator.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the transferred amount.
    function handler_transferFromOperator(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed)
        public
        setCurrentActor
    {
        OperatorTransferParams memory params = transferFromOperatorPreconditions(ownerSeed, receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.receiver);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.operator);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(
                token.transferFrom.selector, params.owner, params.receiver, bondTokenId, params.amount
            ),
            params.operator
        );

        transferFromOperatorPostconditions(
            success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate, params
        );
    }

    /// @notice Batch-transfers one issued token ID from the current actor to one receiver.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the transferred amount.
    function handler_batchTransferFromSingleReceiver(uint256 receiverSeed, uint256 amountSeed) public setCurrentActor {
        TransferParams memory params = batchTransferFromSingleReceiverPreconditions(receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        uint256[] memory tokenIds = _singleUintArray(bondTokenId);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(_BATCH_TRANSFER_SINGLE_RECEIVER_SELECTOR, params.from, params.to, tokenIds, amounts),
            params.from
        );

        batchTransferFromSingleReceiverPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Batch-transfers the issued token ID from the current actor to one receiver.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the transferred amount.
    function handler_batchTransferFromMultipleReceivers(uint256 receiverSeed, uint256 amountSeed)
        public
        setCurrentActor
    {
        TransferParams memory params = batchTransferFromMultipleReceiversPreconditions(receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        address[] memory tos = _singleActorArray(params.to);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(_BATCH_TRANSFER_MULTIPLE_RECEIVERS_SELECTOR, params.from, tos, bondTokenId, amounts),
            params.from
        );

        batchTransferFromMultipleReceiversPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Freezes part of a tracked user's bond-token balance.
    /// @param accountSeed Seed used to pick an account with free balance.
    /// @param amountSeed Seed used to derive the frozen amount.
    function handler_freezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        FreezeParams memory params = freezePartialTokensPreconditions(accountSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.account);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.freezePartialTokens.selector, params.account, bondTokenId, params.amount)
        );

        freezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Batch-freezes part of a tracked user's bond-token balance.
    /// @param accountSeed Seed used to pick an account with free balance.
    /// @param amountSeed Seed used to derive the frozen amount.
    function handler_batchFreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        FreezeParams memory params = batchFreezePartialTokensPreconditions(accountSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.account);
        address[] memory wallets = _singleActorArray(params.account);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.batchFreezePartialTokens.selector, wallets, bondTokenId, amounts)
        );

        batchFreezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Unfreezes part of a tracked user's frozen bond-token balance.
    /// @param accountSeed Seed used to pick an account with frozen balance.
    /// @param amountSeed Seed used to derive the unfrozen amount.
    function handler_unfreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        FreezeParams memory params = unfreezePartialTokensPreconditions(accountSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.account);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.unfreezePartialTokens.selector, params.account, bondTokenId, params.amount)
        );

        unfreezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Batch-unfreezes part of a tracked user's frozen bond-token balance.
    /// @param accountSeed Seed used to pick an account with frozen balance.
    /// @param amountSeed Seed used to derive the unfrozen amount.
    function handler_batchUnfreezePartialTokens(uint256 accountSeed, uint256 amountSeed) public {
        FreezeParams memory params = batchUnfreezePartialTokensPreconditions(accountSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.account);
        address[] memory wallets = _singleActorArray(params.account);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.batchUnfreezePartialTokens.selector, wallets, bondTokenId, amounts)
        );

        batchUnfreezePartialTokensPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Force transfers a tracked user's balance through the harness role holder.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the forced transfer amount.
    function handler_forcedTransfer(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed) public {
        ForcedTransferParams memory params = forcedTransferPreconditions(fromSeed, receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.forcedTransfer.selector, params.from, params.to, bondTokenId, params.amount)
        );

        forcedTransferPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Batch force-transfers a tracked user's balance through the harness role holder.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the forced transfer amount.
    function handler_batchForcedTransfer(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed) public {
        ForcedTransferParams memory params = batchForcedTransferPreconditions(fromSeed, receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        address[] memory froms = _singleActorArray(params.from);
        address[] memory tos = _singleActorArray(params.to);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token), abi.encodeWithSelector(token.batchForcedTransfer.selector, froms, tos, bondTokenId, amounts)
        );

        batchForcedTransferPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Attempts a forced transfer into protected custody and expects the protected-receiver guard.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param amountSeed Seed used to derive the forced transfer amount.
    function handler_forcedTransferToProtectedReceiver(uint256 fromSeed, uint256 amountSeed) public {
        ForcedTransferParams memory params = forcedTransferToProtectedReceiverPreconditions(fromSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.forcedTransfer.selector, params.from, params.to, bondTokenId, params.amount)
        );

        forcedTransferToProtectedReceiverPostconditions(success, returnData, actorsToUpdate);
    }

    /// @notice Attempts a batch forced transfer into protected custody and expects the protected-receiver guard.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param amountSeed Seed used to derive the forced transfer amount.
    function handler_batchForcedTransferToProtectedReceiver(uint256 fromSeed, uint256 amountSeed) public {
        ForcedTransferParams memory params = batchForcedTransferToProtectedReceiverPreconditions(fromSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        address[] memory froms = _singleActorArray(params.from);
        address[] memory tos = _singleActorArray(params.to);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token), abi.encodeWithSelector(token.batchForcedTransfer.selector, froms, tos, bondTokenId, amounts)
        );

        batchForcedTransferToProtectedReceiverPostconditions(success, returnData, actorsToUpdate);
    }

    /// @notice Burns a tracked user's balance through the BondRegistry-only token entrypoint.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burn(uint256 fromSeed, uint256 amountSeed) public {
        TokenBurnParams memory params = burnPreconditions(fromSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.from);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.burn.selector, params.from, bondTokenId, params.amount),
            address(bondRegistry)
        );

        if (success) {
            (, uint8 version) = bondRegistry.getBondSeriesByTokenId(bondTokenId);
            burnedSettled[version] += params.amount;
        }

        burnPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Batch-burns a tracked user's balance through the BondRegistry-only token entrypoint.
    /// @param fromSeed Seed used to pick a source account with balance.
    /// @param amountSeed Seed used to derive the burned amount.
    function handler_burnBatch(uint256 fromSeed, uint256 amountSeed) public {
        TokenBurnParams memory params = burnBatchPreconditions(fromSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.from);
        address[] memory froms = _singleActorArray(params.from);
        uint256[] memory amounts = _singleUintArray(params.amount);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.burnBatch.selector, froms, bondTokenId, amounts),
            address(bondRegistry)
        );

        if (success) {
            (, uint8 version) = bondRegistry.getBondSeriesByTokenId(bondTokenId);
            burnedSettled[version] += params.amount;
        }

        burnBatchPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Marks a non-token-flow address as protected custody through the token owner.
    /// @param accountSeed Seed used to pick an unprotected address from the fuzz wallet pool.
    function handler_protectAddress(uint256 accountSeed) public {
        ProtectAddressParams memory params = protectAddressPreconditions(accountSeed);

        _beforeToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) =
            fl.doFunctionCall(address(token), abi.encodeWithSelector(token.protectAddress.selector, params.account));

        protectAddressPostconditions(success, returnData, params);
    }

    /// @notice Attempts a normal transfer into a protected custody address.
    /// @param senderSeed Seed used to pick a source account with free balance.
    /// @param amountSeed Seed used to derive the attempted transfer amount.
    function handler_protectedReceiverTransfer(uint256 senderSeed, uint256 amountSeed) public {
        ProtectedReceiverTransferParams memory params = protectedReceiverTransferPreconditions(senderSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, params.to, bondTokenId, params.amount),
            params.from
        );

        protectedReceiverTransferPostconditions(success, returnData, actorsToUpdate, params);
    }

    /// @notice Exercises the future-block checkpoint rejection path.
    /// @param accountSeed Seed used to pick a tracked account for the historical query.
    function handler_checkpointFutureReverts(uint256 accountSeed) public {
        FutureCheckpointParams memory params = futureCheckpointPreconditions(accountSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.balanceOfAt.selector, params.account, bondTokenId, params.blockNumber)
        );

        futureCheckpointPostconditions(success, returnData);
    }

    /// @notice Toggles the token contract-level pause state.
    /// @param paused True to pause, false to unpause.
    function handler_setContractPause(bool paused) public {
        PauseParams memory params = setContractPausePreconditions(paused);

        _beforeToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());

        bytes memory callData = params.paused
            ? abi.encodeWithSelector(token.pause.selector)
            : abi.encodeWithSelector(token.unpause.selector);
        (bool success, bytes memory returnData) = fl.doFunctionCall(address(token), callData);

        setContractPausePostconditions(success, returnData, params);
    }

    /// @notice Toggles the issued bond suspension state through BondRegistry.
    /// @param suspended True to suspend, false to unsuspend.
    function handler_setBondSuspended(bool suspended) public {
        BondSuspensionParams memory params = setBondSuspendedPreconditions(suspended);

        _beforeToken(_emptyAddressArray(), _emptyAddressArray(), _emptyAddressArray());

        bytes memory callData = params.suspended
            ? abi.encodeWithSelector(bondRegistry.suspendBond.selector, BOND_ISIN, 1)
            : abi.encodeWithSelector(bondRegistry.unsuspendBond.selector, BOND_ISIN, 1);
        (bool success, bytes memory returnData) = fl.doFunctionCall(address(bondRegistry), callData);

        setBondSuspendedPostconditions(success, returnData, params);
    }

    /// @notice Ensures contract-level pause blocks token actions.
    /// @param spenderSeed Seed used to pick an approval spender.
    function handler_contractPauseBlocksAction(uint256 spenderSeed) public setCurrentActor {
        ApproveParams memory params = contractPauseBlocksActionPreconditions(spenderSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.owner, params.spender);
        address[] memory ownersToUpdate = _singleActorArray(params.owner);
        address[] memory spendersToUpdate = _singleActorArray(params.spender);
        _beforeToken(actorsToUpdate, ownersToUpdate, spendersToUpdate);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.approve.selector, params.spender, bondTokenId, params.amount),
            params.owner
        );

        contractPauseBlocksActionPostconditions(success, returnData, actorsToUpdate, ownersToUpdate, spendersToUpdate);
    }

    /// @notice Ensures a suspended bond token ID blocks normal transfers.
    /// @param senderSeed Seed used to pick a source account with free balance.
    /// @param receiverSeed Seed used to pick the transfer receiver.
    /// @param amountSeed Seed used to derive the attempted transfer amount.
    function handler_tokenIdPauseBlocksTransfer(uint256 senderSeed, uint256 receiverSeed, uint256 amountSeed) public {
        TransferParams memory params = tokenIdPauseBlocksTransferPreconditions(senderSeed, receiverSeed, amountSeed);

        address[] memory actorsToUpdate = _twoActorArray(params.from, params.to);
        _beforeToken(actorsToUpdate, _emptyAddressArray(), _emptyAddressArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, params.to, bondTokenId, params.amount),
            params.from
        );

        tokenIdPauseBlocksTransferPostconditions(success, returnData, actorsToUpdate, params);
    }
}

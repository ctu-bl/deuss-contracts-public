// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {BondStatus} from "src/registry/BondStructs.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsDEUSSToken is PreconditionsBase {
    struct ApproveParams {
        address owner;
        address spender;
        uint256 amount;
    }

    struct GrantRolesBatchParams {
        address[] users;
        uint256 roles;
        uint256[] beforeRoles;
    }

    struct TransferParams {
        address from;
        address to;
        uint256 amount;
    }

    struct AllowanceTransferParams {
        address owner;
        address spender;
        address receiver;
        uint256 amount;
    }

    struct OperatorParams {
        address owner;
        address operator;
        bool approved;
    }

    struct OperatorTransferParams {
        address owner;
        address operator;
        address receiver;
        uint256 amount;
    }

    struct FreezeParams {
        address account;
        uint256 amount;
    }

    struct ForcedTransferParams {
        address from;
        address to;
        uint256 amount;
        uint256 expectedFrozenAfter;
    }

    struct TokenBurnParams {
        address from;
        uint256 amount;
        uint256 expectedFrozenAfter;
    }

    struct ProtectAddressParams {
        address account;
    }

    struct ProtectedReceiverTransferParams {
        address from;
        address to;
        uint256 amount;
    }

    struct FutureCheckpointParams {
        address account;
        uint256 blockNumber;
    }

    struct PauseParams {
        bool paused;
    }

    struct BondSuspensionParams {
        bool suspended;
    }

    function approvePreconditions(uint256 spenderSeed, uint256 amountSeed)
        internal
        returns (ApproveParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        address owner = currentActor;
        address spender = users[fl.clamp(spenderSeed, 0, users.length - 1)];

        params.owner = owner;
        params.spender = spender;
        params.amount = fl.clamp(amountSeed, 0, initialIssuedSupply);
    }

    function approveOverwriteExistingPreconditions(uint256 spenderSeed, uint256 amountSeed)
        internal
        returns (ApproveParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        address owner = currentActor;
        address spender = _pickApprovedSpender(owner, spenderSeed);

        params.owner = owner;
        params.spender = spender;
        params.amount = fl.clamp(amountSeed, 1, initialIssuedSupply);
    }

    function grantRolesBatchInvalidRolesPreconditions(uint256 userSeed, uint256 roleBitSeed)
        internal
        returns (GrantRolesBatchParams memory params)
    {
        uint256 userCount = users.length;
        uint256 userIdx = fl.clamp(userSeed, 0, userCount - 1);
        address firstUser = users[userIdx];
        address secondUser = users[(userIdx + 1) % userCount];

        params.users = new address[](2);
        params.users[0] = firstUser;
        params.users[1] = secondUser;
        params.roles = token.ALL_ROLES() | _invalidTokenRoleBit(roleBitSeed);

        params.beforeRoles = new uint256[](2);
        params.beforeRoles[0] = token.rolesOf(firstUser);
        params.beforeRoles[1] = token.rolesOf(secondUser);
    }

    function transferPreconditions(uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (TransferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        uint256 freeBalance = _freeBalance(currentActor);
        require(freeBalance != 0, ClampFail("sender has no free balance"));

        params.from = currentActor;
        params.to = _pickDifferentUser(currentActor, receiverSeed);
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function transferFromAllowancePreconditions(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (AllowanceTransferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (address owner, uint256 allowance, uint256 freeBalance) = _pickAllowanceOwner(currentActor, ownerSeed);
        uint256 maxAmount = allowance < freeBalance ? allowance : freeBalance;

        params.owner = owner;
        params.spender = currentActor;
        params.receiver = _pickDifferentUser(owner, receiverSeed);
        params.amount = fl.clamp(amountSeed, 1, maxAmount);
    }

    function setOperatorPreconditions(uint256 operatorSeed, bool approved)
        internal
        returns (OperatorParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        params.owner = currentActor;
        params.operator = _pickDifferentUser(currentActor, operatorSeed);
        params.approved = approved;
    }

    function setOperatorUnregisteredPreconditions() internal view returns (OperatorParams memory params) {
        require(!token.paused(), ClampFail("token contract paused"));
        require(!entityRegistry.isAccountEnabled(FUZZ_TOKEN_UNREGISTERED_OPERATOR), ClampFail("operator enabled"));

        params.owner = currentActor;
        params.operator = FUZZ_TOKEN_UNREGISTERED_OPERATOR;
        params.approved = true;
    }

    function transferFromOperatorPreconditions(uint256 ownerSeed, uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (OperatorTransferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (address owner, uint256 freeBalance) = _pickOperatorOwner(currentActor, ownerSeed);

        params.owner = owner;
        params.operator = currentActor;
        params.receiver = _pickDifferentUser(owner, receiverSeed);
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function batchTransferFromSingleReceiverPreconditions(uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (TransferParams memory params)
    {
        params = transferPreconditions(receiverSeed, amountSeed);
    }

    function batchTransferFromMultipleReceiversPreconditions(uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (TransferParams memory params)
    {
        params = transferPreconditions(receiverSeed, amountSeed);
    }

    function freezePartialTokensPreconditions(uint256 accountSeed, uint256 amountSeed)
        internal
        returns (FreezeParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        (address account, uint256 freeBalance) = _pickUserWithFreeBalance(accountSeed);

        params.account = account;
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function unfreezePartialTokensPreconditions(uint256 accountSeed, uint256 amountSeed)
        internal
        returns (FreezeParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        (address account, uint256 frozenBalance) = _pickUserWithFrozenBalance(accountSeed);

        params.account = account;
        params.amount = fl.clamp(amountSeed, 1, frozenBalance);
    }

    function forcedTransferPreconditions(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (ForcedTransferParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        (address from, uint256 balance) = _pickUserWithBalance(fromSeed);
        uint256 frozen = token.frozenBalanceOf(from, bondTokenId);
        uint256 freeBalance = balance - frozen;
        uint256 amount = fl.clamp(amountSeed, 1, balance);

        params.from = from;
        params.to = _pickDifferentUser(from, receiverSeed);
        params.amount = amount;
        params.expectedFrozenAfter = amount > freeBalance ? frozen - (amount - freeBalance) : frozen;
    }

    function batchForcedTransferPreconditions(uint256 fromSeed, uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (ForcedTransferParams memory params)
    {
        params = forcedTransferPreconditions(fromSeed, receiverSeed, amountSeed);
    }

    function forcedTransferToProtectedReceiverPreconditions(uint256 fromSeed, uint256 amountSeed)
        internal
        returns (ForcedTransferParams memory params)
    {
        address protectedReceiver = address(escrowManager);
        require(entityRegistry.isAccountEnabled(protectedReceiver), ClampFail("protected receiver not enabled"));

        if (!token.isAddressProtected(protectedReceiver)) {
            token.protectAddress(protectedReceiver);
        }

        (address from, uint256 balance) = _pickUserWithBalance(fromSeed);

        params.from = from;
        params.to = protectedReceiver;
        params.amount = fl.clamp(amountSeed, 1, balance);
    }

    function batchForcedTransferToProtectedReceiverPreconditions(uint256 fromSeed, uint256 amountSeed)
        internal
        returns (ForcedTransferParams memory params)
    {
        params = forcedTransferToProtectedReceiverPreconditions(fromSeed, amountSeed);
    }

    function batchFreezePartialTokensPreconditions(uint256 accountSeed, uint256 amountSeed)
        internal
        returns (FreezeParams memory params)
    {
        params = freezePartialTokensPreconditions(accountSeed, amountSeed);
    }

    function batchUnfreezePartialTokensPreconditions(uint256 accountSeed, uint256 amountSeed)
        internal
        returns (FreezeParams memory params)
    {
        params = unfreezePartialTokensPreconditions(accountSeed, amountSeed);
    }

    function burnPreconditions(uint256 fromSeed, uint256 amountSeed) internal returns (TokenBurnParams memory params) {
        if (token.paused()) {
            token.unpause();
        }

        (address from, uint256 balance) = _pickUnprotectedEnabledUserWithBalance(fromSeed);
        uint256 frozen = token.frozenBalanceOf(from, bondTokenId);
        uint256 freeBalance = balance - frozen;
        uint256 maxAmount = balance > 100 ? 100 : balance;
        uint256 amount = fl.clamp(amountSeed, 1, maxAmount);

        params.from = from;
        params.amount = amount;
        params.expectedFrozenAfter = amount > freeBalance ? frozen - (amount - freeBalance) : frozen;
    }

    function burnBatchPreconditions(uint256 fromSeed, uint256 amountSeed)
        internal
        returns (TokenBurnParams memory params)
    {
        params = burnPreconditions(fromSeed, amountSeed);
    }

    function protectAddressPreconditions(uint256 accountSeed) internal returns (ProtectAddressParams memory params) {
        address account = _pickUnprotectedProtectionCandidate(accountSeed);

        params.account = account;
    }

    function protectedReceiverTransferPreconditions(uint256 senderSeed, uint256 amountSeed)
        internal
        returns (ProtectedReceiverTransferParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (address from, uint256 freeBalance) = _pickUserWithFreeBalance(senderSeed);
        require(from != FUZZ_WALLET_7, ClampFail("protected receiver is sender"));
        require(entityRegistry.isAccountEnabled(FUZZ_WALLET_7), ClampFail("protected receiver not enabled"));

        if (!token.isAddressProtected(FUZZ_WALLET_7)) {
            token.protectAddress(FUZZ_WALLET_7);
        }

        params.from = from;
        params.to = FUZZ_WALLET_7;
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function futureCheckpointPreconditions(uint256 accountSeed)
        internal
        returns (FutureCheckpointParams memory params)
    {
        params.account = users[fl.clamp(accountSeed, 0, users.length - 1)];
        params.blockNumber = block.number + 1;
    }

    function setContractPausePreconditions(bool paused) internal view returns (PauseParams memory params) {
        require(token.paused() != paused, ClampFail("contract pause already set"));
        params.paused = paused;
    }

    function setBondSuspendedPreconditions(bool suspended) internal view returns (BondSuspensionParams memory params) {
        BondStatus status = _getBondAtVersion(1).status;
        if (suspended) {
            require(status == BondStatus.Issued, ClampFail("bond not issued"));
        } else {
            require(!token.paused(), ClampFail("token contract paused"));
            require(status == BondStatus.Suspended, ClampFail("bond not suspended"));
        }

        params.suspended = suspended;
    }

    function contractPauseBlocksActionPreconditions(uint256 spenderSeed)
        internal
        returns (ApproveParams memory params)
    {
        if (!token.paused()) {
            token.pause();
        }

        params.owner = currentActor;
        params.spender = users[fl.clamp(spenderSeed, 0, users.length - 1)];
        params.amount = 0;
    }

    function tokenIdPauseBlocksTransferPreconditions(uint256 senderSeed, uint256 receiverSeed, uint256 amountSeed)
        internal
        returns (TransferParams memory params)
    {
        require(!token.paused(), ClampFail("token contract paused"));

        BondStatus status = _getBondAtVersion(1).status;
        if (status == BondStatus.Issued) {
            bondRegistry.suspendBond(BOND_ISIN, 1);
        } else {
            require(status == BondStatus.Suspended, ClampFail("bond not suspendable"));
        }

        (address from, uint256 freeBalance) = _pickUserWithFreeBalance(senderSeed);

        params.from = from;
        params.to = _pickDifferentUser(from, receiverSeed);
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function _pickDifferentUser(address excluded, uint256 seed) internal returns (address user) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            if (candidate != excluded) return candidate;
        }
        revert ClampFail("no different user");
    }

    function _pickUserWithBalance(uint256 seed) internal returns (address user, uint256 balance) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            uint256 candidateBalance = token.balanceOf(candidate, bondTokenId);
            if (candidateBalance != 0) {
                return (candidate, candidateBalance);
            }
        }
        revert ClampFail("no user with balance");
    }

    function _pickUnprotectedEnabledUserWithBalance(uint256 seed) internal returns (address user, uint256 balance) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            if (!entityRegistry.isAccountEnabled(candidate) || token.isAddressProtected(candidate)) continue;

            uint256 candidateBalance = token.balanceOf(candidate, bondTokenId);
            if (candidateBalance != 0) {
                return (candidate, candidateBalance);
            }
        }
        revert ClampFail("no burnable user");
    }

    function _pickUserWithFreeBalance(uint256 seed) internal returns (address user, uint256 freeBalance) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            uint256 candidateFreeBalance = _freeBalance(candidate);
            if (candidateFreeBalance != 0) {
                return (candidate, candidateFreeBalance);
            }
        }
        revert ClampFail("no user with free balance");
    }

    function _pickUserWithFrozenBalance(uint256 seed) internal returns (address user, uint256 frozenBalance) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            uint256 candidateFrozenBalance = token.frozenBalanceOf(candidate, bondTokenId);
            if (candidateFrozenBalance != 0) {
                return (candidate, candidateFrozenBalance);
            }
        }
        revert ClampFail("no user with frozen balance");
    }

    function _pickApprovedSpender(address owner, uint256 seed) internal returns (address spender) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            if (token.allowance(owner, candidate, bondTokenId) != 0) return candidate;
        }
        revert ClampFail("no nonzero allowance");
    }

    function _pickAllowanceOwner(address spender, uint256 seed)
        internal
        returns (address owner, uint256 allowance, uint256 freeBalance)
    {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            if (candidate == spender || token.isOperator(candidate, spender)) continue;

            uint256 candidateAllowance = token.allowance(candidate, spender, bondTokenId);
            uint256 candidateFreeBalance = _freeBalance(candidate);
            if (candidateAllowance != 0 && candidateFreeBalance != 0) {
                return (candidate, candidateAllowance, candidateFreeBalance);
            }
        }
        revert ClampFail("no allowance owner");
    }

    function _pickOperatorOwner(address operator, uint256 seed) internal returns (address owner, uint256 freeBalance) {
        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(seed, 0, userCount - 1);
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            if (candidate == operator || !token.isOperator(candidate, operator)) continue;

            uint256 candidateFreeBalance = _freeBalance(candidate);
            if (candidateFreeBalance != 0) {
                return (candidate, candidateFreeBalance);
            }
        }
        revert ClampFail("no operator owner");
    }

    function _pickUnprotectedProtectionCandidate(uint256 seed) internal returns (address account) {
        uint256 walletCount = fuzzWallets.length;
        uint256 startIdx = fl.clamp(seed, 0, walletCount - 1);
        for (uint256 i; i < walletCount; ++i) {
            address candidate = fuzzWallets[(startIdx + i) % walletCount];
            if (!token.isAddressProtected(candidate)) return candidate;
        }
        revert ClampFail("no unprotected address");
    }

    function _freeBalance(address account) internal view returns (uint256) {
        uint256 balance = token.balanceOf(account, bondTokenId);
        uint256 frozen = token.frozenBalanceOf(account, bondTokenId);
        return balance > frozen ? balance - frozen : 0;
    }

    function _invalidTokenRoleBit(uint256 roleBitSeed) internal returns (uint256) {
        return 2 ** fl.clamp(roleBitSeed, 3, 255);
    }
}

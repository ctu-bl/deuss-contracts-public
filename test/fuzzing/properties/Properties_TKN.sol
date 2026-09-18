// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore */

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BondStatus} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_TKN is PropertiesBase {
    function invariant_TKN_01() internal {
        fl.eq(states[AFTER].allTrackedFrozenBalancesBounded, true, TKN_01);
    }

    function invariant_TKN_10(address owner, address spender, uint256 expectedAllowance) internal {
        fl.eq(states[AFTER].tokenPairStates[owner][spender].allowance, expectedAllowance, TKN_10);
    }

    function invariant_TKN_11(address owner, address spender) internal {
        fl.eq(states[AFTER].actorStates[owner].balance, states[BEFORE].actorStates[owner].balance, TKN_11);
        fl.eq(states[AFTER].actorStates[spender].balance, states[BEFORE].actorStates[spender].balance, TKN_11);
    }

    function invariant_TKN_12(address owner, address spender, uint256 expectedAllowance) internal {
        fl.eq(states[AFTER].tokenPairStates[owner][spender].allowance, expectedAllowance, TKN_12);
    }

    function invariant_TKN_13(bool success, bytes4 errorSelector, address[] memory users, uint256[] memory beforeRoles)
        internal
    {
        fl.eq(success, false, TKN_13);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.InvalidRoles.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_13);

        for (uint256 i; i < users.length; ++i) {
            fl.eq(token.rolesOf(users[i]), beforeRoles[i], TKN_13);
            fl.eq(states[AFTER].actorStates[users[i]].balance, states[BEFORE].actorStates[users[i]].balance, TKN_13);
        }
    }

    function invariant_TKN_20(address from, address to, uint256 amount) internal {
        fl.eq(states[AFTER].actorStates[from].balance + amount, states[BEFORE].actorStates[from].balance, TKN_20);
        fl.eq(states[AFTER].actorStates[to].balance, states[BEFORE].actorStates[to].balance + amount, TKN_20);
    }

    function invariant_TKN_21(address owner, address spender, uint256 amount) internal {
        fl.eq(
            states[AFTER].tokenPairStates[owner][spender].allowance + amount,
            states[BEFORE].tokenPairStates[owner][spender].allowance,
            TKN_21
        );
    }

    function invariant_TKN_22(address owner, address operator) internal {
        fl.eq(
            states[AFTER].tokenPairStates[owner][operator].allowance,
            states[BEFORE].tokenPairStates[owner][operator].allowance,
            TKN_22
        );
    }

    function invariant_TKN_30(address owner, address operator, bool expectedApproved) internal {
        fl.eq(states[AFTER].tokenPairStates[owner][operator].operatorApproved, expectedApproved, TKN_30);
    }

    function invariant_TKN_31(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, TKN_31);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__OperatorNotEnabled.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_31);
    }

    function invariant_TKN_40(address account, uint256 amount) internal {
        fl.eq(
            states[AFTER].actorStates[account].frozenBalance,
            states[BEFORE].actorStates[account].frozenBalance + amount,
            TKN_40
        );
        fl.eq(states[AFTER].actorStates[account].balance, states[BEFORE].actorStates[account].balance, TKN_40);
        fl.eq(states[AFTER].totalSupply, states[BEFORE].totalSupply, TKN_40);
    }

    function invariant_TKN_41(address account, uint256 amount) internal {
        fl.eq(
            states[AFTER].actorStates[account].frozenBalance + amount,
            states[BEFORE].actorStates[account].frozenBalance,
            TKN_41
        );
        fl.eq(states[AFTER].actorStates[account].balance, states[BEFORE].actorStates[account].balance, TKN_41);
        fl.eq(states[AFTER].totalSupply, states[BEFORE].totalSupply, TKN_41);
    }

    function invariant_TKN_50(address from, address to, uint256 amount, uint256 expectedFrozenAfter) internal {
        invariant_TKN_20(from, to, amount);
        fl.eq(states[AFTER].actorStates[from].frozenBalance, expectedFrozenAfter, TKN_50);
        fl.eq(states[AFTER].totalSupply, states[BEFORE].totalSupply, TKN_50);
    }

    function invariant_TKN_51(address from, uint256 amount, uint256 expectedFrozenAfter) internal {
        fl.eq(states[AFTER].actorStates[from].balance + amount, states[BEFORE].actorStates[from].balance, TKN_51);
        fl.eq(states[AFTER].actorStates[from].frozenBalance, expectedFrozenAfter, TKN_51);
        fl.eq(states[AFTER].totalSupply + amount, states[BEFORE].totalSupply, TKN_51);
    }

    function invariant_TKN_52(bool success, bytes4 errorSelector, address from, address to) internal {
        fl.eq(success, false, TKN_52_REVERT);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__ProtectedReceiverTransferNotAllowed.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_52_ERROR);

        fl.eq(states[AFTER].actorStates[from].balance, states[BEFORE].actorStates[from].balance, TKN_52_FROM_BALANCE);
        fl.eq(
            states[AFTER].actorStates[from].frozenBalance,
            states[BEFORE].actorStates[from].frozenBalance,
            TKN_52_FROM_FROZEN
        );
        fl.eq(states[AFTER].actorStates[to].balance, states[BEFORE].actorStates[to].balance, TKN_52_TO_BALANCE);
        fl.eq(
            states[AFTER].actorStates[to].frozenBalance, states[BEFORE].actorStates[to].frozenBalance, TKN_52_TO_FROZEN
        );
        fl.eq(states[AFTER].totalSupply, states[BEFORE].totalSupply, TKN_52_SUPPLY);
    }

    function invariant_TKN_60(bool expectedPaused) internal {
        fl.eq(states[AFTER].tokenPaused, expectedPaused, TKN_60);
    }

    function invariant_TKN_61(bool expectedSuspended) internal {
        BondStatus expectedStatus = expectedSuspended ? BondStatus.Suspended : BondStatus.Issued;
        fl.eq(uint256(states[AFTER].bondStatus), uint256(expectedStatus), TKN_61);
        fl.eq(states[AFTER].tokenIdPaused, expectedSuspended, TKN_61);
    }

    function invariant_TKN_62(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, TKN_62);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = PausableUpgradeable.EnforcedPause.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_62);
    }

    function invariant_TKN_63(bool success, bytes4 errorSelector, address from, address to) internal {
        fl.eq(success, false, TKN_63);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__TokenIdIsPaused.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_63);
        fl.eq(states[AFTER].actorStates[from].balance, states[BEFORE].actorStates[from].balance, TKN_63);
        fl.eq(states[AFTER].actorStates[to].balance, states[BEFORE].actorStates[to].balance, TKN_63);
    }

    function invariant_TKN_70(address actor) internal {
        uint256 available = states[AFTER].actorStates[actor].balance > states[AFTER].actorStates[actor].frozenBalance
            ? states[AFTER].actorStates[actor].balance - states[AFTER].actorStates[actor].frozenBalance
            : 0;

        fl.eq(states[AFTER].actorStates[actor].balanceAtCurrentBlock, states[AFTER].actorStates[actor].balance, TKN_70);
        fl.eq(
            states[AFTER].actorStates[actor].frozenBalanceAtCurrentBlock,
            states[AFTER].actorStates[actor].frozenBalance,
            TKN_70
        );
        fl.eq(states[AFTER].actorStates[actor].availableBalanceAtCurrentBlock, available, TKN_70);
    }

    function invariant_TKN_71(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, TKN_71);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__BlockInFuture.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_71);
    }

    function invariant_TKN_80(address account) internal {
        fl.eq(token.isAddressProtected(account), true, TKN_80);
    }

    function invariant_TKN_81(bool success, bytes4 errorSelector, address from, address to) internal {
        fl.eq(success, false, TKN_81);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = Errors.Token__ProtectedReceiverTransferNotAllowed.selector;
        fl.errAllow(errorSelector, allowedErrors, TKN_81);
        fl.eq(states[AFTER].actorStates[from].balance, states[BEFORE].actorStates[from].balance, TKN_81);
        fl.eq(states[AFTER].actorStates[to].balance, states[BEFORE].actorStates[to].balance, TKN_81);
    }
}

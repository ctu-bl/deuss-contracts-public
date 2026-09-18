// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable private-vars-leading-underscore, gas-strict-inequalities */

import {AssetType, Escrow} from "src/marketplace/MarketStructs.sol";
import {EscrowBucket} from "../FuzzStateIndex.sol";
import {PreconditionsBase} from "./PreconditionsBase.sol";

abstract contract PreconditionsEscrowManager is PreconditionsBase {
    struct CreateEscrowParams {
        address depositor;
        uint256 amount;
    }

    struct EscrowAmountParams {
        uint256 escrowId;
        uint256 amount;
    }

    struct ClaimEscrowParams {
        uint256 escrowId;
        uint256 amount;
        address beneficiary;
    }

    struct SweepParams {
        uint256 amount;
        address beneficiary;
    }

    struct DirectTransferToEscrowParams {
        address sender;
        uint256 amount;
    }

    struct MultiStandardEscrowParams {
        address depositor;
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    function createEscrowPreconditions(uint256 depositorSeed, uint256 amountSeed)
        internal
        returns (CreateEscrowParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(depositorSeed, 0, userCount - 1);
        address depositor;
        uint256 freeBalance;
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            uint256 balance = token.balanceOf(candidate, bondTokenId);
            uint256 frozen = token.frozenBalanceOf(candidate, bondTokenId);
            if (balance > frozen && token.isOperator(candidate, address(escrowManager))) {
                depositor = candidate;
                freeBalance = balance - frozen;
                break;
            }
        }
        require(depositor != address(0), ClampFail("no eligible depositor"));

        params.depositor = depositor;
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }

    function withdrawEscrowPreconditions(uint256 escrowSeed, uint256 amountSeed)
        internal
        returns (EscrowAmountParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 escrowId, Escrow memory escrow) =
            _pickEscrowFromBucket(EscrowBucket.FuzzTestFunded, escrowSeed);
        require(found, ClampFail("no tracked fuzz escrow"));

        require(escrow.amount > 0, ClampFail("escrow empty"));

        params.escrowId = escrowId;
        params.amount = fl.clamp(amountSeed, 1, escrow.amount);
    }

    function claimEscrowPreconditions(uint256 escrowSeed, uint256 amountSeed, uint256 beneficiarySeed)
        internal
        returns (ClaimEscrowParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        (bool found, uint256 escrowId, Escrow memory escrow) =
            _pickEscrowFromBucket(EscrowBucket.FuzzTestFunded, escrowSeed);
        require(found, ClampFail("no tracked fuzz escrow"));

        require(escrow.amount > 0, ClampFail("escrow empty"));

        uint256 userCount = users.length;
        address beneficiary = users[fl.clamp(beneficiarySeed, 0, userCount - 1)];

        params.escrowId = escrowId;
        params.amount = fl.clamp(amountSeed, 1, escrow.amount);
        params.beneficiary = beneficiary;
    }

    function sweepPreconditions(uint256 amountSeed, uint256 beneficiarySeed)
        internal
        returns (SweepParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        uint256 surplus = escrowManager.getSweepableAmount(AssetType.ERC6909, address(token), bondTokenId);
        require(surplus != 0, ClampFail("no sweepable surplus"));

        params.amount = fl.clamp(amountSeed, 1, surplus);
        params.beneficiary = users[fl.clamp(beneficiarySeed, 0, users.length - 1)];
    }

    function directTransferToEscrowPreconditions(uint256 senderSeed, uint256 amountSeed)
        internal
        returns (DirectTransferToEscrowParams memory params)
    {
        require(!_tokenPaused(), ClampFail("token paused"));

        uint256 userCount = users.length;
        uint256 startIdx = fl.clamp(senderSeed, 0, userCount - 1);
        address sender;
        uint256 freeBalance;
        for (uint256 i; i < userCount; ++i) {
            address candidate = users[(startIdx + i) % userCount];
            uint256 balance = token.balanceOf(candidate, bondTokenId);
            uint256 frozen = token.frozenBalanceOf(candidate, bondTokenId);
            if (balance > frozen) {
                sender = candidate;
                freeBalance = balance - frozen;
                break;
            }
        }
        require(sender != address(0), ClampFail("no eligible transfer sender"));

        params.sender = sender;
        params.amount = fl.clamp(amountSeed, 1, freeBalance);
    }
}

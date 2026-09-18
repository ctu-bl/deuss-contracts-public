// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzIntegrityBase} from "./FuzzIntegrityBase.sol";
import {HandlerEscrowManager} from "./helper/handlers/HandlerEscrowManager.sol";

/**
 * @title FuzzEscrowManagerIntegrity
 * @notice Checks handler integrity for the EscrowManager fuzz harness
 */
contract FuzzEscrowManagerIntegrity is HandlerEscrowManager, FuzzIntegrityBase {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         INTEGRITY                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Checks the integrity of `handler_createEscrow`
     * @param depositorSeed Seed used to pick an eligible depositor
     * @param amountSeed Seed used to derive the deposited amount
     */
    function fuzz_createEscrow(uint256 depositorSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowManager.handler_createEscrow.selector, depositorSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-CREATE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_createEscrowUnauthorized`
     * @param depositorSeed Seed used to pick an eligible depositor
     * @param amountSeed Seed used to derive the attempted amount
     */
    function fuzz_createEscrowUnauthorized(uint256 depositorSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowManager.handler_createEscrowUnauthorized.selector, depositorSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-CREATE-UNAUTH");
        }
    }

    /**
     * @notice Checks the integrity of `handler_withdraw`
     * @param escrowSeed Seed used to pick a tracked fuzz escrow
     * @param amountSeed Seed used to derive the withdrawn amount
     */
    function fuzz_withdraw(uint256 escrowSeed, uint256 amountSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowManager.handler_withdraw.selector, escrowSeed, amountSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-WITHDRAW");
        }
    }

    /**
     * @notice Checks the integrity of `handler_claim`
     * @param escrowSeed Seed used to pick a tracked fuzz escrow
     * @param amountSeed Seed used to derive the claimed amount
     * @param beneficiarySeed Seed used to pick the beneficiary
     */
    function fuzz_claim(uint256 escrowSeed, uint256 amountSeed, uint256 beneficiarySeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowManager.handler_claim.selector, escrowSeed, amountSeed, beneficiarySeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-CLAIM");
        }
    }

    /**
     * @notice Checks the integrity of `handler_sweep`
     * @param amountSeed Seed used to derive the swept amount
     * @param beneficiarySeed Seed used to pick the sweep beneficiary
     */
    function fuzz_sweep(uint256 amountSeed, uint256 beneficiarySeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowManager.handler_sweep.selector, amountSeed, beneficiarySeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-SWEEP");
        }
    }

    /**
     * @notice Checks the integrity of `handler_directTransferToEscrow`
     * @param senderSeed Seed used to pick a tracked sender with free balance
     * @param amountSeed Seed used to derive the direct transfer amount
     */
    function fuzz_directTransferToEscrow(uint256 senderSeed, uint256 amountSeed) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowManager.handler_directTransferToEscrow.selector, senderSeed, amountSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-DIRECT-TRANSFER");
        }
    }

    /**
     * @notice Checks ERC20/ERC721/ERC1155 EscrowManager coverage paths
     * @param assetTypeSeed Seed used to pick the asset standard
     * @param depositorSeed Seed used to pick the depositor
     * @param amountSeed Seed used to derive fungible amounts
     * @param tokenIdSeed Seed used to derive ERC1155 token ids
     */
    function fuzz_multiStandardEscrowSurface(
        uint256 assetTypeSeed,
        uint256 depositorSeed,
        uint256 amountSeed,
        uint256 tokenIdSeed
    ) public {
        bytes memory callData = abi.encodeWithSelector(
            HandlerEscrowManager.handler_multiStandardEscrowSurface.selector,
            assetTypeSeed,
            depositorSeed,
            amountSeed,
            tokenIdSeed
        );

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-MULTI-STANDARD");
        }
    }

    /**
     * @notice Checks the integrity of `handler_registerModule`
     * @param moduleSeed Seed used to pick a candidate module address
     */
    function fuzz_registerModule(uint256 moduleSeed) public {
        bytes memory callData = abi.encodeWithSelector(HandlerEscrowManager.handler_registerModule.selector, moduleSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-REGISTER-MODULE");
        }
    }

    /**
     * @notice Checks the integrity of `handler_deactivateModule`
     * @param moduleSeed Seed used to pick a candidate module address
     */
    function fuzz_deactivateModule(uint256 moduleSeed) public {
        bytes memory callData =
            abi.encodeWithSelector(HandlerEscrowManager.handler_deactivateModule.selector, moduleSeed);

        (bool success, bytes4 errorSelector) = _testSelf(callData);
        if (!success) {
            _allowClampFail(errorSelector, "SELF-ESCROW-DEACTIVATE-MODULE");
        }
    }
}

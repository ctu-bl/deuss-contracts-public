// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AssetType, Escrow} from "src/marketplace/MarketStructs.sol";
import {IEscrowManager} from "src/marketplace/interfaces/IEscrowManager.sol";
import {PreconditionsEscrowManager} from "../preconditions/PreconditionsEscrowManager.sol";
import {PostconditionsEscrowManager} from "../postconditions/PostconditionsEscrowManager.sol";

/// @title HandlerEscrowManager
/// @notice Stateful fuzz handlers for the EscrowManager vertical slice.
abstract contract HandlerEscrowManager is PreconditionsEscrowManager, PostconditionsEscrowManager {
    /// @notice Attempts to create a new escrow via the authorized fuzz test module.
    /// @dev Deposits bond tokens from one of the tracked users into EscrowManager.
    /// On success, the allocated escrow ID is added to the bounded tracked escrow
    /// set so later fuzz actions can discover and reuse it.
    /// @param depositorSeed Seed used to pick an eligible depositor from the tracked users.
    /// @param amountSeed Seed used to derive the deposited amount.
    function handler_createEscrow(uint256 depositorSeed, uint256 amountSeed) public {
        CreateEscrowParams memory params = createEscrowPreconditions(depositorSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.depositor);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.createEscrow.selector, params.amount, params.depositor, address(token), bondTokenId
            ),
            FUZZ_ESCROW_TEST_MODULE
        );

        uint256 escrowId;
        if (success) {
            escrowId = _decodeUint256(returnData);
            _trackEscrowId(escrowId);
        }

        createEscrowPostconditions(success, returnData, actorsToUpdate, escrowId, params);
    }

    /// @notice Attempts to create an escrow from an unauthorized caller.
    /// @dev Exercises the authorization boundary: any non-module caller must be
    /// rejected with `ModuleNotRegistered` or `ModuleNotAuthorized`.
    /// @param depositorSeed Seed used to pick an eligible depositor (parameters are
    /// shaped as if the call were authorized so only the auth boundary is exercised).
    /// @param amountSeed Seed used to derive the attempted deposit amount.
    function handler_createEscrowUnauthorized(uint256 depositorSeed, uint256 amountSeed) public {
        CreateEscrowParams memory params = createEscrowPreconditions(depositorSeed, amountSeed);

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.createEscrow.selector, params.amount, params.depositor, address(token), bondTokenId
            ),
            FUZZ_ESCROW_UNAUTH_CALLER
        );

        createEscrowUnauthorizedPostconditions(success, returnData);
    }

    /// @notice Attempts to withdraw tokens from a tracked fuzz escrow back to its depositor.
    /// @dev The withdrawal is issued from the authorized fuzz test module so
    /// `_requireAuthorizedEscrow` is satisfied.
    /// @param escrowSeed Seed used to pick a tracked fuzz escrow with a positive amount.
    /// @param amountSeed Seed used to derive the withdrawn amount.
    function handler_withdraw(uint256 escrowSeed, uint256 amountSeed) public {
        EscrowAmountParams memory params = withdrawEscrowPreconditions(escrowSeed, amountSeed);

        Escrow memory escrow = escrowManager.getEscrow(params.escrowId);
        address[] memory actorsToUpdate = _singleActorArray(escrow.depositor);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.withdraw.selector, params.escrowId, params.amount),
            FUZZ_ESCROW_TEST_MODULE
        );

        _syncEscrow(params.escrowId);

        withdrawEscrowPostconditions(success, returnData, actorsToUpdate, params.escrowId, params.amount);
    }

    /// @notice Attempts to claim tokens from a tracked fuzz escrow to a chosen beneficiary.
    /// @dev The claim is issued from the authorized fuzz test module. The beneficiary
    /// is selected from the tracked user set so its balance can be snapshotted.
    /// @param escrowSeed Seed used to pick a tracked fuzz escrow with a positive amount.
    /// @param amountSeed Seed used to derive the claimed amount.
    /// @param beneficiarySeed Seed used to pick the beneficiary from the tracked users.
    function handler_claim(uint256 escrowSeed, uint256 amountSeed, uint256 beneficiarySeed) public {
        ClaimEscrowParams memory params = claimEscrowPreconditions(escrowSeed, amountSeed, beneficiarySeed);

        address[] memory actorsToUpdate = _singleActorArray(params.beneficiary);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.claim.selector, params.escrowId, params.amount, params.beneficiary),
            FUZZ_ESCROW_TEST_MODULE
        );

        _syncEscrow(params.escrowId);

        claimEscrowPostconditions(success, returnData, actorsToUpdate, params.escrowId, params.amount);
    }

    /// @notice Attempts to sweep surplus (untracked) bond tokens held by EscrowManager.
    /// @dev Executed by the harness admin. Sweep must never touch the reserved
    /// portion of the balance or any tracked escrow amount.
    /// @param amountSeed Seed used to derive the swept amount (clamped to surplus).
    /// @param beneficiarySeed Seed used to pick the sweep beneficiary.
    function handler_sweep(uint256 amountSeed, uint256 beneficiarySeed) public {
        SweepParams memory params = sweepPreconditions(amountSeed, beneficiarySeed);

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.sweep.selector,
                AssetType.ERC6909,
                address(token),
                bondTokenId,
                params.amount,
                params.beneficiary
            ),
            address(this)
        );

        sweepPostconditions(success, returnData);
    }

    /// @notice Attempts to transfer bond tokens directly to EscrowManager without
    /// creating an escrow entry.
    /// @dev Models accidental or surplus balances that sweep is allowed to recover.
    /// The sender is selected from tracked users with free bond balance.
    /// @param senderSeed Seed used to pick the transfer sender from the tracked users.
    /// @param amountSeed Seed used to derive the transferred amount.
    function handler_directTransferToEscrow(uint256 senderSeed, uint256 amountSeed) public {
        DirectTransferToEscrowParams memory params = directTransferToEscrowPreconditions(senderSeed, amountSeed);

        address[] memory actorsToUpdate = _singleActorArray(params.sender);
        _before(actorsToUpdate, _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, address(escrowManager), bondTokenId, params.amount),
            params.sender
        );

        directTransferToEscrowPostconditions(success, returnData, actorsToUpdate, params.amount);
    }

    /// @notice Exercises EscrowManager transfer branches for ERC20, ERC721, and ERC1155 assets.
    /// @dev These synthetic escrows are created and fully withdrawn in the same handler call, and
    /// are intentionally not added to the tracked ERC6909 escrow set.
    /// @param assetTypeSeed Seed used to pick ERC20, ERC721, or ERC1155.
    /// @param depositorSeed Seed used to pick the depositor from USERS.
    /// @param amountSeed Seed used to derive the escrow amount for fungible standards.
    /// @param tokenIdSeed Seed mixed into ERC1155 token id selection.
    function handler_multiStandardEscrowSurface(
        uint256 assetTypeSeed,
        uint256 depositorSeed,
        uint256 amountSeed,
        uint256 tokenIdSeed
    ) public {
        uint256 option = fl.clamp(assetTypeSeed, 0, 2);
        address depositor = users[fl.clamp(depositorSeed, 0, users.length - 1)];

        if (option == 0) {
            _exerciseMultiStandardEscrow(_prepareERC20Escrow(depositor, amountSeed));
        } else if (option == 1) {
            _exerciseMultiStandardEscrow(_prepareERC721Escrow(depositor));
        } else {
            _exerciseMultiStandardEscrow(_prepareERC1155Escrow(depositor, amountSeed, tokenIdSeed));
        }
    }

    function _prepareERC20Escrow(address depositor, uint256 amountSeed)
        internal
        returns (MultiStandardEscrowParams memory params)
    {
        params = MultiStandardEscrowParams({
            depositor: depositor, tokenAddress: address(fuzzERC20), tokenId: 0, amount: fl.clamp(amountSeed, 1, 100)
        });
        fuzzERC20.mint(depositor, params.amount);
        (bool approveSuccess, bytes memory approveReturnData) = fl.doFunctionCall(
            params.tokenAddress,
            abi.encodeWithSelector(fuzzERC20.approve.selector, address(escrowManager), params.amount),
            depositor
        );
        escrowManagerCoverageCallPostconditions(approveSuccess, approveReturnData);
    }

    function _prepareERC721Escrow(address depositor) internal returns (MultiStandardEscrowParams memory params) {
        params = MultiStandardEscrowParams({
            depositor: depositor, tokenAddress: address(fuzzERC721), tokenId: ++fuzzERC721TokenCursor, amount: 1
        });
        fuzzERC721.mint(depositor, params.tokenId);
        (bool approveSuccess, bytes memory approveReturnData) = fl.doFunctionCall(
            params.tokenAddress,
            abi.encodeWithSelector(fuzzERC721.approve.selector, address(escrowManager), params.tokenId),
            depositor
        );
        escrowManagerCoverageCallPostconditions(approveSuccess, approveReturnData);
    }

    function _prepareERC1155Escrow(address depositor, uint256 amountSeed, uint256 tokenIdSeed)
        internal
        returns (MultiStandardEscrowParams memory params)
    {
        params = MultiStandardEscrowParams({
            depositor: depositor,
            tokenAddress: address(fuzzERC1155),
            tokenId: fl.clamp(tokenIdSeed, 1, 16),
            amount: fl.clamp(amountSeed, 1, 100)
        });
        fuzzERC1155.mint(depositor, params.tokenId, params.amount);
        (bool approveSuccess, bytes memory approveReturnData) = fl.doFunctionCall(
            params.tokenAddress,
            abi.encodeWithSelector(fuzzERC1155.setApprovalForAll.selector, address(escrowManager), true),
            depositor
        );
        escrowManagerCoverageCallPostconditions(approveSuccess, approveReturnData);
    }

    function _exerciseMultiStandardEscrow(MultiStandardEscrowParams memory params) internal {
        uint256 escrowId = _createMultiStandardEscrow(params);

        _exerciseEscrowCoverageGetters(escrowId);
        _withdrawMultiStandardEscrow(escrowId, params.amount);
    }

    function _createMultiStandardEscrow(MultiStandardEscrowParams memory params) internal returns (uint256 escrowId) {
        (bool createSuccess, bytes memory createReturnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(
                escrowManager.createEscrow.selector,
                params.amount,
                params.depositor,
                params.tokenAddress,
                params.tokenId,
                BOND_NOMINAL_VALUE
            ),
            FUZZ_ESCROW_TEST_MODULE
        );
        escrowManagerCoverageCallPostconditions(createSuccess, createReturnData);

        escrowId = _decodeUint256(createReturnData);
    }

    function _exerciseEscrowCoverageGetters(uint256 escrowId) internal {
        (bool getterSuccess, bytes memory getterReturnData) = fl.doFunctionCall(
            address(escrowManager), abi.encodeWithSelector(escrowManager.escrows.selector, escrowId), address(this)
        );
        escrowManagerCoverageCallPostconditions(getterSuccess, getterReturnData);

        (bool interfaceSuccess, bytes memory interfaceReturnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.supportsInterface.selector, type(IEscrowManager).interfaceId),
            address(this)
        );
        escrowManagerCoverageCallPostconditions(interfaceSuccess, interfaceReturnData);

        (bool erc165Success, bytes memory erc165ReturnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.supportsInterface.selector, type(IERC165).interfaceId),
            address(this)
        );
        escrowManagerCoverageCallPostconditions(erc165Success, erc165ReturnData);
    }

    function _withdrawMultiStandardEscrow(uint256 escrowId, uint256 amount) internal {
        (bool withdrawSuccess, bytes memory withdrawReturnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.withdraw.selector, escrowId, amount),
            FUZZ_ESCROW_TEST_MODULE
        );
        escrowManagerCoverageCallPostconditions(withdrawSuccess, withdrawReturnData);
    }

    /// @notice Attempts to register a new module under the fuzz test module type.
    /// @dev Exercises the admin-only module registration path. The module address
    /// comes from the tracked user set so registration does not collide with
    /// `FUZZ_ESCROW_TEST_MODULE` or `FUZZ_ESCROW_UNAUTH_CALLER`.
    /// @param moduleSeed Seed used to pick a candidate module address.
    function handler_registerModule(uint256 moduleSeed) public {
        address candidate = users[fl.clamp(moduleSeed, 0, users.length - 1)];
        require(escrowManager.moduleTypeOf(candidate) == bytes32(0), ClampFail("module already registered"));

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.registerModule.selector, FUZZ_ESCROW_TEST_MODULE_TYPE, candidate),
            address(this)
        );

        registerModulePostconditions(success, returnData);
    }

    /// @notice Attempts to deactivate a previously registered module.
    /// @dev Only targets modules registered under the fuzz test module type so
    /// core modules (Marketplace, OrderbookMarketplace) are never torn down.
    /// @param moduleSeed Seed used to pick a candidate user-registered module address.
    function handler_deactivateModule(uint256 moduleSeed) public {
        uint256 len = users.length;
        uint256 start = fl.clamp(moduleSeed, 0, len - 1);
        address candidate;
        for (uint256 i; i < len; ++i) {
            address user = users[(start + i) % len];
            if (escrowManager.moduleTypeOf(user) == FUZZ_ESCROW_TEST_MODULE_TYPE) {
                candidate = user;
                break;
            }
        }
        require(candidate != address(0), ClampFail("no deactivatable fuzz module"));

        _before(_emptyAddressArray(), _emptyUintArray(), _emptyUintArray());

        (bool success, bytes memory returnData) = fl.doFunctionCall(
            address(escrowManager),
            abi.encodeWithSelector(escrowManager.deactivateModule.selector, FUZZ_ESCROW_TEST_MODULE_TYPE, candidate),
            address(this)
        );

        deactivateModulePostconditions(success, returnData, candidate);
    }
}

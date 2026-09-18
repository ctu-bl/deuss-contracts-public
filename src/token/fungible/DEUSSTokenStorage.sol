// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @title DEUSSTokenStorage
 * @author DEUSS Team
 * @notice Defines storage layout for DEUSSToken-specific state
 * @dev Separated from logic to preserve storage compatibility across proxy upgrades
 */
abstract contract DEUSSTokenStorage {
    /**
     * @notice Protected-custody registry plus balance, supply, and frozen-balance checkpoint storage.
     * @custom:storage-location erc7201:deuss.deussToken.storage
     */
    struct DEUSSTokenState {
        /// @dev Addresses permanently marked as protected custody.
        mapping(address protectedAddress => bool isProtected) protectedAddress;
        /// @dev Per-token, per-account balance checkpoints keyed by block number.
        mapping(uint256 tokenId => mapping(address account => Checkpoints.Trace208 balanceCheckpoints)) balanceCkpts;
        /// @dev Per-token total supply checkpoints keyed by block number.
        mapping(uint256 tokenId => Checkpoints.Trace208 supplyCheckpoints) supplyCkpts;
        /// @dev Per-token, per-account frozen balance checkpoints keyed by block number.
        mapping(uint256 tokenId => mapping(address account => Checkpoints.Trace208 frozenBalanceCheckpoints))
            frozenBalanceCkpts;
    }

    /**
     * @notice ERC-7201 storage location for DEUSSToken state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.deussToken.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _DEUSS_TOKEN_STORAGE_LOCATION =
        0x81f87555f780583a8c92e8f0edec5aa7eb56647385146977b7175b53533e7900;

    /**
     * @notice Returns DEUSSToken namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _deussTokenStorage() internal pure returns (DEUSSTokenState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _DEUSS_TOKEN_STORAGE_LOCATION
        }
    }
}

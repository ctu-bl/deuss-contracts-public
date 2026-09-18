// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Escrow} from "./MarketStructs.sol";

/**
 * @title EscrowManagerStorage
 * @author DEUSS Team
 * @notice Storage layout for EscrowManager.
 */
abstract contract EscrowManagerStorage {
    /**
     * @notice Escrow custody, module authorization, and accounting storage.
     * @custom:storage-location erc7201:deuss.escrowManager.storage
     */
    struct EscrowManagerState {
        /// @notice Address of asset manager used for whitelist and transfer-shape validation
        address assetManager;
        /// @notice Monotonic escrow ID allocator
        uint256 nextEscrowId;
        /// @notice Escrows keyed by Escrow ID
        mapping(uint256 escrowId => Escrow escrow) escrows;
        /// @notice Authorization matrix: moduleType => module address => is authorized
        mapping(bytes32 moduleType => mapping(address moduleAddress => bool authorized)) isAuthorizedModule;
        /// @notice Module type assigned to each module address
        mapping(address moduleAddress => bytes32 moduleType) moduleTypeOf;
        /// @notice Aggregate reserved balance per asset key, derived from (assetType, token, tokenId)
        mapping(bytes32 assetKey => uint256 reservedAmount) reservedByAsset;
        /// @notice Number of escrows with non-zero balance created by each module address
        mapping(address moduleAddress => uint256 activeEscrows) activeEscrowsByModule;
    }

    /**
     * @notice ERC-7201 storage location for EscrowManager state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.escrowManager.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _ESCROW_MANAGER_STORAGE_LOCATION =
        0x60ce498f4d0cc13d813fdb91551eea26d56e554fb819ecaa166e41704f55f600;

    /**
     * @notice Returns EscrowManager namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _escrowManagerStorage() internal pure returns (EscrowManagerState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _ESCROW_MANAGER_STORAGE_LOCATION
        }
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title BaseTokenStorage
 * @author DEUSS Team
 * @notice This contract defines the storage layout for the BaseToken
 * @dev It is used to store the basic information of the token
 */
abstract contract BaseTokenStorage {
    /// @notice The version of the token (Used for tracking updates)
    string public constant TOKEN_VERSION = "1.0.0";

    /**
     * @notice Registry dependencies and per-token pause/freeze storage.
     * @custom:storage-location erc7201:deuss.baseToken.storage
     */
    struct BaseTokenState {
        /// @dev BondRegistry contract address
        address bondRegistry;
        /// @dev EntityRegistry contract address
        address entityRegistry;
        /// @dev Mapping of individual token IDs that are paused
        mapping(uint256 tokenId => bool paused) pausedTokenIds;
        /// @notice Mapping of frozen token amounts per account per token ID
        mapping(address account => mapping(uint256 tokenId => uint256 amount)) frozenTokens;
    }

    /**
     * @notice ERC-7201 storage location for BaseToken state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.baseToken.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _BASE_TOKEN_STORAGE_LOCATION =
        0x306d654b0f84205d63eadb02830f6b056d632e5e28f0f15651042898a790b800;

    /**
     * @notice Returns BaseToken namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _baseTokenStorage() internal pure returns (BaseTokenState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _BASE_TOKEN_STORAGE_LOCATION
        }
    }
}

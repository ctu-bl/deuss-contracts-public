// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title PolicyRegistryStorage
 * @author DEUSS Team
 * @notice Storage layout for the wallet-scoped policy registry.
 *
 * @dev Wallet-local policy state is keyed by (wallet, ownershipEpoch) so that any
 *      CompanyWallet ownership transfer automatically invalidates the entire previous
 *      set of delegated admins, user roles, operation roles, and operation modules —
 *      without requiring an explicit on-chain cleanup step.
 */
abstract contract PolicyRegistryStorage {
    /**
     * @notice Wallet-scoped policy authorization storage.
     * @custom:storage-location erc7201:deuss.policyRegistry.storage
     */
    struct PolicyRegistryState {
        /// @notice Wallet-and-epoch-scoped role bitmap for each user.
        mapping(address wallet => mapping(uint256 epoch => mapping(address user => uint256 roles))) walletUserRoles;
        /// @notice Wallet-and-epoch-scoped allowed role bitmap for each operation key.
        mapping(address wallet => mapping(uint256 epoch => mapping(bytes32 operationKey => uint256 roles)))
            walletOperationRoles;
        /// @notice Optional wallet-and-epoch-scoped validation module for each operation key.
        mapping(address wallet => mapping(uint256 epoch => mapping(bytes32 operationKey => address module)))
            walletOperationModules;
        /// @notice Delegated wallet policy admins authorized for wallet-local policy changes, scoped by epoch.
        mapping(address wallet => mapping(uint256 epoch => mapping(address admin => bool isAdmin))) walletPolicyAdmins;
        /// @notice Global allowlist of trusted policy modules.
        mapping(address module => bool allowed) allowedPolicyModules;
        /// @notice Compact on-chain metadata for role ids.
        mapping(uint8 roleId => bytes32 label) roleLabels;
    }

    /**
     * @notice ERC-7201 storage location for PolicyRegistry state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.policyRegistry.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _POLICY_REGISTRY_STORAGE_LOCATION =
        0xce7b8f57451b6d30cca783bcc35015d56dd0906abf0fcbad62a7d3f1c297ce00;

    /**
     * @notice Returns PolicyRegistry namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _policyRegistryStorage() internal pure returns (PolicyRegistryState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _POLICY_REGISTRY_STORAGE_LOCATION
        }
    }
}

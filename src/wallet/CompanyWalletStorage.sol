// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title CompanyWalletStorage
 * @author DEUSS Team
 * @notice Storage layout for CompanyWallet.
 */
abstract contract CompanyWalletStorage {
    /**
     * @notice CompanyWallet authorization and ownership-epoch storage.
     * @custom:storage-location erc7201:deuss.companyWallet.storage
     */
    struct CompanyWalletState {
        /// @dev Legacy EntityRegistry dependency retained for storage schema compatibility.
        address entityRegistry;
        /// @notice Shared authorization authority for non-owner execution.
        address policyRegistry;
        /// @notice Monotonically increasing counter; advanced on every ownership transfer.
        uint256 ownershipEpoch;
        /// @dev Legacy operation role mapping retained for storage schema compatibility.
        mapping(bytes32 operation => uint256 roles) operations;
    }

    /**
     * @notice ERC-7201 storage location for CompanyWallet state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.companyWallet.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _COMPANY_WALLET_STORAGE_LOCATION =
        0x26cfa5c152e9ee40b0d968aa8da53f10848b2d702288b6ba255c6d38b1fc0a00;

    /**
     * @notice Returns CompanyWallet namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _companyWalletStorage() internal pure returns (CompanyWalletState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _COMPANY_WALLET_STORAGE_LOCATION
        }
    }
}

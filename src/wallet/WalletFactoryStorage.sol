// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title WalletFactoryStorage
 * @author DEUSS Team
 * @notice Storage layout for WalletFactory.
 */
abstract contract WalletFactoryStorage {
    /**
     * @notice Wallet factory configuration storage.
     * @custom:storage-location erc7201:deuss.walletFactory.storage
     */
    struct WalletFactoryState {
        /// @notice EntityRegistry used for manager authorization and wallet registration flows.
        address entityRegistry;
        /// @notice Template id overrides by wallet type.
        mapping(bytes32 walletType => bytes32 templateId) walletTemplateIdByType;
    }

    /**
     * @notice ERC-7201 storage location for WalletFactory state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.walletFactory.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _WALLET_FACTORY_STORAGE_LOCATION =
        0x2320b74ecaa9dbb202c7d616b11399e5bb5587b679a25fda569c70e1176ff500;

    /**
     * @notice Returns WalletFactory namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _walletFactoryStorage() internal pure returns (WalletFactoryState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _WALLET_FACTORY_STORAGE_LOCATION
        }
    }
}

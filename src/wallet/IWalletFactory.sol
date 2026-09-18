// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IProxyDeployer} from "src/deployer/IProxyDeployer.sol";

/**
 * @title IWalletFactory
 * @author DEUSS Team
 * @notice Entity-manager controlled deployment of typed wallet proxies.
 */
interface IWalletFactory is IProxyDeployer {
    /**
     * @notice Parameters for wallet creation.
     * @param entityId Entity identifier managed by the caller.
     * @param walletType Wallet type identifier.
     * @param initData Wallet-specific initialization payload forwarded to the proxy as-is.
     */
    struct CreateWalletParams {
        bytes32 entityId;
        bytes32 walletType;
        bytes initData;
    }

    /**
     * @notice Emitted when a new wallet is deployed.
     * @param entityId Entity that the deployed wallet belongs to.
     * @param wallet Deployed wallet proxy address.
     * @param walletType Requested wallet type.
     * @param caller Address that initiated wallet creation.
     */
    event WalletCreated(bytes32 indexed entityId, address indexed wallet, bytes32 walletType, address indexed caller);

    /**
     * @notice Emitted when a wallet type is mapped to a deployment template.
     * @param walletType Wallet type identifier.
     * @param templateId Template identifier configured for the wallet type.
     * @param name Template name registered in EBSI template registry.
     * @param version Template version registered in EBSI template registry.
     */
    event WalletTemplateForTypeSet(bytes32 indexed walletType, bytes32 indexed templateId, string name, string version);

    /**
     * @notice Emitted when the EntityRegistry reference is set.
     * @param entityRegistry EntityRegistry address bound to this factory.
     */
    event EntityRegistrySet(address indexed entityRegistry);

    /**
     * @notice Deploys a wallet proxy for a managed entity.
     * @param params Wallet creation parameters.
     * @return wallet Deployed wallet address.
     */
    function createWallet(CreateWalletParams calldata params) external returns (address wallet);

    /**
     * @notice Sets wallet template for a wallet type.
     * @param walletType Wallet type identifier.
     * @param name Template name registered in EBSI template registry.
     * @param version Template version registered in EBSI template registry.
     * @dev Emits WalletTemplateForTypeSet on success.
     */
    function setWalletTemplateForType(bytes32 walletType, string calldata name, string calldata version) external;

    /**
     * @notice Returns wallet template id configured for a type.
     * @param walletType Wallet type identifier.
     * @return templateId Template identifier configured for the wallet type.
     */
    function getWalletTemplateIdForType(bytes32 walletType) external view returns (bytes32 templateId);

    /**
     * @notice Returns bound EntityRegistry address.
     * @return registry EntityRegistry address used by this factory.
     */
    function entityRegistry() external view returns (address registry);
}

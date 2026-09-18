// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {AssetType, Escrow} from "../MarketStructs.sol";

/**
 * @title IEscrowManager
 * @author DEUSS Team
 * @notice Interface for managing token escrow operations in the marketplace
 */
interface IEscrowManager {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when a new escrow is created
     * @param escrowId The ID of the escrow
     * @param moduleType The module type this escrow belongs to
     * @param depositor The address of the depositor
     * @param tokenAddress The address of the token contract
     * @param tokenId The ID of the token
     * @param amount The amount of tokens deposited
     * @param assetType The token standard of the escrowed asset
     */
    event EscrowCreated(
        uint256 indexed escrowId,
        bytes32 indexed moduleType,
        address indexed depositor,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        AssetType assetType
    );

    /**
     * @notice Emitted when tokens are claimed from an escrow with asset details
     * @param escrowId The ID of the escrow
     * @param beneficiary The address of the beneficiary receiving the tokens
     * @param amount The amount of tokens claimed from the escrow
     * @param tokenAddress The address of the token contract
     * @param tokenId The ID of the token
     * @param assetType The token standard of the claimed asset
     */
    event Claimed(
        uint256 indexed escrowId,
        address indexed beneficiary,
        uint256 indexed amount,
        address tokenAddress,
        uint256 tokenId,
        AssetType assetType
    );

    /**
     * @notice Emitted when tokens are withdrawn from an escrow with asset details
     * @param escrowId The ID of the escrow
     * @param beneficiary The address receiving withdrawn tokens
     * @param amount The amount of tokens withdrawn from the escrow
     * @param tokenAddress The address of the token contract
     * @param tokenId The ID of the token
     * @param assetType The token standard of the withdrawn asset
     */
    event Withdrawn(
        uint256 indexed escrowId,
        address indexed beneficiary,
        uint256 indexed amount,
        address tokenAddress,
        uint256 tokenId,
        AssetType assetType
    );

    /**
     * @notice Emitted when a module is registered for a module type
     * @param moduleType The module type
     * @param moduleAddress The module address
     */
    event ModuleRegistered(bytes32 indexed moduleType, address indexed moduleAddress);

    /**
     * @notice Emitted when a module is deactivated for a module type
     * @param moduleType The module type
     * @param moduleAddress The module address
     */
    event ModuleDeactivated(bytes32 indexed moduleType, address indexed moduleAddress);

    /**
     * @notice Emitted when the asset manager address is updated with previous and new addresses
     * @param previousAssetManager The previous asset manager address
     * @param assetManager The new asset manager address
     */
    event AssetManagerSet(address indexed previousAssetManager, address indexed assetManager);

    /**
     * @notice Emitted when surplus (untracked) assets are swept from the contract
     * @param assetType The token standard of the swept asset
     * @param token The token contract address
     * @param tokenId The token identifier
     * @param beneficiary The address receiving the swept assets
     * @param amount The amount of tokens swept
     */
    event Swept(
        AssetType indexed assetType, address indexed token, uint256 indexed tokenId, address beneficiary, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Registers an authorized module for a module type
     * @param moduleType The module type
     * @param moduleAddress The module address
     * @dev Only callable by addresses with ADMIN role
     */
    function registerModule(bytes32 moduleType, address moduleAddress) external;

    /**
     * @notice Deactivates an authorized module for a module type
     * @param moduleType The module type
     * @param moduleAddress The module address
     * @dev Only callable by addresses with ADMIN role
     */
    function deactivateModule(bytes32 moduleType, address moduleAddress) external;

    /**
     * @notice Sets the asset manager used for whitelist and asset-type validation
     * @param assetManager Address of the asset manager contract
     * @dev Only callable by addresses with ADMIN role
     */
    function setAssetManager(address assetManager) external;

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Creates a new escrow and deposits tokens
     * @param amount The amount of tokens to deposit into escrow
     * @param depositor The address of the token depositor
     * @param tokenAddress The address of the token contract
     * @param tokenId The ID of the specific token
     * @return escrowId The allocated escrow ID
     */
    function createEscrow(uint256 amount, address depositor, address tokenAddress, uint256 tokenId)
        external
        returns (uint256 escrowId);

    /**
     * @notice Withdraws tokens from an escrow back to the original depositor
     * @param escrowId The ID of the escrow
     * @param amount The amount of tokens to withdraw from the escrow (must be non-zero)
     */
    function withdraw(uint256 escrowId, uint256 amount) external;

    /**
     * @notice Claims tokens from an escrow to a beneficiary
     * @param escrowId The ID of the escrow
     * @param amount The amount of tokens to claim from the escrow (must be non-zero)
     * @param beneficiary The address of the beneficiary receiving the tokens
     */
    function claim(uint256 escrowId, uint256 amount, address beneficiary) external;

    /**
     * @notice Sweeps surplus (untracked) assets from the contract to a beneficiary
     * @param assetType The token standard of the asset to sweep
     * @param token The token contract address
     * @param tokenId The token identifier
     * @param amount The amount to sweep (must not exceed surplus)
     * @param beneficiary The address receiving the swept assets
     * @dev Only callable by addresses with ADMIN role
     */
    function sweep(AssetType assetType, address token, uint256 tokenId, uint256 amount, address beneficiary) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the escrow details for an escrow ID
     * @param escrowId The escrow ID
     * @return escrow The complete escrow struct containing all escrow data
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory escrow);

    /**
     * @notice Returns the escrow ID expected to be allocated by the next createEscrow call.
     * @return escrowId Next escrow ID.
     */
    function previewNextEscrowId() external view returns (uint256 escrowId);

    /**
     * @notice Returns the amount of surplus (untracked) assets that can be swept
     * @param assetType The token standard of the asset
     * @param token The token contract address
     * @param tokenId The token identifier
     * @return surplus The sweepable surplus amount, clamped at zero
     */
    function getSweepableAmount(AssetType assetType, address token, uint256 tokenId)
        external
        view
        returns (uint256 surplus);
}

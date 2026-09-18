// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IBondRegistry} from "src/registry/interfaces/IBondRegistry.sol";
import {IEntityRegistry} from "src/registry/interfaces/IEntityRegistry.sol";

/**
 * @title IBaseToken
 * @author DEUSS Team
 * @notice This interface defines the basic functionalities of a token
 * @dev Interface for the BaseToken contract
 */
interface IBaseToken is IERC6909 {
    /**
     * @notice This event is emitted when the BondRegistry has been set for the token
     * @dev The event is emitted by the token constructor and by the setBondRegistry function
     * @param bondRegistry The BondRegistry address
     */
    event BondRegistryUpdated(address indexed bondRegistry);

    /**
     * @notice This event is emitted when the EntityRegistry has been set for the token
     * @dev The event is emitted by the token constructor and by the setEntityRegistry function
     * @param entityRegistry The EntityRegistry address
     */
    event EntityRegistryUpdated(address indexed entityRegistry);

    /**
     * @notice This event is emitted when a specific token ID is paused
     * @dev The event is emitted by the pauseTokenId function
     * @param tokenId The token ID that was paused
     * @param operator The address that called the function
     */
    event TokenPaused(uint256 indexed tokenId, address indexed operator);

    /**
     * @notice This event is emitted when a specific token ID is unpaused
     * @dev The event is emitted by the unpauseTokenId function
     * @param tokenId The token ID that was unpaused
     * @param operator The address that called the function
     */
    event TokenUnpaused(uint256 indexed tokenId, address indexed operator);

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the BondRegistry
     * @dev Only the owner of the token smart contract can call this function
     * This function can be called even if the token contract is paused.
     * Reverts if the BondRegistry is already configured.
     * @param bondRegistryAddr The address of BondRegistry to set
     */
    function setBondRegistry(address bondRegistryAddr) external;

    /**
     * @notice Set the EntityRegistry
     * @dev Only the owner of the token smart contract can call this function.
     * This function can be called even if the token contract is paused.
     * Reverts if the EntityRegistry is already configured.
     * @param entityRegistryAddr The address of EntityRegistry to set
     */
    function setEntityRegistry(address entityRegistryAddr) external;

    /*//////////////////////////////////////////////////////////////
                            AGENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint tokens to a specified address
     * @dev This enhanced version of the default mint method allows tokens to be minted to an address only
     * if it is a verified and whitelisted address according to the security token.
     * This function can only be called by the BondRegistry contract.
     * This function can only be performed during `Issued` token phase.
     * @param to The address to mint the tokens to
     * @param tokenId Token Id
     * @param amount The amount of tokens to be minted.
     */
    function mint(address to, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Pause the token contract
     * @dev When the contract is paused, all token transfers are temporarily suspended.
     * This function can only be called by the owner of the token contract.
     * The function can be called only when the contract is not already paused.
     */
    function pause() external;

    /**
     * @notice Pause a specific token ID, preventing transfers of that token
     * @dev This function can only be called by the BondRegistry contract
     * It can be called even if the token contract is paused.
     * @param tokenId The token ID to pause
     */
    function pauseTokenId(uint256 tokenId) external;

    /**
     * @notice Unpause the token contract, allowing investors to resume token transfers under normal conditions
     * @dev This function can only be called by the owner of the token contract.
     * The function can be called only when the contract is currently paused.
     */
    function unpause() external;

    /**
     * @notice Unpause a specific token ID, allowing transfers of that token again
     * @dev This function can only be called by the BondRegistry contract
     * It can be called only when the token contract is not paused.
     * @param tokenId The token ID to unpause
     */
    function unpauseTokenId(uint256 tokenId) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieve Bond Registry contract linked to the contract
     * @return BondRegistry contract
     */
    function bondRegistry() external view returns (IBondRegistry);

    /**
     * @notice Retrieve Entity Registry contract linked to the contract
     * @return EntityRegistry contract
     */
    function entityRegistry() external view returns (IEntityRegistry);

    /**
     * @notice Retrieve the amount of tokens that are partially frozen on a wallet
     * @dev The amount of frozen tokens is always <= the total balance of the wallet
     * @param account The address of the wallet on which frozenBalanceOf is called
     * @param tokenId Token Id
     * @return The amount of frozen tokens
     */
    function frozenBalanceOf(address account, uint256 tokenId) external view returns (uint256);

    /**
     * @notice Retrieve if the contract is paused
     * @return True if the contract is paused, otherwise false
     */
    function paused() external view returns (bool);

    /**
     * @notice Retrieve if a specific token ID is paused
     * @param tokenId The token ID to check
     * @return True if the token ID is paused, otherwise false
     */
    function isTokenPaused(uint256 tokenId) external view returns (bool);

    /**
     * @notice Retrieve the DEUSS version of the non-fungible token
     * current version is 1.0.0
     * @return The version as string
     */
    function version() external view returns (string memory);
}

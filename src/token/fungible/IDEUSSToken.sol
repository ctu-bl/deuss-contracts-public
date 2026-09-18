// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC6909TokenSupply} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IBaseToken} from "../base/IBaseToken.sol";

/**
 * @title IDEUSSToken
 * @author DEUSS Team
 * @notice Interface for DEUSSToken extending IBaseToken and IERC6909TokenSupply
 */
interface IDEUSSToken is IBaseToken, IERC6909TokenSupply {
    /**
     * @notice This event is emitted when a certain amount of tokens is frozen on a wallet
     * @dev The event is emitted by freezePartialTokens and batchFreezePartialTokens functions
     * @param account The wallet of the investor that is subject to the freezing status
     * @param tokenId Token Id
     * @param amount The amount of tokens that are frozen
     */
    event TokensFrozen(address indexed account, uint256 indexed tokenId, uint256 indexed amount);

    /**
     * @notice This event is emitted when a certain amount of tokens is unfrozen on a wallet
     * @dev The event is emitted by unfreezePartialTokens and batchUnfreezePartialTokens functions
     * @param account The wallet of the investor that is subject to the freezing status
     * @param tokenId Token Id
     * @param amount The amount of tokens that are unfrozen
     */
    event TokensUnfrozen(address indexed account, uint256 indexed tokenId, uint256 indexed amount);

    /**
     * @notice This event is emitted when an address is marked as protected custody.
     * @dev Protection is one-way only; the event is emitted when protection is first set.
     * @param account The address whose custody status was updated.
     * @param isProtected Always true for this event in the current implementation.
     */
    event ProtectedAddressSet(address indexed account, bool indexed isProtected);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiates forced transfers in batch
     * @dev Use case: regulatory recovery, court-ordered asset seizure, or compliance-driven reallocation across multiple holders.
     * Require that each amounts[i] does not exceed the available balance of froms[i].
     * Require that the `tos` addresses are all verified and whitelisted addresses.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `froms.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * This function can only be called by an address that has been granted the role `FORCE_TRANSFER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * The caller must also be an enabled wallet in the EntityRegistry.
     * This function can be executed if the `froms` balances are sufficient, the `tos` wallets are enabled,
     * the `tos` wallets are not protected-custody addresses, and the token contract is not paused.
     * Disabled `froms` wallets are allowed to support protocol recovery from blocked accounts.
     * @param froms Addresses of the senders
     * @param tos Addresses of the receivers
     * @param tokenId Token Id
     * @param amounts The amount of tokens to transfer to the corresponding receivers
     */
    function batchForcedTransfer(
        address[] calldata froms,
        address[] calldata tos,
        uint256 tokenId,
        uint256[] calldata amounts
    ) external;

    /**
     * @notice Initiates partial freezing of tokens in batch
     * @dev Use case: enforcing vesting schedules, regulatory holds, or compliance restrictions across multiple investors.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `wallets.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * This function can only be called by an address that has been granted the role `TOKEN_FREEZER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * This function can be executed if the wallet balances are sufficient and the token contract is not paused.
     * @param wallets Addresses on which tokens need to be partially frozen
     * @param tokenId Token Id
     * @param amounts The amount of tokens to freeze on the corresponding addresses
     */
    function batchFreezePartialTokens(address[] calldata wallets, uint256 tokenId, uint256[] calldata amounts) external;

    /**
     * @notice Initiates partial unfreezing of tokens in batch
     * @dev Use case: releasing tokens after vesting cliff, lifting regulatory holds, or restoring trading rights for multiple investors.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `wallets.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * This function can only be called by an address that has been granted the role `TOKEN_FREEZER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * This function can be executed if the wallet's frozen balances are sufficient and the token contract is not paused.
     * @param wallets Addresses on which tokens need to be partially unfrozen
     * @param tokenId Token Id
     * @param amounts The amount of tokens to unfreeze on the corresponding addresses
     */
    function batchUnfreezePartialTokens(address[] calldata wallets, uint256 tokenId, uint256[] calldata amounts)
        external;

    /**
     * @notice Burn tokens from a specified address
     * @dev If the account address does not have sufficient free tokens (unfrozen tokens),
     * but possesses a total balance equal to or greater than the specified amount,
     * the frozen token amount is reduced to ensure enough free tokens for the burn.
     * In such cases, the remaining balance in the account consists entirely of frozen tokens post-transaction.
     * This function can only be called by `BondRegistry`.
     * This function can be executed if the `from` balance is sufficient and the token contract is not paused.
     * A disabled `from` wallet is allowed to support protocol recovery from blocked accounts.
     * @param from Address to burn the tokens from
     * @param tokenId Token Id
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Initiates burning of tokens in batch
     * @dev Use case: bond maturity redemption, corporate action processing, or mass token recall across multiple holders.
     * Disabled `froms` wallets are allowed to support protocol recovery from blocked accounts.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `froms.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * This function can only be called by `BondRegistry`.
     * This function can be executed if the `from` balances are sufficient and the token contract is not paused.
     * @param froms Addresses of the wallets concerned by the burn
     * @param tokenId Token Id
     * @param amounts The amount of tokens to burn from the corresponding wallets
     */
    function burnBatch(address[] calldata froms, uint256 tokenId, uint256[] calldata amounts) external;

    /**
     * @notice Initiates a forced transfer of tokens to a whitelisted wallet
     * @dev If the `from` address does not have sufficient free tokens (unfrozen tokens) but possesses a total balance equal to or greater than the specified `amount`,
     * the frozen token amount is reduced to ensure enough free tokens for the transfer.
     * In such cases, the remaining balance in the `from` account consists entirely of frozen tokens post-transfer.
     * This function can only be called by an address that has been granted the role `FORCE_TRANSFER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * The caller must also be an enabled wallet in the EntityRegistry.
     * This function can be executed if the `from` balance is sufficient, `to` is enabled,
     * `to` is not a protected-custody address, and the token contract is not paused.
     * A disabled `from` wallet is allowed to support protocol recovery from blocked accounts.
     * @param from The address of the token owner
     * @param to The address of the receiver
     * @param tokenId Token Id
     * @param amount The amount of tokens to be transferred
     * @return True if the transfer was successful
     */
    function forcedTransfer(address from, address to, uint256 tokenId, uint256 amount) external returns (bool);

    /**
     * @notice Freeze a specified token amount for a given address, preventing those tokens from being transferred
     * @dev This function can only be called by an address that has been granted the role `TOKEN_FREEZER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * This function can be executed if the wallet balance is sufficient and the token contract is not paused.
     * @param wallet The address for which to freeze tokens
     * @param tokenId Token Id
     * @param amount The amount of tokens to be frozen
     */
    function freezePartialTokens(address wallet, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Unfreeze a specified token amount for a given address, allowing those tokens to be transferred again
     * @dev This function can only be called by an address that has been granted the role `TOKEN_FREEZER_ROLE`.
     * If the caller does not have this role, the transaction will revert.
     * This function can be executed if the wallet frozen balance is sufficient and the token contract is not paused.
     * @param wallet The address for which to unfreeze tokens
     * @param tokenId Token Id
     * @param amount The amount of tokens to be unfrozen
     */
    function unfreezePartialTokens(address wallet, uint256 tokenId, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                            GLOBAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer multiple token IDs from one address to a single recipient
     * @dev Use case: consolidating multiple bond tranches or token classes into a single recipient wallet.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `ids.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * @param from The address of the tokens owner
     * @param to The address of the receiver
     * @param tokenIds Token IDs to transfer
     * @param amounts The amount of tokens to transfer for each corresponding token ID
     */
    function batchTransferFrom(address from, address to, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external;

    /**
     * @notice Transfer a single token ID from one address to multiple recipients
     * @dev Use case: bond distribution to multiple investors, dividend or coupon payment distribution.
     * IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `tos.length` IS TOO HIGH.
     * USE WITH CARE TO AVOID "OUT OF GAS" TRANSACTIONS AND POTENTIAL LOSS OF TX FEES.
     * @param from The address of the tokens owner
     * @param tos Addresses of the receivers
     * @param tokenId Token ID to transfer
     * @param amounts The amount of tokens to transfer to each corresponding receiver
     */
    function batchTransferFrom(address from, address[] calldata tos, uint256 tokenId, uint256[] calldata amounts)
        external;

    /**
     * @notice Marks an address as protected custody.
     * @dev Only the owner can call this function. Once an address is protected, it cannot be unprotected.
     * Calling this function again for an already protected address reverts with `Token__AddressAlreadyProtected`.
     * @param account The address to protect.
     */
    function protectAddress(address account) external;

    /**
     * @notice Returns the historical balance of an account for a token ID at a given block
     * @dev Uses checkpointed snapshots and reverts with `Token__BlockInFuture` if `blockNumber` is greater than the current block.
     * @param account The address to query
     * @param tokenId Token ID
     * @param blockNumber The block number to query
     * @return The account balance recorded at `blockNumber`
     */
    function balanceOfAt(address account, uint256 tokenId, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Returns the historical total supply for a token ID at a given block
     * @dev Uses checkpointed snapshots and reverts with `Token__BlockInFuture` if `blockNumber` is greater than the current block.
     * @param tokenId Token ID
     * @param blockNumber The block number to query
     * @return The total supply recorded at `blockNumber`
     */
    function totalSupplyAt(uint256 tokenId, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Returns the historical frozen balance of an account for a token ID at a given block
     * @dev Uses checkpointed snapshots and reverts with `Token__BlockInFuture` if `blockNumber` is greater than the current block.
     * @param account The address to query
     * @param tokenId Token ID
     * @param blockNumber The block number to query
     * @return The account frozen balance recorded at `blockNumber`
     */
    function frozenBalanceOfAt(address account, uint256 tokenId, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Returns the historical available balance of an account for a token ID at a given block
     * @dev Computed as `balanceOfAt - frozenBalanceOfAt` with underflow protection, and reverts
     * with `Token__BlockInFuture` if `blockNumber` is greater than the current block.
     * @param account The address to query
     * @param tokenId Token ID
     * @param blockNumber The block number to query
     * @return The account available balance recorded at `blockNumber`
     */
    function availableBalanceOfAt(address account, uint256 tokenId, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Returns whether an address is marked as protected custody.
     * @param account The address to query.
     * @return True if the address is protected, otherwise false.
     */
    function isAddressProtected(address account) external view returns (bool);
}

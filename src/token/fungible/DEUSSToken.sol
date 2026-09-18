// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// DEUSS:
import {Errors} from "../../libs/Errors.sol";
import {IDEUSSToken} from "./IDEUSSToken.sol";
import {DEUSSTokenStorage} from "./DEUSSTokenStorage.sol";
import {BaseToken} from "../base/BaseToken.sol";
import {IBaseToken} from "../base/IBaseToken.sol";
import {IEntityRegistry} from "../../registry/interfaces/IEntityRegistry.sol";

/**
 * @title DEUSSToken
 * @author DEUSS Team
 * @notice DEUSSToken is a contract that implements a fungible token standard based on ERC-6909
 * @dev Implements the IDEUSSToken interface and the BaseToken contract
 */
contract DEUSSToken is IDEUSSToken, DEUSSTokenStorage, BaseToken {
    using Checkpoints for Checkpoints.Trace208;

    /**
     * @notice Locks any future initializations or reinitializations on the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the DEUSSToken contract
     * @dev This function is called only once during the contract's initialization phase
     * @param owner_ The address of the owner of the token contract
     * @param bondRegistry_ The address of the bond registry contract
     * @param entityRegistry_ The address of the entity registry contract
     * @param escrowManager_ The EscrowManager custody address to protect during initialization
     */
    function initialize(address owner_, address bondRegistry_, address entityRegistry_, address escrowManager_)
        external
        initializer
    {
        __BaseToken_init(owner_, bondRegistry_, entityRegistry_);
        _protectAddress(escrowManager_);
    }

    /*//////////////////////////////////////////////////////////////
                       EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IDEUSSToken
     */
    function batchForcedTransfer(
        address[] calldata froms,
        address[] calldata tos,
        uint256 tokenId,
        uint256[] calldata amounts
    ) external onlyRoles(FORCE_TRANSFER_ROLE) {
        uint256 fromsLen = froms.length;
        uint256 tosLen = tos.length;

        _checkArraysLengthsMatch(fromsLen, tosLen);
        _checkArraysLengthsMatch(tosLen, amounts.length);

        _isCallerWalletEnabled(msg.sender);

        // `i` is bounded by `fromsLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < fromsLen; ++i) {
                uint256 amount = amounts[i];
                address to = tos[i];
                address from = froms[i];

                _beforeRoleTransfer(from, to, tokenId, amount);

                _transfer(from, to, tokenId, amount);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function batchFreezePartialTokens(address[] calldata wallets, uint256 tokenId, uint256[] calldata amounts)
        external
        onlyRoles(TOKEN_FREEZER_ROLE)
    {
        uint256 walletsLen = wallets.length;

        _checkArraysLengthsMatch(walletsLen, amounts.length);

        // `i` is bounded by `walletsLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < walletsLen; ++i) {
                _freezeTokens(wallets[i], tokenId, amounts[i]);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function batchTransferFrom(address from, address to, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
    {
        uint256 tokenIdsLen = tokenIds.length;

        _checkArraysLengthsMatch(tokenIdsLen, amounts.length);

        // `i` is bounded by `tokenIdsLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < tokenIdsLen; ++i) {
                uint256 id = tokenIds[i];
                uint256 amount = amounts[i];

                _beforeTransfer(from, to, id, amount);

                _transfer(from, to, id, amount);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function batchTransferFrom(address from, address[] calldata tos, uint256 tokenId, uint256[] calldata amounts)
        external
    {
        uint256 tosLen = tos.length;

        _checkArraysLengthsMatch(tosLen, amounts.length);

        // `i` is bounded by `tosLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < tosLen; ++i) {
                address to = tos[i];
                uint256 amount = amounts[i];

                _beforeTransfer(from, to, tokenId, amount);

                _transfer(from, to, tokenId, amount);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function batchUnfreezePartialTokens(address[] calldata users, uint256 tokenId, uint256[] calldata amounts)
        external
        onlyRoles(TOKEN_FREEZER_ROLE)
    {
        uint256 usersLen = users.length;

        _checkArraysLengthsMatch(usersLen, amounts.length);

        // `i` is bounded by `usersLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < usersLen; ++i) {
                _unfreezeTokens(users[i], tokenId, amounts[i]);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function burnBatch(address[] calldata froms, uint256 tokenId, uint256[] calldata amounts)
        external
        onlyBondRegistry
    {
        uint256 fromsLen = froms.length;

        _checkArraysLengthsMatch(fromsLen, amounts.length);

        // `i` is bounded by `fromsLen`, which is derived from calldata length, so the increment cannot overflow.
        unchecked {
            for (uint256 i; i < fromsLen; ++i) {
                _burnTokens(froms[i], tokenId, amounts[i]);
            }
        }
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function burn(address from, uint256 tokenId, uint256 amount) external onlyBondRegistry {
        _burnTokens(from, tokenId, amount);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function forcedTransfer(address from, address to, uint256 tokenId, uint256 amount)
        external
        onlyRoles(FORCE_TRANSFER_ROLE)
        returns (bool)
    {
        _isCallerWalletEnabled(msg.sender);

        _beforeRoleTransfer(from, to, tokenId, amount);

        _transfer(from, to, tokenId, amount);

        return true;
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function freezePartialTokens(address account, uint256 tokenId, uint256 amount)
        external
        onlyRoles(TOKEN_FREEZER_ROLE)
    {
        _freezeTokens(account, tokenId, amount);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function unfreezePartialTokens(address account, uint256 tokenId, uint256 amount)
        external
        onlyRoles(TOKEN_FREEZER_ROLE)
    {
        _unfreezeTokens(account, tokenId, amount);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function protectAddress(address account) external onlyOwner {
        _protectAddress(account);
    }

    /**
     * @notice Permanently marks an address as protected custody.
     * @param account The address to protect.
     */
    function _protectAddress(address account) internal {
        require(account != address(0), Errors.ZeroAddress());
        require(!_deussTokenStorage().protectedAddress[account], Errors.Token__AddressAlreadyProtected(account));

        _deussTokenStorage().protectedAddress[account] = true;

        emit ProtectedAddressSet(account, true);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function isAddressProtected(address account) external view returns (bool) {
        return _deussTokenStorage().protectedAddress[account];
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function balanceOfAt(address account, uint256 tokenId, uint256 blockNumber) external view returns (uint256) {
        return _historicalBalanceOf(account, tokenId, blockNumber);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function totalSupplyAt(uint256 tokenId, uint256 blockNumber) external view returns (uint256) {
        return _historicalTotalSupplyOf(tokenId, blockNumber);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function frozenBalanceOfAt(address account, uint256 tokenId, uint256 blockNumber) external view returns (uint256) {
        return _historicalFrozenBalanceOf(account, tokenId, blockNumber);
    }

    /**
     * @inheritdoc IDEUSSToken
     */
    function availableBalanceOfAt(address account, uint256 tokenId, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        uint256 historicalBalance = _historicalBalanceOf(account, tokenId, blockNumber);
        uint256 historicalFrozenBalance = _historicalFrozenBalanceOf(account, tokenId, blockNumber);

        return historicalFrozenBalance > historicalBalance ? 0 : historicalBalance - historicalFrozenBalance;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBaseToken
     */
    function mint(address to, uint256 tokenId, uint256 amount) public override(IBaseToken, BaseToken) onlyBondRegistry {
        _beforeRoleTransfer(address(0), to, tokenId, amount);

        _mint(to, tokenId, amount);
    }

    /**
     * @inheritdoc IERC6909
     */
    function approve(address spender, uint256 tokenId, uint256 amount)
        public
        override(IERC6909, BaseToken)
        whenNotPaused
        returns (bool)
    {
        if (amount != 0) {
            return super.approve(spender, tokenId, amount);
        }
        _approve(msg.sender, spender, tokenId, 0);
        return true;
    }

    /**
     * @inheritdoc IERC6909
     * @dev Granting operator approval requires the owner and operator to be approval-eligible in the
     *      EntityRegistry. Revocation remains allowed even if either side is no longer enabled.
     */
    function setOperator(address spender, bool approved)
        public
        override(IERC6909, BaseToken)
        whenNotPaused
        returns (bool)
    {
        require(
            !approved || IEntityRegistry(_baseTokenStorage().entityRegistry).canApprove(msg.sender, spender, 0, 0),
            Errors.Token__OperatorNotEnabled(spender)
        );

        return super.setOperator(spender, approved);
    }

    /**
     * @notice ERC-6909 overridden function that includes logic to transfer.
     * @dev Delegates to {transferFrom} with `from = msg.sender`.
     *      Enforces EntityRegistry transfer policy, token pause checks, and free-balance (non-frozen) availability.
     * @param receiver The address of the receiver
     * @param tokenId The identifier of token
     * @param amount The amount of tokens to transfer
     * @return bool indicating whether the operation succeeded
     * See {IERC6909.transfer}
     */
    function transfer(address receiver, uint256 tokenId, uint256 amount)
        public
        override(IERC6909, ERC6909Upgradeable)
        returns (bool)
    {
        return transferFrom(msg.sender, receiver, tokenId, amount);
    }

    /**
     * @notice IERC-6909 overridden function that includes logic to transferFrom.
     * @dev Enforces non-zero amount, token-id pause checks, EntityRegistry transfer policy (`canTransfer`),
     *      and that `amount` does not exceed the sender's free balance (`balance - frozenBalance`).
     *      If `msg.sender != from`, the caller must be an operator or have sufficient allowance.
     * @param from The address of the sender
     * @param to The address of the receiver
     * @param tokenId The identifier of token
     * @param amount The amount of tokens to transfer
     * @return bool indicating whether the operation succeeded
     */
    function transferFrom(address from, address to, uint256 tokenId, uint256 amount)
        public
        override(IERC6909, ERC6909Upgradeable)
        returns (bool)
    {
        _beforeTransfer(from, to, tokenId, amount);

        _transfer(from, to, tokenId, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC FUNCTIONS THAT ARE VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, BaseToken) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IDEUSSToken).interfaceId;
    }

    /**
     * @inheritdoc IBaseToken
     */
    function paused() public view override(BaseToken, IBaseToken) returns (bool) {
        return BaseToken.paused();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Hook called before a normal transfer.
     * @dev Protected custody may pull tokens through approved flows, but arbitrary holders cannot push tokens into it.
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param tokenId The identifier of the token
     * @param amount The amount of tokens to transfer
     */
    function _beforeTransfer(address from, address to, uint256 tokenId, uint256 amount) internal override {
        super._beforeTransfer(from, to, tokenId, amount);

        if (_deussTokenStorage().protectedAddress[to] && msg.sender != to) {
            revert Errors.Token__ProtectedReceiverTransferNotAllowed(from, to, msg.sender, tokenId);
        }
    }

    /**
     * @notice Hook called before a privileged transfer, mint, or burn.
     * @dev Validates and unfreezes the sender's balance if needed, allowing frozen tokens to be moved by privileged roles.
     *      Protected receiver validation applies only to privileged transfers, not minting or burning.
     *      Sender validation is skipped for minting operations (when `from` is address(0)).
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param tokenId The identifier of the token
     * @param amount The amount of tokens to transfer
     */
    function _beforeRoleTransfer(address from, address to, uint256 tokenId, uint256 amount) internal override {
        super._beforeRoleTransfer(from, to, tokenId, amount);

        if (from != address(0)) {
            require(!_deussTokenStorage().protectedAddress[from], Errors.Token__AddressProtected(from));
            if (to != address(0) && _deussTokenStorage().protectedAddress[to]) {
                revert Errors.Token__ProtectedReceiverTransferNotAllowed(from, to, msg.sender, tokenId);
            }
            _validateAndUnfreezeBalance(from, tokenId, amount);
        }
    }

    /**
     * @notice Internal function to burn a specified amount of tokens for a given token ID.
     * Calls the underlying {ERC6909._burn} function after validating and unfreezing the balance.
     * @param from The address from which the tokens will be burned
     * @param tokenId The identifier of the token to burn
     * @param amount The amount of tokens to burn from the corresponding wallet
     */
    function _burnTokens(address from, uint256 tokenId, uint256 amount) internal {
        _beforeRoleTransfer(from, address(0), tokenId, amount);

        _burn(from, tokenId, amount);
    }

    /**
     * @notice Internally freeze a specified amount of tokens from a given address
     * @dev Reduces the available transferable balance of the `from` address by `amount`, effectively locking the tokens.
     * This function should be used to enforce restrictions on token transfers, such as vesting or compliance requirements.
     * @param from The address from which tokens will be frozen
     * @param tokenId Token Id to freeze
     * @param amount The number of tokens to freeze
     */
    function _freezeTokens(address from, uint256 tokenId, uint256 amount) internal whenNotPaused {
        _validateNonZeroAmount(amount);
        require(!_deussTokenStorage().protectedAddress[from], Errors.Token__AddressProtected(from));

        uint256 newFrozen = _baseTokenStorage().frozenTokens[from][tokenId] + amount;

        _validateSufficientBalance(balanceOf(from, tokenId), newFrozen);

        _baseTokenStorage().frozenTokens[from][tokenId] = newFrozen;

        _writeFrozenBalanceCheckpoint(from, tokenId, newFrozen);

        emit TokensFrozen(from, tokenId, amount);
    }

    /**
     * @notice Internally unfreeze a specified amount of tokens for a given address
     * @dev Increases the transferable balance of the `from` address by `amount`, restoring previously frozen tokens.
     * This function should be used to lift restrictions on token transfers, such as after vesting periods or compliance clearance.
     * @param from The address for which tokens will be unfrozen
     * @param tokenId Token Id to unfreeze
     * @param amount The number of tokens to unfreeze
     */
    function _unfreezeTokens(address from, uint256 tokenId, uint256 amount) internal whenNotPaused {
        _validateNonZeroAmount(amount);

        uint256 frozen = _baseTokenStorage().frozenTokens[from][tokenId];
        uint256 newFrozen;

        _validateSufficientBalance(frozen, amount);

        // Safely deduct amount from frozen tokens (validated above)
        unchecked {
            newFrozen = frozen - amount;
        }

        _baseTokenStorage().frozenTokens[from][tokenId] = newFrozen;

        _writeFrozenBalanceCheckpoint(from, tokenId, newFrozen);

        emit TokensUnfrozen(from, tokenId, amount);
    }

    /**
     * @notice Validates that an address has sufficient balance and unfreezes tokens if necessary to meet the requested amount
     * @dev Checks if the `from` address has enough total balance to cover `amount`. If part of the balance is frozen and
     * insufficient free tokens are available, this function will unfreeze the required difference to enable the operation.
     * Calls `_validateSufficientBalance` to ensure the total balance is adequate and `_unfreezeTokens` to release frozen tokens if needed.
     * @param from The address from which the token balance will be validated and potentially unfrozen
     * @param tokenId Token Id to validate and unfreeze
     * @param amount The total amount of tokens required for the operation
     */
    function _validateAndUnfreezeBalance(address from, uint256 tokenId, uint256 amount) internal {
        uint256 balance = balanceOf(from, tokenId);

        _validateSufficientBalance(balance, amount);

        uint256 freeBalance = balance - frozenBalanceOf(from, tokenId);

        if (amount > freeBalance) {
            _unfreezeTokens(from, tokenId, amount - freeBalance);
        }
    }

    /**
     * @notice Writes a frozen-balance checkpoint for an account and token.
     * @dev Uses OpenZeppelin Checkpoints semantics: if multiple writes happen in the same block,
     *      the latest checkpoint for that block is updated instead of creating a duplicate.
     * @param account The account whose frozen balance changed.
     * @param tokenId The token identifier.
     * @param frozenBalance The new frozen balance value to checkpoint.
     */
    function _writeFrozenBalanceCheckpoint(address account, uint256 tokenId, uint256 frozenBalance) internal {
        // slither-disable-next-line unused-return
        _deussTokenStorage()
        .frozenBalanceCkpts[tokenId][account].push(SafeCast.toUint48(block.number), SafeCast.toUint208(frozenBalance));
    }

    /**
     * @notice Reverts if the given address is not an enabled wallet in the EntityRegistry.
     * @param caller The address to check
     */
    function _isCallerWalletEnabled(address caller) internal view {
        require(
            IEntityRegistry(_baseTokenStorage().entityRegistry).isAccountEnabled(caller),
            Errors.Token__CallerNotEnabled(caller)
        );
    }

    /**
     * @inheritdoc BaseToken
     * @notice Updates balances and writes historical balance/supply checkpoints for snapshots.
     * @param from The source account; `address(0)` for mint.
     * @param to The destination account; `address(0)` for burn.
     * @param id The token identifier.
     * @param amount The amount being moved, minted, or burned.
     */
    function _update(address from, address to, uint256 id, uint256 amount) internal override(BaseToken) {
        super._update(from, to, id, amount);

        if (from == to) return;
        uint48 bn = SafeCast.toUint48(block.number);

        if (from == address(0) || to == address(0)) {
            // slither-disable-next-line unused-return
            _deussTokenStorage().supplyCkpts[id].push(bn, SafeCast.toUint208(totalSupply(id)));
        }
        if (from != address(0)) {
            // slither-disable-next-line unused-return
            _deussTokenStorage().balanceCkpts[id][from].push(bn, SafeCast.toUint208(balanceOf(from, id)));
        }
        if (to != address(0)) {
            // slither-disable-next-line unused-return
            _deussTokenStorage().balanceCkpts[id][to].push(bn, SafeCast.toUint208(balanceOf(to, id)));
        }
    }

    /**
     * @notice Reverts when a checkpoint query targets a future block.
     * @param blockNumber The historical block number requested by the caller.
     */
    function _validateCheckpointBlockNumber(uint256 blockNumber) internal view {
        if (blockNumber > block.number) {
            revert Errors.Token__BlockInFuture(block.number, blockNumber);
        }
    }

    /**
     * @notice Reads an account's historical balance for a token at a given block.
     * @param account The account to query.
     * @param tokenId The token identifier.
     * @param blockNumber The block number used for the historical lookup.
     * @return The account balance at or before `blockNumber`.
     */
    function _historicalBalanceOf(address account, uint256 tokenId, uint256 blockNumber)
        internal
        view
        returns (uint256)
    {
        _validateCheckpointBlockNumber(blockNumber);
        return _deussTokenStorage().balanceCkpts[tokenId][account].upperLookupRecent(SafeCast.toUint48(blockNumber));
    }

    /**
     * @notice Reads historical total supply for a token at a given block.
     * @param tokenId The token identifier.
     * @param blockNumber The block number used for the historical lookup.
     * @return The total supply at or before `blockNumber`.
     */
    function _historicalTotalSupplyOf(uint256 tokenId, uint256 blockNumber) internal view returns (uint256) {
        _validateCheckpointBlockNumber(blockNumber);
        return _deussTokenStorage().supplyCkpts[tokenId].upperLookupRecent(SafeCast.toUint48(blockNumber));
    }

    /**
     * @notice Reads an account's historical frozen balance for a token at a given block.
     * @param account The account to query.
     * @param tokenId The token identifier.
     * @param blockNumber The block number used for the historical lookup.
     * @return The frozen balance at or before `blockNumber`.
     */
    function _historicalFrozenBalanceOf(address account, uint256 tokenId, uint256 blockNumber)
        internal
        view
        returns (uint256)
    {
        _validateCheckpointBlockNumber(blockNumber);
        return
            _deussTokenStorage().frozenBalanceCkpts[tokenId][account].upperLookupRecent(SafeCast.toUint48(blockNumber));
    }
}

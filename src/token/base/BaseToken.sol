// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ERC6909TokenSupplyUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC6909/extensions/ERC6909TokenSupplyUpgradeable.sol";
import {ERC6909Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC6909/ERC6909Upgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

// DEUSS:
import {AddressExtensions} from "src/libs/AddressExtensions.sol";
import {BaseTokenStorage} from "../base/BaseTokenStorage.sol";
import {Errors} from "../../libs/Errors.sol";
import {IBaseToken} from "../base/IBaseToken.sol";
import {IBondRegistry} from "../../registry/interfaces/IBondRegistry.sol";
import {IEntityRegistry} from "../../registry/interfaces/IEntityRegistry.sol";
import {OwnableRolesExtension} from "../../utils/OwnableRolesExtension.sol";

/**
 * @title BaseToken
 * @author DEUSS Team
 * @notice This contract provides the foundational functionality for a token
 * @dev Base implementation of a token contract
 */
abstract contract BaseToken is
    IBaseToken,
    BaseTokenStorage,
    OwnableRolesExtension,
    ERC6909TokenSupplyUpgradeable,
    PausableUpgradeable
{
    using AddressExtensions for address;

    /// @notice Role for burning tokens
    uint256 public constant BURNER_ROLE = _ROLE_0;

    /// @notice Role for freezing and unfreezing tokens
    uint256 public constant TOKEN_FREEZER_ROLE = _ROLE_1;

    /// @notice Role for force transferring tokens (Can transfer frozen tokens as well)
    uint256 public constant FORCE_TRANSFER_ROLE = _ROLE_2;

    /// @notice Constant representing all roles (bitmask)
    uint256 public constant ALL_ROLES = BURNER_ROLE | TOKEN_FREEZER_ROLE | FORCE_TRANSFER_ROLE;

    modifier onlyBondRegistry() {
        _onlyBondRegistry();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBaseToken
     */
    function pause() external virtual onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @inheritdoc IBaseToken
     */
    function pauseTokenId(uint256 tokenId) external virtual onlyBondRegistry {
        require(!_baseTokenStorage().pausedTokenIds[tokenId], Errors.Token__TokenIdAlreadyPaused(tokenId));

        _baseTokenStorage().pausedTokenIds[tokenId] = true;

        emit TokenPaused(tokenId, msg.sender);
    }

    /**
     * @inheritdoc IBaseToken
     */
    function unpause() external virtual onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @inheritdoc IBaseToken
     */
    function unpauseTokenId(uint256 tokenId) external virtual onlyBondRegistry whenNotPaused {
        require(_baseTokenStorage().pausedTokenIds[tokenId], Errors.Token__TokenIdNotPaused(tokenId));

        _baseTokenStorage().pausedTokenIds[tokenId] = false;

        emit TokenUnpaused(tokenId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBaseToken
     */
    function bondRegistry() external view virtual returns (IBondRegistry) {
        return IBondRegistry(_baseTokenStorage().bondRegistry);
    }

    /**
     * @inheritdoc IBaseToken
     */
    function entityRegistry() external view virtual returns (IEntityRegistry) {
        return IEntityRegistry(_baseTokenStorage().entityRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBaseToken
     */
    function version() external pure virtual returns (string memory) {
        return TOKEN_VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC6909
     * @dev Follows ERC-6909 set semantics: each successful call overwrites the previous allowance.
     */
    function approve(address spender, uint256 tokenId, uint256 amount)
        public
        virtual
        override(IERC6909, ERC6909Upgradeable)
        whenNotPaused
        returns (bool)
    {
        require(
            IEntityRegistry(_baseTokenStorage().entityRegistry).canApprove(msg.sender, spender, tokenId, amount),
            Errors.Token__ApprovalNotAllowed(msg.sender, spender, tokenId, amount)
        );

        _approve(msg.sender, spender, tokenId, amount);

        return true;
    }

    /**
     * @inheritdoc OwnableRolesExtension
     */
    function grantRoles(address user, uint256 roles) public payable override onlyOwner {
        require(roles & ~(ALL_ROLES) == 0, Errors.InvalidRoles());

        super.grantRoles(user, roles);
    }

    /**
     * @inheritdoc OwnableRolesExtension
     */
    function grantRoles(address[] calldata users, uint256 roles) public payable override onlyOwner {
        require(roles & ~(ALL_ROLES) == 0, Errors.InvalidRoles());

        super.grantRoles(users, roles);
    }

    /**
     * @inheritdoc IBaseToken
     */
    function mint(address to, uint256 tokenId, uint256 amount) public virtual;

    /**
     * @inheritdoc IBaseToken
     */
    function setBondRegistry(address bondRegistryAddr) public virtual onlyOwner {
        bondRegistryAddr.assertAddressNotZero();
        require(_baseTokenStorage().bondRegistry == address(0), Errors.BaseToken__BondRegistryAlreadySet());

        _baseTokenStorage().bondRegistry = bondRegistryAddr;

        emit BondRegistryUpdated(bondRegistryAddr);
    }

    /**
     * @inheritdoc IBaseToken
     */
    function setEntityRegistry(address entityRegistryAddr) public virtual onlyOwner {
        entityRegistryAddr.assertAddressNotZero();
        require(_baseTokenStorage().entityRegistry == address(0), Errors.BaseToken__EntityRegistryAlreadySet());

        _baseTokenStorage().entityRegistry = entityRegistryAddr;

        emit EntityRegistryUpdated(entityRegistryAddr);
    }

    /**
     * @inheritdoc IERC6909
     */
    function setOperator(address spender, bool approved)
        public
        virtual
        override(IERC6909, ERC6909Upgradeable)
        whenNotPaused
        returns (bool)
    {
        return super.setOperator(spender, approved);
    }

    /*//////////////////////////////////////////////////////////////
                       PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IBaseToken
     */
    function frozenBalanceOf(address account, uint256 tokenId) public view returns (uint256) {
        return _baseTokenStorage().frozenTokens[account][tokenId];
    }

    /**
     * @inheritdoc IBaseToken
     */
    function paused() public view virtual override(IBaseToken, PausableUpgradeable) returns (bool) {
        return PausableUpgradeable.paused();
    }

    /**
     * @inheritdoc IBaseToken
     */
    function isTokenPaused(uint256 tokenId) public view virtual returns (bool) {
        return _baseTokenStorage().pausedTokenIds[tokenId];
    }

    /**
     * @inheritdoc ERC6909Upgradeable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC6909Upgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == type(IBaseToken).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check the participants' state in the transfer
     * @param from current tokens holder
     * @param to new tokens holder
     * @param tokenId The identifier of token
     * @param amount The amount of tokens to transfer
     */
    function _beforeTransfer(address from, address to, uint256 tokenId, uint256 amount) internal virtual {
        _validateNonZeroAmount(amount);

        require(!isTokenPaused(tokenId), Errors.Token__TokenIdIsPaused(tokenId));

        require(
            IEntityRegistry(_baseTokenStorage().entityRegistry).canTransfer(from, to, msg.sender, tokenId, amount),
            Errors.Token__TransferNotAllowed(from, to, tokenId)
        );

        _validateSufficientBalance(balanceOf(from, tokenId) - frozenBalanceOf(from, tokenId), amount);

        if (from != msg.sender && !isOperator(from, msg.sender)) {
            _spendAllowance(from, msg.sender, tokenId, amount);
        }
    }

    /**
     * @notice Check privileged transfer state
     * @dev The source may be disabled to support protocol recovery flows from blocked wallets.
     * @param from current tokens holder
     * @param to new tokens holder
     * @param tokenId The identifier of token
     * @param amount The amount of tokens to transfer
     */
    function _beforeRoleTransfer(address from, address to, uint256 tokenId, uint256 amount) internal virtual {
        _validateNonZeroAmount(amount);

        require(
            to == address(0) || IEntityRegistry(_baseTokenStorage().entityRegistry).isAccountEnabled(to),
            Errors.Token__TransferNotAllowed(from, to, tokenId)
        );
    }

    // solhint-disable func-name-mixedcase
    /**
     * @notice Initialize the token contract
     * @param owner_ the address that will own the token contract
     * @param bondRegistry_ The BondRegistry contract address
     * @param entityRegistry_ The EntityRegistry contract address
     */
    function __BaseToken_init(address owner_, address bondRegistry_, address entityRegistry_)
        internal
        onlyInitializing
    {
        _initializeOwner(msg.sender);
        __ERC6909TokenSupply_init();
        __Pausable_init();

        _pause();

        setBondRegistry(bondRegistry_);
        setEntityRegistry(entityRegistry_);

        if (owner_ != address(0) && owner_ != msg.sender) {
            transferOwnership(owner_);
        }
    }

    /**
     * @inheritdoc ERC6909TokenSupplyUpgradeable
     * @notice Overrides the _update function to track total supply changes on minting and burning
     * @param from The address of the sender (Can be address(0) for minting)
     * @param to The address of the receiver (Can be address(0) for burning)
     * @param id The identifier of the token
     * @param amount The amount of tokens to update
     */
    function _update(address from, address to, uint256 id, uint256 amount) internal virtual override whenNotPaused {
        super._update(from, to, id, amount);
    }

    /**
     * @inheritdoc ContextUpgradeable
     * @notice Returns the current caller according to the upgradeable context implementation.
     * @return caller The current caller.
     */
    function _msgSender() internal view virtual override(ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    /**
     * @inheritdoc ContextUpgradeable
     * @notice Returns the calldata payload for the current call according to the upgradeable context implementation.
     * @return data The calldata payload.
     */
    function _msgData() internal view virtual override(ContextUpgradeable) returns (bytes calldata) {
        return ContextUpgradeable._msgData();
    }

    /**
     * @inheritdoc ContextUpgradeable
     * @notice Returns the context suffix length according to the upgradeable context implementation.
     * @return suffixLength The context suffix length.
     */
    function _contextSuffixLength() internal view virtual override(ContextUpgradeable) returns (uint256) {
        return ContextUpgradeable._contextSuffixLength();
    }

    /// @notice Reverts if the caller is not the BondRegistry contract.
    function _onlyBondRegistry() internal view {
        require(msg.sender == _baseTokenStorage().bondRegistry, Errors.Token__CallerNotBondRegistry(msg.sender));
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the lengths of arrays match
     * @param arr1Len array1 length
     * @param arr2Len array2 length
     */
    function _checkArraysLengthsMatch(uint256 arr1Len, uint256 arr2Len) internal pure virtual {
        require(arr1Len == arr2Len, Errors.Token__InvalidArrayLength());
    }

    /**
     * @notice Validates that the given amount is not zero.
     * @dev Reverts with Token__ZeroAmount if the input amount is zero.
     * @param amount The amount to validate.
     */
    function _validateNonZeroAmount(uint256 amount) internal pure {
        require(!(amount == 0), Errors.Token__ZeroAmount());
    }

    /**
     * @notice Validates that a given balance is sufficient to cover a specified amount
     * @dev Reverts with a standardized error if the balance is insufficient.
     * @param balance The current token balance to validate.
     * @param amount The required amount to compare against the balance.
     */
    function _validateSufficientBalance(uint256 balance, uint256 amount) internal pure {
        require(!(amount > balance), Errors.Token__InsufficientBalance());
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {OwnableRolesExtension} from "../utils/OwnableRolesExtension.sol";
import {Errors} from "../libs/Errors.sol";
import {AssetType, Escrow} from "./MarketStructs.sol";
import {EscrowManagerStorage} from "./EscrowManagerStorage.sol";
import {IAssetManager} from "./interfaces/IAssetManager.sol";
import {IEscrowManager} from "./interfaces/IEscrowManager.sol";

/**
 * @title EscrowManager
 * @author DEUSS Team
 * @notice Manages token escrow for marketplace modules through module-type authorization
 * @dev Holds ERC-20 / ERC-721 / ERC-1155 / ERC-6909 balances on behalf of escrows. State-changing entrypoints use
 *      `nonReentrant` where reentrancy via token hooks is a risk. Only `moduleType`-registered authorized modules
 *      may move value; `AssetManager` validates asset kinds before deposit/transfer paths.
 */
contract EscrowManager is
    IEscrowManager,
    EscrowManagerStorage,
    IERC165,
    Initializable,
    OwnableRolesExtension,
    ReentrancyGuard,
    ERC721Holder,
    ERC1155Holder
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice The main admin role
    uint256 public constant ADMIN = _ROLE_0;

    /// @notice Default module type for Marketplace
    bytes32 public constant MARKETPLACE_MODULE = keccak256("MARKETPLACE");

    /// @notice Default module type for OrderbookMarketplace
    bytes32 public constant ORDERBOOK_MARKETPLACE_MODULE = keccak256("ORDERBOOK_MARKETPLACE");

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Locks any future initializations or reinitializations
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract and registers initial marketplace modules
     * @param owner_ Address of the contract owner
     * @param marketplace_ Address of the Marketplace module
     * @param orderbookMarketplace_ Address of the OrderbookMarketplace module
     */
    function initialize(address owner_, address marketplace_, address orderbookMarketplace_) external initializer {
        __EscrowManager_init(owner_, marketplace_, orderbookMarketplace_);
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function registerModule(bytes32 moduleType, address moduleAddress) external onlyRoles(ADMIN) {
        _registerModule(moduleType, moduleAddress);
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function deactivateModule(bytes32 moduleType, address moduleAddress) external onlyRoles(ADMIN) {
        require(moduleType != bytes32(0), Errors.EscrowManager__InvalidModuleType());
        require(moduleAddress != address(0), Errors.EscrowManager__InvalidModuleAddress());

        EscrowManagerState storage $ = _escrowManagerStorage();
        bytes32 currentType = $.moduleTypeOf[moduleAddress];
        require(currentType != bytes32(0), Errors.EscrowManager__ModuleNotRegistered(moduleAddress));
        require(currentType == moduleType, Errors.EscrowManager__ModuleTypeMismatch(currentType, moduleType));
        uint256 activeEscrows = $.activeEscrowsByModule[moduleAddress];
        require(activeEscrows == 0, Errors.EscrowManager__ModuleHasActiveEscrows(moduleAddress, activeEscrows));

        $.isAuthorizedModule[moduleType][moduleAddress] = false;
        delete $.moduleTypeOf[moduleAddress];

        emit ModuleDeactivated(moduleType, moduleAddress);
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function setAssetManager(address assetManager_) external onlyRoles(ADMIN) {
        require(assetManager_ != address(0), Errors.ZeroAddress());
        EscrowManagerState storage $ = _escrowManagerStorage();
        address previousAssetManager = $.assetManager;
        $.assetManager = assetManager_;

        emit AssetManagerSet(previousAssetManager, assetManager_);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc IEscrowManager
     */
    function createEscrow(uint256 amount, address depositor, address tokenAddress, uint256 tokenId)
        external
        nonReentrant
        returns (uint256 escrowId)
    {
        EscrowManagerState storage $ = _escrowManagerStorage();
        bytes32 callerModuleType = _requireAuthorizedCallerModule(msg.sender);

        require(amount != 0, Errors.EscrowManager__ZeroAmount());
        require(depositor != address(0), Errors.EscrowManager__InvalidDepositor());
        require(tokenAddress != address(0), Errors.EscrowManager__InvalidTokenAddress());
        address configuredAssetManager = $.assetManager;
        require(configuredAssetManager != address(0), Errors.EscrowManager__AssetManagerNotSet());

        AssetType assetType = IAssetManager(configuredAssetManager).validateAsset(tokenAddress, tokenId, amount);

        escrowId = ++$.nextEscrowId;

        $.escrows[escrowId] = Escrow({
            depositor: depositor,
            assetType: assetType,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            amount: amount,
            moduleType: callerModuleType,
            moduleAddress: msg.sender
        });
        ++$.activeEscrowsByModule[msg.sender];

        _transferToEscrow(assetType, tokenAddress, depositor, tokenId, amount);

        emit EscrowCreated(escrowId, callerModuleType, depositor, tokenAddress, tokenId, amount, assetType);
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function withdraw(uint256 escrowId, uint256 amount) external nonReentrant {
        Escrow storage escrow = _getAuthorizedEscrow(escrowId, msg.sender);

        address depositor = escrow.depositor;
        _transferFromEscrow(escrow, amount, depositor);

        emit Withdrawn(escrowId, depositor, amount, escrow.tokenAddress, escrow.tokenId, escrow.assetType);
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function claim(uint256 escrowId, uint256 amount, address beneficiary) external nonReentrant {
        Escrow storage escrow = _getAuthorizedEscrow(escrowId, msg.sender);

        _transferFromEscrow(escrow, amount, beneficiary);

        emit Claimed(escrowId, beneficiary, amount, escrow.tokenAddress, escrow.tokenId, escrow.assetType);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN SWEEP
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc IEscrowManager
     */
    function sweep(AssetType assetType, address token, uint256 tokenId, uint256 amount, address beneficiary)
        external
        onlyRoles(ADMIN)
        nonReentrant
    {
        _validateAssetTypeAndTokenId(assetType, tokenId);
        require(amount != 0, Errors.EscrowManager__InvalidSweepAmount());
        require(beneficiary != address(0), Errors.EscrowManager__InvalidBeneficiary());
        if (assetType == AssetType.ERC721) {
            require(amount == 1, Errors.EscrowManager__InvalidERC721Amount(amount));
        }

        uint256 surplus = _sweepableAmount(assetType, token, tokenId);
        require(!(amount > surplus), Errors.EscrowManager__SweepExceedsSurplus(amount, surplus));

        _transferAsset(assetType, token, address(this), beneficiary, tokenId, amount);

        emit Swept(assetType, token, tokenId, beneficiary, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc IEscrowManager
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return _escrowManagerStorage().escrows[escrowId];
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function previewNextEscrowId() external view returns (uint256 escrowId) {
        escrowId = _escrowManagerStorage().nextEscrowId + 1;
    }

    /**
     * @notice Returns escrow details for an escrow ID.
     * @param escrowId Escrow identifier.
     * @return depositor Escrow depositor.
     * @return assetType Escrow asset standard.
     * @return tokenAddress Escrowed token address.
     * @return tokenId Escrowed token identifier.
     * @return amount Current escrowed amount.
     * @return moduleType Module type that created the escrow.
     * @return moduleAddress Module address that created the escrow.
     */
    function escrows(uint256 escrowId)
        public
        view
        returns (
            address depositor,
            AssetType assetType,
            address tokenAddress,
            uint256 tokenId,
            uint256 amount,
            bytes32 moduleType,
            address moduleAddress
        )
    {
        Escrow storage escrow = _escrowManagerStorage().escrows[escrowId];
        return (
            escrow.depositor,
            escrow.assetType,
            escrow.tokenAddress,
            escrow.tokenId,
            escrow.amount,
            escrow.moduleType,
            escrow.moduleAddress
        );
    }

    /**
     * @notice Returns whether `moduleAddress` is authorized for `moduleType`.
     * @param moduleType Module type.
     * @param moduleAddress Module address.
     * @return authorized True when the module address is authorized for the module type.
     */
    function isAuthorizedModule(bytes32 moduleType, address moduleAddress) public view returns (bool authorized) {
        return _escrowManagerStorage().isAuthorizedModule[moduleType][moduleAddress];
    }

    /**
     * @notice Returns the module type assigned to a module address.
     * @param moduleAddress Module address.
     * @return moduleType Registered module type, or zero when the address is not registered.
     */
    function moduleTypeOf(address moduleAddress) public view returns (bytes32 moduleType) {
        return _escrowManagerStorage().moduleTypeOf[moduleAddress];
    }

    /**
     * @notice Returns the latest allocated escrow id.
     * @return escrowId Latest allocated escrow id.
     */
    function nextEscrowId() public view returns (uint256 escrowId) {
        return _escrowManagerStorage().nextEscrowId;
    }

    /**
     * @notice Returns the configured asset manager address.
     * @return assetManager_ Configured AssetManager address.
     */
    function assetManager() public view returns (address assetManager_) {
        return _escrowManagerStorage().assetManager;
    }

    /**
     * @inheritdoc IEscrowManager
     */
    function getSweepableAmount(AssetType assetType, address token, uint256 tokenId)
        external
        view
        returns (uint256 surplus)
    {
        _validateAssetTypeAndTokenId(assetType, tokenId);
        surplus = _sweepableAmount(assetType, token, tokenId);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Holder, IERC165) returns (bool) {
        return interfaceId == type(IEscrowManager).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract and default modules
     * @param owner_ Address of the contract owner
     * @param marketplace_ Address of the Marketplace module
     * @param orderbookMarketplace_ Address of the OrderbookMarketplace module
     */
    // solhint-disable-next-line func-name-mixedcase
    function __EscrowManager_init(address owner_, address marketplace_, address orderbookMarketplace_)
        internal
        onlyInitializing
    {
        _initializeOwner(msg.sender);

        if (marketplace_ != address(0)) {
            _registerModule(MARKETPLACE_MODULE, marketplace_);
        }
        if (orderbookMarketplace_ != address(0)) {
            _registerModule(ORDERBOOK_MARKETPLACE_MODULE, orderbookMarketplace_);
        }

        transferOwnership(owner_);
    }

    /**
     * @notice Registers a module under a module type
     * @param moduleType The module type
     * @param moduleAddress The module address
     */
    function _registerModule(bytes32 moduleType, address moduleAddress) internal {
        require(moduleType != bytes32(0), Errors.EscrowManager__InvalidModuleType());
        require(moduleAddress != address(0), Errors.EscrowManager__InvalidModuleAddress());

        EscrowManagerState storage $ = _escrowManagerStorage();
        bytes32 currentType = $.moduleTypeOf[moduleAddress];
        if (currentType != bytes32(0)) {
            // If the module is already registered to a different type, revert
            require(currentType == moduleType, Errors.EscrowManager__ModuleTypeMismatch(currentType, moduleType));
            // If the module is already registered to the same type, revert
            require(
                !$.isAuthorizedModule[moduleType][moduleAddress],
                Errors.EscrowManager__ModuleAlreadyRegistered(moduleAddress, moduleType)
            );
        }

        $.moduleTypeOf[moduleAddress] = moduleType;
        $.isAuthorizedModule[moduleType][moduleAddress] = true;

        emit ModuleRegistered(moduleType, moduleAddress);
    }

    /**
     * @notice Shared internal logic to move tokens out of escrow and emit the appropriate event
     * @param escrow Authorized escrow storage reference
     * @param amount The amount of tokens to transfer
     * @param recipient The address receiving the tokens
     */
    function _transferFromEscrow(Escrow storage escrow, uint256 amount, address recipient) internal {
        require(amount != 0, Errors.EscrowManager__ZeroAmount());
        require(!(escrow.amount < amount), Errors.EscrowManager__InsufficientBalance());
        require(recipient != address(0), Errors.EscrowManager__InvalidBeneficiary());

        escrow.amount -= amount;
        EscrowManagerState storage $ = _escrowManagerStorage();
        $.reservedByAsset[_assetKey(escrow.assetType, escrow.tokenAddress, escrow.tokenId)] -= amount;
        address moduleAddress = escrow.moduleAddress;
        if (escrow.amount == 0 && moduleAddress != address(0)) {
            --$.activeEscrowsByModule[moduleAddress];
        }

        _transferAsset(escrow.assetType, escrow.tokenAddress, address(this), recipient, escrow.tokenId, amount);
    }

    /**
     * @notice Performs transfer into escrow based on configured asset type
     * @param assetType Asset standard
     * @param token Token contract address
     * @param from Depositor address
     * @param tokenId Token identifier
     * @param amount Transfer amount
     */
    function _transferToEscrow(AssetType assetType, address token, address from, uint256 tokenId, uint256 amount)
        internal
    {
        _escrowManagerStorage().reservedByAsset[_assetKey(assetType, token, tokenId)] += amount;

        uint256 balanceBefore = _balanceHeld(assetType, token, tokenId);
        // False positive: `createEscrow` (sole caller) is `nonReentrant`; the balance-before/after
        // pattern is intentional and cannot be exploited through reentrancy.
        // slither-disable-next-line reentrancy-balance
        _transferAsset(assetType, token, from, address(this), tokenId, amount);
        uint256 received = _balanceHeld(assetType, token, tokenId) - balanceBefore;
        // Intentional: we require the received delta to equal the requested amount exactly,
        // rejecting shortfall (fee-on-transfer).
        require(!(received < amount), Errors.EscrowManager__DepositAmountMismatch());
    }

    /**
     * @notice Performs token transfer for supported asset types
     * @param assetType Asset standard
     * @param token Token contract address
     * @param from Transfer source address
     * @param to Transfer destination address
     * @param tokenId Token identifier
     * @param amount Transfer amount
     */
    function _transferAsset(
        AssetType assetType,
        address token,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        if (assetType == AssetType.ERC20) {
            if (from == address(this)) {
                IERC20(token).safeTransfer(to, amount);
            } else {
                // NOTE:
                // This `from` is intentionally module-supplied (not `msg.sender`) because authorized marketplace
                // modules create escrows on behalf of depositors. Depositors grant allowance to EscrowManager, and
                // modules execute business validation before calling `createEscrow`.
                //
                // Security model: module authorization is a trusted boundary. If an authorized module is compromised
                // or misconfigured, it can abuse existing allowances and pull tokens from arbitrary approved
                // depositors. Governance must only authorize trusted modules and promptly deactivate compromised ones.
                // slither-disable-next-line arbitrary-send-erc20
                IERC20(token).safeTransferFrom(from, to, amount);
            }
            return;
        }

        if (assetType == AssetType.ERC721) {
            require(amount == 1, Errors.EscrowManager__InvalidERC721Amount(amount));
            IERC721(token).safeTransferFrom(from, to, tokenId);
            return;
        }

        if (assetType == AssetType.ERC1155) {
            IERC1155(token).safeTransferFrom(from, to, tokenId, amount, "");
            return;
        }

        if (assetType == AssetType.ERC6909) {
            bool success = IERC6909(token).transferFrom(from, to, tokenId, amount);
            require(success, Errors.EscrowManager__TokensTransferFailed());
            return;
        }

        revert Errors.EscrowManager__InvalidAssetType(uint8(assetType));
    }

    /**
     * @notice Validates caller authorization and returns module type
     * @param moduleAddress Module address to validate
     * @return moduleType Authorized module type
     */
    function _requireAuthorizedCallerModule(address moduleAddress) internal view returns (bytes32 moduleType) {
        moduleType = _escrowManagerStorage().moduleTypeOf[moduleAddress];
        require(moduleType != bytes32(0), Errors.EscrowManager__ModuleNotRegistered(moduleAddress));
        _requireAuthorizedModule(moduleType, moduleAddress);
    }

    /**
     * @notice Returns escrow after validating module authorization
     * @param escrowId Escrow identifier
     * @param moduleAddress Module address to authorize
     * @return escrow Authorized escrow storage reference
     */
    function _getAuthorizedEscrow(uint256 escrowId, address moduleAddress)
        internal
        view
        returns (Escrow storage escrow)
    {
        escrow = _escrowManagerStorage().escrows[escrowId];
        bytes32 moduleType = escrow.moduleType;
        require(moduleType != bytes32(0), Errors.EscrowManager__EscrowNotFound(escrowId));
        _requireAuthorizedModule(moduleType, moduleAddress);
    }

    /**
     * @notice Validates caller authorization for a module type
     * @param moduleType The required module type
     * @param moduleAddress The module address
     */
    function _requireAuthorizedModule(bytes32 moduleType, address moduleAddress) internal view {
        require(
            _escrowManagerStorage().isAuthorizedModule[moduleType][moduleAddress],
            Errors.EscrowManager__ModuleNotAuthorized(moduleAddress, moduleType)
        );
    }

    /**
     * @notice Returns the actual on-chain balance held by this contract for a given asset
     * @param assetType Asset standard
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return balance The current balance held by this contract
     */
    function _balanceHeld(AssetType assetType, address token, uint256 tokenId) internal view returns (uint256 balance) {
        if (assetType == AssetType.ERC20) {
            return IERC20(token).balanceOf(address(this));
        }
        if (assetType == AssetType.ERC721) {
            try IERC721(token).ownerOf(tokenId) returns (address tokenOwner) {
                return tokenOwner == address(this) ? 1 : 0;
            } catch {
                return 0;
            }
        }
        if (assetType == AssetType.ERC1155) {
            return IERC1155(token).balanceOf(address(this), tokenId);
        }
        if (assetType == AssetType.ERC6909) {
            return IERC6909(token).balanceOf(address(this), tokenId);
        }
        revert Errors.EscrowManager__InvalidAssetType(uint8(assetType));
    }

    /**
     * @notice Computes the sweepable surplus for a given asset
     * @param assetType Asset standard
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return surplus The amount of untracked tokens available for sweeping
     */
    function _sweepableAmount(AssetType assetType, address token, uint256 tokenId)
        internal
        view
        returns (uint256 surplus)
    {
        uint256 actual = _balanceHeld(assetType, token, tokenId);
        uint256 reserved = _escrowManagerStorage().reservedByAsset[_assetKey(assetType, token, tokenId)];
        surplus = actual > reserved ? actual - reserved : 0;
    }

    /**
     * @notice Computes a unique key for an asset based on its type, token address, and token ID
     * @param assetType Asset standard
     * @param token Token contract address
     * @param tokenId Token identifier
     * @return key The keccak256 hash representing the asset identity
     */
    function _assetKey(AssetType assetType, address token, uint256 tokenId) internal pure returns (bytes32 key) {
        key = keccak256(abi.encode(assetType, token, tokenId));
    }

    /**
     * @notice Validates asset coordinates for admin/view entrypoints that do not call AssetManager
     * @param assetType Asset standard
     * @param tokenId Token identifier
     */
    function _validateAssetTypeAndTokenId(AssetType assetType, uint256 tokenId) internal pure {
        require(assetType != AssetType.NONE, Errors.EscrowManager__InvalidAssetType(uint8(assetType)));
        require(assetType != AssetType.ERC20 || tokenId == 0, Errors.AssetManager__InvalidTokenId(tokenId));
    }
}

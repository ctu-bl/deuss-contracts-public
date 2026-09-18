// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Errors} from "../libs/Errors.sol";
import {CompanyWalletStorage} from "./CompanyWalletStorage.sol";
import {IPolicyRegistry} from "../registry/interfaces/IPolicyRegistry.sol";
import {ICompanyWallet} from "./ICompanyWallet.sol";

/**
 * @title CompanyWallet
 * @author DEUSS Team
 * @notice Minimal execution wallet with externalized non-owner authorization.
 * @dev Intended for use behind a beacon/proxy: the implementation constructor calls `_disableInitializers()`;
 *      each instance is configured via `initialize`. External calls from `execute` are guarded by `nonReentrant`.
 *      Policy-based authorization is delegated to `IPolicyRegistry`; the owner can always execute.
 */
contract CompanyWallet is
    ICompanyWallet,
    CompanyWalletStorage,
    Ownable,
    ReentrancyGuard,
    Initializable,
    ERC721Holder,
    ERC1155Holder
{
    using ERC165Checker for address;

    /**
     * @notice Prevents implementation initialization.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Accepts plain native currency transfers.
     */
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /**
     * @inheritdoc ICompanyWallet
     */
    function initialize(address owner_, address policyRegistry_) external initializer {
        require(owner_ != address(0), Errors.ZeroAddress());

        _companyWalletStorage().ownershipEpoch = 1;
        _initializeOwner(owner_);
        _setPolicyRegistry(policyRegistry_);
    }

    /**
     * @notice Disabled — ownership of a wallet cannot be renounced.
     */
    function renounceOwnership() public payable override onlyOwner {
        revert Errors.CompanyWallet__RenounceOwnershipDisabled();
    }

    // slither-disable-start arbitrary-send-eth
    /**
     * @inheritdoc ICompanyWallet
     */
    function execute(address target, uint256 value, bytes calldata data) external payable nonReentrant {
        require(
            target != address(0) && target != address(this) && target.code.length != 0,
            Errors.CompanyWallet__InvalidCallTarget()
        );
        require(msg.value == 0 || msg.value == value, Errors.CompanyWallet__MsgValueMismatch());
        require(data.length > 3, Errors.CompanyWallet__InvalidCallData());

        address sender = msg.sender;
        require(
            sender == owner()
                || IPolicyRegistry(_companyWalletStorage().policyRegistry)
                    .canExecute(address(this), sender, target, value, data),
            Errors.CompanyWallet__Unauthorized()
        );

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        bytes memory verifiedReturnData = Address.verifyCallResult(success, returnData);

        emit Execution(sender, target, value, data, verifiedReturnData);
    }

    // slither-disable-end arbitrary-send-eth

    /**
     * @inheritdoc ICompanyWallet
     */
    function setPolicyRegistry(address policyRegistry_) external onlyOwner {
        _setPolicyRegistry(policyRegistry_);
    }

    /**
     * @inheritdoc ICompanyWallet
     */
    function advancePolicyEpoch(bytes32 reason) external onlyOwner {
        require(reason != bytes32(0), Errors.CompanyWallet__ZeroPolicyEpochReason());

        _advanceOwnershipEpoch(reason);
    }

    /**
     * @inheritdoc ICompanyWallet
     */
    function policyRegistry() external view returns (address registry) {
        return _companyWalletStorage().policyRegistry;
    }

    /**
     * @inheritdoc ICompanyWallet
     */
    function ownershipEpoch() external view returns (uint256 epoch) {
        return _companyWalletStorage().ownershipEpoch;
    }

    /**
     * @inheritdoc ICompanyWallet
     */
    function owner() public view override(ICompanyWallet, Ownable) returns (address walletOwner) {
        return Ownable.owner();
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Holder, IERC165) returns (bool) {
        return interfaceId == type(ICompanyWallet).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Advances the ownership epoch before delegating to the parent owner update.
     *         Called by transferOwnership and completeOwnershipHandover (all paths).
     * @param newOwner Incoming owner address.
     */
    function _setOwner(address newOwner) internal override {
        require(newOwner != owner(), Errors.CompanyWallet__OwnerTransferToSelf());

        _advanceOwnershipEpoch(bytes32(0));
        super._setOwner(newOwner);
    }

    /**
     * @notice Advances the wallet epoch used to scope policy registry state.
     * @param reason Opaque reason code; zero for ordinary ownership transfers.
     * @return previousEpoch Epoch before the advance.
     * @return nextEpoch Epoch after the advance.
     */
    function _advanceOwnershipEpoch(bytes32 reason) internal returns (uint256 previousEpoch, uint256 nextEpoch) {
        CompanyWalletState storage $ = _companyWalletStorage();
        previousEpoch = $.ownershipEpoch;
        nextEpoch = previousEpoch + 1;
        $.ownershipEpoch = nextEpoch;
        emit OwnershipEpochAdvanced(previousEpoch, nextEpoch, reason, msg.sender);
    }

    /**
     * @notice Stores the policy registry after validation.
     * @param policyRegistry_ Policy registry address.
     */
    function _setPolicyRegistry(address policyRegistry_) internal {
        require(
            policyRegistry_ != address(0) && policyRegistry_.code.length != 0,
            Errors.CompanyWallet__InvalidPolicyRegistry(policyRegistry_)
        );
        require(
            policyRegistry_.supportsInterface(type(IPolicyRegistry).interfaceId),
            Errors.CompanyWallet__UnsupportedPolicyRegistry(policyRegistry_)
        );

        CompanyWalletState storage $ = _companyWalletStorage();
        address previousPolicyRegistry = $.policyRegistry;
        $.policyRegistry = policyRegistry_;

        emit PolicyRegistryUpdated(previousPolicyRegistry, policyRegistry_);
    }
}

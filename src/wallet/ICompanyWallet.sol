// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ICompanyWallet
 * @author DEUSS Team
 * @notice Minimal execution wallet with externalized authorization.
 */
interface ICompanyWallet is IERC165 {
    /**
     * @notice Emitted when the wallet receives native currency directly.
     * @param sender Native currency sender.
     * @param amount Received amount.
     */
    event NativeReceived(address indexed sender, uint256 amount); // solhint-disable-line gas-indexed-events

    /**
     * @notice Emitted when the policy registry is updated.
     * @param previousPolicyRegistry Previous policy registry.
     * @param newPolicyRegistry New policy registry.
     */
    event PolicyRegistryUpdated(address indexed previousPolicyRegistry, address indexed newPolicyRegistry);

    /**
     * @notice Emitted when the ownership epoch is advanced.
     * @param previousEpoch Epoch before the advance.
     * @param newEpoch Epoch after the advance.
     * @param reason Opaque reason code; zero for ordinary ownership transfers.
     * @param caller Caller that triggered the epoch advance.
     */
    event OwnershipEpochAdvanced(
        uint256 indexed previousEpoch, uint256 indexed newEpoch, bytes32 indexed reason, address caller
    );

    /**
     * @notice Emitted when a wallet call is executed.
     * @param caller Transaction sender that initiated execution.
     * @param target Call target.
     * @param value Native value forwarded with the call.
     * @param data Call data.
     * @param returnData Returned data from the target call.
     */
    event Execution(address indexed caller, address indexed target, uint256 value, bytes data, bytes returnData); // solhint-disable-line gas-indexed-events

    /**
     * @notice Initializes the wallet owner and policy registry.
     * @param owner_ Wallet owner.
     * @param policyRegistry_ Policy registry for non-owner authorization.
     */
    function initialize(address owner_, address policyRegistry_) external;

    /**
     * @notice Executes a call from the wallet.
     * @param target Call target (must be a contract, not this wallet).
     * @param value Native value forwarded with the call (`msg.value` must match when non-zero).
     * @param data Encoded call data; must include at least a 4-byte function selector.
     */
    function execute(address target, uint256 value, bytes calldata data) external payable;

    /**
     * @notice Updates the wallet policy registry.
     * @param policyRegistry_ New policy registry.
     */
    function setPolicyRegistry(address policyRegistry_) external;

    /**
     * @notice Advances the policy epoch without changing the wallet owner.
     * @dev Invalidates all wallet-local policy state keyed by the previous epoch in PolicyRegistry.
     * @param reason Non-zero opaque reason code for auditability.
     */
    function advancePolicyEpoch(bytes32 reason) external;

    /**
     * @notice Returns the configured policy registry.
     * @return registry Policy registry address.
     */
    function policyRegistry() external view returns (address registry);

    /**
     * @notice Returns the wallet owner.
     * @return walletOwner Wallet owner.
     */
    function owner() external view returns (address walletOwner);

    /**
     * @notice Returns the current ownership epoch.
     *         Starts at 1 for newly initialized wallets and increments on every ownership transfer or
     *         manual policy epoch advance.
     *         PolicyRegistry uses this value to scope wallet-local policy state so that old
     *         delegated permissions are automatically invalidated after an epoch advance.
     * @return epoch Current ownership epoch.
     */
    function ownershipEpoch() external view returns (uint256 epoch);
}

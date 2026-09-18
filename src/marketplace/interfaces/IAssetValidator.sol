// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

/**
 * @title IAssetValidator
 * @author DEUSS Team
 * @notice Optional per-token validation hook invoked by AssetManager.validateAsset.
 *         Implementations MUST revert when the asset is not valid for the requested marketplace flow.
 */
interface IAssetValidator {
    /**
     * @notice Reverts when the asset is invalid for the requested transfer.
     * @param token Asset token contract.
     * @param tokenId Asset token identifier.
     * @param amount Transfer amount.
     */
    function validate(address token, uint256 tokenId, uint256 amount) external view;
}

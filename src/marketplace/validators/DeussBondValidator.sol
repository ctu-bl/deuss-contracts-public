// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IAssetValidator} from "../interfaces/IAssetValidator.sol";
import {IBondRegistry} from "../../registry/interfaces/IBondRegistry.sol";
import {Bond, BondStatus} from "../../registry/BondStructs.sol";
import {Errors} from "../../libs/Errors.sol";

/**
 * @title DeussBondValidator
 * @author DEUSS Team
 * @notice IAssetValidator that allows trading iff the bond's status is Issued or Replaced.
 *         Reads live status from IBondRegistry; the `token` argument is validated against the bond's recorded
 *         token contract before status is checked.
 */
contract DeussBondValidator is IAssetValidator {
    /// @notice DEUSS bond registry contract
    IBondRegistry public immutable bondRegistry;

    constructor(address bondRegistry_) {
        require(bondRegistry_ != address(0), Errors.ZeroAddress());
        bondRegistry = IBondRegistry(bondRegistry_);
    }

    /// @inheritdoc IAssetValidator
    function validate(
        address token,
        uint256 tokenId,
        uint256 /*amount*/
    )
        external
        view
    {
        Bond memory bond = bondRegistry.getBondByTokenId(tokenId);

        require(bond.tokenAddress == token, Errors.DeussBondValidator__TokenMismatch(token, bond.tokenAddress));
        require(
            bond.status == BondStatus.Issued || bond.status == BondStatus.Replaced,
            Errors.DeussBondValidator__NotTradable(tokenId, uint8(bond.status))
        );
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {IBondMetadataAdapter} from "./interfaces/IBondMetadataAdapter.sol";
import {IBondRegistry} from "../../registry/interfaces/IBondRegistry.sol";
import {Bond} from "../../registry/BondStructs.sol";
import {Errors} from "../../libs/Errors.sol";

/**
 * @title DeussBondMetadataAdapter
 * @author DEUSS Team
 * @notice Metadata adapter that reads bond records from the DEUSS BondRegistry.
 *         Thin proxy over IBondRegistry.getBondByTokenId / getCurrentCouponRateForBond.
 *         The `token` argument is validated against the registry's single token contract before forwarding `tokenId`.
 */
contract DeussBondMetadataAdapter is IBondMetadataAdapter {
    /// @notice DEUSS bond registry contract
    IBondRegistry public immutable bondRegistry;

    constructor(address bondRegistry_) {
        require(bondRegistry_ != address(0), Errors.ZeroAddress());
        bondRegistry = IBondRegistry(bondRegistry_);
    }

    /// @inheritdoc IBondMetadataAdapter
    function getBond(address token, uint256 tokenId) external view returns (Bond memory bond) {
        require(token == bondRegistry.getToken(), Errors.BondRegistry__NonExistentBond(bytes12(0)));
        bond = bondRegistry.getBondByTokenId(tokenId);
    }

    /// @inheritdoc IBondMetadataAdapter
    function getCurrentCouponRate(Bond calldata bond) external view returns (uint256 rate) {
        rate = bondRegistry.getCurrentCouponRateForBond(bond);
    }
}

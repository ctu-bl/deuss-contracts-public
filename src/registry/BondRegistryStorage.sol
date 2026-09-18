// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Bond, Scoring, Tranche} from "./BondStructs.sol";

/**
 * @title BondRegistryStorage
 * @author DEUSS Team
 * @notice This contract defines the storage layout for the BondRegistry
 * @dev It is used to store the basic information of the bond registry
 */
abstract contract BondRegistryStorage {
    /**
     * @notice Bond, tranche, scoring, and shared-token registry storage.
     * @custom:storage-location erc7201:deuss.bondRegistry.storage
     */
    struct BondRegistryState {
        /// @notice shared ERC6909 token contract where all bond tokens are minted with unique token IDs
        address token;
        /// @notice prevents changing the shared token contract
        bool multiTokenLocked;
        /// @notice maps ISIN and version to bond data
        mapping(bytes12 isin => mapping(uint8 version => Bond bond)) bonds;
        /// @notice maps ISIN + version + trancheId to tranche data
        mapping(bytes12 isin => mapping(uint8 version => mapping(uint16 trancheId => Tranche tranche))) tranches;
        /// @notice tracks which 3-letter currency codes (ISO 4217) are allowed for bond issuance
        mapping(bytes3 currency => bool allowed) allowedCurrencies;
        /// @notice maps ISIN to latest created version number (highest version ever published)
        mapping(bytes12 isin => uint8 latestVersion) isinToLatestVersion;
        /// @notice maps ISIN to the active version (issuer-designated current series for ISIN-only reads)
        mapping(bytes12 isin => uint8 activeVersion) isinToActiveVersion;
        /// @notice reverse lookup from tokenId to ISIN for token-centric integrations
        mapping(uint256 tokenId => bytes12 isin) tokenIdToIsin;
        /// @notice reverse lookup from tokenId to version for token-centric integrations
        mapping(uint256 tokenId => uint8 version) tokenIdToVersion;
        /// @notice maps issuer wallet address to the number of scoring records appended
        mapping(address wallet => uint256 scoringCount) scoringCount;
        /// @notice maps issuer wallet address and 1-based scoring ID to scoring data
        mapping(address wallet => mapping(uint256 scoringId => Scoring scoring)) scorings;
    }

    /**
     * @notice ERC-7201 storage location for BondRegistry state.
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("deuss.bondRegistry.storage"))) - 1))
     *      & ~bytes32(uint256(0xff))
     */
    // slither-disable-next-line unused-state
    bytes32 internal constant _BOND_REGISTRY_STORAGE_LOCATION =
        0xf05f5cf5695160f1ef171461a32473c19258f33f48be4d0d6fc8cab4126ef500;

    /**
     * @notice Returns BondRegistry namespaced storage.
     * @return $ Namespaced storage pointer.
     */
    // slither-disable-next-line uninitialized-storage,assembly
    function _bondRegistryStorage() internal pure returns (BondRegistryState storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _BOND_REGISTRY_STORAGE_LOCATION
        }
    }
}

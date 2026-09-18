// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Initializable} from "solady/src/utils/Initializable.sol";
import {OwnableRolesExtension} from "../../utils/OwnableRolesExtension.sol";
import {Errors} from "../../libs/Errors.sol";
import {IMarketFilter} from "../interfaces/IMarketFilter.sol";
import {IBondMetadataAdapter} from "./interfaces/IBondMetadataAdapter.sol";
import {Bond, BondStatus, CouponRateType} from "../../registry/BondStructs.sol";

/**
 * @title BondMarketFilter
 * @author DEUSS Team
 * @notice IMarketFilter implementation that evaluates caller-supplied BondFilter payloads against bond metadata.
 *         Supports multiple issuers via a per-token metadata adapter mapping; unknown tokens silently evaluate to
 *         false so the caller (OrderbookMarketplace) can skip non-bond markets without reverting.
 */
contract BondMarketFilter is IMarketFilter, Initializable, OwnableRolesExtension {
    /**
     * @notice Filter over bond metadata used by batch-order callers to select candidate markets
     * @param maturityFrom Inclusive lower bound on bond.maturityDate (0 = no lower bound)
     * @param maturityTo Inclusive upper bound on bond.maturityDate (0 = no upper bound)
     * @param currencyWhitelist If non-empty, bond.currency must be in the list
     * @param currencyBlacklist If non-empty and bond.currency is in the list, reject
     * @param couponRateFrom Inclusive lower bound on current coupon rate
     * @param couponRateTo Inclusive upper bound on current coupon rate (0 = no upper bound)
     * @param couponRateTypes If non-empty, bond.couponRateType must be in the list
     * @param issuerWhitelist If non-empty, bond.issuer must be in the list
     * @param issuerBlacklist If non-empty and bond.issuer is in the list, reject
     * @param bondNominalValueFrom Inclusive lower bound on bond.bondNominalValue (0 = no lower bound)
     * @param bondNominalValueTo Inclusive upper bound on bond.bondNominalValue (0 = no upper bound)
     */
    struct BondFilter {
        uint256 maturityFrom;
        uint256 maturityTo;
        bytes3[] currencyWhitelist;
        bytes3[] currencyBlacklist;
        uint256 couponRateFrom;
        uint256 couponRateTo;
        CouponRateType[] couponRateTypes;
        address[] issuerWhitelist;
        address[] issuerBlacklist;
        uint256 bondNominalValueFrom;
        uint256 bondNominalValueTo;
    }

    /// @notice Admin role for configuration updates
    uint256 public constant ADMIN = _ROLE_0;

    /// @notice Per-token metadata adapter; address(0) means the token is not recognized as a bond
    mapping(address token => IBondMetadataAdapter adapter) internal _adapters;

    /**
     * @notice Emitted when the metadata adapter for a token is set or cleared
     * @param token Token contract address
     * @param adapter Metadata adapter address
     */
    event AdapterSet(address indexed token, address indexed adapter);

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract owner
     * @param owner_ Owner address
     */
    function initialize(address owner_) external initializer {
        require(owner_ != address(0), Errors.ZeroAddress());
        _initializeOwner(owner_);
    }

    /**
     * @notice Registers or clears the metadata adapter for a token
     * @param token Token contract address
     * @param adapter_ Metadata adapter address
     */
    function setAdapter(address token, address adapter_) external onlyRoles(ADMIN) {
        require(token != address(0), Errors.ZeroAddress());
        _adapters[token] = IBondMetadataAdapter(adapter_);
        emit AdapterSet(token, adapter_);
    }

    /**
     * @notice Returns the metadata adapter currently configured for a token
     * @param token Token contract address
     * @return adapter Adapter address
     */
    function adapter(address token) external view returns (address) {
        return address(_adapters[token]);
    }

    /**
     * @inheritdoc IMarketFilter
     * @dev filterData MUST ABI-decode to BondFilter. Invalid ABI causes revert (caller bug, fail loud).
     *      Invalid range bounds (e.g. maturityFrom > maturityTo) revert.
     *      Unknown tokens (no adapter) return false. Adapter reverts (e.g. non-bond tokenId) yield false.
     *      Bonds not in Issued status return false.
     */
    function matchesFilter(address token, uint256 tokenId, bytes calldata filterData) external view returns (bool) {
        IBondMetadataAdapter adapter_ = _adapters[token];
        if (address(adapter_) == address(0)) return false;

        BondFilter memory filter = abi.decode(filterData, (BondFilter));
        _validateFilterRanges(filter);

        Bond memory bond;
        try adapter_.getBond(token, tokenId) returns (Bond memory b) {
            bond = b;
        } catch {
            return false;
        }

        if (bond.status != BondStatus.Issued) return false;

        if (filter.maturityFrom != 0 && bond.maturityDate < filter.maturityFrom) return false;
        if (filter.maturityTo != 0 && bond.maturityDate > filter.maturityTo) return false;

        if (filter.bondNominalValueFrom != 0 && bond.bondNominalValue < filter.bondNominalValueFrom) return false;
        if (filter.bondNominalValueTo != 0 && bond.bondNominalValue > filter.bondNominalValueTo) return false;

        if (!_bytes3InList(filter.currencyWhitelist, bond.currency, true)) return false;
        if (_bytes3InList(filter.currencyBlacklist, bond.currency, false)) return false;

        if (!_addressInList(filter.issuerWhitelist, bond.issuer, true)) return false;
        if (_addressInList(filter.issuerBlacklist, bond.issuer, false)) return false;

        if (filter.couponRateTypes.length != 0) {
            bool found;
            for (uint256 i; i < filter.couponRateTypes.length; ++i) {
                if (filter.couponRateTypes[i] == bond.couponRateType) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        if (filter.couponRateFrom != 0 || filter.couponRateTo != 0) {
            uint256 rate = adapter_.getCurrentCouponRate(bond);
            if (rate < filter.couponRateFrom) return false;
            if (filter.couponRateTo != 0 && rate > filter.couponRateTo) return false;
        }

        return true;
    }

    /**
     * @notice Convenience encoder for callers that want to build BondFilter payloads from Solidity tests/scripts
     * @param filter Bond filter payload to ABI-encode
     * @return ABI-encoded bond filter payload
     * @dev Pure helper; ABI-encodes the struct identically to abi.encode(filter)
     */
    function encodeFilter(BondFilter calldata filter) external pure returns (bytes memory) {
        return abi.encode(filter);
    }

    /**
     * @dev Validates range bounds. Reverts on inverted ranges on bounded sides.
     */
    function _validateFilterRanges(BondFilter memory f) private pure {
        if (f.maturityFrom != 0 && f.maturityTo != 0 && f.maturityFrom > f.maturityTo) {
            revert Errors.BondMarketFilter__InvalidFilterRange();
        }
        if (f.couponRateTo != 0 && f.couponRateFrom > f.couponRateTo) {
            revert Errors.BondMarketFilter__InvalidFilterRange();
        }
        if (f.bondNominalValueFrom != 0 && f.bondNominalValueTo != 0 && f.bondNominalValueFrom > f.bondNominalValueTo) {
            revert Errors.BondMarketFilter__InvalidFilterRange();
        }
    }

    /**
     * @dev Whitelist/blacklist helper for bytes3 lists; empty list + whitelistMode returns true
     */
    function _bytes3InList(bytes3[] memory list, bytes3 value, bool whitelistMode) private pure returns (bool) {
        if (list.length == 0) return whitelistMode;
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == value) return true;
        }
        return false;
    }

    /**
     * @dev Whitelist/blacklist helper for address lists; empty list + whitelistMode returns true
     */
    function _addressInList(address[] memory list, address value, bool whitelistMode) private pure returns (bool) {
        if (list.length == 0) return whitelistMode;
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == value) return true;
        }
        return false;
    }
}

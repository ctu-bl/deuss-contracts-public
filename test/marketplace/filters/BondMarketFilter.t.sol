// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {BondMarketFilter} from "src/marketplace/filters/BondMarketFilter.sol";
import {IBondMetadataAdapter} from "src/marketplace/filters/interfaces/IBondMetadataAdapter.sol";
import {Bond, BondStatus, CouponRateType, CouponFrequency, CouponRates} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";

contract StubBondAdapter is IBondMetadataAdapter {
    mapping(address token => mapping(uint256 tokenId => Bond)) internal _bonds;
    mapping(address token => mapping(uint256 tokenId => bool)) internal _registered;
    mapping(bytes12 isin => uint256 rate) internal _rates;

    error UnknownBond();

    function setBond(address token, uint256 tokenId, Bond calldata bond) external {
        _bonds[token][tokenId] = bond;
        _registered[token][tokenId] = true;
    }

    function setCurrentRate(bytes12 isin, uint256 rate) external {
        _rates[isin] = rate;
    }

    function getBond(address token, uint256 tokenId) external view returns (Bond memory) {
        if (!_registered[token][tokenId]) {
            revert UnknownBond();
        }
        return _bonds[token][tokenId];
    }

    function getCurrentCouponRate(Bond calldata bond) external view returns (uint256) {
        return _rates[bond.isin];
    }
}

contract BondMarketFilterTest is Test {
    BondMarketFilter internal _filter;
    UpgradeableBeacon internal _beacon;
    StubBondAdapter internal _adapter;

    address internal _owner;
    address internal _admin;
    address internal _outsider;
    address internal _bondToken;
    address internal _otherToken;

    function setUp() public {
        _owner = makeAddr("owner");
        _admin = makeAddr("admin");
        _outsider = makeAddr("outsider");
        _bondToken = makeAddr("bondToken");
        _otherToken = makeAddr("otherToken");

        _adapter = new StubBondAdapter();
        (_filter, _beacon) = _deployFilter(_owner);

        uint256 adminRole = _filter.ADMIN();
        vm.prank(_filter.owner());
        _filter.grantRoles(_admin, adminRole);

        vm.prank(_admin);
        _filter.setAdapter(_bondToken, address(_adapter));
    }

    function _deployFilter(address owner_) internal returns (BondMarketFilter, UpgradeableBeacon) {
        BondMarketFilter impl = new BondMarketFilter();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner_);
        BeaconProxy proxy =
            new BeaconProxy(address(beacon), abi.encodeWithSelector(BondMarketFilter.initialize.selector, owner_));
        return (BondMarketFilter(address(proxy)), beacon);
    }

    function _bond(bytes12 isin, BondStatus status) internal pure returns (Bond memory bond) {
        bond.isin = isin;
        bond.status = status;
        bond.currency = bytes3("EUR");
        bond.issuer = address(0xAA);
        bond.maturityDate = 2000;
        bond.bondNominalValue = 1000;
        bond.couponRateType = CouponRateType.FIXED;
        bond.couponFrequency = CouponFrequency.Annual;
        bond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});
    }

    function _emptyFilter() internal pure returns (BondMarketFilter.BondFilter memory f) {
        f.currencyWhitelist = new bytes3[](0);
        f.currencyBlacklist = new bytes3[](0);
        f.couponRateTypes = new CouponRateType[](0);
        f.issuerWhitelist = new address[](0);
        f.issuerBlacklist = new address[](0);
    }

    function _encode(BondMarketFilter.BondFilter memory f) internal pure returns (bytes memory) {
        return abi.encode(f);
    }

    /*//////////////////////////////////////////////////////////////
                             initialize
    //////////////////////////////////////////////////////////////*/
    function test_initialize_setsOwner() public view {
        assertEq(_filter.owner(), _owner);
    }

    function test_initialize_reverts_reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _filter.initialize(_owner);
    }

    function test_initialize_reverts_zeroOwner() public {
        BondMarketFilter impl = new BondMarketFilter();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), _owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        new BeaconProxy(address(beacon), abi.encodeWithSelector(BondMarketFilter.initialize.selector, address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                             setAdapter
    //////////////////////////////////////////////////////////////*/
    function test_setAdapter_admin_setsAddressAndEmits() public {
        vm.expectEmit();
        emit BondMarketFilter.AdapterSet(_otherToken, address(_adapter));

        vm.prank(_admin);
        _filter.setAdapter(_otherToken, address(_adapter));

        assertEq(_filter.adapter(_otherToken), address(_adapter));
    }

    function test_setAdapter_admin_canClear() public {
        vm.prank(_admin);
        _filter.setAdapter(_bondToken, address(0));
        assertEq(_filter.adapter(_bondToken), address(0));
    }

    function test_setAdapter_nonAdmin_reverts() public {
        vm.prank(_outsider);
        vm.expectRevert();
        _filter.setAdapter(_otherToken, address(_adapter));
    }

    function test_setAdapter_zeroToken_reverts() public {
        vm.prank(_admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _filter.setAdapter(address(0), address(_adapter));
    }

    /*//////////////////////////////////////////////////////////////
                           matchesFilter
    //////////////////////////////////////////////////////////////*/
    function test_matchesFilter_returnsFalse_forUnknownToken() public view {
        assertFalse(_filter.matchesFilter(_otherToken, 1, _encode(_emptyFilter())));
    }

    function test_matchesFilter_returnsFalse_whenAdapterReverts() public view {
        // token known (bondToken), but tokenId not registered → adapter reverts → false
        assertFalse(_filter.matchesFilter(_bondToken, 999, _encode(_emptyFilter())));
    }

    function test_matchesFilter_returnsFalse_forNonIssuedBond() public {
        Bond memory b = _bond(bytes12("BOND001"), BondStatus.Suspended);
        _adapter.setBond(_bondToken, 1, b);

        assertFalse(_filter.matchesFilter(_bondToken, 1, _encode(_emptyFilter())));
    }

    function test_matchesFilter_returnsTrue_forIssuedBond_emptyFilter() public {
        Bond memory b = _bond(bytes12("BOND002"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 2, b);

        assertTrue(_filter.matchesFilter(_bondToken, 2, _encode(_emptyFilter())));
    }

    function test_matchesFilter_maturityBelowLowerBound() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.maturityDate = 1500;
        _adapter.setBond(_bondToken, 3, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.maturityFrom = 2000;
        assertFalse(_filter.matchesFilter(_bondToken, 3, _encode(f)));
    }

    function test_matchesFilter_maturityAboveUpperBound() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.maturityDate = 2500;
        _adapter.setBond(_bondToken, 4, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.maturityTo = 2000;
        assertFalse(_filter.matchesFilter(_bondToken, 4, _encode(f)));
    }

    function test_matchesFilter_bondNominalValueOutOfRange() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.bondNominalValue = 500;
        _adapter.setBond(_bondToken, 5, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.bondNominalValueFrom = 1000;
        assertFalse(_filter.matchesFilter(_bondToken, 5, _encode(f)));
    }

    function test_matchesFilter_currencyWhitelistMiss() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.currency = bytes3("USD");
        _adapter.setBond(_bondToken, 6, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.currencyWhitelist = new bytes3[](1);
        f.currencyWhitelist[0] = bytes3("EUR");
        assertFalse(_filter.matchesFilter(_bondToken, 6, _encode(f)));
    }

    function test_matchesFilter_currencyBlacklistHit() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.currency = bytes3("USD");
        _adapter.setBond(_bondToken, 7, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.currencyBlacklist = new bytes3[](1);
        f.currencyBlacklist[0] = bytes3("USD");
        assertFalse(_filter.matchesFilter(_bondToken, 7, _encode(f)));
    }

    function test_matchesFilter_issuerWhitelistMiss() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.issuer = address(0xBB);
        _adapter.setBond(_bondToken, 8, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.issuerWhitelist = new address[](1);
        f.issuerWhitelist[0] = address(0xAA);
        assertFalse(_filter.matchesFilter(_bondToken, 8, _encode(f)));
    }

    function test_matchesFilter_issuerBlacklistHit() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.issuer = address(0xBB);
        _adapter.setBond(_bondToken, 9, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.issuerBlacklist = new address[](1);
        f.issuerBlacklist[0] = address(0xBB);
        assertFalse(_filter.matchesFilter(_bondToken, 9, _encode(f)));
    }

    function test_matchesFilter_couponRateTypeMismatch() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        b.couponRateType = CouponRateType.FIXED;
        _adapter.setBond(_bondToken, 10, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.couponRateTypes = new CouponRateType[](1);
        f.couponRateTypes[0] = CouponRateType.FLOATING;
        assertFalse(_filter.matchesFilter(_bondToken, 10, _encode(f)));
    }

    function test_matchesFilter_couponRateBelowLowerBound() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 11, b);
        _adapter.setCurrentRate(b.isin, 300);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.couponRateFrom = 500;
        assertFalse(_filter.matchesFilter(_bondToken, 11, _encode(f)));
    }

    function test_matchesFilter_couponRateAboveUpperBound() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 12, b);
        _adapter.setCurrentRate(b.isin, 900);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.couponRateTo = 500;
        assertFalse(_filter.matchesFilter(_bondToken, 12, _encode(f)));
    }

    function test_matchesFilter_couponRateCheckSkipped_whenBothBoundsZero() public {
        // adapter.setCurrentRate NOT called — assert the coupon check is skipped entirely (no revert on unset rate).
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 13, b);

        assertTrue(_filter.matchesFilter(_bondToken, 13, _encode(_emptyFilter())));
    }

    function test_matchesFilter_reverts_onInvertedMaturityRange() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 20, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.maturityFrom = 3000;
        f.maturityTo = 2000;
        vm.expectRevert(Errors.BondMarketFilter__InvalidFilterRange.selector);
        _filter.matchesFilter(_bondToken, 20, _encode(f));
    }

    function test_matchesFilter_reverts_onInvertedCouponRateRange() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 21, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.couponRateFrom = 1000;
        f.couponRateTo = 500;
        vm.expectRevert(Errors.BondMarketFilter__InvalidFilterRange.selector);
        _filter.matchesFilter(_bondToken, 21, _encode(f));
    }

    function test_matchesFilter_reverts_onInvertedBondNominalValueRange() public {
        Bond memory b = _bond(bytes12("BD"), BondStatus.Issued);
        _adapter.setBond(_bondToken, 22, b);

        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.bondNominalValueFrom = 2000;
        f.bondNominalValueTo = 1000;
        vm.expectRevert(Errors.BondMarketFilter__InvalidFilterRange.selector);
        _filter.matchesFilter(_bondToken, 22, _encode(f));
    }

    /*//////////////////////////////////////////////////////////////
                            encodeFilter
    //////////////////////////////////////////////////////////////*/
    function test_encodeFilter_matchesAbiEncode() public view {
        BondMarketFilter.BondFilter memory f = _emptyFilter();
        f.maturityFrom = 1234;
        assertEq(_filter.encodeFilter(f), abi.encode(f));
    }
}

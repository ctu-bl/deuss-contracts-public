// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DeussBondMetadataAdapter} from "src/marketplace/filters/DeussBondMetadataAdapter.sol";
import {Bond, BondStatus, CouponRateType, CouponFrequency, CouponRates} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";

contract StubBondRegistryForAdapter {
    mapping(uint256 tokenId => Bond bond) internal _bonds;
    mapping(uint256 tokenId => bool registered) internal _registered;
    mapping(bytes12 isin => uint256 rate) internal _rates;
    address internal _token;

    error NonBond();

    function setToken(address token) external {
        _token = token;
    }

    function setBond(uint256 tokenId, Bond calldata bond) external {
        _bonds[tokenId] = bond;
        _registered[tokenId] = true;
    }

    function setCurrentRate(bytes12 isin, uint256 rate) external {
        _rates[isin] = rate;
    }

    function getToken() external view returns (address) {
        return _token;
    }

    function getBondByTokenId(uint256 tokenId) external view returns (Bond memory) {
        if (!_registered[tokenId]) {
            revert NonBond();
        }
        return _bonds[tokenId];
    }

    function getCurrentCouponRateForBond(Bond calldata bond) external view returns (uint256) {
        return _rates[bond.isin];
    }
}

contract DeussBondMetadataAdapterTest is Test {
    DeussBondMetadataAdapter internal _adapter;
    StubBondRegistryForAdapter internal _registry;
    address internal _token;

    function setUp() public {
        _registry = new StubBondRegistryForAdapter();
        _adapter = new DeussBondMetadataAdapter(address(_registry));
        _token = makeAddr("bondToken");
        _registry.setToken(_token);
    }

    function _bond(bytes12 isin) internal pure returns (Bond memory bond) {
        bond.isin = isin;
        bond.status = BondStatus.Issued;
        bond.couponRateType = CouponRateType.FIXED;
        bond.couponFrequency = CouponFrequency.Annual;
        bond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});
    }

    function test_constructor_setsRegistry() public view {
        assertEq(address(_adapter.bondRegistry()), address(_registry));
    }

    function test_constructor_reverts_withZeroRegistry() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new DeussBondMetadataAdapter(address(0));
    }

    function test_getBond_proxiesToRegistry() public {
        Bond memory b = _bond(bytes12("BOND001"));
        _registry.setBond(42, b);

        Bond memory returned = _adapter.getBond(_token, 42);

        assertEq(returned.isin, b.isin);
        assertEq(uint256(returned.status), uint256(BondStatus.Issued));
    }

    function test_getBond_revertsPropagated_forUnknownToken() public {
        vm.expectRevert(StubBondRegistryForAdapter.NonBond.selector);
        _adapter.getBond(_token, 999);
    }

    function test_getBond_reverts_whenTokenMismatch() public {
        address otherToken = makeAddr("otherToken");
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, bytes12(0)));
        _adapter.getBond(otherToken, 42);
    }

    function test_getCurrentCouponRate_proxiesToRegistry() public {
        Bond memory b = _bond(bytes12("BOND002"));
        _registry.setCurrentRate(b.isin, 500);

        assertEq(_adapter.getCurrentCouponRate(b), 500);
    }
}

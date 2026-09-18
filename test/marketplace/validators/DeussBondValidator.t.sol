// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DeussBondValidator} from "src/marketplace/validators/DeussBondValidator.sol";
import {Bond, BondStatus, CouponRateType, CouponFrequency, CouponRates} from "src/registry/BondStructs.sol";
import {Errors} from "src/libs/Errors.sol";

contract StubBondRegistryForValidator {
    mapping(uint256 tokenId => Bond bond) internal _bonds;
    mapping(uint256 tokenId => bool registered) internal _registered;

    function setBond(uint256 tokenId, Bond calldata bond) external {
        _bonds[tokenId] = bond;
        _registered[tokenId] = true;
    }

    function getBondByTokenId(uint256 tokenId) external view returns (Bond memory) {
        if (!_registered[tokenId]) {
            revert Errors.BondRegistry__NonExistentBond(bytes12(0));
        }
        return _bonds[tokenId];
    }
}

contract DeussBondValidatorTest is Test {
    DeussBondValidator internal _validator;
    StubBondRegistryForValidator internal _registry;
    address internal _token;

    uint256 internal constant _TOKEN_ID = 42;

    function setUp() public {
        _registry = new StubBondRegistryForValidator();
        _validator = new DeussBondValidator(address(_registry));
        _token = makeAddr("bondToken");
    }

    function _bond(BondStatus status) internal view returns (Bond memory bond) {
        bond.isin = bytes12("ISIN000001");
        bond.status = status;
        bond.tokenAddress = _token;
        bond.couponRateType = CouponRateType.FIXED;
        bond.couponFrequency = CouponFrequency.Annual;
        bond.couponRates = CouponRates({paymentTimestamps: new uint256[](0), rates: new uint256[](0)});
    }

    function _seed(BondStatus status) internal {
        _registry.setBond(_TOKEN_ID, _bond(status));
    }

    /*//////////////////////////////////////////////////////////////
                              constructor
    //////////////////////////////////////////////////////////////*/
    function test_constructor_setsRegistry() public view {
        // ASSERT
        assertEq(address(_validator.bondRegistry()), address(_registry));
    }

    function test_constructor_reverts_withZeroRegistry() public {
        // ACT & ASSERT
        vm.expectRevert(Errors.ZeroAddress.selector);
        new DeussBondValidator(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                validate
    //////////////////////////////////////////////////////////////*/
    function test_validate_succeeds_whenIssued() public {
        // PREPARE
        _seed(BondStatus.Issued);

        // ACT & ASSERT
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_succeeds_whenReplaced() public {
        // PREPARE
        _seed(BondStatus.Replaced);

        // ACT & ASSERT
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_reverts_whenPublished() public {
        // PREPARE
        _seed(BondStatus.Published);

        // ACT & ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.DeussBondValidator__NotTradable.selector, _TOKEN_ID, uint8(BondStatus.Published)
            )
        );
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_reverts_whenSuspended() public {
        // PREPARE
        _seed(BondStatus.Suspended);

        // ACT & ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.DeussBondValidator__NotTradable.selector, _TOKEN_ID, uint8(BondStatus.Suspended)
            )
        );
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_reverts_whenRedeemed() public {
        // PREPARE
        _seed(BondStatus.Redeemed);

        // ACT & ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.DeussBondValidator__NotTradable.selector, _TOKEN_ID, uint8(BondStatus.Redeemed)
            )
        );
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_reverts_whenCancelled() public {
        // PREPARE
        _seed(BondStatus.Cancelled);

        // ACT & ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.DeussBondValidator__NotTradable.selector, _TOKEN_ID, uint8(BondStatus.Cancelled)
            )
        );
        _validator.validate(_token, _TOKEN_ID, 1);
    }

    function test_validate_reverts_forUnknownTokenId() public {
        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.BondRegistry__NonExistentBond.selector, bytes12(0)));
        _validator.validate(_token, 999, 1);
    }

    function test_validate_reverts_whenTokenMismatch() public {
        // PREPARE
        _seed(BondStatus.Issued);
        address spoofed = makeAddr("spoofedToken");

        // ACT & ASSERT
        vm.expectRevert(abi.encodeWithSelector(Errors.DeussBondValidator__TokenMismatch.selector, spoofed, _token));
        _validator.validate(spoofed, _TOKEN_ID, 1);
    }
}

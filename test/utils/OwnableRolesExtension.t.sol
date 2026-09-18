// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {OwnableRoles} from "src/utils/OwnableRolesExtension.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Errors} from "src/libs/Errors.sol";
// test files
import {OwnableRolesExtensionFixture} from "test/fixtures/OwnableRolesExtensionFixture.t.sol";

contract OwnableRolesExtensionTest is OwnableRolesExtensionFixture {
    address internal _owner;
    address internal _unauthorized;

    function setUp() public virtual override {
        super.setUp();
        _owner = this.owner();
        _unauthorized = makeAddr("unauthorized");
    }

    function test_grantRoles_success() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectEmit();
        emit OwnableRoles.RolesUpdated(newUser, roles);
        this.grantRoles(newUser, roles);

        // ASSERT
        assertEq(this.rolesOf(newUser), roles);
    }

    function test_grantRoles_revert_unauthorized() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_unauthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        this.grantRoles(newUser, roles);

        // ASSERT
        assertEq(this.rolesOf(newUser), 0);
    }

    function test_grantRoles_revert_zeroAddress() public {
        // ARRANGE
        address newUser = address(0);
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        this.grantRoles(newUser, roles);

        // ASSERT
        assertEq(this.rolesOf(newUser), 0);
    }

    function test_grantRoles_array_success() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = makeAddr("newUser");
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectEmit();
        emit OwnableRoles.RolesUpdated(newUsers[0], roles);
        this.grantRoles(newUsers, roles);

        // ASSERT
        assertEq(this.rolesOf(newUsers[0]), roles);
    }

    function test_grantRoles_array_revert_unauthorized() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = makeAddr("newUser");
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_unauthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        this.grantRoles(newUsers, roles);

        // ASSERT
        assertEq(this.rolesOf(newUsers[0]), 0);
    }

    function test_grantRoles_array_revert_zeroAddress() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = address(0);
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        this.grantRoles(newUsers, roles);

        // ASSERT
        assertEq(this.rolesOf(newUsers[0]), 0);
    }

    function test_revokeRoles_success() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = SOME_ROLE;
        vm.prank(_owner);
        this.grantRoles(newUser, roles);

        // ACT
        vm.expectEmit();
        emit OwnableRoles.RolesUpdated(newUser, 0);
        vm.prank(_owner);
        this.revokeRoles(newUser, roles);

        // ASSERT
        assertEq(this.rolesOf(newUser), 0);
    }

    function test_revokeRoles_revert_unauthorized() public {
        // ARRANGE
        address newUser = makeAddr("newUser");
        uint256 roles = SOME_ROLE;
        vm.prank(_owner);
        this.grantRoles(newUser, roles);

        // ACT
        vm.prank(_unauthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        this.revokeRoles(newUser, roles);

        // ASSERT
        assertEq(this.rolesOf(newUser), roles);
    }

    function test_revokeRoles_revert_zeroAddress() public {
        // ARRANGE
        address newUser = address(0);
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        this.revokeRoles(newUser, roles);
    }

    function test_revokeRoles_array_success() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = makeAddr("newUser");
        uint256 roles = SOME_ROLE;
        vm.prank(_owner);
        this.grantRoles(newUsers, roles);

        // ACT
        vm.prank(_owner);
        vm.expectEmit();
        emit OwnableRoles.RolesUpdated(newUsers[0], 0);
        this.revokeRoles(newUsers, roles);

        // ASSERT
        assertEq(this.rolesOf(newUsers[0]), 0);
    }

    function test_revokeRoles_array_revert_unauthorized() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = makeAddr("newUser");
        uint256 roles = SOME_ROLE;
        vm.prank(_owner);
        this.grantRoles(newUsers, roles);

        // ACT
        vm.prank(_unauthorized);
        vm.expectRevert(Ownable.Unauthorized.selector);
        this.revokeRoles(newUsers, roles);

        // ASSERT
        assertEq(this.rolesOf(newUsers[0]), roles);
    }

    function test_revokeRoles_array_revert_zeroAddress() public {
        // ARRANGE
        address[] memory newUsers = new address[](1);
        newUsers[0] = address(0);
        uint256 roles = SOME_ROLE;

        // ACT
        vm.prank(_owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        this.revokeRoles(newUsers, roles);
    }
}

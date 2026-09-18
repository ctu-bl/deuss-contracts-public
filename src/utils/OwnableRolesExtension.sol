// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {AddressExtensions} from "src/libs/AddressExtensions.sol";

/**
 * @title OwnableRolesExtension
 * @author DEUSS Team
 * @notice Extension of Solady `OwnableRoles` with batched grant/revoke and zero-address guards.
 * @dev Solady's base API updates one account per call; this adds `address[]` overloads. Every `user` must be
 *      non-zero before `_grantRoles` / `_removeRoles` runs (defense-in-depth vs misconfigured scripts).
 */
abstract contract OwnableRolesExtension is OwnableRoles {
    using AddressExtensions for address;

    /**
     * @notice Allows the owner to grant `roles` for a `user`
     * @dev Adds a validation of the param address - cannot be address(0)
     * @param user Address that you want to grant the `roles` to
     * @param roles Bitmap of the role flags to grant
     */
    function grantRoles(address user, uint256 roles) public payable virtual override onlyOwner {
        user.assertAddressNotZero();
        _grantRoles(user, roles);
    }

    /**
     * @notice Allows the owner to grant `roles` for multiple `users` at once
     * @dev Solady's default API only grants `roles` to one user per call
     * @dev Adds a validation of the param addresses - cannot be address(0)
     * @param users Array of users that you want to grant the `roles` to
     * @param roles Bitmap of the role flags to grant
     */
    function grantRoles(address[] calldata users, uint256 roles) public payable virtual onlyOwner {
        for (uint256 i; i < users.length; ++i) {
            users[i].assertAddressNotZero();
            _grantRoles(users[i], roles);
        }
    }

    /**
     * @notice Allows the owner to revoke `roles` for a `user`
     * @dev Adds a validation of the param address - cannot be address(0)
     * @param user Address that you want to revoke the `roles` from
     * @param roles Bitmap of the role flags to revoke
     */
    function revokeRoles(address user, uint256 roles) public payable virtual override onlyOwner {
        user.assertAddressNotZero();
        _removeRoles(user, roles);
    }

    /**
     * @notice Allows the owner to revoke `roles` from multiple `users` at once
     * @dev Solady's default API only revokes `roles` from one user per call
     * @dev Adds a validation of the param addresses - cannot be address(0)
     * @param users Array of users that you want to revoke the `roles` from
     * @param roles Bitmap of the role flags to revoke
     */
    function revokeRoles(address[] calldata users, uint256 roles) public payable virtual onlyOwner {
        for (uint256 i; i < users.length; ++i) {
            users[i].assertAddressNotZero();
            _removeRoles(users[i], roles);
        }
    }
}

# OwnableRolesExtension Documentation

## Overview

`OwnableRolesExtension` is the shared role-management base used by protocol contracts that rely on Solady `OwnableRoles`. It keeps the base Solady owner/role model and adds batched grant/revoke helpers plus zero-address validation. Protocol role assignments are summarized in [`roles.md`](../roles.md).

## Contract Architecture

- Inherits from `solady/src/auth/OwnableRoles.sol`
- Uses `AddressExtensions.assertAddressNotZero`
- Adds batch overloads for role grants and revokes
- Does not define role constants itself; inheriting contracts define their own role bitmaps

## Core Functions

### grantRoles(address user, uint256 roles)

Owner-only role grant for one account.

**Errors:**
- `Unauthorized()`: Caller is not owner
- `ZeroAddress()`: `user` is zero

### grantRoles(address[] calldata users, uint256 roles)

Owner-only role grant for multiple accounts. Every user must be non-zero.

### revokeRoles(address user, uint256 roles)

Owner-only role revoke for one account.

**Errors:**
- `Unauthorized()`: Caller is not owner
- `ZeroAddress()`: `user` is zero

### revokeRoles(address[] calldata users, uint256 roles)

Owner-only role revoke for multiple accounts. Every user must be non-zero.

## Trust and Security Notes

- Inheriting contracts may override `grantRoles` to restrict valid role bits, for example `BaseToken`, `BondRegistry`, and `EntityRegistry`.
- Owner custody is critical: the owner can grant or revoke all roles exposed by the inheriting contract.
- Batch functions apply the same role bitmap to each account in the input array.

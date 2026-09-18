# Shared Libraries Documentation

## Overview

The repository uses small shared libraries and centralized custom errors to keep validation behavior consistent across contracts.

## Libraries

### AddressExtensions

Provides `assertAddressNotZero(address)`.

**Behavior:**
- Reverts with `ZeroAddress()` when the address is zero
- Used by dependency wiring and role-management helpers

### StringExtensions

Provides fixed-length ASCII conversion helpers used by registry logic.

**Core helpers:**
- `_isinToBytes12(string memory isin)`: Converts an exact 12-byte ISIN string to `bytes12`; positions `0..1` must be `A-Z`, positions `2..10` must be `A-Z` or `0-9`, and position `11` must be `0-9`; checksum validation is not performed
- `_currencyToBytes3(string memory currency)`: Converts an exact 3-byte uppercase currency code (`A-Z`) to `bytes3`
- `_stringToFixedBytes(string memory input, uint256 expectedLength)`: Validates exact length and printable ASCII bytes (`0x20..0x7E`) before packing into `bytes32`

**Errors:**
- `StringExtensions__InvalidBytesLength()`: Input length does not match the expected byte length, or the expected length is greater than 32.
- `StringExtensions__NonAsciiCharacter()`: Input contains a byte outside 7-bit ASCII.
- `StringExtensions__InvalidCharacter()`: Input contains an ASCII byte outside the required printable/domain-specific character set.

### Errors

`src/libs/Errors.sol` centralizes custom errors for the protocol.

**Important Notes:**
- Contracts should reuse shared errors instead of introducing ad hoc revert strings
- Several utility-level checks use shared errors such as `ZeroAddress()` and `EmptyString()`
- Contract-specific errors are grouped by protocol area inside the same file

## Trust and Security Notes

- These helpers are pure validation utilities and do not hold state.
- Changes to shared errors or library validation semantics can affect multiple protocol surfaces and should be reviewed with all call sites.

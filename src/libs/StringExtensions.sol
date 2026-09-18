// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Errors} from "./Errors.sol";

/**
 * @title StringExtensions
 * @author DEUSS Team
 * @notice Provides utility functions for string type
 * @dev Fixed-byte packing requires exact byte length and printable ASCII (0x20-0x7E). ISIN uses positional
 *      uppercase alphanumeric rules; currency uses uppercase letters only.
 */
library StringExtensions {
    /**
     * @notice Converts a strict 12-byte ISIN string to bytes12
     * @param isin The ISIN string to convert. Positions 0-1 must be A-Z, positions 2-10 A-Z or 0-9, position 11 0-9.
     * @return bytes12 representation of the ISIN
     */
    function _isinToBytes12(string memory isin) internal pure returns (bytes12) {
        bytes memory inputBytes = bytes(isin);
        _validateFixedLengthAndPrintableAscii(inputBytes, 12);
        _validateIsinCharacters(inputBytes);
        return bytes12(_packFixedBytes(inputBytes));
    }

    /**
     * @notice Converts a strict 3-byte currency code to bytes3
     * @param currency The uppercase currency code string to convert. Each byte must be A-Z.
     * @return bytes3 representation of the currency code
     */
    function _currencyToBytes3(string memory currency) internal pure returns (bytes3) {
        bytes memory inputBytes = bytes(currency);
        _validateFixedLengthAndPrintableAscii(inputBytes, 3);
        _validateCurrencyCharacters(inputBytes);
        return bytes3(_packFixedBytes(inputBytes));
    }

    /**
     * @notice Packs a fixed-length printable ASCII string into the leading bytes of `bytes32`.
     * @param input The string to convert (byte length must equal `expectedLength`, at most 32).
     * @param expectedLength The expected length of the string in bytes
     * @return result Right-padded string contents in `bytes32`
     */
    function _stringToFixedBytes(string memory input, uint256 expectedLength) internal pure returns (bytes32 result) {
        bytes memory inputBytes = bytes(input);

        _validateFixedLengthAndPrintableAscii(inputBytes, expectedLength);
        result = _packFixedBytes(inputBytes);
    }

    /**
     * @notice Validates exact byte length and printable ASCII range.
     * @param inputBytes The string bytes to validate
     * @param expectedLength The exact expected byte length
     */
    function _validateFixedLengthAndPrintableAscii(bytes memory inputBytes, uint256 expectedLength) private pure {
        require(
            !(expectedLength > 32 || inputBytes.length != expectedLength), Errors.StringExtensions__InvalidBytesLength()
        );

        uint256 length = inputBytes.length;
        for (uint256 i; i < length; ++i) {
            uint8 b = uint8(inputBytes[i]);
            require(!(b > 0x7F), Errors.StringExtensions__NonAsciiCharacter());
            require(!(b < 0x20 || b > 0x7E), Errors.StringExtensions__InvalidCharacter());
        }
    }

    /**
     * @notice Packs already-validated bytes into bytes32.
     * @param inputBytes The bytes to pack. Length must be at most 32.
     * @return result Right-padded bytes32 representation
     */
    function _packFixedBytes(bytes memory inputBytes) private pure returns (bytes32 result) {
        uint256 length = inputBytes.length;
        for (uint256 i; i < length; ++i) {
            result |= bytes32(uint256(uint8(inputBytes[i])) << ((31 - i) * 8));
        }
    }

    /**
     * @notice Validates the ISIN character shape without checksum validation.
     * @param inputBytes The 12-byte ISIN payload
     */
    function _validateIsinCharacters(bytes memory inputBytes) private pure {
        require(
            _isUppercaseLetter(uint8(inputBytes[0])) && _isUppercaseLetter(uint8(inputBytes[1])),
            Errors.StringExtensions__InvalidCharacter()
        );

        for (uint256 i = 2; i < 11; ++i) {
            uint8 b = uint8(inputBytes[i]);
            require(_isUppercaseLetter(b) || _isDigit(b), Errors.StringExtensions__InvalidCharacter());
        }

        require(_isDigit(uint8(inputBytes[11])), Errors.StringExtensions__InvalidCharacter());
    }

    /**
     * @notice Validates uppercase ISO-style currency code characters.
     * @param inputBytes The 3-byte currency payload
     */
    function _validateCurrencyCharacters(bytes memory inputBytes) private pure {
        for (uint256 i; i < 3; ++i) {
            require(_isUppercaseLetter(uint8(inputBytes[i])), Errors.StringExtensions__InvalidCharacter());
        }
    }

    /**
     * @notice Checks whether a byte is an uppercase ASCII letter.
     * @param b The byte to inspect.
     * @return True when `b` is in the `A-Z` range.
     */
    function _isUppercaseLetter(uint8 b) private pure returns (bool) {
        return !(b < 0x41 || b > 0x5A);
    }

    /**
     * @notice Checks whether a byte is an ASCII digit.
     * @param b The byte to inspect.
     * @return True when `b` is in the `0-9` range.
     */
    function _isDigit(uint8 b) private pure returns (bool) {
        return !(b < 0x30 || b > 0x39);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Errors} from "src/libs/Errors.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";

contract StringExtensionsHarness {
    using StringExtensions for string;

    function isinToBytes12(string calldata isin) external pure returns (bytes12) {
        return isin._isinToBytes12();
    }

    function currencyToBytes3(string calldata currency) external pure returns (bytes3) {
        return currency._currencyToBytes3();
    }

    function stringToFixedBytes(string calldata input, uint256 expectedLength) external pure returns (bytes32) {
        return input._stringToFixedBytes(expectedLength);
    }
}

contract StringExtensionsTest is Test {
    StringExtensionsHarness private _harness;

    function setUp() public {
        _harness = new StringExtensionsHarness();
    }

    /*//////////////////////////////////////////////////////////////
                              _isinToBytes12
    //////////////////////////////////////////////////////////////*/

    function test_isinToBytes12_success_withUppercaseAlphanumericShape() public view {
        assertEq(_harness.isinToBytes12("SK0001002059"), bytes12("SK0001002059"));
        assertEq(_harness.isinToBytes12("USABCDEF1G29"), bytes12("USABCDEF1G29"));
    }

    function test_isinToBytes12_reverts_invalidLength() public {
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _harness.isinToBytes12("SK000100205");
    }

    function test_isinToBytes12_reverts_nonAsciiCharacter() public {
        vm.expectRevert(Errors.StringExtensions__NonAsciiCharacter.selector);
        _harness.isinToBytes12(unicode"SK00010020é");
    }

    function test_isinToBytes12_reverts_controlCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("SK00010020\n9");
    }

    function test_isinToBytes12_reverts_delCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12(string(abi.encodePacked("SK00010020", bytes1(0x7F), "9")));
    }

    function test_isinToBytes12_reverts_firstCountryCharacterIsNotUppercaseLetter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("1K0001002059");
    }

    function test_isinToBytes12_reverts_secondCountryCharacterIsNotUppercaseLetter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("S10001002059");
    }

    function test_isinToBytes12_reverts_lowercaseCountryCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("Sk0001002059");
    }

    function test_isinToBytes12_reverts_bodyCharacterIsNotUppercaseLetterOrDigit() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("SK00010020-9");
    }

    function test_isinToBytes12_reverts_finalCharacterIsNotDigit() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.isinToBytes12("SK000100205A");
    }

    /*//////////////////////////////////////////////////////////////
                             _currencyToBytes3
    //////////////////////////////////////////////////////////////*/

    function test_currencyToBytes3_success_uppercaseCurrency() public view {
        assertEq(_harness.currencyToBytes3("EUR"), bytes3("EUR"));
    }

    function test_currencyToBytes3_reverts_invalidLength() public {
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _harness.currencyToBytes3("EURO");
    }

    function test_currencyToBytes3_reverts_nonAsciiCharacter() public {
        vm.expectRevert(Errors.StringExtensions__NonAsciiCharacter.selector);
        _harness.currencyToBytes3(unicode"Eé");
    }

    function test_currencyToBytes3_reverts_controlCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.currencyToBytes3("EU\n");
    }

    function test_currencyToBytes3_reverts_digitCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.currencyToBytes3("EU1");
    }

    function test_currencyToBytes3_reverts_lowercaseCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.currencyToBytes3("EuR");
    }

    /*//////////////////////////////////////////////////////////////
                            _stringToFixedBytes
    //////////////////////////////////////////////////////////////*/

    function test_stringToFixedBytes_success_emptyString() public view {
        assertEq(_harness.stringToFixedBytes("", 0), bytes32(0));
    }

    function test_stringToFixedBytes_success_printableAsciiBoundaryCharacters() public view {
        bytes32 expected = bytes32(" ~");
        assertEq(_harness.stringToFixedBytes(" ~", 2), expected);
    }

    function test_stringToFixedBytes_success_maxLength() public view {
        string memory input = "12345678901234567890123456789012";
        assertEq(_harness.stringToFixedBytes(input, 32), bytes32(bytes(input)));
    }

    function test_stringToFixedBytes_reverts_expectedLengthGreaterThan32() public {
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _harness.stringToFixedBytes(string.concat("12345678901234567890123456789012", "3"), 33);
    }

    function test_stringToFixedBytes_reverts_inputLengthMismatch() public {
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _harness.stringToFixedBytes("ABC", 2);
    }

    function test_stringToFixedBytes_reverts_nonEmptyStringWithZeroExpectedLength() public {
        vm.expectRevert(Errors.StringExtensions__InvalidBytesLength.selector);
        _harness.stringToFixedBytes("A", 0);
    }

    function test_stringToFixedBytes_reverts_multiByteUtf8WithMatchingByteCount() public {
        vm.expectRevert(Errors.StringExtensions__NonAsciiCharacter.selector);
        _harness.stringToFixedBytes(unicode"é", 2);
    }

    function test_stringToFixedBytes_reverts_nullCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.stringToFixedBytes(string(abi.encodePacked(bytes1(0x00))), 1);
    }

    function test_stringToFixedBytes_reverts_controlCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.stringToFixedBytes("\t", 1);
    }

    function test_stringToFixedBytes_reverts_delCharacter() public {
        vm.expectRevert(Errors.StringExtensions__InvalidCharacter.selector);
        _harness.stringToFixedBytes(string(abi.encodePacked(bytes1(0x7F))), 1);
    }
}

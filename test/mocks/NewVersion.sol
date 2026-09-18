// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract NewVersion {
    uint8 public constant VERSION = 2; // adding new variable to validate the version when upgrading in tests

    // adding new function to validate the new version of the contract when upgrading in tests
    function isNewVersion() external pure returns (bool) {
        return true;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BondFixture} from "test/fixtures/BondFixture.t.sol";

/**
 * @title FTFixture
 * @notice Fungible token fixture for token-related tests
 * @dev Provides common token setup functionality
 */
contract FTFixture is BondFixture {
    address internal _tokenRecipient1;
    address internal _tokenRecipient2;
    address internal _tokenRecipient3;
    address internal _newWallet;

    function setUp() public virtual override {
        super.setUp();

        _tokenRecipient1 = _createAddress("tokenRecipient1");
        _tokenRecipient2 = _createAddress("tokenRecipient2");
        _tokenRecipient3 = _createAddress("tokenRecipient3");
        _newWallet = _createAddress("newWallet");

        // Register token recipients 1 & 2 in entity registry (needed for regular transfers)
        // tokenRecipient3 intentionally left unregistered (used as forced transfer target)
        _createAndRegisterEntityWallet(_erAdmin, _tokenRecipient1);
        _createAndRegisterEntityWallet(_erAdmin, _tokenRecipient2);

        // issue bond — full supply in one tranche (version 1)
        vm.startPrank(_cwAddr);
        _br.issueBond(_bondFT.isin, 1, BOND_MAX_SUPPLY);
        vm.stopPrank();
    }

    /// @notice Helper to register an address in the entity registry
    function _registerWallet(address wallet) internal {
        _createAndRegisterEntityWallet(_erAdmin, wallet);
    }
}

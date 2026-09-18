// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// fixtures
import {BaseToken} from "src/token/base/BaseToken.sol";
import {CompanyFixture} from "test/fixtures/CompanyFixture.t.sol";
// import {SharedUtilities} from "test/fixtures/SharedUtilities.t.sol";
import {StringExtensions} from "src/libs/StringExtensions.sol";

contract BondFixture is CompanyFixture {
    using StringExtensions for string;

    address internal _tokenAdmin;

    function setUp() public virtual override {
        // Deploy DEUSS suite (includes EBSI, registries, etc.) and company setup
        CompanyFixture.setUp();

        /*//////////////////////////////////////////////////////////////
                                SETUP BOND
        //////////////////////////////////////////////////////////////*/
        _maturityDate = block.timestamp + (365 * 24 * 60 * 60);
        _bondFT = _createBond(BOND_ISIN_ERC6909_FT, _cwAddr);
        bytes12 isinBytes = BOND_ISIN_ERC6909_FT._isinToBytes12();
        _bondFTId = uint256(keccak256(abi.encodePacked(isinBytes, uint8(1))));

        /*//////////////////////////////////////////////////////////////
                                BOND REGISTRY
        //////////////////////////////////////////////////////////////*/
        vm.startPrank(_publisher);
        _br.setAllowedCurrency(_bondFT.currency, true);
        _br.publishBond(_bondFT);
        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////
                                    Token
        //////////////////////////////////////////////////////////////*/
        _tokenAdmin = _createAddress("tokenAdmin");
        _createAndRegisterEntityWallet(_erAdmin, _tokenAdmin);

        _tokenAddr = _br.getToken();

        uint256 roles = BaseToken(_tokenAddr).BURNER_ROLE() | BaseToken(_tokenAddr).TOKEN_FREEZER_ROLE()
            | BaseToken(_tokenAddr).FORCE_TRANSFER_ROLE();

        _grantRoles(_tokenAddr, _tokenAdmin, roles);

        if (BaseToken(_tokenAddr).paused()) {
            // BaseToken(_tokenAddr).unpause();
            bytes memory data = abi.encodeWithSelector(BaseToken.unpause.selector);
            _timelockOp(_tokenAddr, data);
        }

        /*//////////////////////////////////////////////////////////////
                                EscrowManager
        //////////////////////////////////////////////////////////////*/
        // Bootstrap may already register EscrowManager as a protocol entity.
        if (!_er.doesAccountExist(_escrowManager)) {
            _createAndRegisterEntityWallet(_erAdmin, _escrowManager);
        }
    }
}

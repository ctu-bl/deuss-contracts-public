// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
// contracts
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";

// fixtures
import {SharedUtilities} from "test/fixtures/SharedUtilities.t.sol";

contract CompanyFixture is SharedUtilities {
    // actors
    address internal _company;
    uint256 internal _companyPK;
    address internal _publisher;

    function setUp() public virtual override {
        super.setUp();

        (_company, _companyPK) = makeAddrAndKey("company");

        // Create addresses using shared utilities
        _publisher = _createAddress("publisher");

        // registries initialization
        _br = BondRegistry(_brAddr);

        /*//////////////////////////////////////////////////////////////
                              ENTITY REGISTRY
        //////////////////////////////////////////////////////////////*/

        (_cwAddr,) = _createAndRegisterEntityWalletForCompany(_erAdmin, _company);
        vm.label(_cwAddr, "CompanyWallet");

        /*//////////////////////////////////////////////////////////////
                             BOND REGISTRY
        //////////////////////////////////////////////////////////////*/
        uint256 brRoles = _br.PUBLISHER() | _br.CURRENCY();
        _grantRoles(_brAddr, _publisher, brRoles);
    }

    function _deployPolicyRegistry(address owner_) internal returns (PolicyRegistry registry) {
        PolicyRegistry implementation = new PolicyRegistry();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner_);
        bytes memory initData = abi.encodeWithSelector(PolicyRegistry.initialize.selector, owner_);
        registry = PolicyRegistry(address(new BeaconProxy(address(beacon), initData)));
    }
}

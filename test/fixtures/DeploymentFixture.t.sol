// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Suite} from "script/DeployTypes.sol";
import {DeployBootstrapHarness} from "../mocks/DeployBootstrapHarness.t.sol";
import {Constants} from "../Constants.t.sol";
import {StorageLayoutHelpers} from "./StorageLayoutHelpers.t.sol";
import {BondInput, CouponFrequency, CouponRates} from "src/registry/BondStructs.sol";

contract DeploymentFixture is StorageLayoutHelpers, Constants {
    // Suite
    DeployBootstrapHarness internal _harness;
    Suite internal _suite;
    // addresses
    address internal _deployer;
    address internal _governance;
    address internal _timelockControllerAdmin;
    address internal _timelockControllerActor;
    address internal _admin;
    // other params
    uint256 internal _maturityDate;

    function setUp() public virtual {
        _harness = new DeployBootstrapHarness();
        _suite = _harness.deploySuite();
        // addresses
        _deployer = _harness.deployer();
        _governance = _deployer;
        _timelockControllerAdmin = _harness.timelockControllerAdmin();
        _timelockControllerActor = _harness.timelockControllerActor();
        _admin = _harness.admin();
        // labels
        vm.label(_deployer, "Deployer");
        vm.label(_governance, "Governance");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function _createBond(string memory isin, address issuer) internal view returns (BondInput memory) {
        return BondInput({
            isin: isin,
            issuer: issuer,
            currency: BOND_CURRENCY,
            bondNominalValue: BOND_NOMINAL_VALUE,
            maxSupply: BOND_MAX_SUPPLY,
            couponRateType: BOND_COUPON_RATE_TYPE,
            couponRates: _createCouponRatesFromOneRate(BOND_COUPON_RATE),
            couponFrequency: CouponFrequency.Annual,
            maturityDate: _maturityDate,
            isGuaranteed: false,
            issuanceCountry: BOND_ISSUANCE_COUNTRY
        });
    }

    function _createCouponRatesFromOneRate(uint256 rate) internal view returns (CouponRates memory) {
        uint256[] memory paymentTimestamps = new uint256[](2);
        uint256[] memory rates = new uint256[](2);
        paymentTimestamps[0] = block.timestamp;
        paymentTimestamps[1] = _maturityDate;
        rates[0] = rate;
        rates[1] = 0;

        return CouponRates({paymentTimestamps: paymentTimestamps, rates: rates});
    }
}

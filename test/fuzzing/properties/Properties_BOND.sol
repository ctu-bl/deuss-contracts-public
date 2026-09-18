// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable contract-name-capwords, private-vars-leading-underscore, gas-small-strings */

import {BondInput, BondStatus, Scoring, Tranche} from "src/registry/BondStructs.sol";
import {PropertiesBase} from "./PropertiesBase.sol";

abstract contract Properties_BOND is PropertiesBase {
    function invariant_BOND_01() internal {
        fl.eq(states[1].allTrackedBondSupplyConsistent, true, BOND_01);
    }

    function invariant_BOND_02() internal {
        fl.eq(states[1].allTrackedBondCapacityConsistent, true, BOND_02);
    }

    function invariant_BOND_03() internal {
        fl.eq(states[1].allTrackedBondPauseConsistent, true, BOND_03);
    }

    function invariant_BOND_04() internal {
        fl.eq(states[1].allTrackedBondReverseMappingsConsistent, true, BOND_04);
    }

    function invariant_BOND_04(bytes12 reverseIsin, uint8 reverseVersion, uint8 expectedVersion) internal {
        fl.eq(reverseIsin == BOND_ISIN_BYTES12, true, BOND_04);
        fl.eq(uint256(reverseVersion), uint256(expectedVersion), BOND_04);
    }

    function invariant_BOND_05() internal {
        fl.eq(states[1].allTrackedBondTranchesConsistent, true, BOND_05);
    }

    function invariant_BOND_10(uint8 version) internal {
        fl.eq(uint256(version), uint256(states[0].latestBondVersion) + 1, BOND_10);
    }

    function invariant_BOND_11(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Published), BOND_11);
    }

    function invariant_BOND_12(uint8 version) internal {
        fl.eq(states[1].bondVersionStates[version].mintedSupply, 0, BOND_12);
        fl.eq(
            states[1].bondVersionStates[version].remainingIssuableSupply,
            states[1].bondVersionStates[version].maxSupply,
            BOND_12
        );
    }

    function invariant_BOND_13(uint8 previousVersion) internal {
        fl.eq(
            uint256(states[1].bondVersionStates[previousVersion].status),
            uint256(states[0].bondVersionStates[previousVersion].status),
            BOND_13
        );
    }

    function invariant_BOND_15() internal {
        fl.eq(uint256(states[1].activeBondVersion), uint256(states[0].activeBondVersion), BOND_15);
    }

    function invariant_BOND_16(uint8 version, BondInput memory input) internal {
        _assertBondInputWritten(version, input, BOND_16);
    }

    function invariant_BOND_14(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_14);
    }

    function invariant_BOND_20(uint8 version) internal {
        fl.eq(states[1].bondVersionStates[version].tokenId, states[0].bondVersionStates[version].tokenId, BOND_20);
        fl.eq(
            uint256(states[1].bondVersionStates[version].trancheCount),
            uint256(states[0].bondVersionStates[version].trancheCount),
            BOND_20
        );
    }

    function invariant_BOND_21(uint8 version) internal {
        fl.eq(
            states[1].bondVersionStates[version].remainingIssuableSupply,
            states[1].bondVersionStates[version].maxSupply,
            BOND_21
        );
    }

    function invariant_BOND_22(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Published), BOND_22);
    }

    function invariant_BOND_23(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_23);
    }

    function invariant_BOND_24(uint8 version, BondInput memory input) internal {
        _assertBondInputWritten(version, input, BOND_24);
    }

    function invariant_BOND_30(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].mintedSupply,
            states[0].bondVersionStates[version].mintedSupply + amount,
            BOND_30
        );
    }

    function invariant_BOND_31(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].remainingIssuableSupply + amount,
            states[0].bondVersionStates[version].remainingIssuableSupply,
            BOND_31
        );
    }

    function invariant_BOND_32(uint8 version, uint256 amount) internal {
        fl.eq(
            uint256(states[1].bondVersionStates[version].trancheCount),
            uint256(states[0].bondVersionStates[version].trancheCount) + 1,
            BOND_32
        );
        uint16 trancheId = states[1].bondVersionStates[version].trancheCount;
        Tranche memory tranche = bondRegistry.getTranche(BOND_ISIN_BYTES12, version, trancheId);
        fl.eq(tranche.issueCount, amount, BOND_32);
        fl.eq(tranche.issueDate, block.timestamp, BOND_32);
    }

    function invariant_BOND_33(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].issuerBalance,
            states[0].bondVersionStates[version].issuerBalance + amount,
            BOND_33
        );
    }

    function invariant_BOND_34(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].totalSupply,
            states[0].bondVersionStates[version].totalSupply + amount,
            BOND_34
        );
    }

    function invariant_BOND_35(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Issued), BOND_35);
    }

    function invariant_BOND_102(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Issued), BOND_102);
    }

    function invariant_BOND_36(uint8 previousVersion) internal {
        fl.eq(uint256(states[1].bondVersionStates[previousVersion].status), uint256(BondStatus.Replaced), BOND_36);
    }

    function invariant_BOND_39(uint8 version) internal {
        fl.eq(uint256(states[1].activeBondVersion), uint256(version), BOND_39);
    }

    function invariant_BOND_37(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_37);
    }

    function invariant_BOND_40(uint8 version) internal {
        fl.eq(states[1].bondVersionStates[version].issuanceClosed, true, BOND_40);
    }

    function invariant_BOND_41(uint8 version) internal {
        fl.eq(
            uint256(states[1].bondVersionStates[version].status),
            uint256(states[0].bondVersionStates[version].status),
            BOND_41
        );
    }

    function invariant_BOND_42(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_42);
    }

    function invariant_BOND_50(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Cancelled), BOND_50);
    }

    function invariant_BOND_53(uint8 version) internal {
        fl.eq(uint256(states[1].latestBondVersion), uint256(states[0].latestBondVersion), BOND_53);

        uint8 expectedActiveVersion = states[0].activeBondVersion == version ? 0 : states[0].activeBondVersion;
        fl.eq(uint256(states[1].activeBondVersion), uint256(expectedActiveVersion), BOND_53);
    }

    function invariant_BOND_51(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_51);
    }

    function invariant_BOND_60(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Suspended), BOND_60);
    }

    function invariant_BOND_61(uint8 version) internal {
        fl.eq(states[1].bondVersionStates[version].tokenIdPaused, true, BOND_61);
    }

    function invariant_BOND_62(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Issued), BOND_62);
    }

    function invariant_BOND_63(uint8 version) internal {
        fl.eq(states[1].bondVersionStates[version].tokenIdPaused, false, BOND_63);
    }

    function invariant_BOND_64(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_64);
    }

    function invariant_BOND_70(uint8 version) internal {
        fl.eq(states[0].bondVersionStates[version].totalSupply, 0, BOND_70);
    }

    function invariant_BOND_71(uint8 version) internal {
        fl.eq(uint256(states[1].bondVersionStates[version].status), uint256(BondStatus.Redeemed), BOND_71);
    }

    function invariant_BOND_72(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_72);
    }

    function invariant_BOND_80(uint8 version, address source, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionAccountBalances[version][source] + amount,
            states[0].bondVersionAccountBalances[version][source],
            BOND_80
        );
    }

    function invariant_BOND_80_BATCH(uint8 version, address[] memory froms, uint256[] memory amounts) internal {
        for (uint256 i; i < froms.length; ++i) {
            bool alreadyChecked;
            for (uint256 j; j < i; ++j) {
                if (froms[j] == froms[i]) {
                    alreadyChecked = true;
                    break;
                }
            }
            if (alreadyChecked) continue;

            uint256 totalForSource;
            for (uint256 j; j < froms.length; ++j) {
                if (froms[j] == froms[i]) {
                    totalForSource += amounts[j];
                }
            }

            invariant_BOND_80(version, froms[i], totalForSource);
        }
    }

    function invariant_BOND_81(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].totalSupply + amount,
            states[0].bondVersionStates[version].totalSupply,
            BOND_81
        );
    }

    function invariant_BOND_82(uint8 version) internal {
        fl.eq(
            states[1].bondVersionStates[version].mintedSupply,
            states[0].bondVersionStates[version].mintedSupply,
            BOND_82
        );
    }

    function invariant_BOND_83(uint8 version, uint256 amount) internal {
        fl.eq(
            states[1].bondVersionStates[version].remainingIssuableSupply,
            states[0].bondVersionStates[version].remainingIssuableSupply + amount,
            BOND_83
        );
    }

    function invariant_BOND_84(uint8 version) internal {
        fl.eq(
            states[1].bondVersionStates[version].remainingIssuableSupply,
            states[0].bondVersionStates[version].remainingIssuableSupply,
            BOND_84
        );
    }

    function invariant_BOND_85(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_85);
    }

    function invariant_BOND_38(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_38);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_38);
    }

    function invariant_BOND_52(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_52);
        bytes4[] memory allowedErrors = new bytes4[](2);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        allowedErrors[1] = bytes4(keccak256("BondRegistry__BondAlreadyIssued(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_52);
    }

    function invariant_BOND_65(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_65);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_65);
    }

    function invariant_BOND_66(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_66);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_66);
    }

    function invariant_BOND_73(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_73);
        bytes4[] memory allowedErrors = new bytes4[](3);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        allowedErrors[1] = bytes4(keccak256("BondRegistry__TotalSupplyNotZero()"));
        allowedErrors[2] = bytes4(keccak256("BondRegistry__SuccessorAlreadyPublished(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_73);
    }

    function invariant_BOND_86(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_86);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__UnauthorizedBurnCaller(address,uint8)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_86);
    }

    function invariant_BOND_87(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_87);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__UnauthorizedIssuer(address)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_87);
    }

    function invariant_BOND_88(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_88);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__IssuanceClosed(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_88);
    }

    function invariant_BOND_89(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_89);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__IssuanceAmountIsZero()"));
        fl.errAllow(errorSelector, allowedErrors, BOND_89);
    }

    function invariant_BOND_90(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_90);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__MaxSupplyExceeded(uint256,uint256)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_90);
    }

    function invariant_BOND_91(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_91);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__MaturityDateExpired()"));
        fl.errAllow(errorSelector, allowedErrors, BOND_91);
    }

    function invariant_BOND_92(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_92);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_92);
    }

    function invariant_BOND_93(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_93);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__UnauthorizedIssuanceCloser(address)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_93);
    }

    function invariant_BOND_94(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_94);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__IssuanceClosed(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_94);
    }

    function invariant_BOND_95(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_95);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBurnSource(address,bytes12,uint8)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_95);
    }

    function invariant_BOND_96(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_96);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_96);
    }

    function invariant_BOND_97(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_97);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("LengthMismatch()"));
        fl.errAllow(errorSelector, allowedErrors, BOND_97);
    }

    function invariant_BOND_98(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_98);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBurnSource(address,bytes12,uint8)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_98);
    }

    function invariant_BOND_99(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_99);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__ActiveVersionNotIssuable(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_99);
    }

    function invariant_BOND_100(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_100);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__SuccessorAlreadyPublished(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_100);
    }

    function invariant_BOND_101(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_101);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_101);
    }

    function invariant_BOND_103(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_103);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_103);
    }

    function invariant_BOND_104(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_104);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] =
            bytes4(keccak256("BondRegistry__FrozenIssuerReclaimDenied(address,bytes12,uint8,uint256,uint256)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_104);
    }

    function invariant_BOND_105(uint8 version, address newIssuer) internal {
        fl.eq(states[1].bondVersionStates[version].issuer, newIssuer, BOND_105);
    }

    function invariant_BOND_106(uint8 version) internal {
        BondVersionState storage beforeState = states[0].bondVersionStates[version];
        BondVersionState storage afterState = states[1].bondVersionStates[version];

        fl.eq(uint256(afterState.status), uint256(beforeState.status), BOND_106_STATUS);
        fl.eq(afterState.issuanceClosed, beforeState.issuanceClosed, BOND_106_ISSUANCE_CLOSED);
        fl.eq(afterState.isGuaranteed, beforeState.isGuaranteed, BOND_106_IS_GUARANTEED);
        fl.eq(afterState.tokenIdPaused, beforeState.tokenIdPaused, BOND_106_TOKEN_ID_PAUSED);
        fl.eq(uint256(afterState.trancheCount), uint256(beforeState.trancheCount), BOND_106_TRANCHE_COUNT);
        fl.eq(afterState.tokenId, beforeState.tokenId, BOND_106_TOKEN_ID);
        fl.eq(afterState.tokenAddress, beforeState.tokenAddress, BOND_106_TOKEN_ADDRESS);
        fl.eq(afterState.mintedSupply, beforeState.mintedSupply, BOND_106_MINTED_SUPPLY);
        fl.eq(
            afterState.remainingIssuableSupply, beforeState.remainingIssuableSupply, BOND_106_REMAINING_ISSUABLE_SUPPLY
        );
        fl.eq(afterState.maxSupply, beforeState.maxSupply, BOND_106_MAX_SUPPLY);
        fl.eq(afterState.totalSupply, beforeState.totalSupply, BOND_106_TOTAL_SUPPLY);
        fl.eq(afterState.currency == beforeState.currency, true, BOND_106_CURRENCY);
        fl.eq(afterState.bondNominalValue, beforeState.bondNominalValue, BOND_106_NOMINAL_VALUE);
        fl.eq(uint256(afterState.couponRateType), uint256(beforeState.couponRateType), BOND_106_COUPON_RATE_TYPE);
        fl.eq(uint256(afterState.couponFrequency), uint256(beforeState.couponFrequency), BOND_106_COUPON_FREQUENCY);
        fl.eq(uint256(afterState.issuanceCountry), uint256(beforeState.issuanceCountry), BOND_106_ISSUANCE_COUNTRY);
        fl.eq(afterState.maturityDate, beforeState.maturityDate, BOND_106_MATURITY_DATE);
        fl.eq(afterState.couponRatesHash == beforeState.couponRatesHash, true, BOND_106_COUPON_RATES_HASH);
        fl.eq(uint256(states[1].latestBondVersion), uint256(states[0].latestBondVersion), BOND_106_LATEST_VERSION);
        fl.eq(uint256(states[1].activeBondVersion), uint256(states[0].activeBondVersion), BOND_106_ACTIVE_VERSION);
    }

    function invariant_BOND_107(uint8 version, address oldIssuer, address newIssuer) internal {
        fl.eq(
            states[1].bondVersionAccountBalances[version][oldIssuer],
            states[0].bondVersionAccountBalances[version][oldIssuer],
            BOND_107
        );
        fl.eq(
            states[1].bondVersionAccountBalances[version][newIssuer],
            states[0].bondVersionAccountBalances[version][newIssuer],
            BOND_107
        );
    }

    function invariant_BOND_108(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_108);
    }

    function invariant_BOND_109(bool success, bytes4 errorSelector) internal {
        fl.eq(success, false, BOND_109);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = bytes4(keccak256("BondRegistry__InvalidBondStatus(bytes12)"));
        fl.errAllow(errorSelector, allowedErrors, BOND_109);
    }

    function invariant_BOND_110(
        address wallet,
        uint256 scoringId,
        Scoring memory expected,
        Scoring memory stored,
        Scoring memory latest
    ) internal {
        fl.eq(bondRegistry.getScoringCount(wallet), scoringId, BOND_110);
        _assertScoringEqual(stored, expected, BOND_110);
        _assertScoringEqual(latest, expected, BOND_110);
    }

    function invariant_BOND_111(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_111);
    }

    function invariant_BOND_112(bool success, bytes4 errorSelector, bytes4 expectedError) internal {
        fl.eq(success, false, BOND_112);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedError;
        fl.errAllow(errorSelector, allowedErrors, BOND_112);
    }

    function invariant_BOND_113(bool success, bytes4 errorSelector, bytes4 expectedError) internal {
        fl.eq(success, false, BOND_113);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedError;
        fl.errAllow(errorSelector, allowedErrors, BOND_113);
    }

    function invariant_BOND_114(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_114);
    }

    function invariant_BOND_115(bool success, bytes4 errorSelector, bytes4 expectedError) internal {
        fl.eq(success, false, BOND_115);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedError;
        fl.errAllow(errorSelector, allowedErrors, BOND_115);
    }

    function invariant_BOND_116(bool success, bytes4 errorSelector, bytes4 expectedError) internal {
        fl.eq(success, false, BOND_116);
        bytes4[] memory allowedErrors = new bytes4[](1);
        allowedErrors[0] = expectedError;
        fl.errAllow(errorSelector, allowedErrors, BOND_116);
    }

    function invariant_BOND_117(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_117);
    }

    function invariant_BOND_118(bytes4 errorSelector) internal {
        bytes4[] memory allowedErrors = new bytes4[](0);
        fl.errAllow(errorSelector, allowedErrors, BOND_118);
    }

    function _assertBondInputWritten(uint8 version, BondInput memory input, string memory description) internal {
        fl.eq(states[1].bondVersionStates[version].issuer, input.issuer, description);
        fl.eq(states[1].bondVersionStates[version].currency == bytes3(bytes(input.currency)), true, description);
        fl.eq(states[1].bondVersionStates[version].bondNominalValue, input.bondNominalValue, description);
        fl.eq(states[1].bondVersionStates[version].maxSupply, input.maxSupply, description);
        fl.eq(states[1].bondVersionStates[version].couponRateType, uint8(input.couponRateType), description);
        fl.eq(states[1].bondVersionStates[version].couponFrequency, uint8(input.couponFrequency), description);
        fl.eq(
            uint256(states[1].bondVersionStates[version].issuanceCountry), uint256(input.issuanceCountry), description
        );
        fl.eq(states[1].bondVersionStates[version].maturityDate, input.maturityDate, description);
        fl.eq(states[1].bondVersionStates[version].isGuaranteed, input.isGuaranteed, description);
        fl.eq(
            states[1].bondVersionStates[version].couponRatesHash
                == keccak256(abi.encode(input.couponRates.paymentTimestamps, input.couponRates.rates)),
            true,
            description
        );
    }

    function _assertScoringEqual(Scoring memory actual, Scoring memory expected, string memory description) private {
        fl.eq(uint256(actual.defaultProbabilityBps), uint256(expected.defaultProbabilityBps), description);
        fl.eq(uint256(actual.issueDate), uint256(expected.issueDate), description);
        fl.eq(uint256(actual.expirationDate), uint256(expected.expirationDate), description);
        fl.eq(actual.distributorId == expected.distributorId, true, description);
    }
}

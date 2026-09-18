// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FuzzEntityRegistryIntegrity} from "./FuzzEntityRegistryIntegrity.sol";
import {FuzzEscrowManagerIntegrity} from "./FuzzEscrowManagerIntegrity.sol";
import {FuzzAssetManagerIntegrity} from "./FuzzAssetManagerIntegrity.sol";
import {FuzzEscrowAuthIntegrity} from "./FuzzEscrowAuthIntegrity.sol";
import {FuzzDEUSSTokenIntegrity} from "./FuzzDEUSSTokenIntegrity.sol";
import {FuzzMarketplaceIntegrity} from "./FuzzMarketplaceIntegrity.sol";
import {FuzzOrderbookMarketplaceIntegrity} from "./FuzzOrderbookMarketplaceIntegrity.sol";
import {FuzzPolicyRegistryIntegrity} from "./FuzzPolicyRegistryIntegrity.sol";
import {FuzzBondRegistryIntegrity} from "./FuzzBondRegistryIntegrity.sol";
import {FuzzDEPIntegrity} from "./FuzzDEPIntegrity.sol";
import {FuzzWALLETIntegrity} from "./FuzzWALLETIntegrity.sol";
import {FuzzTLIntegrity} from "./FuzzTLIntegrity.sol";

/**
 * @title Fuzz
 * @notice Composite fuzz harness for Marketplace, EscrowManager, EntityRegistry, DEUSSToken, AssetManager, EscrowAuth, PolicyRegistry, and BondRegistry handlers
 */
contract Fuzz is
    FuzzMarketplaceIntegrity,
    FuzzOrderbookMarketplaceIntegrity,
    FuzzEscrowManagerIntegrity,
    FuzzEntityRegistryIntegrity,
    FuzzDEUSSTokenIntegrity,
    FuzzAssetManagerIntegrity,
    FuzzEscrowAuthIntegrity,
    FuzzPolicyRegistryIntegrity,
    FuzzBondRegistryIntegrity,
    FuzzDEPIntegrity,
    FuzzWALLETIntegrity,
    FuzzTLIntegrity
{
    /**
     * @notice Initializes the fuzz harness and shared actor state
     */
    constructor() payable {
        setup();
        setupActors();
        if (VALIDATE_FUZZ_SETUP) validateSetup();
    }
}

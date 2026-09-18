// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseFixture} from "./BaseFixture.t.sol";
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
import {Constants} from "../Constants.t.sol";

/**
 * @title SharedUtilities
 * @notice Common utility functions used across multiple fixtures
 * @dev This fixture provides reusable patterns to reduce code duplication
 */
contract SharedUtilities is BaseFixture {
    /**
     * @notice Setup bond registry with common roles
     * @param publisher The publisher address
     */
    function _setupBondRegistry(address publisher) internal {
        bytes memory data = abi.encodeWithSelector(BondRegistry.setMultiToken.selector, _tokenAddr);
        _timelockOp(_brAddr, data);

        uint256 brRoles = _br.PUBLISHER() | _br.CURRENCY();
        _grantRoles(_brAddr, publisher, brRoles);
    }

    /**
     * @notice Setup entity registry with admin
     * @param admin The admin address for the entity registry
     */
    function _setupEntityRegistry(address admin) internal {
        uint256 erRoles = _er.ADMIN_ROLE();
        _grantRoles(_erAddr, admin, erRoles);
    }

    /**
     * @notice Register bonds in the bond registry
     * @param publisher The publisher address
     */
    function _registerBonds(address publisher) internal {
        // Set allowed currencies
        vm.startPrank(publisher);
        _br.setAllowedCurrency(_bondFT.currency, true);

        // Publish a bond
        _br.publishBond(_bondFT);
        vm.stopPrank();
    }

    /**
     * @notice Create and setup a company wallet
     * @param company The company address
     * @param admin The admin address for the company wallet registry
     * @return companyWallet The created company wallet address
     */
    function _setupCompanyWallet(address company, address admin) internal returns (address companyWallet) {
        _setupEntityRegistry(admin);

        (companyWallet,) = _createAndRegisterEntityWalletForCompany(admin, company);
        vm.label(companyWallet, "CompanyWallet");

        return companyWallet;
    }

    /**
     * @notice Setup complete bond infrastructure
     * @param company The company address
     * @param publisher The publisher address
     * @param admin The admin address for the company wallet registry
     * @return companyWallet The created company wallet address
     */
    function _setupCompleteBondInfrastructure(address company, address publisher, address admin)
        internal
        returns (address companyWallet)
    {
        // Setup registries
        _br = BondRegistry(_brAddr);
        _er = EntityRegistry(_erAddr);

        // Setup company wallet
        companyWallet = _setupCompanyWallet(company, admin);

        // Setup bond registry
        _setupBondRegistry(publisher);

        // Register bonds
        _registerBonds(publisher);

        return companyWallet;
    }

    /**
     * @notice Create test users with wallets
     * @param userNames Array of user names
     * @param walletsPerUser Number of wallets per user
     */
    function _createTestUsers(string[] memory userNames, uint256 walletsPerUser) internal {
        for (uint256 i; i < userNames.length; ++i) {
            address[] memory wallets = _createAddresses(userNames[i], walletsPerUser);
            for (uint256 j; j < wallets.length; ++j) {
                vm.label(wallets[j], string(abi.encodePacked(userNames[i], "Wallet", _toString(j + 1))));
            }
        }
    }

    /**
     * @notice Grant roles to an address using a role mask
     * @param target The contract address
     * @param user The user to grant roles to
     * @param roles The roles to grant
     */
    function _grantRoles(address target, address user, uint256 roles) internal {
        (bool success, bytes memory result) =
            target.staticcall(abi.encodeWithSignature("hasAllRoles(address,uint256)", user, roles));
        if (success && result.length == 32 && abi.decode(result, (bool))) {
            return;
        }

        bytes memory data = abi.encodeWithSignature("grantRoles(address,uint256)", user, roles);
        _timelockOp(target, data);
    }

    /**
     * @notice Schedule and execute a TimelockController operation in a single call.
     * @param target Contract to call
     * @param data Encoded calldata to execute
     */
    function _timelockOp(address target, bytes memory data) internal {
        _timelockSchedule(target, data);
        _timelockExecute(target, data);
    }

    /**
     * @notice Schedule a TimelockController operation.
     * @param target Contract to call
     * @param data Encoded calldata to execute
     */
    function _timelockSchedule(address target, bytes memory data) internal {
        vm.prank(_timelockControllerActor);
        TimelockController(_timelockController)
            .schedule(
                target,
                0,
                data,
                bytes32(0),
                Constants.TIMELOCK_CONTROLLER_OP_SALT,
                Constants.TIMELOCK_CONTROLLER_MIN_DELAY
            );

        vm.warp(block.timestamp + Constants.TIMELOCK_CONTROLLER_MIN_DELAY);
    }

    /**
     * @notice Execute a previously scheduled TimelockController operation.
     * @param target Contract to call
     * @param data Encoded calldata to execute
     */
    function _timelockExecute(address target, bytes memory data) internal {
        vm.prank(_timelockControllerActor);
        TimelockController(_timelockController)
            .execute(target, 0, data, bytes32(0), Constants.TIMELOCK_CONTROLLER_OP_SALT);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title ProtocolAddresses
 * @author DEUSS Team
 * @notice Shared storage for protocol actor addresses. Inherited by SetupEBSIInfrastructure
 *         so that DeployProtocol and BootstrapBase operate on the same storage slot when
 *         combined in DeployBootstrapHarness (diamond inheritance).
 */
abstract contract ProtocolAddresses {
    /// @notice Deployer address derived from the active network config
    address public deployer;

    /// @notice Admin account granted privileged roles across deployed contracts
    address public admin;

    /// @notice Admin address derived from the active network config
    address public timelockControllerAdmin;

    /// @notice Account granted PROPOSER and EXECUTOR roles on the TimelockController
    address public timelockControllerActor;

    /// @notice Deployed TimelockController proxy address
    address payable public timelockController;
}

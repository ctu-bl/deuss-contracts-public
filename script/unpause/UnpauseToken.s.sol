// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {DeploymentArtifacts} from "../lib/DeploymentArtifacts.s.sol";
import {IBaseToken} from "src/token/base/IBaseToken.sol";

/**
 * @title UnpauseToken
 * @author DEUSS Team
 * @notice Script to unpause the DEUSSToken contract
 * @dev Reads the token address from the deployment manifest and calls unpause().
 *      Safe to rerun — paused() is checked before calling unpause().
 */
contract UnpauseToken is DeploymentArtifacts {
    /**
     * @notice Unpause the token contract
     * @dev Caller must hold the governance key configured for this network.
     */
    function run() public {
        string memory json = _readManifest();
        // solhint-disable-next-line gas-small-strings
        address token = abi.decode(vm.parseJson(json, ".multiToken.deussToken.contractAddress"), (address));

        vm.startBroadcast(_activeNetworkConfig.deployerKey);
        if (IBaseToken(token).paused()) {
            IBaseToken(token).unpause();
        }
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {DeploymentFixture} from "./DeploymentFixture.t.sol";
import {OwnableRolesExtension} from "src/utils/OwnableRolesExtension.sol";

contract OwnableRolesExtensionFixture is DeploymentFixture, OwnableRolesExtension {
    uint256 public constant SOME_ROLE = _ROLE_0;

    function setUp() public virtual override {
        super.setUp();
        _initializeOwner(msg.sender);
    }
}

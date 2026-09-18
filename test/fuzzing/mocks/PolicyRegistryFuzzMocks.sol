// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPolicyModule} from "src/registry/interfaces/IPolicyModule.sol";

/**
 * @notice Minimal call target deployed by the PolicyRegistry fuzz harness.
 * @dev Tracks state mutations so postconditions can verify that CompanyWallet.execute
 *      correctly forwards calls and that unauthorized callers are blocked.
 */
contract FuzzPolicyTarget {
    bool public flag;
    uint256 public number;
    uint256 public callCount;
    address public lastCaller;
    uint256 public lastValue;

    function setFlag(bool flag_) external payable {
        flag = flag_;
        _recordCall();
    }

    function setNumber(uint256 number_) external payable {
        number = number_;
        _recordCall();
    }

    function _recordCall() internal {
        ++callCount;
        lastCaller = msg.sender;
        lastValue = msg.value;
    }
}

/**
 * @notice Configurable IPolicyModule stub used by the fuzz harness.
 * @dev Constructed with a fixed allow/revert flag so the harness can exercise
 *      the allow, deny, and reverting module branches without extra deployments.
 */
contract FuzzPolicyModule is IPolicyModule {
    error FuzzPolicyModule__Denied();

    bool internal immutable _allow;
    bool internal immutable _revertOnCall;

    constructor(bool allow_, bool revertOnCall_) {
        _allow = allow_;
        _revertOnCall = revertOnCall_;
    }

    function canExecute(address, address, address, uint256, bytes calldata) external view returns (bool) {
        if (_revertOnCall) {
            revert FuzzPolicyModule__Denied();
        }
        return _allow;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPolicyModule).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @notice IPolicyModule stub that returns fewer than 32 bytes.
 * @dev Used to exercise the bad-return-data branch in PolicyRegistry._checkOperationModule,
 *      where `returnData.length != 32` causes the module call to be treated as failed.
 */
contract FuzzInvalidReturnPolicyModule is IPolicyModule {
    function canExecute(address, address, address, uint256, bytes calldata) external pure returns (bool) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x00, 0x01)
            return(0x1f, 0x01)
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPolicyModule).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

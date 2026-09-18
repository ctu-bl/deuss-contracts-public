// SPDX-License-Identifier: MIT
/* solhint-disable one-contract-per-file */
pragma solidity 0.8.34;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// implementations
import {CompanyWallet} from "src/wallet/CompanyWallet.sol";
import {EscrowManager} from "src/marketplace/EscrowManager.sol";
import {DEUSSToken} from "src/token/fungible/DEUSSToken.sol";
import {Marketplace} from "src/marketplace/Marketplace.sol";
import {OrderbookMarketplace} from "src/marketplace/OrderbookMarketplace.sol";
import {TimelockController} from "src/governance/TimelockController.sol";
// registry
import {BondRegistry} from "src/registry/BondRegistry.sol";
import {BondInput} from "src/registry/BondStructs.sol";
import {EntityRegistry} from "src/registry/EntityRegistry.sol";
import {IPolicyModule} from "src/registry/interfaces/IPolicyModule.sol";
import {PolicyRegistry} from "src/registry/PolicyRegistry.sol";
// validator
import {IAssetValidator} from "src/marketplace/interfaces/IAssetValidator.sol";

// helpers
import {NewVersion} from "./NewVersion.sol";

/* solhint-disable no-empty-blocks */
// factories

/**
 * @dev Mock ProxyFactory that returns zero address for testing
 */
contract MockZeroAddressProxyFactory {
    address private immutable _templateRegistry;

    constructor(address templateRegistry_) {
        _templateRegistry = templateRegistry_;
    }

    function templateRegistry() external view returns (address) {
        return _templateRegistry;
    }

    // solhint-disable-next-line no-unused-vars
    function deployProxy(
        string calldata, /* templateName */
        string calldata, /* templateVersion */
        bytes calldata, /* initData */
        string calldata /* issuerDID */
    )
        external
        pure
        returns (address)
    {
        return address(0);
    }
}

/**
 * @dev Malicious ProxyFactory that attempts reentrancy attack during deployProxy call
 */
abstract contract MockMaliciousProxyFactory {
    bool internal _useLowLevelCall;
    address internal immutable _templateRegistry;

    constructor(bool useLowLevelCall, address templateRegistry_) {
        _useLowLevelCall = useLowLevelCall;
        _templateRegistry = templateRegistry_;
    }

    function templateRegistry() external view returns (address) {
        return _templateRegistry;
    }

    // solhint-disable-next-line no-unused-vars
    function deployProxy(
        string calldata, /* templateName */
        string calldata, /* templateVersion */
        bytes calldata, /* initData */
        string calldata /* issuerDID */
    )
        external
        virtual
        returns (address);
}

/**
 * @dev Malicious ProxyFactory that attempts reentrancy attack during deployProxy call from BondRegistry
 */
contract MockMaliciousProxyFactoryBondRegistry is MockMaliciousProxyFactory {
    constructor(bool useLowLevelCall, address templateRegistry_)
        MockMaliciousProxyFactory(useLowLevelCall, templateRegistry_)
    {}

    // solhint-disable-next-line no-unused-vars
    function deployProxy(
        string calldata, /* templateName */
        string calldata, /* templateVersion */
        bytes calldata, /* initData */
        string calldata /* issuerDID */
    )
        external
        override
        returns (address)
    {
        BondInput memory fakeBond;
        fakeBond.isin = "SK0001002060";

        // Attempt reentrancy attack
        if (_useLowLevelCall) {
            // Use low-level call to avoid bubbling up the revert
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = msg.sender.call(abi.encodeWithSignature("publishBond(BondInput)", fakeBond));
            success;
            // Return zero address after attempted reentrancy
            return address(0);
        } else {
            // Direct call that will revert with ReentrancyGuard.Reentrancy
            BondRegistry(msg.sender).publishBond(fakeBond);
            return address(0);
        }
    }
}

/**
 * @dev Malicious ProxyFactory with specific role that properly tests reentrancy guard
 * @notice This factory will have the specific role granted, so it can bypass access control
 *         and actually trigger the ReentrancyGuard
 */
abstract contract MockMaliciousReentrantProxyFactory {
    address internal immutable _templateRegistry;
    address internal immutable _registry;

    constructor(address templateRegistry_, address registry_) {
        _templateRegistry = templateRegistry_;
        _registry = registry_;
    }

    function templateRegistry() external view returns (address) {
        return _templateRegistry;
    }

    // solhint-disable-next-line no-unused-vars
    function deployProxy(
        string calldata, /* templateName */
        string calldata, /* templateVersion */
        bytes calldata, /* initData */
        string calldata /* issuerDID */
    )
        external
        virtual
        returns (address);
}

/**
 * @dev Malicious ProxyFactory with REGISTER_ROLE that properly tests reentrancy guard in BondRegistry
 */
contract MockMaliciousReentrantProxyFactoryBondRegistry is MockMaliciousReentrantProxyFactory {
    constructor(address templateRegistry_, address registry_)
        MockMaliciousReentrantProxyFactory(templateRegistry_, registry_)
    {}

    // solhint-disable-next-line no-unused-vars
    function deployProxy(
        string calldata, /* templateName */
        string calldata, /* templateVersion */
        bytes calldata, /* initData */
        string calldata /* issuerDID */
    )
        external
        override
        returns (address)
    {
        BondInput memory fakeBond;
        fakeBond.isin = "SK0001002060";
        // Since this factory has PUBLISHER, the call will pass access control
        // and hit the reentrancy guard
        BondRegistry(_registry).publishBond(fakeBond);
        return address(0);
    }
}

// implementations
contract MockTimeController is TimelockController, NewVersion {}

contract MockBondRegistry is BondRegistry, NewVersion {}

contract MockEntityRegistry is EntityRegistry, NewVersion {}

contract MockCompanyWallet is CompanyWallet {}

contract MockEscrowManager is EscrowManager, NewVersion {}

contract MockDEUSSToken is DEUSSToken, NewVersion {}

contract MockDEUSSTokenContextHarness is DEUSSToken {
    function exposedMsgData() external view returns (bytes memory) {
        return _msgData();
    }

    function exposedContextSuffixLength() external view returns (uint256) {
        return _contextSuffixLength();
    }
}

contract MockMarketplace is Marketplace, NewVersion {}

contract MockOrderbookMarketplace is OrderbookMarketplace, NewVersion {}

contract MockPolicyRegistryV2 is PolicyRegistry, NewVersion {}

/**
 * @dev Configurable IAssetValidator mock for AssetManager tests
 */
contract MockAssetValidator is IAssetValidator {
    error MockAssetValidator__Rejected();

    bool public shouldRevert;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function validate(address, uint256, uint256) external view {
        if (shouldRevert) revert MockAssetValidator__Rejected();
    }
}

contract MockTargetContract is ERC1155 {
    bool public state;
    uint256 public receivedValue;

    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public {
        _mintBatch(to, ids, amounts, data);
    }

    function simulateSuccess(bool state_) external {
        state = state_;
    }

    function simulateFailure() external pure {
        // solhint-disable-next-line gas-custom-errors
        revert("External call failed");
    }

    function simulateSilentFailure() external pure {
        // solhint-disable-next-line no-inline-assembly
        assembly { revert(0, 0) }
    }

    function acceptEther() external payable {
        state = true;
        receivedValue += msg.value;
    }

    function acceptEtherThenRevert() external payable {
        state = true;
        receivedValue += msg.value;
        // solhint-disable-next-line gas-custom-errors
        revert("Reverted after receiving ETH");
    }
}

contract MockReentrantTarget {
    address public timelockAddr;
    address public reentrantTarget;
    bytes public reentrantPayload;
    bytes32 public reentrantPredecessor;
    bytes32 public reentrantSalt;

    bool private _reentryDone;

    function configure(address timelock_, address target_, bytes calldata payload_, bytes32 predecessor_, bytes32 salt_)
        external
    {
        timelockAddr = timelock_;
        reentrantTarget = target_;
        reentrantPayload = payload_;
        reentrantPredecessor = predecessor_;
        reentrantSalt = salt_;
    }

    // Called by timelock during execute; re-enters execute with same id on first call
    function attack() external {
        if (_reentryDone) return;
        _reentryDone = true;
        TimelockController(payable(timelockAddr))
            .execute(reentrantTarget, 0, reentrantPayload, reentrantPredecessor, reentrantSalt);
    }
}

contract MockPolicyModule is IPolicyModule {
    error MockPolicyModule__Denied();

    bool internal immutable _allow;
    bool internal immutable _revertOnCall;

    constructor(bool allow_, bool revertOnCall_) {
        _allow = allow_;
        _revertOnCall = revertOnCall_;
    }

    function canExecute(address, address, address, uint256, bytes calldata) external view returns (bool) {
        if (_revertOnCall) {
            revert MockPolicyModule__Denied();
        }
        return _allow;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPolicyModule).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

contract MockInvalidReturnPolicyModule is IPolicyModule {
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

/**
 * @title MockInitializable
 * @notice Simple mock contract for testing proxy deployment
 * @dev Minimal implementation with initialize function for ProxyDeployer tests
 */
contract MockInitializable {
    bool public initialized;
    address public owner;
    uint256 public value;

    event Initialized(address indexed owner, uint256 indexed value);

    /// @notice Prevents direct initialization of implementation
    constructor() {
        initialized = true;
    }

    /**
     * @notice Initialize the contract
     * @param owner_ The owner address
     * @param value_ A test value
     */
    function initialize(address owner_, uint256 value_) external {
        // solhint-disable-next-line gas-custom-errors
        require(!initialized, "Already initialized");

        owner = owner_;
        value = value_;
        initialized = true;

        emit Initialized(owner_, value_);
    }

    /**
     * @notice Simple getter for testing
     */
    function getData() external view returns (address, uint256, bool) {
        return (owner, value, initialized);
    }
}

/**
 * @title MockExecutionTarget
 * @notice Simple mock contract for testing entity onboarding flow
 * @dev Minimal stub used as the execute() target in delegation tests.
 *      Any caller may invoke it — authorization is checked by CompanyWallet,
 *      not by this target.
 */
contract MockExecutionTarget {
    bool public invoked;

    function operate() external {
        invoked = true;
    }
}

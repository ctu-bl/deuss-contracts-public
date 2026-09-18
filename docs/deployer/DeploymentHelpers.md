# Deployment Helpers Documentation

## Overview

The deployment helper contracts under `src/deployer/` provide deterministic deployment and EBSI proxy integration for the protocol deployment scripts. The operator-facing deployment flow is documented in [`deployment.md`](../deployment.md).

These contracts are not normal protocol entrypoints for users. They matter because they define how implementations, beacons, proxies, ownership, and EBSI template-based wallets are created during deployment.

## Create2Deployer

`Create2Deployer` is the shared internal helper for deterministic deployments.

**Core helpers:**
- `_deployImplementationViaCreate2`: Deploys implementation bytecode with optional constructor data
- `_deployBeaconViaCreate2`: Deploys an `UpgradeableBeacon` for an implementation and beacon owner
- `_deployBeaconProxyViaCreate2`: Deploys a `BeaconProxy` with initialization calldata
- `_prepareImplementationCreationCode`, `_prepareBeaconCreationCode`, `_prepareBeaconProxyCreationCode`: Build creation bytecode

**Important Notes:**
- String salts are hashed with `keccak256(abi.encodePacked(salt))`
- Deployments use OpenZeppelin `Create2.deploy`
- The helper emits `Deployed(address)` for each deployed contract

## Protocol Deployer Pattern

Domain deployers such as `AssetManagerDeployer`, `EscrowManagerDeployer`, `MarketplaceDeployer`, `OrderbookMarketplaceDeployer`, `BRDeployer`, `ERDeployer`, `PolicyRegistryDeployer`, `WalletFactoryDeployer`, and `TokenDeployer` follow the same pattern:

1. Deploy implementation via CREATE2
2. Deploy `UpgradeableBeacon`
3. Deploy `BeaconProxy`
4. Initialize the proxy with deployment-time owner and dependency arguments
5. Expose the deployed proxy address through an immutable public variable

Ownership is temporary during deployment/bootstrap and is later transferred to the configured governance owner or timelock by the deployment scripts.

`MarketplaceDeployer` receives its deployment and initializer inputs through `MarketplaceDeployParams`. This keeps the constructor stack small while preserving the same CREATE2 implementation/beacon/proxy flow and the same `Marketplace.initialize(...)` arguments.

## TimelockControllerDeployer

Deploys `TimelockController` implementation, beacon, and proxy via CREATE2. The proxy is initialized with:
- `initialMinDelay`
- `proposers`
- `executors`
- `initialAdmin`

After initialization, the deployer transfers the timelock beacon ownership to the deployed timelock controller so future beacon upgrades go through governance. Timelock operation flow is documented in [`TimelockController`](../governance/TimelockController.md).

## ProxyDeployer

`ProxyDeployer` is the shared helper for EBSI template-based proxy deployments.

Its mutable configuration (`factory`, `registry`, issuer DID, and template configs) uses ERC-7201 namespaced
storage so inheriting upgradeable contracts do not receive ordinary sequential parent slots from this helper.

**Core functions:**
- `setFactory(address factory)`: Sets and validates the EBSI proxy factory
- `setRegistry(address registry)`: Sets and validates the EBSI template registry
- `setDid(string calldata did)`: Stores the issuer DID used for proxy deployments
- `addTemplateConfig(string calldata name, string calldata version)`: Stores an active template configuration after checking the registry
- `deactivateTemplateConfig(bytes32 templateId)`: Soft-deactivates a stored template config
- `computeProxyAddress(...)`: Returns the deterministic factory-computed proxy address
- `_deployProxy(...)` / `_deployProxyWithSalt(...)`: Internal deployment helpers used by inheriting deployers

**Trust assumptions:**
- The configured factory and registry must be the intended EBSI infrastructure.
- Factory/registry wiring is validated when both are set.
- Template configs are trusted deployment inputs; stale or wrong template names/versions can deploy the wrong implementation.

## Operational Guidance

### CREATE2 salts

CREATE2 salts are deployment inputs, and `script/DeployConstants.sol` is the source of truth for their values. External network runbooks may reference the constants or list expected deterministic addresses derived from a specific commit, but they should not duplicate salt values as independent configuration unless the runbook has an explicit owner and update process.

Duplicating salts outside the repository can make deployment instructions stale. If `DeployConstants.sol`, deployment bytecode, constructor arguments, or deployer addresses change while an external runbook keeps old salt values, operators can verify against the wrong expected addresses or misdiagnose a valid deployment as incorrect.

### EBSI template additions

EBSI template mappings are not expected to rotate or update during normal operations. If a new wallet template is needed, the template must first be approved by the relevant EBSI trust-chain authority on the EBSI infrastructure side. After approval, protocol-side registration or mapping changes should be executed through the protocol timelock/governance path.

The deployer helper contracts define the low-level template configuration mechanism used during bootstrap. They are not the preferred production entrypoint after ownership has moved to governance. A future operator script may encode the timelock operation for adding a new template, but the authority model remains the same: EBSI trust-chain approval first, protocol timelock execution second.

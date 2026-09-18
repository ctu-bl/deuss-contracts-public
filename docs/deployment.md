# EBSI-Integrated Deployment Guide

## Overview

The deployment system has been refactored to support environment-based conditional deployment with proper separation of concerns. The operator-facing flow now runs in stages: deploy contracts, bootstrap protocol wiring, and optionally seed test data.

## Architecture

```
DeployConfig.s.sol (base configuration)
ProtocolAddresses.s.sol (shared actor addresses)
    ↓
SetupEBSIInfrastructure.s.sol (abstract, all EBSI logic)
    ├─ DeployProtocol.s.sol (deploy contracts + write manifest)
    │    ↓
    │  BootstrapBase.s.sol (abstract, all wiring logic)
    │    ↓
    │  BootstrapProtocol.s.sol (loads manifest, wires protocol)
    │    ↓
    │  SeedDemoData.s.sol (optional test data seed)
    ↓
DeployEBSI.s.sol (standalone EBSI deployment wrapper)
```

### Key Components

1. **`DeployConfig.s.sol`**

   - Network configuration management
   - EBSI configuration via `getEBSIConfig()`
   - Custom errors following `ContractName__RevertReason` pattern
   - Support for Anvil (default) and Besu networks

2. **`SetupEBSIInfrastructure.s.sol`** (Abstract Base)

   - Abstract base contract for EBSI functionality
   - Handles EBSI infrastructure deployment
   - Manages beacon deployment for `CompanyWallet`
   - Template registration in `ProxyTemplateRegistry`
   - WalletFactory integration with EBSI
   - JSON serialization for EBSI contracts

3. **`DeployProtocol.s.sol`** (Main Deployment)

   - Inherits from `SetupEBSIInfrastructure`
   - Orchestrates DEUSS suite deployment
   - Modular deployment functions for registries, token, core contracts, and utils
   - Writes deployment manifests to `./deployments/`
   - Leaves protocol wiring and role grants for bootstrap

4. **`BootstrapProtocol.s.sol`** (Bootstrap Stage)

   - Loads the latest usable deployment manifest
   - Initialises actor addresses from the active network config
   - Sets `timelockController` state variable from the loaded manifest
   - Applies idempotent protocol wiring and minimal environment setup
   - Sets up TimelockController roles (PROPOSER / EXECUTOR / CANCELLER for the actor)
   - Grants the standard governance/admin roles
   - Configures token, assets, currencies, and WalletFactory/EBSI bindings
   - Transfers protocol ownership to the TimelockController at the end of the flow

5. **`SeedDemoData.s.sol`** (Test Data Seed)

   - Single operator-facing entrypoint for development and demo data
   - Runs after bootstrap using the shared deployment manifest
   - Replaces the older individual mock-data scripts

6. **`DeployEBSI.s.sol`** (Standalone EBSI)

   - Thin wrapper around `SetupEBSIInfrastructure`
   - Used by `make deploy_ebsi` target
   - Standalone EBSI infrastructure deployment only

7. **`DeployConstants.sol`** (Constants Library)

   - Centralized constants for all deployment scripts
   - Network configuration constants
   - EBSI / wallet template configuration
   - CREATE2 deployment salts
   - Time-based constants

8. **`DeployTypes.sol`** (Type Definitions)
   - Struct definitions for all deployment data
   - EBSI configuration and contract structures
   - Network configuration types
   - Factory, registry, and core contract structures

## Script Organization

### Main Scripts (`script/`)

- **`deploy/DeployProtocol.s.sol`** - Main deployment script for the DEUSS suite (deploy only)
- **`bootstrap/BootstrapProtocol.s.sol`** - Bootstrap / wiring script driven by the latest manifest
- **`test_data/SeedDemoData.s.sol`** - Operator-facing test/demo data seed script
- **`lib/DeploymentArtifacts.s.sol`** - Shared manifest read/write/resolve helpers used by all scripts
- **`SetupEBSIInfrastructure.s.sol`** - Abstract base for EBSI functionality
- **`DeployEBSI.s.sol`** - Standalone EBSI deployment wrapper
- **`DeployConfig.s.sol`** - Configuration and network management
- **`DeployConstants.sol`** - Centralized constants library
- **`DeployTypes.sol`** - Type definitions and structs

### Role Management

The standard operator flow does not use standalone role-setting scripts. `BootstrapProtocol.s.sol` grants the default operational roles during bootstrap, and later changes must be executed by the current contract owner or timelock through the target contract's role or admin functions.

Most protocol contracts use `OwnableRolesExtension.grantRoles(...)` / `revokeRoles(...)` for owner-gated role changes. Contract-specific admin roles then manage runtime configuration such as marketplace thresholds, asset allowlists, module registrations, and entity type allowlists.

### Mock Data Scripts (`script/test_data/`)

Test data creation scripts for development and testing:

- **`BaseMockData.s.sol`** - Shared mock data helpers and datasets, including one deterministic issuer company wallet owner per seeded bond and three deterministic buyer wallet owners
- **`SeedDemoData.s.sol`** - Consolidated seed flow for wallets, currencies, bonds, issuer scoring records, offers, and marketplace deals

### Operational Scripts (`script/ops/`, `script/unpause/`)

- **`ops/GenerateBondTransferEvent.s.sol`** - Idempotent local Anvil helper that prepares a demo bond transfer scenario and emits an ERC-6909 `Transfer` event. The wrapped export workflow is documented in [`../tools/log-export.md`](../tools/log-export.md).
- **`UnpauseToken.s.sol`** - Owner/timelock-facing helper for unpausing the deployed ERC-6909 token from a deployment manifest.

### Constants and Configuration

**`DeployConstants.sol`** provides centralized constants:

- **Network Configuration**: Anvil and Besu network settings
- **EBSI Templates**: CompanyWallet template names, versions, and metadata
- **Repository URIs**: GitHub and audit report URLs
- **CREATE2 Salts**: Deterministic deployment salts for factories
- **Time Constants**: Validity periods and expiry thresholds for marketplace operations
- **EIP-1967 Slot**: Proxy implementation storage slot

Production timing defaults are also centralized there:

| Area | Setting | Default |
|---|---|---|
| Marketplace | Direct marketplace payment expiry | 4 days / 96 hours |
| Marketplace | Redemption payment expiry | 5 days / 120 hours |
| Marketplace | Interest-discovery payment expiry | 4 days / 96 hours |
| Marketplace | Minimum offer and counter-offer lifetime | 1 day / 24 hours |
| Marketplace | Dispute buffer period | 3 days / 72 hours |
| Orderbook | Payment expiry | 1 day / 24 hours |
| Orderbook | Minimum non-zero order expiry | 1 day / 24 hours |
| Orderbook | Dispute buffer period | 1 day / 24 hours |

The lower-level deployer helpers and CREATE2/beacon deployment pattern are documented in [`deployer/DeploymentHelpers.md`](deployer/DeploymentHelpers.md).

## Environment Variables

### Required Variables

Create a `.env` file based on the template below:

```bash
# Network Configuration
BESU_NETWORK_ID=1337
BESU_RPC_URL=http://localhost:8545
BESU_DEPLOYER_PRIVATE_KEY=0x...
BESU_ADMIN_PRIVATE_KEY=0x...
BESU_DEPLOY_ENV=dev
BESU_TIMELOCK_ADMIN_PRIVATE_KEY=0x...
BESU_TIMELOCK_ACTOR_PRIVATE_KEY=0x...

# Timelock Configuration (optional, defaults to 1 day)
# Set to 0 for testnet deployments where you don't want to wait for the delay
# PRODUCTION: never use 0 — a zero-delay timelock defeats governance entirely
# See the launch gates in docs/security/operational-model.md
TIMELOCK_MIN_DELAY=0

# EBSI Configuration
DEPLOY_EBSI=true  # true=deploy EBSI, false=connect to existing

# Required when DEPLOY_EBSI=false
EBSI_PROXY_FACTORY=
EBSI_PROXY_REGISTRY=
EBSI_DID_BOND_REGISTRY=did:ebsi:bond-registry
EBSI_DID_ENTITY_REGISTRY=did:ebsi:entity-registry

# Beacon Configuration (optional)
DEPLOY_BEACONS=true  # true=deploy new, false=use existing
BEACON_CW=  # Required if DEPLOY_BEACONS=false

# Bootstrap Configuration (optional, defaults apply when absent)
BOOTSTRAP_UNPAUSE_TOKEN=true           # Unpause the token after bootstrap
BOOTSTRAP_ALLOWED_CURRENCIES=EUR       # Comma-separated currency codes to allowlist
BOOTSTRAP_REGISTER_ESCROW_ENTITY=true  # Register EscrowManager as a protocol entity
BOOTSTRAP_COMPANY_ENTITY_NAME=COMPANY  # Entity type name for COMPANY_ENTITY
BOOTSTRAP_COMPANY_ENTITY_CAPS=0        # Entity capability bitmask
```

**Note:** Despite the variable name, `EBSI_DID_BOND_REGISTRY` is currently used as the existing DID registry address when `DEPLOY_EBSI=false`.

## Deployment Scenarios

### Scenario 1: Own Testnet (Full Deployment)

Deploy everything including EBSI infrastructure.

```bash
# Set environment
export DEPLOY_EBSI=true

# Run deployment
make setup_full

# Or simply
make setup
```

**What happens:**

1. Deploys complete EBSI infrastructure (PolicyRegistry, DidRegistry, ProxyFactory, etc.)
2. Deploys the CompanyWallet beacon
3. Registers the CompanyWallet template in `ProxyTemplateRegistry`
4. Runs `DeployProtocol.s.sol` to deploy the DEUSS suite (registries, token, marketplace modules, utils)
5. Writes deployment artifacts to `./deployments/`
6. Runs `BootstrapProtocol.s.sol` to wire protocol dependencies, grant roles, configure token/assets, and connect WalletFactory to EBSI
7. Does not seed demo data unless you use `make setup_full_test_data` or `make setup_test_data`

### Scenario 2: EBSI Chain (Existing Infrastructure)

Connect to existing EBSI contracts.

```bash
# Set environment
export DEPLOY_EBSI=false
export EBSI_PROXY_FACTORY=0x...
export EBSI_PROXY_REGISTRY=0x...
export EBSI_DID_BOND_REGISTRY=0x...

# Run deployment
make setup_ebsi_existing
```

**What happens:**

1. Loads existing EBSI infrastructure addresses
2. Deploys or loads the CompanyWallet beacon, depending on `DEPLOY_BEACONS`
3. Registers the CompanyWallet template in the existing `ProxyTemplateRegistry`
4. Runs `DeployProtocol.s.sol` to deploy the DEUSS suite
5. Runs `BootstrapProtocol.s.sol` to wire the protocol, grant roles, configure token/assets, and connect WalletFactory to the existing EBSI/core modules
6. Uses `make setup_ebsi_existing_test_data` if demo data is needed

## Existing Deployments

For already deployed environments that have not yet handed ownership to the TimelockController, you can rerun the bootstrap stage against the existing deployment manifest to apply the current wiring flow:

```bash
make bootstrap
```

After bootstrap has transferred ownership to the TimelockController, owner-gated bootstrap steps can no longer be rerun with the deployer key alone. Run `make mock_data` only when you need development/demo data on an already bootstrapped environment.

### Scenario 3: Reuse Existing Beacons

Useful for upgrades or testing without redeploying the CompanyWallet beacon.

```bash
# Set environment
export DEPLOY_EBSI=true  # or false
export DEPLOY_BEACONS=false
export BEACON_CW=0x...

# Run deployment
make setup
```

## Makefile Targets

### Main Targets

- **`make setup`** - Standard deployment (`make deploy` + `make bootstrap`)
- **`make setup_full`** - Explicit full deployment with EBSI infrastructure
- **`make setup_ebsi_existing`** - Deploy to existing EBSI (validates env vars)
- **`make setup_test_data`** - Standard deployment plus test data seed

### Component Targets

- **`make deploy`** - Deploy DEUSS contracts only (via `script/deploy/DeployProtocol.s.sol`)
- **`make bootstrap`** - Apply protocol wiring, default role grants, and transfer ownership to the TimelockController (via `script/bootstrap/BootstrapProtocol.s.sol`)
- **`make deploy_ebsi`** - Deploy EBSI infrastructure only (via `DeployEBSI.s.sol`)
- **`make mock_data`** - Run test data seed against an already bootstrapped deployment (via `script/test_data/SeedDemoData.s.sol`)
- **`make generate_bond_transfer_event`** - Run the local transfer-event generator against an already deployed and bootstrapped Anvil network (via `script/ops/GenerateBondTransferEvent.s.sol`)
- **`make verify_contracts`** - Verify already-deployed contracts using existing broadcast files (retryable, no redeployment)

### Role Management

There is no `set_roles` Make target in the current workflow. `BootstrapProtocol.s.sol` grants the default operational roles automatically. Later role changes are contract-owner/timelock operations against the deployed contracts.

The relevant role surfaces are documented in [`roles.md`](roles.md). Production operations should respect the active timelock delay for the current owner before calling owner-gated role functions.

> **Production warning.** `BootstrapProtocol.s.sol` grants the default operational role
> bundles to a single admin actor and, on testnets, may run with `TIMELOCK_MIN_DELAY=0`.
> This is **not a production-safe role/ownership layout**. Before opening to users, run
> the launch gates in the [operational model](security/operational-model.md): non-zero
> timelock delay, owners transferred to a governance multisig behind the timelock,
> critical roles split across distinct signers/services matched to their latency and
> blast radius (notably fast `FREEZE_ROLE` separate from governed `SEIZURE_ROLE`,
> `FORCE_TRANSFER_ROLE` assigned to `TimelockController`, and `WALLET_TRANSFER`
> multisig-controlled with timelock where viable), and deployment manifests reconciled
> against the recommended role/owner model.

### Mock Data Scripts

The `mock_data` target runs the consolidated test data flow against an already bootstrapped deployment. The `setup_test_data`, `setup_full_test_data`, and `setup_ebsi_existing_test_data` targets run deployment/bootstrap plus the same seed flow.

- **`BaseMockData.s.sol`** - Shared helpers and datasets, including per-bond issuer indexes and per-deal buyer indexes
- **`SeedDemoData.s.sol`** - Creates test wallets, currencies, bonds, issuer scoring records, offers, pending deals, paid deals, and settled successful deals

## Custom Errors

All validation errors follow the pattern `ContractName__RevertReason`:

### DeployConfig Errors

- `DeployConfig__EBSIProxyFactoryNotSet()` - EBSI_PROXY_FACTORY not configured
- `DeployConfig__EBSIProxyRegistryNotSet()` - EBSI_PROXY_REGISTRY not configured
- `DeployConfig__EBSIDidRegistryNotSet()` - EBSI_DID_BOND_REGISTRY not configured
- `DeployConfig__BeaconCWNotSet()` - BEACON_CW not configured

## Deployment Flow

### Complete Flow Diagram

```
1. Read Environment Config (DeployConfig.s.sol)
   ├─ getNetworkConfig() - Load network settings
   ├─ getEBSIConfig() - Load EBSI configuration
   └─ Validate required variables

2. Setup EBSI (SetupEBSIInfrastructure.s.sol)
   ├─ Deploy or Load EBSI Infrastructure
   │  ├─ If DEPLOY_EBSI=true
   │  │  ├─ Deploy PolicyRegistry
   │  │  ├─ Deploy DidRegistry
   │  │  ├─ Deploy ProxyTemplateRegistry
   │  │  ├─ Deploy ProxyFactory
   │  │  └─ Deploy Tir
   │  └─ If DEPLOY_EBSI=false
   │     └─ Load from environment variables
   │
   ├─ Deploy or Load Beacons
   │  ├─ If DEPLOY_BEACONS=true
   │  │  ├─ Deploy CompanyWallet implementation
   │  │  └─ Deploy CompanyWallet UpgradeableBeacon
   │  └─ If DEPLOY_BEACONS=false
   │     └─ Load CompanyWallet beacon from environment variables
   │
   └─ Register Templates in ProxyTemplateRegistry
      └─ Register CompanyWallet template

3. Deploy DEUSS Contracts (DeployProtocol.s.sol)
   ├─ Deploy Registries
   │  ├─ BondRegistry (via BRDeployer)
   │  ├─ EntityRegistry (via ERDeployer)
   │  ├─ PolicyRegistry (via PolicyRegistryDeployer)
   │  └─ WalletFactory (standalone deployment, configured later in bootstrap)
   │
   ├─ Deploy Core Contracts
   │  ├─ AssetManager (via AssetManagerDeployer)
   │  ├─ Marketplace (via MarketplaceDeployer, initialized with EntityRegistry)
   │  ├─ OrderbookMarketplace (via OrderbookMarketplaceDeployer)
   │  └─ EscrowManager (via EscrowManagerDeployer)
   │
   ├─ Deploy Token
   │  └─ ERC-6909 token proxy (via TokenDeployer)
   │     └─ initialize(..., EscrowManager) atomically protects EscrowManager custody
   │
   └─ Deploy Utils
      ├─ Multicall3
      └─ MarketplaceLens

4. Save Deployment JSON
   ├─ Serialize all contract addresses
   ├─ Include EBSI contracts and CompanyWallet beacon
   ├─ Include MarketplaceLens proxy, beacon, and implementation
   ├─ Write to ./deployments/{chainId}_{env}_latest.json
   └─ Write block snapshot to ./deployments/{chainId}_{env}_{block}.json

> **Utility ownership note.** `MarketplaceLens` is read-only, but it is deployed as an
> upgradeable beacon proxy. The deployment manifest stores its proxy, beacon, and
> implementation so bootstrap can transfer both proxy and beacon ownership to
> `TimelockController` with the rest of the protocol-owned surface.

5. Bootstrap Protocol (BootstrapProtocol.s.sol)
   ├─ Load latest usable deployment manifest
   ├─ Set timelockController from manifest
   ├─ Set up TimelockController roles (PROPOSER / EXECUTOR / CANCELLER → timelockControllerActor)
   ├─ Wire core dependencies
   │  └─ Marketplace receives EntityRegistry during deployment; bootstrap wires the remaining core dependencies
   ├─ Grant EntityRegistry roles → admin (ADMIN_ROLE | ONBOARDING | GUARD | ...)
   ├─ Grant BondRegistry operational roles → admin (PUBLISHER | CANCEL | CLOSE | SCORING | ...)
   ├─ Grant BondRegistry critical recovery role → TimelockController (ISSUER_RECOVERY)
   ├─ Leave BondRegistry BURNER unset
   ├─ Grant marketplace operational roles → admin (ADMIN | PAYMENT_HANDLER | ARBITRATOR | FREEZE_ROLE | ...)
   ├─ Grant marketplace seizure roles → TimelockController (SEIZURE_ROLE)
   ├─ Wire WalletFactory to EBSI
   │  ├─ Grant TRUSTED_ISSUER_ROLE to WalletFactory
   │  ├─ setFactory(proxyFactory)
   │  ├─ setRegistry(proxyTemplateRegistry)
   │  ├─ setDid(entityRegistryDID)
   │  └─ setWalletTemplateForType(COMPANY_WALLET_TYPE, ...)
   │
   ├─ Configure token and assets
   │  ├─ setMultiToken(erc6909)
   │  │  └─ one-time BondRegistry token wiring; later calls revert after the lock is set
   │  ├─ grant FORCE_TRANSFER_ROLE → TimelockController
   │  ├─ optionally unpause token
   │  ├─ AssetManager.setAsset(erc6909, ERC6909, true, false)
   │  └─ EscrowManager custody is already protected by DEUSSToken initialization
   │
   └─ Ensure baseline entity types, currencies, escrow entity, and timelock protocol entity

6. Mock Data (test_data/ folder, optional)
   ├─ BaseMockData.s.sol
   └─ SeedDemoData.s.sol
      ├─ Ensure company wallets
      │  ├─ registerEntity → adminKey (ONBOARDING role)
      │  ├─ setEntityStatus → adminKey (GUARD role)
      │  ├─ setEntityAuthority / setEntityManager → adminKey (ADMIN_ROLE path)
      │  └─ createWallet / registerAccount → adminKey (ADMIN_ROLE; immediate bootstrap path)
      ├─ Ensure currencies → adminKey (CURRENCY role)
      ├─ Publish test bonds → adminKey (PUBLISHER role)
      ├─ Append issuer scoring records → adminKey (SCORING role)
      ├─ Issue / cancel test bonds → adminKey (PUBLISHER / CANCEL role)
      └─ Seed marketplace and orderbook offers / deals
         ├─ Marketplace.resolvePayment → adminKey (PAYMENT_HANDLER role)
         └─ OrderbookMarketplace.markTradePaid → adminKey (PAYMENT_HANDLER role)
```

## Output JSON Structure

The deployment creates a comprehensive JSON file with all addresses:

```json
{
  "governance": {
    "TimelockController": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    }
  },
  "core": {
    "AssetManager": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "EscrowManager": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "Marketplace": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "OrderbookMarketplace": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    }
  },
  "registries": {
    "BondRegistry": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "EntityRegistry": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "PolicyRegistry": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    },
    "WalletFactory": {
      "contractAddress": "0x...",
      "beaconAddress": "0x..."
    }
  },
  "wallet": {
    "CompanyWallet": {
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    }
  },
  "multiToken": {
    "deussToken": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    }
  },
  "utils": {
    "Multicall3": {
      "contractAddress": "0x..."
    },
    "MarketplaceLens": {
      "contractAddress": "0x...",
      "beaconAddress": "0x...",
      "implementationAddress": "0x..."
    }
  },
  "ebsi": {
    "DidRegistry": {
      "contractAddress": "0x..."
    },
    "ProxyTemplateRegistry": {
      "contractAddress": "0x..."
    },
    "ProxyFactory": {
      "contractAddress": "0x..."
    },
    "PolicyRegistry": {
      "contractAddress": "0x..."
    },
    "Tir": {
      "contractAddress": "0x..."
    }
  }
}
```

## Testing the Deployment

### Verify Environment Configuration

```bash
# Check environment variables
echo $DEPLOY_EBSI
echo $EBSI_PROXY_FACTORY
```

### Test Scenarios

1. **Local Anvil (Full)**

   ```bash
   # Start anvil
   anvil

   # In another terminal
   make setup_full
   ```

2. **Besu Testnet (Full)**

   ```bash
   # Ensure .env is configured with Besu settings
   make setup_full NETWORK=besu
   ```

3. **EBSI Chain (Existing Infrastructure)**
   ```bash
   # Configure EBSI addresses in .env
   make setup_ebsi_existing
   ```

## Troubleshooting

### Error: EBSI addresses not set

**Problem:** Running `setup_ebsi_existing` without configuring EBSI addresses

**Solution:**

```bash
export EBSI_PROXY_FACTORY=0x...
export EBSI_PROXY_REGISTRY=0x...
export EBSI_DID_BOND_REGISTRY=0x...
```

### Error: DeployConfig__EBSIProxyFactoryNotSet

**Problem:** `DEPLOY_EBSI=false` but EBSI addresses not configured

**Solution:** Set all required EBSI environment variables

### Error: Template already exists

**Problem:** Trying to register the CompanyWallet template when it already exists in `ProxyTemplateRegistry`

**Solution:** This is expected behavior - templates persist in the registry. Either:

1. Use existing templates (don't redeploy EBSI)
2. Deploy to a fresh chain/network

### Error: Bootstrap fails

**Problem:** `BootstrapProtocol.s.sol` or `SeedDemoData.s.sol` cannot find a usable deployment manifest

**Solution:** Ensure deployment completed successfully and the JSON file exists at `./deployments/{chainId}_{env}_latest.json`

### Error: Mock data scripts fail

**Problem:** `SeedDemoData.s.sol` fails due to missing bootstrap state or permissions

**Solution:**

1. Ensure contracts were deployed successfully
2. Run `make bootstrap` before `make mock_data`
3. Do not rerun `make bootstrap` after ownership has already been transferred unless the current owner/timelock is performing the owner-gated calls
4. Verify environment variables are set correctly

## Best Practices

1. **Use environment files** - Keep separate `.env.dev`, `.env.demo`, `.env.prod`
2. **Never commit private keys** - Always use `.env` (gitignored)
3. **Verify addresses** - Double-check EBSI addresses before deployment
4. **Test locally first** - Always test on Anvil before deploying to testnets
5. **Save deployment artifacts** - Keep JSON outputs for future reference
6. **Document custom DIDs** - Track which DIDs are used for which contracts

## Migration from Old System

If migrating from the old deployment system:

1. **Environment variables** - Add the current EBSI-related variables to `.env`
2. **Makefile** - Use `setup`, `bootstrap`, `mock_data`, `setup_test_data`, `setup_full`, or `setup_ebsi_existing` depending on the environment
3. **Scripts** - Individual mock-data scripts have been consolidated into `SeedDemoData.s.sol`
4. **Roles** - Default operational role grants are now part of bootstrap
5. **Constants** - All hardcoded constants are centralized in `DeployConstants.sol`
6. **Types** - All deployment structs are defined in `DeployTypes.sol`

### Key Changes from Previous Versions

- **`DeployDEUSSSuite.s.sol`** → **`DeployProtocol.s.sol` + `BootstrapProtocol.s.sol`** for the standard operator flow
- **Individual mock-data scripts** → **`SeedDemoData.s.sol`** (consolidated seed flow)
- **`EBSIDeploymentBase.s.sol`** → **`SetupEBSIInfrastructure.s.sol`** (renamed for clarity)
- **Constants extraction** - All constants moved to `DeployConstants.sol`
- **Type definitions** - All structs moved to `DeployTypes.sol`
- **JSON structure** - Updated to reflect current deployment output format

## Support

For issues or questions:

1. Check this guide
2. Verify environment configuration
3. Review linter errors: `make lint`
4. Check deployment logs in terminal output

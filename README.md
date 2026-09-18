# DEUSS Smart Contracts

Smart contracts for **DEUSS (Decentralised EU Securities Service)**, an initiative led by the **Czech Technical University in Prague**. DEUSS develops shared infrastructure connecting financial intermediaries and their issuer and investor networks for SME bond issuance, distribution, and secondary trading across Europe.

Visit [deussblockchain.eu](https://deussblockchain.eu/) for the project overview and participation information.

This repository contains the Solidity implementation of the on-chain protocol: bond and entity registries, ERC-6909 tokens, marketplaces, settlement and escrow components, company wallets, and governance. It also includes deployment scripts, Foundry tests, and stateful fuzzing harnesses.

## Protocol components

| Component | Purpose |
| --- | --- |
| [BondRegistry](docs/registry/BondRegistry.md) | Bond publication, issuance, and lifecycle management. |
| [EntityRegistry](docs/registry/EntityRegistry.md) | Entity records, account registration, and entity authorization. |
| [DEUSSToken](docs/token/DEUSSToken.md) | ERC-6909 multi-token implementation for bond assets. |
| [Marketplace](docs/marketplace/Marketplace.md) and [OrderbookMarketplace](docs/marketplace/OrderbookMarketplace.md) | Marketplace offers and orderbook-based trading. |
| [AssetManager](docs/marketplace/AssetManager.md) and [EscrowManager](docs/marketplace/EscrowManager.md) | Asset custody and escrow workflows. |
| [CompanyWallet](docs/wallet/CompanyWallet.md), [WalletFactory](docs/wallet/WalletFactory.md), and [PolicyRegistry](docs/registry/PolicyRegistry.md) | Company wallet deployment and policy-controlled execution. |
| [TimelockController](docs/governance/TimelockController.md) | Timelocked governance operations. |

## Getting started

### Requirements

- Foundry **v1.7.0**; check the active version with `forge --version`.
- Git for cloning the repository and fetching dependencies.
- Node.js and npm for the repository's linting and analysis command wrappers.

The Foundry configuration selects **Solidity 0.8.34** and the **Cancun** EVM target. Dependencies and their versions are defined in [foundry.toml](foundry.toml).

**EBSI dependency:** installation fetches `ebsi-infrastructure-contracts` version `0.0.3` from the project's GitLab instance. Access to this GitHub repository alone does not grant access to that dependency; configure GitLab authentication if required before running `forge soldeer install`.

### Install and build

With Foundry installed:

```bash
git clone https://github.com/ctu-bl/deuss-contracts-public.git
cd deuss-contracts-public

foundryup -i v1.7.0
forge --version
forge soldeer install
npm ci
forge build
```

## Tests and analysis

Run these commands from the repository root after installing dependencies:

| Command | Purpose |
| --- | --- |
| `forge test` | Run the Foundry test suites. |
| `npm run coverage` | Generate coverage summary and LCOV output. |
| `npm run lint-all` | Lint Solidity contracts, tests, and scripts. |
| `npm run slither-debug` | Run the local Slither analysis command. |
| `npm run mythril-fast` | Run a shorter Mythril symbolic-execution pass. |
| `npm run mythril` | Run the configured Mythril analysis targets. |

Slither and Mythril require separate tool installations. See the [static-analysis guide](docs/security/static-analysis.md) for setup, triage, and the GitLab CI gate policy. The local Slither command is configured not to fail on findings; a successful exit alone does not establish that the analysis found no issues. The included GitLab pipeline configuration does not automatically configure GitHub Actions or scheduled scans.

For Echidna and Medusa prerequisites, commands, and harness coverage, see the [fuzzing README](test/fuzzing/README.md), [invariant validation ledger](test/fuzzing/INVARIANT_VALIDATION.md), and [fuzzing documentation](docs/fuzzing/).

## Deployment

Deployment runs in separate stages: contract deployment, protocol bootstrap and role wiring, and optional demo-data seeding. Follow the [deployment guide](docs/deployment.md) for Anvil, Besu, existing EBSI infrastructure, environment variables, and deployment manifests.

Use [.env.example](.env.example) as the configuration reference. Review the [roles overview](docs/roles.md) and [operational model](docs/security/operational-model.md) before configuring a deployment.

## Repository layout

- [`src/`](src/) — protocol contracts, interfaces, and shared libraries.
- [`test/`](test/) — Foundry suites, fixtures, mocks, and fuzzing harnesses.
- [`script/`](script/) — deployment, bootstrap, demo-data, and operational scripts.
- [`docs/`](docs/) — architecture, contract behavior, deployment, and security documentation.
- [`tools/`](tools/) — analysis, fuzzing, export, and local tooling.

## Documentation

Start with the documentation included alongside this version of the contracts:

- [Deployment guide](docs/deployment.md)
- [Roles and permissions](docs/roles.md)
- [Operational model](docs/security/operational-model.md)
- [Threat model](docs/security/threat-model.md)
- [Wallet operational modes](docs/security/wallet-operational-modes.md)
- [Static-analysis policy](docs/security/static-analysis.md)
- [Security development lifecycle](docs/security/sdlc.md)

Contract-specific guides and sequence diagrams are organized under [docs/](docs/).

## Resources

- [DEUSS project website](https://deussblockchain.eu/)
- [ERC-6909: Minimal Multi-Token Interface](https://eips.ethereum.org/EIPS/eip-6909)

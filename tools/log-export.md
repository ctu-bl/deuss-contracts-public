# Log Export

Short manual for exporting decoded logs from local Anvil runs.

## Prerequisites

- `forge` and `cast` installed
- project dependencies installed via `forge soldeer install`

## Recommended Workflow

Use this when you want setup logs and one or more repeatable bond transfer event exports.

### 1. Setup and export deployment logs

```bash
npm run events
```

This command installs Solidity dependencies, starts Anvil if needed, deploys the protocol, bootstraps it, seeds mock data,
and exports decoded logs for each setup stage. If the wrapper starts Anvil itself, it keeps that Anvil running so the
transfer event generator can reuse the same deployed chain.

Generated setup exports:

- `deployments/31337_anvil_DeployProtocol_events.json`
- `deployments/31337_anvil_BootstrapProtocol_events.json`
- `deployments/31337_anvil_SeedDemoData_events.json`

### 2. Generate transfer events

Run `npm run events` before this step. The transfer generator expects the protocol to be deployed and bootstrapped on
the running Anvil chain.

```bash
npm run gen-transfer
```

This command uses the running Anvil chain, derives entropy from the latest block number and timestamp, ensures two
event-demo company wallets and one event-demo bond exist, then transfers a clamped amount of bonds from whichever wallet
currently has balance to the other wallet.

Run it repeatedly to append more decoded transfer runs:

```bash
npm run gen-transfer
npm run gen-transfer
npm run gen-transfer
```

Generated transfer exports:

- `deployments/31337_anvil_GenerateBondTransferEvent_events.json` contains the latest `gen-transfer` run.
- `deployments/31337_anvil_GenerateBondTransferEvent_history.json` appends every `gen-transfer` run.

Useful inspection commands:

```bash
jq '.runCount, .logCount' deployments/31337_anvil_GenerateBondTransferEvent_history.json
jq '.runs[].decodedLogs[] | select(.eventName == "Transfer")' \
  deployments/31337_anvil_GenerateBondTransferEvent_history.json
```

### 3. Stop Anvil

If `npm run events` started Anvil, stop it when finished:

```bash
npm run events:stop-anvil
```

Full npm sequence:

```bash
npm run events
npm run gen-transfer
npm run gen-transfer
npm run events:stop-anvil
```

For a non-default Anvil port:

```bash
ANVIL_RPC_URL=http://127.0.0.1:9545 npm run events
ANVIL_RPC_URL=http://127.0.0.1:9545 npm run gen-transfer
npm run events:stop-anvil
```

## Command Reference

### Setup and setup-log export

Npm:

```bash
npm run events
```

Shell wrapper:

```bash
tools/local/run_anvil_setup_with_exports.sh --start-anvil --keep-anvil
```

If Anvil is already running:

```bash
tools/local/run_anvil_setup_with_exports.sh
```

Stop Anvil kept alive by the wrapper:

```bash
npm run events:stop-anvil
# or
tools/local/run_anvil_setup_with_exports.sh --stop-anvil
```

Notes:

- When the wrapper starts Anvil with `--keep-anvil`, it writes `.tmp/anvil-events.pid` and `.tmp/anvil-events.log`.
- `npm run events` uses `--start-anvil --keep-anvil`.

### Transfer event generation

Npm:

```bash
npm run gen-transfer
```

Shell wrapper:

```bash
tools/local/generate_bond_transfer_event_with_export.sh
```

Non-default RPC:

```bash
tools/local/generate_bond_transfer_event_with_export.sh --rpc-url http://127.0.0.1:9545
```

Custom latest/history output files:

```bash
tools/local/generate_bond_transfer_event_with_export.sh \
  --out deployments/custom_transfer_latest.json \
  --history-out deployments/custom_transfer_history.json
```

Useful environment overrides:

- `BOND_TRANSFER_EVENT_ISIN` (default: `XT0000000001`)
- `BOND_TRANSFER_EVENT_CURRENCY` (default: `EUR`)
- `BOND_TRANSFER_EVENT_ISSUE_AMOUNT` (default: `1000`)
- `BOND_TRANSFER_EVENT_MAX_SUPPLY` (default: `1000000000`)

Entropy is always derived from the latest block number and timestamp on the configured RPC.

### Manual log export

After any Foundry script has run with `--broadcast`, decode its `run-latest.json` with:

```bash
make export_logs \
  BROADCAST=broadcast/SomeScript.s.sol/31337/run-latest.json \
  DEPLOYMENT=deployments/31337_anvil_latest.json \
  OUT=deployments/31337_anvil_SomeScript_events.json \
  RPC_URL=http://127.0.0.1:8545
```

For setup stages, the broadcast paths are:

- `broadcast/DeployProtocol.s.sol/31337/run-latest.json`
- `broadcast/BootstrapProtocol.s.sol/31337/run-latest.json`
- `broadcast/SeedDemoData.s.sol/31337/run-latest.json`
- `broadcast/GenerateBondTransferEvent.s.sol/31337/run-latest.json`

## Output Format

Raw Foundry receipts are stored in `broadcast/.../run-latest.json`. Decoded exports are written to `deployments/*.json`.
The decoder uses local ABI artifacts from `out/`.

Each decoded export contains:

- `broadcastPath`: source Foundry receipt file
- `deploymentPath`: deployment manifest used for address-to-contract mapping
- `rpcUrl`: RPC endpoint used during decoding
- `receiptCount`: number of processed receipts
- `logCount`: number of processed logs
- `decodedLogs`: decoded log entries

Each item in `decodedLogs` contains:

- `emitter`: contract address that emitted the log
- `resolvedContractName`: canonical contract name resolved from deployment data or proxy/beacon lookup when it can be identified uniquely
- `transactionHash`
- `blockNumber`
- `logIndex`
- `decodeStatus`
- `topic0`
- `eventName`
- `eventSignature`
- `contractName`
- `artifactPath`
- `sourceGroup`
- `arguments`: decoded event arguments with names, types, and values
- `argumentsByName`: decoded event arguments as a name-to-value map
- `raw`: original raw log from the Foundry receipt

`decodeStatus` is normally `decoded`. Other values indicate unknown or ambiguous event matching.

When event attribution stays ambiguous:

- `decodeStatus` is set to `ambiguous-topic0`
- `candidateEvents` contains the candidate artifact contracts for that topic

Notes about decoding:

- indexed event arguments are decoded from `topics`
- non-indexed event arguments are decoded from `data`
- indexed dynamic values like `bytes`, `string`, arrays, or tuples remain hashed in topics and cannot be fully reconstructed from the log alone

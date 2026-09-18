-include .env

SHELL := /bin/bash

# //////////////////////////////////////
# ANVIL local testnet configuration ////
# //////////////////////////////////////

# network configuration
ANVIL_RPC_URL ?= http://127.0.0.1:8545
ANVIL_NETWORK_ID := 31337
FORGE_VERBOSITY ?= -vvvv
# Reachable from inside the anvil-dev container via the compose network; override for host use.
ANVIL_VERIFIER_URL ?= http://backend:4000/api/

# /////////////////////////////
# Define network arguments ////
# /////////////////////////////

# Setup configuration for chain
ifeq ($(NETWORK),besu)
	NETWORK_ID := $(BESU_NETWORK_ID)
	NETWORK_ARGS := --rpc-url $(BESU_RPC_URL) --broadcast --ffi
	DEPLOY_ARGS := $(NETWORK_ARGS) --private-key $(BESU_DEPLOYER_PRIVATE_KEY) -vv
	VERIFY_ARGS := $(NETWORK_ARGS) --resume --verify --verifier blockscout --verifier-url $(BESU_VERIFIER_URL) --private-keys $(BESU_DEPLOYER_PRIVATE_KEY) --private-keys $(BESU_TIMELOCK_ADMIN_PRIVATE_KEY) --private-keys $(BESU_TIMELOCK_ACTOR_PRIVATE_KEY) --private-keys $(BESU_ADMIN_PRIVATE_KEY)
else
	# For Anvil, use the default deployer key
	NETWORK_ID := $(ANVIL_NETWORK_ID)
	NETWORK_ARGS := --rpc-url $(ANVIL_RPC_URL) --broadcast --ffi
	DEPLOY_ARGS := $(NETWORK_ARGS) --slow --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 $(FORGE_VERBOSITY)
	VERIFY_ARGS := --rpc-url $(ANVIL_RPC_URL) --broadcast --ffi --resume --verify --verifier blockscout --verifier-url $(ANVIL_VERIFIER_URL) \
		--private-keys 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--private-keys 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		--private-keys 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6 \
		--private-keys 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
endif

# mock_data seeds the Orderbook with sequential, dependent same-signer transactions
# (e.g. markTradePaid -> settleTrade). --slow makes forge wait for each tx receipt
# before broadcasting the next one, which real networks with non-instant block times
# (like Besu) need to avoid racing a dependent tx ahead of the one it relies on.
# Anvil's DEPLOY_ARGS already contains --slow, so do not pass it twice.
ifeq ($(NETWORK),besu)
	MOCK_DATA_ARGS := $(DEPLOY_ARGS) --slow
else
	MOCK_DATA_ARGS := $(DEPLOY_ARGS)
endif

define bump_or_sleep
if [ "$(NETWORK_ID)" = "$(ANVIL_NETWORK_ID)" ]; then \
CURRENT_TIMESTAMP=$$(cast rpc --rpc-url $(ANVIL_RPC_URL) eth_getBlockByNumber latest true | jq -r '.timestamp'); \
CURRENT_DEC=$$(printf "%d" $$CURRENT_TIMESTAMP); \
NEW_TIMESTAMP=$$((CURRENT_DEC + 3600)); \
echo "Current timestamp: $$CURRENT_DEC"; \
echo "Setting next block timestamp to: $$NEW_TIMESTAMP"; \
cast rpc --rpc-url $(ANVIL_RPC_URL) evm_setNextBlockTimestamp $$NEW_TIMESTAMP; \
cast rpc --rpc-url $(ANVIL_RPC_URL) evm_mine; \
else \
sleep 60; \
fi
endef

# Targets
.PHONY: create_deployments_folder \
        deploy deploy_ebsi bootstrap mock_data \
        generate_bond_transfer_event \
        setup setup_test_data setup_verified setup_test_data_verified \
        setup_full setup_full_test_data setup_full_verified setup_full_test_data_verified \
        setup_ebsi_existing setup_ebsi_existing_test_data setup_ebsi_existing_verified setup_ebsi_existing_test_data_verified \
        export_logs \
        verify_contracts

create_deployments_folder:
	mkdir -p ./deployments

# ////////////////////
# Stage 1: Deploy  ///
# ////////////////////

deploy: create_deployments_folder
	forge script script/deploy/DeployProtocol.s.sol $(DEPLOY_ARGS)

deploy_ebsi: create_deployments_folder
	forge script script/DeployEBSI.s.sol $(DEPLOY_ARGS)

# Verify contracts from existing broadcast files (retryable, no redeployment)
# Note: forge script --verify (without --broadcast) reads from broadcast receipts
# and verifies contracts without redeploying
verify_contracts:
	@echo "=== Verifying Contracts ==="
	@echo "Verifying contracts from broadcast files (no redeployment)..."
	@if [ ! -d "broadcast/DeployProtocol.s.sol" ]; then \
		echo "Error: No broadcast files found. Deploy contracts first."; \
		exit 1; \
	fi
	@echo "Running forge script with --verify (will verify from broadcast receipts)..."
	forge script script/deploy/DeployProtocol.s.sol $(VERIFY_ARGS)

# ///////////////////////
# Stage 2: Bootstrap  ///
# ///////////////////////

bootstrap:
	forge script script/bootstrap/BootstrapProtocol.s.sol $(DEPLOY_ARGS)

# ///////////////////////
# Stage 3: Seed test_data  ///
# ///////////////////////

mock_data:
	forge script script/test_data/SeedDemoData.s.sol $(MOCK_DATA_ARGS)

generate_bond_transfer_event:
	forge script script/ops/GenerateBondTransferEvent.s.sol $(DEPLOY_ARGS)


# ////////////////////////////
# Composed targets          ///
# ////////////////////////////

# deploy + bootstrap (no seed data)
setup:
	make deploy && \
	make bootstrap

setup_verified:
	make setup && \
	make verify_contracts

# deploy + bootstrap + test_data seed
setup_test_data:
	make setup && \
	make mock_data

setup_test_data_verified:
	make setup_test_data && \
	make verify_contracts

# Full deployment including EBSI infrastructure (own testnet)
setup_full:
	@echo "=== Full Deployment (with EBSI infrastructure) ==="
	DEPLOY_EBSI=true make setup

setup_full_verified:
	@echo "=== Full Deployment (with EBSI infrastructure) ==="
	DEPLOY_EBSI=true make setup_verified

setup_full_test_data:
	@echo "=== Full Deployment (with EBSI infrastructure + test_data seed) ==="
	DEPLOY_EBSI=true make setup_test_data

setup_full_test_data_verified:
	@echo "=== Full Deployment (with EBSI infrastructure + test_data seed) ==="
	DEPLOY_EBSI=true make setup_test_data_verified

# Deploy to existing EBSI infrastructure (EBSI chain)
define check_ebsi_vars
	@if [ -z "$(EBSI_PROXY_FACTORY)" ] || [ -z "$(EBSI_PROXY_REGISTRY)" ] || [ -z "$(EBSI_DID_BOND_REGISTRY)" ]; then \
		echo "Error: EBSI addresses not set in environment. Required:"; \
		echo "  EBSI_PROXY_FACTORY"; \
		echo "  EBSI_PROXY_REGISTRY"; \
		echo "  EBSI_DID_BOND_REGISTRY"; \
		exit 1; \
	fi
endef

setup_ebsi_existing:
	@echo "=== Deployment to Existing EBSI Infrastructure ==="
	$(call check_ebsi_vars)
	DEPLOY_EBSI=false make setup

setup_ebsi_existing_verified:
	@echo "=== Deployment to Existing EBSI Infrastructure ==="
	$(call check_ebsi_vars)
	DEPLOY_EBSI=false make setup_verified

setup_ebsi_existing_test_data:
	@echo "=== Deployment to Existing EBSI Infrastructure (with test_data seed) ==="
	$(call check_ebsi_vars)
	DEPLOY_EBSI=false make setup_test_data

setup_ebsi_existing_test_data_verified:
	@echo "=== Deployment to Existing EBSI Infrastructure (with test_data seed) ==="
	$(call check_ebsi_vars)
	DEPLOY_EBSI=false make setup_test_data_verified

# Decode broadcast receipts into ABI-decoded event logs.
# Example:
# make export_logs \
#   BROADCAST=broadcast/DeployProtocol.s.sol/31337/run-latest.json \
#   DEPLOYMENT=deployments/31337_anvil_latest.json \
#   OUT=deployments/31337_anvil_events_DeployProtocol.json \
#   RPC_URL=$(ANVIL_RPC_URL)
export_logs:
	@test -n "$(BROADCAST)" || (echo "Usage: make export_logs BROADCAST=... OUT=... [DEPLOYMENT=...] [RPC_URL=...]"; exit 1)
	@test -n "$(OUT)" || (echo "Usage: make export_logs BROADCAST=... OUT=... [DEPLOYMENT=...] [RPC_URL=...]"; exit 1)
	python3 tools/local/export_broadcast_logs.py --broadcast "$(BROADCAST)" --out "$(OUT)" $(if $(DEPLOYMENT),--deployment "$(DEPLOYMENT)",) $(if $(RPC_URL),--rpc-url "$(RPC_URL)",)

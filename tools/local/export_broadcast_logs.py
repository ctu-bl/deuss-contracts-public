#!/usr/bin/env python3
"""Decode Foundry broadcast receipt logs using local ABI artifacts.

Typical local workflow:

1. Run a script against Anvil with `--broadcast`.
2. Decode the generated receipt logs:

   python3 tools/local/export_broadcast_logs.py \
     --broadcast broadcast/DeployProtocol.s.sol/31337/run-latest.json \
     --deployment deployments/31337_anvil_latest.json \
     --rpc-url http://127.0.0.1:8545 \
     --out deployments/31337_anvil_events_DeployProtocol.json

The exporter prefers emitter-address matches from the deployment manifest. For
unknown emitters, it can optionally resolve EIP-1967 proxy/beacon slots over
RPC, which is useful for beacon-proxy wallets created during bootstrap/seeding.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
BEACON_SLOT = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


@dataclass(frozen=True)
class EventDefinition:
    contract_name: str
    artifact_path: str
    source_group: str
    signature: str
    topic0: str
    abi: dict[str, Any]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Decode Foundry broadcast logs from local ABI artifacts.")
    parser.add_argument("--broadcast", required=True, help="Path to a Foundry run-latest.json or broadcast receipt file.")
    parser.add_argument("--out", required=True, help="Output path for decoded JSON.")
    parser.add_argument("--deployment", help="Optional deployment manifest path, e.g. deployments/31337_anvil_latest.json.")
    parser.add_argument("--rpc-url", help="Optional RPC URL for proxy/beacon resolution, e.g. http://127.0.0.1:8545.")
    parser.add_argument("--out-dir", default="out", help="Foundry artifact directory. Defaults to out.")
    return parser.parse_args()


def normalize_address(value: str | None) -> str | None:
    if not isinstance(value, str):
        return None
    if not re.fullmatch(r"0x[0-9a-fA-F]{40}", value):
        return None
    return value.lower()


def normalize_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)


def canonical_abi_type(item: dict[str, Any]) -> str:
    item_type = item["type"]
    if not item_type.startswith("tuple"):
        return item_type
    suffix = item_type[len("tuple") :]
    components = ",".join(canonical_abi_type(component) for component in item.get("components", []))
    return f"({components}){suffix}"


def event_signature(abi_entry: dict[str, Any]) -> str:
    arg_types = ",".join(canonical_abi_type(item) for item in abi_entry.get("inputs", []))
    return f'{abi_entry["name"]}({arg_types})'


def run_command(command: list[str], *, expect_json: bool = False) -> Any:
    completed = subprocess.run(command, capture_output=True, text=True, check=True)
    output = completed.stdout.strip()
    if expect_json:
        return json.loads(output)
    return output


def topic0_for_signature(signature: str, cache: dict[str, str]) -> str:
    cached = cache.get(signature)
    if cached is not None:
        return cached
    topic0 = run_command(["cast", "sig-event", signature]).lower()
    cache[signature] = topic0
    return topic0


def load_artifacts(out_dir: Path) -> tuple[dict[str, list[EventDefinition]], dict[str, list[EventDefinition]]]:
    by_contract: dict[str, list[EventDefinition]] = defaultdict(list)
    by_topic0: dict[str, list[EventDefinition]] = defaultdict(list)
    topic_cache: dict[str, str] = {}

    for artifact_path in sorted(out_dir.rglob("*.json")):
        try:
            artifact = read_json(artifact_path)
        except json.JSONDecodeError:
            continue

        abi = artifact.get("abi")
        if not isinstance(abi, list):
            continue

        contract_name = artifact_path.stem
        source_group = artifact_path.parent.name.removesuffix(".sol")

        seen_signatures: set[str] = set()
        for entry in abi:
            if entry.get("type") != "event" or entry.get("anonymous") is True:
                continue

            signature = event_signature(entry)
            dedupe_key = f"{contract_name}:{signature}"
            if dedupe_key in seen_signatures:
                continue
            seen_signatures.add(dedupe_key)

            definition = EventDefinition(
                contract_name=contract_name,
                artifact_path=str(artifact_path),
                source_group=source_group,
                signature=signature,
                topic0=topic0_for_signature(signature, topic_cache),
                abi=entry,
            )
            by_contract[normalize_name(contract_name)].append(definition)
            by_topic0[definition.topic0].append(definition)

    return dict(by_contract), dict(by_topic0)


def extract_receipts(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        receipts = payload.get("receipts")
        if isinstance(receipts, list):
            return [receipt for receipt in receipts if isinstance(receipt, dict)]
        if isinstance(payload.get("logs"), list) and payload.get("transactionHash"):
            return [payload]
    if isinstance(payload, list):
        return [receipt for receipt in payload if isinstance(receipt, dict) and isinstance(receipt.get("logs"), list)]
    raise ValueError("Could not find receipts in the provided broadcast file.")


class AddressBook:
    def __init__(self, deployment_path: Path | None) -> None:
        self.deployment_path = deployment_path
        self.contract_addresses: dict[str, str] = {}
        self.beacon_addresses: dict[str, str] = {}
        self.implementation_addresses: dict[str, str] = {}
        self._all_addresses: dict[str, str] = {}

        if deployment_path is not None:
            deployment = read_json(deployment_path)
            self._index_manifest(deployment)

    def _remember(self, table: dict[str, str], address: str, contract_name: str) -> None:
        normalized = normalize_address(address)
        if normalized is None:
            return
        table[normalized] = contract_name
        self._all_addresses.setdefault(normalized, contract_name)

    def _index_manifest(self, obj: Any, current_name: str | None = None) -> None:
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "contractAddress" and current_name:
                    self._remember(self.contract_addresses, value, current_name)
                elif key == "beaconAddress" and current_name:
                    self._remember(self.beacon_addresses, value, current_name)
                elif key == "implementationAddress" and current_name:
                    self._remember(self.implementation_addresses, value, current_name)
                else:
                    next_name = key if key not in {"core", "registries", "governance", "wallet", "token", "utils", "ebsi"} else current_name
                    self._index_manifest(value, next_name)
        elif isinstance(obj, list):
            for value in obj:
                self._index_manifest(value, current_name)

    def direct_contract_name(self, address: str | None) -> str | None:
        normalized = normalize_address(address)
        if normalized is None:
            return None
        return self._all_addresses.get(normalized)


class RpcResolver:
    def __init__(self, rpc_url: str | None, address_book: AddressBook) -> None:
        self.rpc_url = rpc_url
        self.address_book = address_book
        self._cache: dict[str, str | None] = {}

    def resolve_contract_name(self, emitter: str | None) -> str | None:
        normalized = normalize_address(emitter)
        if normalized is None:
            return None

        direct = self.address_book.direct_contract_name(normalized)
        if direct is not None:
            return direct

        if normalized in self._cache:
            return self._cache[normalized]

        resolved: str | None = None
        if self.rpc_url:
            implementation = self._read_slot_address(normalized, IMPLEMENTATION_SLOT)
            if implementation:
                resolved = self.address_book.implementation_addresses.get(implementation)

            if resolved is None:
                beacon = self._read_slot_address(normalized, BEACON_SLOT)
                if beacon:
                    resolved = self.address_book.beacon_addresses.get(beacon)
                    if resolved is None:
                        implementation = self._read_beacon_implementation(beacon)
                        if implementation:
                            resolved = self.address_book.implementation_addresses.get(implementation)

        self._cache[normalized] = resolved
        return resolved

    def _read_slot_address(self, address: str, slot: str) -> str | None:
        try:
            raw = run_command(["cast", "storage", address, slot, "--rpc-url", self.rpc_url or ""])
        except subprocess.CalledProcessError:
            return None

        raw = raw.strip().lower()
        if not re.fullmatch(r"0x[0-9a-f]{64}", raw):
            return None
        resolved = f"0x{raw[-40:]}"
        return None if resolved == ZERO_ADDRESS else resolved

    def _read_beacon_implementation(self, beacon: str) -> str | None:
        try:
            output = run_command(
                ["cast", "call", beacon, "implementation()(address)", "--rpc-url", self.rpc_url or ""]
            ).strip()
        except subprocess.CalledProcessError:
            return None
        return normalize_address(output)


def is_dynamic_indexed_type(abi_type: str) -> bool:
    return abi_type == "string" or abi_type == "bytes" or abi_type == "tuple" or "[" in abi_type


def decode_int(word_hex: str, bits: int, signed: bool) -> str:
    value = int(word_hex, 16)
    if signed:
        sign_bit = 1 << (bits - 1)
        if value & sign_bit:
            value -= 1 << bits
    return str(value)


def decode_static_indexed_value(abi_type: str, topic_word: str) -> Any:
    raw = topic_word.lower().removeprefix("0x")
    if abi_type == "address":
        return f"0x{raw[-40:]}"
    if abi_type == "bool":
        return bool(int(raw, 16))

    uint_match = re.fullmatch(r"uint(\d{0,3})", abi_type)
    if uint_match:
        bits = int(uint_match.group(1) or "256")
        return decode_int(raw, bits, signed=False)

    int_match = re.fullmatch(r"int(\d{0,3})", abi_type)
    if int_match:
        bits = int(int_match.group(1) or "256")
        return decode_int(raw, bits, signed=True)

    bytes_match = re.fullmatch(r"bytes(\d+)", abi_type)
    if bytes_match:
        size = int(bytes_match.group(1))
        return f"0x{raw[: size * 2]}"

    if abi_type == "function":
        return f"0x{raw[:48]}"

    return topic_word


def cast_decode_outputs(types: list[str], data_hex: str) -> list[Any]:
    if not types:
        return []
    calldata = data_hex.removeprefix("0x")
    signature = f"decoded()({','.join(types)})"
    return run_command(["cast", "decode-abi", "--json", signature, calldata], expect_json=True)


def candidate_definitions(
    candidates: list[EventDefinition], resolved_contract_name: str | None, by_contract: dict[str, list[EventDefinition]]
) -> list[EventDefinition]:
    if not candidates:
        return []

    deduped: dict[tuple[str, str], EventDefinition] = {}
    for candidate in candidates:
        deduped[(candidate.contract_name, candidate.signature)] = candidate
    unique_candidates = list(deduped.values())

    signatures = {candidate.signature for candidate in unique_candidates}
    if len(signatures) == 1:
        if resolved_contract_name is not None:
            normalized = normalize_name(resolved_contract_name)
            exact_matches = [
                candidate for candidate in unique_candidates if normalize_name(candidate.contract_name) == normalized
            ]
            if exact_matches:
                concrete_candidates = [candidate for candidate in exact_matches if not candidate.contract_name.startswith("I")]
                return [concrete_candidates[0] if concrete_candidates else exact_matches[0]]

            # Multiple concrete contracts can share inherited events like
            # Ownable's OwnershipTransferred. If the resolved emitter name does
            # not match any ABI exactly, keep the result ambiguous instead of
            # silently attributing the event to the first artifact.
            return unique_candidates

        concrete_candidates = [candidate for candidate in unique_candidates if not candidate.contract_name.startswith("I")]
        if len(concrete_candidates) == 1:
            return [concrete_candidates[0]]
        if len(unique_candidates) == 1:
            return [unique_candidates[0]]
        return unique_candidates

    if resolved_contract_name is None:
        return unique_candidates

    normalized = normalize_name(resolved_contract_name)
    exact_matches = [candidate for candidate in unique_candidates if normalize_name(candidate.contract_name) == normalized]
    if exact_matches:
        return exact_matches

    fallback_contract_entries = by_contract.get(normalized, [])
    if fallback_contract_entries:
        fallback_signatures = {candidate.signature for candidate in fallback_contract_entries}
        narrowed = [candidate for candidate in unique_candidates if candidate.signature in fallback_signatures]
        if narrowed:
            return narrowed

    return unique_candidates


def canonical_contract_name(name: str | None, by_contract: dict[str, list[EventDefinition]]) -> str | None:
    if name is None:
        return None

    candidates = by_contract.get(normalize_name(name), [])
    if not candidates:
        return name

    unique_names: list[str] = []
    seen_names: set[str] = set()
    concrete_candidates = [candidate for candidate in candidates if not candidate.contract_name.startswith("I")]
    source = concrete_candidates or candidates
    for candidate in source:
        if candidate.contract_name in seen_names:
            continue
        seen_names.add(candidate.contract_name)
        unique_names.append(candidate.contract_name)

    return unique_names[0] if len(unique_names) == 1 else name


def decode_log(
    log: dict[str, Any],
    receipt: dict[str, Any],
    *,
    by_contract: dict[str, list[EventDefinition]],
    by_topic0: dict[str, list[EventDefinition]],
    resolver: RpcResolver,
) -> dict[str, Any]:
    emitter = normalize_address(log.get("address"))
    topics = [topic.lower() for topic in log.get("topics", []) if isinstance(topic, str)]
    topic0 = topics[0] if topics else None
    resolved_contract_name = canonical_contract_name(resolver.resolve_contract_name(emitter), by_contract)

    decoded: dict[str, Any] = {
        "emitter": emitter,
        "resolvedContractName": resolved_contract_name,
        "transactionHash": receipt.get("transactionHash") or log.get("transactionHash"),
        "blockNumber": receipt.get("blockNumber") or log.get("blockNumber"),
        "logIndex": log.get("logIndex"),
        "raw": log,
    }

    if topic0 is None:
        decoded["decodeStatus"] = "no-topics"
        return decoded

    candidates = candidate_definitions(by_topic0.get(topic0, []), resolved_contract_name, by_contract)
    if not candidates:
        decoded["decodeStatus"] = "unknown-topic0"
        decoded["topic0"] = topic0
        return decoded

    if len(candidates) > 1:
        decoded["decodeStatus"] = "ambiguous-topic0"
        decoded["topic0"] = topic0
        decoded["candidateEvents"] = [
            {
                "contractName": candidate.contract_name,
                "signature": candidate.signature,
                "artifactPath": candidate.artifact_path,
            }
            for candidate in candidates
        ]
        return decoded

    definition = candidates[0]
    inputs = definition.abi.get("inputs", [])
    indexed_inputs = [item for item in inputs if item.get("indexed")]
    non_indexed_inputs = [item for item in inputs if not item.get("indexed")]

    decoded["topic0"] = topic0
    decoded["decodeStatus"] = "decoded"
    decoded["eventName"] = definition.abi["name"]
    decoded["eventSignature"] = definition.signature
    decoded["contractName"] = definition.contract_name
    decoded["artifactPath"] = definition.artifact_path
    decoded["sourceGroup"] = definition.source_group

    if len(topics) - 1 != len(indexed_inputs):
        decoded["decodeStatus"] = "topic-count-mismatch"
        decoded["expectedIndexedInputs"] = len(indexed_inputs)
        decoded["actualIndexedTopics"] = len(topics) - 1
        return decoded

    indexed_values = []
    for topic_word, item in zip(topics[1:], indexed_inputs, strict=True):
        abi_type = canonical_abi_type(item)
        name = item.get("name") or f"arg{len(indexed_values)}"
        if is_dynamic_indexed_type(item["type"]):
            value = {"hash": topic_word, "note": "Indexed dynamic values are hashed in topics and cannot be fully decoded."}
        else:
            value = decode_static_indexed_value(abi_type, topic_word)
        indexed_values.append(
            {
                "name": name,
                "type": abi_type,
                "indexed": True,
                "value": value,
                "rawTopic": topic_word,
            }
        )

    non_indexed_values = []
    raw_data = log.get("data", "0x")
    if non_indexed_inputs:
        decoded_data = cast_decode_outputs([canonical_abi_type(item) for item in non_indexed_inputs], raw_data)
        for item, value in zip(non_indexed_inputs, decoded_data, strict=True):
            name = item.get("name") or f"arg{len(indexed_values) + len(non_indexed_values)}"
            non_indexed_values.append(
                {
                    "name": name,
                    "type": canonical_abi_type(item),
                    "indexed": False,
                    "value": value,
                }
            )

    args = indexed_values + non_indexed_values
    decoded["arguments"] = args
    decoded["argumentsByName"] = {argument["name"]: argument["value"] for argument in args}
    return decoded


def main() -> int:
    args = parse_args()

    broadcast_path = Path(args.broadcast)
    out_path = Path(args.out)
    deployment_path = Path(args.deployment) if args.deployment else None
    out_dir = Path(args.out_dir)

    by_contract, by_topic0 = load_artifacts(out_dir)
    address_book = AddressBook(deployment_path)
    resolver = RpcResolver(args.rpc_url, address_book)

    receipts = extract_receipts(read_json(broadcast_path))
    decoded_logs = []
    for receipt in receipts:
        for log in receipt.get("logs", []):
            if isinstance(log, dict):
                decoded_logs.append(
                    decode_log(log, receipt, by_contract=by_contract, by_topic0=by_topic0, resolver=resolver)
                )

    payload = {
        "broadcastPath": str(broadcast_path),
        "deploymentPath": str(deployment_path) if deployment_path else None,
        "rpcUrl": args.rpc_url,
        "receiptCount": len(receipts),
        "logCount": len(decoded_logs),
        "decodedLogs": decoded_logs,
    }
    write_json(out_path, payload)

    print(f"Wrote {len(decoded_logs)} decoded logs to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Append the latest decoded transfer-event export to a persistent history file."""

from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Append decoded GenerateBondTransferEvent logs to a history JSON file.")
    parser.add_argument("--latest", required=True, help="Latest decoded event export JSON.")
    parser.add_argument("--history", required=True, help="Persistent history JSON to append to.")
    parser.add_argument("--entropy-seed", required=True, help="Entropy seed used by the run.")
    return parser.parse_args()


def read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def main() -> None:
    args = parse_args()
    latest_path = Path(args.latest)
    history_path = Path(args.history)

    latest = read_json(latest_path)
    history = read_json(
        history_path,
        {
            "schema": "deuss.generateBondTransferEvent.history.v1",
            "runCount": 0,
            "logCount": 0,
            "runs": [],
        },
    )

    run = {
        "runIndex": len(history["runs"]) + 1,
        "appendedAt": datetime.now(UTC).isoformat(),
        "entropySeed": args.entropy_seed,
        "latestExportPath": str(latest_path),
        "broadcastPath": latest.get("broadcastPath"),
        "deploymentPath": latest.get("deploymentPath"),
        "rpcUrl": latest.get("rpcUrl"),
        "receiptCount": latest.get("receiptCount", 0),
        "logCount": latest.get("logCount", 0),
        "decodedLogs": latest.get("decodedLogs", []),
    }

    history["runs"].append(run)
    history["runCount"] = len(history["runs"])
    history["logCount"] = sum(item.get("logCount", 0) for item in history["runs"])

    write_json(history_path, history)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("export_broadcast_logs.py")
SPEC = importlib.util.spec_from_file_location("export_broadcast_logs", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ExportBroadcastLogsTests(unittest.TestCase):
    def make_definition(self, contract_name: str, signature: str = "Initialized(uint64)"):
        return MODULE.EventDefinition(
            contract_name=contract_name,
            artifact_path=f"out/{contract_name}.json",
            source_group=contract_name,
            signature=signature,
            topic0="0x1234",
            abi={"name": signature.split("(", 1)[0], "inputs": [], "type": "event"},
        )

    def test_shared_signature_without_resolved_contract_stays_ambiguous(self) -> None:
        candidates = [
            self.make_definition("BondRegistry"),
            self.make_definition("EntityRegistry"),
            self.make_definition("AccessControlUpgradeable"),
        ]

        resolved = MODULE.candidate_definitions(candidates, None, {})

        self.assertEqual(
            [candidate.contract_name for candidate in resolved],
            ["BondRegistry", "EntityRegistry", "AccessControlUpgradeable"],
        )

    def test_canonical_contract_name_prefers_unique_concrete_artifact(self) -> None:
        by_contract = {
            "deusstoken": [
                self.make_definition("IDEUSSToken", "TokensFrozen(address,uint256,uint256)"),
                self.make_definition("DEUSSToken", "TokensFrozen(address,uint256,uint256)"),
            ]
        }

        resolved = MODULE.canonical_contract_name("deussToken", by_contract)

        self.assertEqual(resolved, "DEUSSToken")


if __name__ == "__main__":
    unittest.main()

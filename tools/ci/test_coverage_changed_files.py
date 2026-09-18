#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("coverage_changed_files.py")
SPEC = importlib.util.spec_from_file_location("coverage_changed_files", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CoverageChangedFilesTests(unittest.TestCase):
    def assert_declaration_only(self, source: str, expected: bool) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "Sample.sol"
            path.write_text(source)

            self.assertIs(MODULE.is_declaration_only_source(path), expected)

    def test_interface_with_function_declarations_is_declaration_only(self) -> None:
        # Interface function declarations have no executable bodies to cover.
        self.assert_declaration_only(
            """
            pragma solidity 0.8.34;

            interface IMarketplace {
                function setThreshold(uint256 threshold) external;
            }
            """,
            True,
        )

    def test_error_and_type_library_is_declaration_only(self) -> None:
        # Error/type-only libraries, such as Errors.sol, should not require LCOV entries.
        self.assert_declaration_only(
            """
            pragma solidity 0.8.34;

            library Errors {
                error ThresholdTooHigh(uint256 threshold);

                enum Status {
                    Pending,
                    Final
                }

                struct Config {
                    uint256 threshold;
                }
            }
            """,
            True,
        )

    def test_comments_and_strings_do_not_create_executable_member(self) -> None:
        # Fake function bodies in comments or strings should not make a source executable.
        self.assert_declaration_only(
            '''
            pragma solidity 0.8.34;

            library Errors {
                // function fake() external { revert(); }
                string internal constant NOTE = "function fake() external { revert(); }";
                error Invalid();
            }
            ''',
            True,
        )

    def test_library_with_function_body_is_not_declaration_only(self) -> None:
        # Guards against treating every library as declaration-only.
        self.assert_declaration_only(
            """
            pragma solidity 0.8.34;

            library ExecutableLibrary {
                function addOne(uint256 value) internal pure returns (uint256) {
                    return value + 1;
                }
            }
            """,
            False,
        )

    def test_contract_with_constructor_body_is_not_declaration_only(self) -> None:
        # Constructor bodies are executable and should require coverage data.
        self.assert_declaration_only(
            """
            pragma solidity 0.8.34;

            contract MarketplaceStorage {
                uint256 public immutable threshold;

                constructor(uint256 threshold_) {
                    threshold = threshold_;
                }
            }
            """,
            False,
        )

    def test_contract_with_modifier_body_is_not_declaration_only(self) -> None:
        # Guards the executable-member detector for modifier bodies.
        self.assert_declaration_only(
            """
            pragma solidity 0.8.34;

            contract ModifierHarness {
                modifier onlyOwner() {
                    _;
                }
            }
            """,
            False,
        )


if __name__ == "__main__":
    unittest.main()

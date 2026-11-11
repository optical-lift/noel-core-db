#!/usr/bin/env python3
"""Source-only, no network, no database: classify fictional clone summaries."""
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "access01_phase_report", HERE / "atlas-access01-safe-phase-receipt.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ReceiptTests(unittest.TestCase):
    def test_all_fixed_harness_phases(self):
        for label, code in mod.PHASE_CODES.items():
            self.assertEqual(
                mod.classify(3, f"**FAILED during {label}.**", None), code
            )
            self.assertEqual(
                mod.classify(1, f"Validation command exited during \x60{label}\x60.", None), code
            )

    def test_no_forged_or_extra_diagnostic_can_escape(self):
        mock_secret = "postgresql://private.example.test/secret"
        self.assertEqual(
            mod.classify(3, "**FAILED during candidate migration application.** "
                              + mock_secret, None), "unclassified"
        )
        self.assertEqual(
            mod.classify(3, "**FAILED during unknown source query.** "
                              + mock_secret, None), "unclassified"
        )
        self.assertEqual(
            mod.classify(3, "**FAILED during candidate migration application.**\n"
                              "**FAILED during candidate migration postconditions.**",
                              None), "unclassified"
        )
        self.assertEqual(mod.classify(3, None, mock_secret), "unclassified")

    def test_signed_pass_requires_actual_receipt(self):
        self.assertEqual(
            mod.classify(0, "# Production schema clone validation", "PASS ACCESS-01 signed source"),
            "signed_pass"
        )
        self.assertEqual(
            mod.classify(0, "# Production schema clone validation", "PASS unrelated"),
            "missing_signed_receipt"
        )
        self.assertEqual(mod.classify(0, "", None), "missing_signed_receipt")
        self.assertEqual(mod.classify(124, "", None), "time_bound")
        self.assertEqual(mod.classify(137, "", None), "time_bound")
        self.assertEqual(
            mod.classify(124, "**FAILED during candidate migration postconditions.**", None),
            "postconditions"
        )
        self.assertEqual(mod.classify(None, "", None), "exit_unknown")

    def test_reading_boundary(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root) / "exit"
            p.write_text("3\n")
            self.assertEqual(mod.exit_from_file(p), 3)
            p.write_text("3\n" + "not-a-number")
            self.assertIsNone(mod.exit_from_file(p))
            p.write_bytes(b"x" * (mod.MAX_BYTES + 1))
            self.assertIsNone(mod.bounded_plain(p))
            source = Path(root) / "source"
            source.write_text("sensitive-example")
            link = Path(root) / "link"
            link.symlink_to(source)
            self.assertIsNone(mod.bounded_plain(link))


if __name__ == "__main__":
    unittest.main()

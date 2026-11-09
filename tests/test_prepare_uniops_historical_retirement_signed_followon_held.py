#!/usr/bin/env python3
"""Source-only refusal checks, NOT the protected signed history test."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import prepare_uniops_historical_retirement_signed_followon_held as held


class ImmutableGovernorHistoryFollowon(unittest.TestCase):
    def test_three_immutable_blobs_are_explicit(self):
        self.assertEqual(held.DRIVER_BLOB, "09eeee925ebfa2cb64b1dea336688ba8076ef44d")
        self.assertEqual(held.BRIDGE_BLOB, "f1a4eadb4d0199e8b4d9c1f17738675c281e249d")
        self.assertEqual(held.COMPANION_BLOB, "79151f723e60b33410c760acef715155a53771f3")

    def test_refuses_unreviewed_source_bytes(self):
        for byteset in (
            (b"forged U4 signed driver", b"bridge", b"companion"),
            (b"", b"forged historical bridge", b"companion"),
            (b"", b"", b"forged companion"),
        ):
            with self.subTest(byteset=byteset[0][:10]):
                with self.assertRaises(held.HeldHookRefusal):
                    held.prepare(*byteset)

    def test_only_exact_signed_source_anchors(self):
        self.assertEqual(held.ARG_ANCHOR, "    a=p.parse_args()\n")
        self.assertIn("JWT is not authority", held.ACTOR_ANCHOR)
        self.assertIn("u2_receipt+result_claim+", held.RECEIPT_ANCHOR)
        self.assertIn("if a.historical_retirement_followon:", held.ACTOR_PATCH)
        self.assertIn("check(a.u4_actual_followon,", held.ACTOR_PATCH)
        self.assertIn('signed["no-seat"][0]', held.ACTOR_PATCH)
        self.assertIn("history_mark", held.ACTOR_PATCH)
        self.assertIn("history_mark", held.RECEIPT_ANCHOR.replace(
            "u2_receipt+result_claim+", "u2_receipt+result_claim+history_mark+"
        ))

    def test_main_rejects_path_outside_runner_before_read(self):
        with tempfile.TemporaryDirectory() as root:
            with patch("sys.argv", [
                "held", "--driver", "no-driver", "--bridge", "no-bridge",
                "--companion", "no-companion",
                "--output", str(Path(root).parent / "wrong.py")
            ]), patch.dict("os.environ", {"RUNNER_TEMP": root}):
                with self.assertRaisesRegex(held.HeldHookRefusal, "Output must"):
                    held.main()

    def test_main_rejects_missing_inputs_before_writing(self):
        with tempfile.TemporaryDirectory() as root:
            out = Path(root) / "validate-uniops-historical-signed-local-only.py"
            with patch("sys.argv", [
                "held", "--driver", "missing", "--bridge", "missing",
                "--companion", "missing", "--output", str(out)
            ]), patch.dict("os.environ", {"RUNNER_TEMP": root}):
                with self.assertRaisesRegex(held.HeldHookRefusal, "Missing or symlinked"):
                    held.main()
                self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()

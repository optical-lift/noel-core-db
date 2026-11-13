#!/usr/bin/env python3
"""Source/refusal tests only. These never run a real signed Auth/REST test."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = ROOT / "scripts/run-atlas-e05-isolated-riversong.py"
spec = importlib.util.spec_from_file_location("e05_riversong_bridge", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

FIXED_ENV = {
    "ATLAS_E05_GOVERNOR_EMAIL": "e05-governor-one@example.invalid",
    "ATLAS_E05_RECIPIENT_EMAIL": "e05-recipient-two@example.invalid",
    "ATLAS_E05_OUTSIDER_EMAIL": "e05-outsider-three@example.invalid",
    "ATLAS_E05_GOVERNOR_PASSWORD": "governor-local-1234",
    "ATLAS_E05_RECIPIENT_PASSWORD": "recipient-local-5678",
    "ATLAS_E05_OUTSIDER_PASSWORD": "outsider-local-4321",
    "ATLAS_E05_LOCAL_ANON_KEY": "not-a-real-local-anon-key-TEST-ONLY",
}

class BridgeTest(unittest.TestCase):
    def setup(self, temp):
        runner = temp / "pinned-atlas-runner.py"
        runner.write_text("fixture test only, not an actual runner")
        args = SimpleNamespace(
            db_url="postgresql://postgres:local@127.0.0.1:55433/atlas_e05_12345678",
            api_url="http://127.0.0.1:55434",
            atlas_runner=str(runner),
        )
        return runner, args

    def test_standard_git_blob_hash(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "data.txt"
            p.write_bytes(b"sample E05 bytes")
            known = hashlib.sha1(b"blob 16\\0sample E05 bytes").hexdigest()
            self.assertEqual(bridge.file_blob_sha(p), known)

    def test_remote_and_pathful_api_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _, cfg = self.setup(root)
            e05 = bridge.load_preparer()
            with patch.dict(os.environ, {**FIXED_ENV, "RUNNER_TEMP": d}, clear=True), \
                 patch.object(bridge, "file_blob_sha",
                              return_value=bridge.EXPECTED_ATLAS_RUNNER_BLOB):
                for url in ("https://example.com", "http://127.0.0.1:55434/rest",
                            "http://127.0.0.1:55434?token=1", "http://localhost:55434"):
                    cfg.api_url = url
                    with self.subTest(url=url), self.assertRaises(bridge.Refused):
                        bridge.validate(cfg, e05)

    def test_changed_atlas_runner_refused(self):
        with tempfile.TemporaryDirectory() as d:
            _, cfg = self.setup(Path(d))
            with patch.dict(os.environ, {**FIXED_ENV, "RUNNER_TEMP": d}, clear=True):
                with self.assertRaises(bridge.Refused):
                    bridge.validate(cfg, bridge.load_preparer())

    def test_existing_result_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _, cfg = self.setup(root)
            (root / "e05-local-signed-result.json").write_text("{}")
            with patch.dict(os.environ, {**FIXED_ENV, "RUNNER_TEMP": d}, clear=True), \
                 patch.object(bridge, "file_blob_sha",
                              return_value=bridge.EXPECTED_ATLAS_RUNNER_BLOB):
                with self.assertRaises(bridge.Refused):
                    bridge.validate(cfg, bridge.load_preparer())

    def test_mocked_happy_sequence_and_nonpass_refusal(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            _, cfg = self.setup(root)
            manifest = root / "e05-local-fixture-manifest.json"
            receipt = root / "e05-local-signed-result.json"
            test_success = {
                "signedSourceAcceptance": "PASS",
                "state": "SIGNED_SOURCE_PASS_BROWSER_HELD",
                "separateRealGoTrueSessions": 3,
                "governorAcceptedResultHistoryVerified": True,
                "connectedRecipientIndependentHistory": "NOT_PROVED",
                "browserUserJourney": "NOT_RUN",
                "productionChanges": False,
            }
            commands = []
            def mock_command(argv, timeout):
                commands.append((argv, timeout))
                if len(commands) == 1:
                    manifest.write_text('{"testOnly":true}')
                else:
                    receipt.write_text(json.dumps(test_success))
                return 0
            e05 = bridge.load_preparer()
            with patch.dict(os.environ, {**FIXED_ENV, "RUNNER_TEMP": d}, clear=True), \
                 patch.object(e05, "guard") as guard, \
                 patch.object(bridge, "load_preparer", return_value=e05), \
                 patch.object(bridge, "file_blob_sha",
                              return_value=bridge.EXPECTED_ATLAS_RUNNER_BLOB), \
                 patch.object(bridge, "invoke", side_effect=mock_command):
                self.assertEqual(bridge.execute(cfg), 0)
                self.assertEqual(len(commands), 2)
                self.assertIn("prepare-atlas-e05-nonfarm-clone-fixture.py",
                              commands[0][0][1])
                self.assertEqual(commands[0][1], 150)
                self.assertEqual(commands[1][1], 480)
                guard.assert_called_once()
                receipt.write_text(json.dumps({**test_success,
                                                "separateRealGoTrueSessions": 2}))
                # A pre-existing receipt must fail closed before any fake rerun.
                with self.assertRaises(bridge.Refused):
                    bridge.execute(cfg)

if __name__ == "__main__":
    unittest.main()

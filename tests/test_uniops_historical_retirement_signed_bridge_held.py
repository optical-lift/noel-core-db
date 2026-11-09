#!/usr/bin/env python3
"""No-network admission tests only. Not genuine signed historical acceptance."""
import hashlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import uniops_historical_retirement_signed_bridge_held as held


class ImmutableHistoricalRetirementAdmission(unittest.TestCase):
    def setUp(self):
        self.tokens = {
            "owner": "test-owner-not-a-session",
            "worker": "test-worker-not-a-session",
            "outsider": "test-outsider-not-a-session",
            "no-seat": "test-no-seat-not-a-session",
        }
        self.c1 = SimpleNamespace(sql=lambda db, query: "unused")

    def invoke(self, db, path, tokens=None):
        return held.prove(
            db, "http://127.0.0.1:54321", "not-a-real-key",
            self.tokens if tokens is None else tokens,
            source_path=path, sql=self.c1.sql,
            rpc=lambda *args: (_ for _ in ()).throw(
                AssertionError("No network should be reached")
            ), c1=self.c1,
        )

    def test_pin_is_exact_frozen_companion_not_a_live_branch(self):
        self.assertEqual(
            held.PINNED_SOURCE_COMMIT,
            "ddfb0bf5374798301fe076a61d2b944dfb52ff63"
        )
        self.assertEqual(
            held.PINNED_SOURCE_BLOB,
            "79151f723e60b33410c760acef715155a53771f3"
        )
        self.assertEqual(
            held.PINNED_SOURCE_PATH,
            "tests/validate-atlas-native-historical-retirement-signed-http.py"
        )

    def test_git_blob_hash_uses_real_git_object_format(self):
        contents = b"fixed test-only bytes\n"
        expected = hashlib.sha1(
            b"blob " + str(len(contents)).encode() + b"\0" + contents
        ).hexdigest()
        self.assertEqual(held.git_blob_sha(contents), expected)

    def test_refuses_remote_before_loading_source_or_calling_rpc(self):
        with self.assertRaisesRegex(held.HeldProofRefusal, "local Postgres"):
            self.invoke(
                "postgresql://postgres:secret@remote.example:5432/postgres",
                "/unreadable/missing.py"
            )

    def test_refuses_missing_duplicate_or_unsworn_actor_set(self):
        with self.assertRaisesRegex(held.HeldProofRefusal, "Four independently"):
            self.invoke(
                "postgresql://postgres:secret@127.0.0.1:5432/postgres",
                "missing.py", {**self.tokens, "worker": self.tokens["owner"]}
            )
        with self.assertRaisesRegex(held.HeldProofRefusal, "Four independently"):
            self.invoke(
                "postgresql://postgres:secret@127.0.0.1:5432/postgres",
                "missing.py", {k: v for k, v in self.tokens.items()
                               if k != "no-seat"}
            )

    def test_unpinned_file_cannot_execute_even_if_named_correctly(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / Path(held.PINNED_SOURCE_PATH).name
            path.write_text(
                'raise AssertionError("unreviewed bytes executed")\n',
                encoding="utf-8"
            )
            with self.assertRaisesRegex(held.HeldProofRefusal, "blob mismatch"):
                self.invoke(
                    "postgresql://postgres:secret@127.0.0.1:5432/postgres",
                    path
                )

    def test_denial_failure_is_not_relabeled_as_permission_pass(self):
        self.assertEqual(
            held.expected_denial_code(
                "Stale dependency snapshot must not cancel Work"
            ), "40001"
        )
        self.assertEqual(
            held.expected_denial_code(
                "Worker cannot cancel reviewed original"
            ), "42501"
        )
        self.assertEqual(
            held.expected_denial_code(
                "Outsider cannot cancel reviewed original"
            ), "42501"
        )


if __name__ == "__main__":
    unittest.main()

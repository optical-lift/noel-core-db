#!/usr/bin/env python3
"""Source-only tests for PRE1 disposable, read-only all-Atlas-row comparison."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/validate-atlas-access03c-pre1-local-row-integrity.py"
spec = importlib.util.spec_from_file_location("pre1_local_row_integrity", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PRE1RowIntegrity(unittest.TestCase):
    def test_only_loopback_postgres_is_admissible(self):
        local = "postgresql://postgres:local@127.0.0.1:54322/postgres"
        self.assertEqual(module.local_database_only(local), local)
        for remote in (
            "postgresql://postgres@db.example.com/postgres",
            "postgresql://postgres@localhost:54322/postgres",
            "postgresql://postgres@127.0.0.1:54322/other",
            "postgresql://postgres@127.0.0.1/postgres",
            "https://127.0.0.1:54322/postgres",
        ):
            with self.assertRaises(ValueError):
                module.local_database_only(remote)

    def test_catalog_and_full_row_hashes_are_read_only(self):
        sql = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("n.nspname = 'atlas'", sql)
        self.assertIn("c.relkind IN ('r','p')", sql)
        self.assertIn("NOT c.relispartition", sql)
        self.assertIn("to_jsonb(t)::text", sql)
        self.assertIn("string_agg(", sql)
        self.assertIn("sha256(", sql)
        self.assertIn("os.O_EXCL", sql)
        self.assertIn("capture_output=True", sql)
        self.assertIn("changed Atlas relations", sql)
        for relation in module.REQUIRED:
            self.assertTrue(relation.startswith("atlas."))

    def test_snapshot_conserves_full_row_fingerprints_and_fails_closed(self):
        db = "postgresql://postgres:local@127.0.0.1:54322/postgres"
        base = {name: {"rows": 1, "digest": "a"*64} for name in module.REQUIRED}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "private.json"
            with mock.patch.object(module, "fingerprint", return_value=base):
                module.run(db, "capture", path)
                module.run(db, "verify", path)
            self.assertEqual(json.loads(path.read_text())["tables"], base)
            changed = dict(base)
            changed["atlas.tasks"] = {"rows": 1, "digest": "b"*64}
            with mock.patch.object(module, "fingerprint", return_value=changed):
                with self.assertRaisesRegex(RuntimeError, "changed Atlas relations: atlas.tasks"):
                    module.run(db, "verify", path)
            with mock.patch.object(module, "fingerprint", return_value=base):
                with self.assertRaises(FileExistsError):
                    module.run(db, "capture", path)

    def test_generated_query_is_scoped_to_catalog_names_and_complete(self):
        sample = sorted(x.removeprefix("atlas.") for x in module.REQUIRED)
        row = ["atlas."+sample[0], "1", "a"*64]
        all_rows = [["atlas."+s, "0", "a"*64] for s in sample]
        with mock.patch.object(module, "table_names", return_value=sample):
            with mock.patch.object(module, "select_only", return_value=all_rows) as psql:
                got = module.fingerprint("postgresql://postgres@127.0.0.1:54322/postgres")
        self.assertEqual(len(got), len(module.REQUIRED))
        query = psql.call_args.args[1]
        self.assertNotIn("DELETE FROM", query)
        self.assertNotIn("DROP FUNCTION", query)
        self.assertIn('FROM "atlas"."tasks" AS t', query)


if __name__ == "__main__":
    unittest.main()

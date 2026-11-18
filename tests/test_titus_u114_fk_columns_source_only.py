"""U1.14 fictional-only exercise of the FK-column review membrane."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "candidates/shared-teaching-course-clean-cutover-v1"
SCRIPT = ROOT / "scripts/titus-u114-audit-fk-columns-only.py"
SQL = DATA / "U1_14_HISTORICAL_FK_COLUMNS_CATALOG_ONLY.sql"
OLD = DATA / "U1_13_HISTORICAL_FK_PAIRS_METADATA_ONLY.json"
spec = importlib.util.spec_from_file_location("u114", SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def source_fixture():
    prior = json.loads(OLD.read_text("utf-8"))
    assert len(prior["foreignKeyPairs"]) == 168
    # Entirely invented FK column names; NOT observed production columns.
    rows = []
    for n, pair in enumerate(prior["foreignKeyPairs"]):
        rows.append({
            "child": pair["child"],
            "parent": pair["parent"],
            "constraintName": f"fictional_fk_{n}",
            "childColumns": ["fictional_child_id"],
            "parentColumns": ["fictional_parent_id"],
            "onDeleteCode": "a", "onUpdateCode": "a",
            "deferrable": False, "initiallyDeferred": False,
        })
    for n in range(2):
        duplicate = copy.deepcopy(rows[n])
        duplicate["constraintName"] = f"fictional_extra_{n}"
        rows.append(duplicate)
    return {
        "contractVersion": "titus_u114_fk_column_catalog_only_v1",
        "rowValuesIncluded": False,
        "rowSelectionAuthorized": False,
        "productionChangesAuthorized": False,
        "foreignKeys": rows,
    }, prior


class TestU114(unittest.TestCase):
    def test_fictional_complete_metadata_has_no_authority(self):
        cat, old = source_fixture()
        receipt = audit.check(cat, old)
        self.assertEqual(receipt["catalogConstraintsReviewed"], 170)
        self.assertEqual(receipt["relationPairsMatched"], 168)
        self.assertTrue(all(v is False for k, v in receipt.items()
                            if k.endswith("Authorized") or
                            k in ("customerDataRead", "backupCreated",
                                  "restoredRealData")))
        cat["foreignKeys"][0]["onDeleteCode"] = "c"
        self.assertFalse(audit.check(cat, old)["deletionAuthorized"])

    def test_missing_relation_and_extra_relation_fail(self):
        cat, old = source_fixture()
        cat["foreignKeys"][30]["child"] = "titus.invented"
        with self.assertRaises(ValueError):
            audit.check(cat, old)
        cat, old = source_fixture()
        cat["foreignKeys"].pop()
        with self.assertRaises(ValueError):
            audit.check(cat, old)

    def test_wrong_columns_and_duplicate_constraint_fail(self):
        cat, old = source_fixture()
        cat["foreignKeys"][0]["parentColumns"] = []
        with self.assertRaises(ValueError):
            audit.check(cat, old)
        cat, old = source_fixture()
        cat["foreignKeys"][1] = copy.deepcopy(cat["foreignKeys"][0])
        with self.assertRaises(ValueError):
            audit.check(cat, old)

    def test_forged_row_permissions_and_catalog_key_fail(self):
        cat, old = source_fixture()
        cat["rowSelectionAuthorized"] = True
        with self.assertRaises(ValueError):
            audit.check(cat, old)
        cat, old = source_fixture()
        cat["foreignKeys"][0]["selector"] = "all"
        with self.assertRaises(ValueError):
            audit.check(cat, old)
        cat, old = source_fixture()
        old["foreignKeyPairs"] = old["foreignKeyPairs"][:-1]
        with self.assertRaises(ValueError):
            audit.check(cat, old)

    def test_duplicate_json_keys_fail_to_parse(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.json"
            path.write_text('{"rowValuesIncluded":false,"rowValuesIncluded":true}')
            with self.assertRaises(ValueError):
                audit.load(str(path))

    def test_catalog_sql_is_metadata_only_and_non_mutating(self):
        sql = SQL.read_text("utf-8")
        source = SCRIPT.read_text("utf-8")
        body = "\n".join(line for line in sql.splitlines()
                         if not line.lstrip().startswith("--"))
        self.assertIn("pg_catalog.pg_constraint", body)
        self.assertIn("pg_catalog.pg_attribute", body)
        self.assertIn("WITH ORDINALITY", body)
        self.assertIn("rowSelectionAuthorized', false", body)
        for forbidden in ("INSERT", "DELETE", "UPDATE", "DROP", "ALTER",
                          "CREATE", "GRANT", "TRUNCATE", "COPY",
                          "pg_dump", "pg_restore", "service_role",
                          "auth.users", "SELECT *"):
            self.assertIsNone(re.search(r"\b" + re.escape(forbidden) + r"\b",
                                        body, flags=re.I),
                              msg=f"unsafe catalog SQL word: {forbidden}")
        for forbidden in ("NOEL_CORE_DATABASE_URL", "SUPABASE_DB_URL",
                          "SUPABASE_SERVICE_ROLE_KEY", "psycopg", "requests",
                          "pg_dump", "pg_restore"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()

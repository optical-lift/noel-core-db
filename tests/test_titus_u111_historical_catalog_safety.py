"""U1.11 fictional catalog graph tests; no database access."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/audit-titus-u111-historical-fk-closure.py"
spec = importlib.util.spec_from_file_location("u111_catalog_auditor", SCRIPT)
auditor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auditor)


def edge(child, parent):
    return {"child": child, "parent": parent}


class TestTitusU111HistoricalCatalog(unittest.TestCase):
    def graph(self):
        return [
            edge("titus.customer_course_drafts_v1", "auth.users"),
            edge("titus.customer_course_drafts_v1", "titus.customer_workspaces_v1"),
            edge("titus.customer_course_material_revisions_v1", "titus.customer_course_drafts_v1"),
            edge("titus.customer_course_units_v1", "titus.customer_course_drafts_v1"),
            edge("titus.customer_course_unit_revisions_v1", "titus.customer_course_units_v1"),
            edge("titus.customer_workspace_entitlements_v1", "auth.users"),
            edge("titus.curriculum_versions", "titus.programs"),
            edge("titus.formation_units", "titus.curriculum_versions"),
            edge("titus.formation_units", "titus.lesson_packets"),
            edge("titus.formation_unit_inputs", "titus.formation_units"),
            edge("titus.formation_unit_inputs", "titus.teacher_source_units"),
            edge("titus.formation_unit_inputs", "draft.song_objects"),
            edge("titus.programs", "titus.programs"),
            edge("titus.unrelated_child", "titus.unrelated_parent"),
        ]

    def test_transitive_descendants_and_external_sources_need_review(self):
        result = auditor.audit(self.graph())
        included = set(result["historicalDescendantRelations"])
        self.assertEqual(len(included), 9)
        self.assertIn("titus.formation_unit_inputs", included)
        self.assertIn("titus.customer_course_unit_revisions_v1", included)
        self.assertNotIn("titus.unrelated_child", included)
        outside = {(e["child"], e["parent"]) for e in result["externalForeignKeyReferences"]}
        self.assertEqual(len(outside), 6)
        for parent in (
            "auth.users", "titus.customer_workspaces_v1",
            "titus.lesson_packets", "titus.teacher_source_units",
            "draft.song_objects",
        ):
            self.assertIn(parent, {e[1] for e in outside})
        for guard in (
            "requiresIndependentRowScopedDispositions",):
            self.assertTrue(result[guard])
        for guard in (
            "actualCustomerRowsRead", "dataBackupTaken",
            "productionWriteAuthorized", "deletionOrReleaseAuthorized",
        ):
            self.assertFalse(result[guard])

    def test_duplicates_cycles_and_order_do_not_change_closure(self):
        a = self.graph()
        first = auditor.audit(a)
        second = auditor.audit(list(reversed(a)) + a[:3])
        self.assertEqual(first["historicalDescendantRelations"],
                         second["historicalDescendantRelations"])
        self.assertEqual(first["externalForeignKeyReferences"],
                         second["externalForeignKeyReferences"])
        self.assertEqual(first["observedForeignKeyPairs"],
                         second["observedForeignKeyPairs"])

    def test_incomplete_catalog_and_malformed_relation_fail_closed(self):
        base = self.graph()
        for altered in (
            [],
            [x for x in base if "titus.programs" not in (x["child"], x["parent"])],
            [dict(child="titus.programs", parent="public.foo;DROP TABLE")],
            [dict(child="titus.programs", parent="auth.users", id="secret")],
            [{"child": "titus.programs"}],
        ):
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                auditor.audit(altered)

    def test_catalog_query_reads_pg_catalog_only(self):
        sql = (
            ROOT / "candidates/shared-teaching-course-clean-cutover-v1/"
                   "U1_11_HISTORICAL_FK_CATALOG_ONLY.sql"
        ).read_text()
        statements = "\n".join(x for x in sql.splitlines()
                               if not x.lstrip().startswith("--")).strip()
        self.assertEqual(statements.split(maxsplit=1)[0].upper(), "SELECT")
        self.assertEqual(statements.count(";"), 1)
        for word in ("pg_constraint", "pg_class", "pg_namespace", "contype"):
            self.assertIn(word, statements)
        for forbidden in ("pg_dump", "customer_.* FROM", "DROP TABLE",
                          "INSERT INTO", "UPDATE ", "DELETE FROM",
                          "NOEL_CORE_DATABASE_URL", "supabase db push"):
            self.assertNotIn(forbidden, statements)


if __name__ == "__main__":
    unittest.main()

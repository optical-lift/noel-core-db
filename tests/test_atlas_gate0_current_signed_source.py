#!/usr/bin/env python3
"""Gate 0 test-only source custody. Does not run, apply, or authorize DDL."""
import ast
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
W = (ROOT / ".github/workflows/atlas-gate0-current-schema-signed-readers.yml").read_text()
P = (ROOT / "scripts/validate-atlas-access03-zone-retirement-signed-http.py").read_text()
FIXTURE = ROOT / "validation/fixtures/20261112160559_atlas_access03_zone_direct_reader_retirement_v1.sql"
POST = ROOT / "validation/migrations/20261112160559_atlas_access03_zone_direct_reader_retirement_v1.sql"


class Gate0CurrentSignedSource(unittest.TestCase):
    def test_python_parses_and_remains_local(self):
        ast.parse(P)
        for required in (
            "base.setup_auth(args.db_url)", "c1.sign_in(api,key,name)",
            "auth.sessions", "127[.]0[.]0[.]1",
            "object_crop_bed_map_v1", "farm_care_zone_v1",
            "zone_registry_source_v1", "unknown object hidden from manager",
            "legacy manager lacking native governing root",
            "UNSAFE GATE0 SIGNED LOCAL DIRECT TABLE READ",
            "farm_hand", "synthetic-private-zone",
            "growing_objects?select=id,label,metadata",
            "crop_cycles?select=id,crop_label,metadata",
        ):
            self.assertIn(required, P)
        for forbidden in (
            "zirqkouammpwxlqfbsvf", "supabase.co",
            "service_role", "auth.admin", "localhost:5432",
        ):
            self.assertNotIn(forbidden, P)
        self.assertIn("raise AssertionError(", P)

    def test_owner_only_snapshot_and_no_prod_write(self):
        for required in (
            "github.event.issue.author_association == 'OWNER'",
            "github.actor == github.repository_owner",
            "environment: production",
            "source_sha:",
            'test "$(git rev-parse HEAD)"',
            "ref: main",
            "--role-only --file",
            "Snapshot Production schema and roles READ ONLY",
            "scripts/check-custody.sh",
            "scripts/check-production-schema-validation-contract.sh",
            "scripts/validate-production-schema-clone.sh",
            "NO-OP test-only",
            "SELECT 1 AS gate0_disposable_current_schema_only",
            "atlas_access03_zone_direct_reader_retirement_clone_only_v1",
            "GATE0_CURRENT_SCHEMA_SIGNED_RESULT=FAIL_UNSAFE_DIRECT_RLS",
            "signed-access03-zone-retirement-summary.txt",
        ):
            self.assertIn(required, W)
        for forbidden in (
            "supabase db push", "supabase migration up",
            "mcp__Supabase__apply_migration", "supabase db reset --linked",
            "SUPABASE_SERVICE_ROLE_KEY",
            "scripts/release-production-migration.sh",
            "git push", "create-user", "admin.createUser",
        ):
            self.assertNotIn(forbidden, W)
        self.assertEqual(W.count("NOEL_CORE_DATABASE_URL: "), 1)
        self.assertLess(W.index("Snapshot Production schema and roles READ ONLY"),
                        W.index("Assemble NO-OP test-only"))

    def test_fictional_source_and_existing_postconditions(self):
        self.assertTrue(FIXTURE.is_file())
        self.assertTrue(POST.is_file())
        f = FIXTURE.read_text()
        p = POST.read_text()
        self.assertIn("fictional-zone-a", f)
        self.assertIn("synthetic-private-zone", f)
        self.assertIn("synthetic-private-crop", f)
        self.assertIn("atlas.crop_cycles", f)
        self.assertIn("atlas.farm_memberships", f)
        self.assertIn("cmd IN ('SELECT','ALL')", p)
        self.assertIn("atlas.v_crop_cycle_registry", p)
        self.assertNotIn("supabase.co", f)
        clean = re.sub(r"--[^\n]*", " ", f)
        statements = [s.strip() for s in clean.split(";") if s.strip()]
        self.assertEqual(len(statements), 33)
        self.assertTrue(all(re.match(r"^(SELECT|UPDATE|INSERT\s+INTO)\b", s, re.I)
                            for s in statements))


if __name__ == "__main__":
    unittest.main()

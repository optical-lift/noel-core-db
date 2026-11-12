#!/usr/bin/env python3
"""Trusted ACCESS-03A clone-controller and signed-probe source contract."""
import re
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
H=(R/"scripts/validate-production-schema-clone.sh").read_text()
P=(R/"scripts/validate-atlas-access03-zone-retirement-signed-http.py").read_text()
W=(R/".github/workflows/atlas-access03-owner-protected-signed-clone.yml").read_text()
class Access03Trusted(unittest.TestCase):
    def test_exact_clone_only_source_gate(self):
        self.assertIn("atlas_access03_zone_direct_reader_retirement_clone_only_v1",H)
        self.assertEqual(H.count("signed_access03_zone_retirement_probe=true"),1)
        self.assertEqual(H.count('[ "$signed_access03_zone_retirement_probe" = true ]; then'),4)
        self.assertIn('"public", "graphql_public", "atlas"',H)
        self.assertIn("genuine signed local ACCESS-03A legacy zone",H)
        self.assertIn("signed-access03-zone-retirement-summary.txt",H)
        self.assertIn("supabase start -x",H)
        self.assertIn("validate-atlas-access03-zone-retirement-signed-http.py",H)
        self.assertIn("supabase db start",H)
    def test_no_live_identity_or_fake_denial(self):
        for token in ("127[.]0[.]0[.]1","base.setup_auth(args.db_url)",
                      "c1.sign_in(api,key,name)","auth.sessions",
                      "Accept-Profile","Content-Profile",
                      "must be an actual SQL denial","42501",
                      "zone_registry_source_v1",
                      "governor_farm_current_inventory_options_self_api_v1",
                      "atlas.farm_memberships","role='manager'",
                      "synthetic-private-zone","synthetic-private-crop",
                      "crop_cycles","PASS ACCESS03 signed"):
            self.assertIn(token,P)
        for bad in ("supabase.co","zirqkouammpwxlqfbsvf","service_role","auth.admin"):
            self.assertNotIn(bad,P)
    def test_only_owner_issue_can_use_schema_dump(self):
        for token in (
          "github.event.issue.author_association == 'OWNER'",
          "github.actor == github.repository_owner",
          "environment: production",
          "candidate_sha:",
          "8aba5474f8a9fdab75c0c3b2729ccefb0a4e3a4f",
          "Snapshot current Production schema and roles READ ONLY",
          "Checkout exact held source",
          "genuine signed ACCESS-03A local clone",
          "ACCESS03_DISPOSABLE_SIGNED_RESULT=PASS"
        ):
            self.assertIn(token,W)
        self.assertEqual(W.count("NOEL_CORE_DATABASE_URL: "),1)
        self.assertLess(W.index("Snapshot current Production schema and roles READ ONLY"),
                        W.index("Checkout exact held source"))
        for bad in ("supabase db push","supabase migration up",
                    "db reset --linked","SUPABASE_SERVICE_ROLE_KEY",
                    "mcp__Supabase__apply_migration"):
            self.assertNotIn(bad,W)
if __name__=="__main__":
    unittest.main()

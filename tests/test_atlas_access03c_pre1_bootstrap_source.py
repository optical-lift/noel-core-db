#!/usr/bin/env python3
"""Test-only held PRE1 source launcher; never a migration or release."""
import unittest
from pathlib import Path
WF=(Path(__file__).resolve().parents[1]/".github/workflows/atlas-access03c-pre1-protected-held-pair-clone.yml").read_text()
class Access03CPre1Launcher(unittest.TestCase):
 def test_owner_protected_exact_source(self):
  for required in ("github.event.issue.author_association == 'OWNER'",
   "github.actor == github.repository_owner","environment: production",
   "Atlas ACCESS-03C-PRE1: protected held-pair signed clone test approval",
   "909d95c198671f9c80e28ad4e58d7534ded22675",
   "candidate_sha","trusted_main_sha","persist-credentials: false",
   "scripts/check-custody.sh","scripts/check-production-release-contract.sh"):
   self.assertIn(required,WF)
 def test_read_only_production_and_local_only_candidate(self):
  for required in ("--role-only --file","NOEL_CORE_DATABASE_URL:",
   "supabase migration new atlas_access03_zone_direct_reader_retirement_clone_only_v1",
   "ac8552f35e4de14f1ae337c29cfc1c2971af1c9b",
   "aff86ae537a7dfbffefa4320e6d21328c32c78d7",
   "1e83ea45d4d7cf64c48ac246f1e0fc500a9d8010",
   'cmp "$dir/candidate.sql" "$migration"',
   "scripts/validate-production-schema-clone.sh",
   "PRE1_CLONE_RESULT=PASS_EXISTING_SIGNED_GATES_AND_POSTCONDITIONS_ONLY",
   "PRE1 HTTP RPC endpoint absence and unknown external clients remain separately HELD"):
   self.assertIn(required,WF)
  for forbidden in ("supabase db push","supabase migration up","scripts/release-production-migration.sh",
   "apply_migration","SUPABASE_SERVICE_ROLE_KEY","DROP FUNCTION atlas."):
   self.assertNotIn(forbidden,WF)
  self.assertEqual(WF.count("NOEL_CORE_DATABASE_URL: "),1)
  self.assertLess(WF.index("Verify exact held SQL"),WF.index("Snapshot Production schema"))
  self.assertLess(WF.index("Snapshot Production schema"),WF.index('cp "$dir/candidate.sql" "$migration"'))
 def test_no_production_dump_uploaded(self):
  part=WF.split("- name: Upload bounded localhost diagnostics only",1)
  self.assertEqual(len(part),2)
  for forbidden in ("pre1-roles.sql","pre1-schema.sql","NOEL_CORE_DATABASE_URL","JWT","secret"):
   self.assertNotIn(forbidden,part[1])
if __name__=="__main__":unittest.main()

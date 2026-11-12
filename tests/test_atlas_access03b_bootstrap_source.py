#!/usr/bin/env python3
"""ACCESS-03B bootstrap: immutable unmerged-source owner-gated clone, no live writes."""
import unittest
from pathlib import Path

R=Path(__file__).resolve().parents[1]
W=(R/".github/workflows/atlas-access03b-held-candidate-protected-clone.yml").read_text()

class HeldCandidateGuard(unittest.TestCase):
    def test_separate_immutable_approval_and_source_before_production_read(self):
        for required in (
            "github.event_name == 'issues'",
            "github.event.issue.author_association == 'OWNER'",
            "github.actor == github.repository_owner",
            "environment: production",
            "github.event.issue.title == 'Atlas ACCESS-03B: protected held-candidate signed clone test approval'",
            "'candidate_sha','trusted_main_sha'",
            "856f6fc7a7c6ba099269bfe58b822f4e2a1c31ae",
            "ref: main",
            "ref: ${{ steps.refs.outputs.candidate_sha }}",
            'test "$(git rev-parse HEAD)" = "${{ steps.refs.outputs.trusted_main_sha }}"',
            'test "$(git -C held rev-parse HEAD)" = "${{ steps.refs.outputs.candidate_sha }}"',
            "python3 tests/test_atlas_access03b_two_table_source.py",
            "python3 tests/test_atlas_access03_trusted_signed_source.py",
            "bash -n held/scripts/validate-production-schema-clone.sh",
            "scripts/check-custody.sh",
            "scripts/check-production-release-contract.sh",
            "scripts/check-production-schema-validation-contract.sh",
        ):
            self.assertIn(required,W)
        self.assertLess(W.index("Check HELD source identity and signed contract"),
                        W.index("Snapshot Production schema and roles READ ONLY"))

    def test_only_production_access_is_read_only_dump(self):
        for required in (
            "Snapshot Production schema and roles READ ONLY (no rows)",
            "NOEL_CORE_DATABASE_URL: ${{ secrets.NOEL_CORE_DATABASE_URL }}",
            'supabase db dump --db-url "$NOEL_CORE_DATABASE_URL" --role-only',
            'supabase db dump --db-url "$NOEL_CORE_DATABASE_URL" --file',
            "source_dir=held/candidates/atlas/atlas_access03b_governed_growing_crop_direct_read_v1",
            'cp "$source_dir/candidate.sql" "$migration"',
            'cmp "$source_dir/candidate.sql" "$migration"',
            '--candidate-migration "${{ steps.scratch.outputs.migration }}"',
            'cd held &&',
            "bash scripts/validate-production-schema-clone.sh",
            "grep -q '^PASS ACCESS03B signed '",
            "ACCESS03B_HELD_SIGNED=FAIL_UNSAFE_DIRECT_READ",
            "ACCESS03B_HELD_SIGNED=FAILED_OR_NOT_REACHED",
        ):
            self.assertIn(required,W)
        self.assertEqual(W.count("NOEL_CORE_DATABASE_URL:"),1)
        pre=W[:W.index("Snapshot Production schema and roles READ ONLY")]
        self.assertNotIn("NOEL_CORE_DATABASE_URL",pre)
        for forbidden in (
            "supabase db push", "supabase migration up", "supabase db reset --linked",
            "supabase migration repair", "supabase db query", "apply_migration",
            "execute_sql","scripts/release-production-migration.sh",
            "SUPABASE_SERVICE_ROLE_KEY","curl -X POST https://","git push",
            "actions/upload-artifact@v3","sed -i s/42501/",
        ):
            self.assertNotIn(forbidden,W)

    def test_artifact_allowlist_is_disposable_only(self):
        x=W.split("- name: Preserve ONLY bounded disposable logs; never live schema/roles",1)
        self.assertEqual(len(x),2)
        section=x[1]
        for required in (
            "if: always()","uses: actions/upload-artifact@v4",
            "retention-days: 7", "if-no-files-found: warn",
            "access03b-held-artifacts/summary.md",
            "access03b-held-artifacts/candidate-fixture.log",
            "access03b-held-artifacts/candidate-migration.log",
            "access03b-held-artifacts/postconditions.log",
            "access03b-held-artifacts/schema-lint-delta.json",
            "access03b-held-artifacts/signed-access03-zone-retirement-summary.txt",
            "access03b-held-artifacts/signed-access03-zone-retirement.log",
        ):
            self.assertIn(required,section)
        self.assertEqual(section.count("${{ runner.temp }}/access03b-held-artifacts/"),7)
        for forbidden in ("access03b-held-schema.sql","access03b-held-roles.sql",
                          "NOEL_CORE_DATABASE_URL","secrets.","jwt",
                          "auth.users","restore-schema.log","restore-roles.log"):
            self.assertNotIn(forbidden,section)


if __name__=="__main__":
    unittest.main()

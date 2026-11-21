#!/usr/bin/env python3
"""No-network review-only source-contract proof; never signed HTTP or SQL."""
import os
from pathlib import Path
import unittest

import uniops_history_stale_token_source_contract_held as proposal


class HistoricalStaleImpactReviewOnly(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # CI checks out exact immutable history and bridge refs into safe paths.
        # Missing inputs are a failure, not an assumed approval.
        sql_path = os.environ.get("UNI_OPS_HISTORY_ORIGINAL_SQL", "")
        bridge_path = os.environ.get("UNI_OPS_HISTORY_ORIGINAL_BRIDGE", "")
        if not sql_path or not bridge_path:
            raise proposal.SourceLawHold("Missing immutable source checkout inputs")
        cls.sql = Path(sql_path).read_bytes()
        cls.bridge = Path(bridge_path).read_bytes()

    def test_exact_pinned_source_identities(self):
        self.assertEqual(proposal.git_blob_sha(self.sql), proposal.HISTORY_BLOB)
        self.assertEqual(proposal.git_blob_sha(self.bridge), proposal.BRIDGE_BLOB)

    def test_one_historical_sql_exception_changes_nothing_else(self):
        sql, _ = proposal.propose_historical_conflict(self.sql, self.bridge)
        self.assertEqual(self.sql.count(proposal.OLD_SQL), 1)
        self.assertEqual(sql.count(proposal.NEW_SQL), 1)
        self.assertEqual(sql, self.sql.replace(proposal.OLD_SQL, proposal.NEW_SQL, 1))
        self.assertNotIn(b"ERRCODE='40001'", sql)
        self.assertIn(b"USING ERRCODE='PT409'", sql)

    def test_bridged_signed_expectation_is_exact_conflict_not_http500(self):
        _, bridge = proposal.propose_historical_conflict(self.sql, self.bridge)
        expected = self.bridge.replace(proposal.OLD_BRIDGE, proposal.NEW_BRIDGE, 1)
        expected = expected.replace(proposal.OLD_STATUS, proposal.NEW_STATUS, 1)
        self.assertEqual(bridge, expected)
        self.assertIn(b'return "PT409"', bridge)
        self.assertIn(b'status == 409 if expected == "PT409"', bridge)
        self.assertNotIn(b'return "40001"', bridge)
        self.assertNotIn(b'if status not in (400, 401, 403, 409) or code', bridge)
        compile(bridge, "<review-only-git-blob>", "exec")

    def test_unreviewed_sql_bytes_cannot_be_transformed(self):
        unreviewed = self.sql.replace(b"FOR UPDATE;", b"FOR SHARE;", 1)
        self.assertNotEqual(unreviewed, self.sql)
        with self.assertRaisesRegex(proposal.SourceLawHold, "source mismatch"):
            proposal.propose_historical_conflict(unreviewed, self.bridge)

    def test_unreviewed_bridge_bytes_cannot_be_transformed(self):
        unreviewed = self.bridge.replace(b"return \"42501\"", b"return \"PT403\"", 1)
        self.assertNotEqual(unreviewed, self.bridge)
        with self.assertRaisesRegex(proposal.SourceLawHold, "adapter source mismatch"):
            proposal.propose_historical_conflict(self.sql, unreviewed)

    def test_signed_and_security_invariants_preserved(self):
        sql, bridge = proposal.propose_historical_conflict(self.sql, self.bridge)
        for snippet in (
            b"atlas.company_work_native_ledger_owner_self_v1",
            b"atlas.company_work_retirement_dependency_snapshot_v1",
            b"pg_advisory_xact_lock",
            b"FOR UPDATE;",
            b"historical_self_adoption_review_events_v1",
            b"apply_work_lifecycle_transition_internal_v1",
            b"TO authenticated;",
        ):
            self.assertIn(snippet, sql)
        for snippet in (
            b"PINNED_SOURCE_BLOB",
            b"LOCAL_PG.fullmatch",
            b"len(set(tokens.values())) != 4",
            b"load_pinned_companion(source_path)",
        ):
            self.assertIn(snippet, bridge)


if __name__ == "__main__":
    unittest.main()

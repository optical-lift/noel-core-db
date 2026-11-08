"""No credentials/DB: verify two exact review overrides and 16 untouched stages."""
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "review", Path(__file__).with_name("prepare_reviewed_uniops_u2c_context_scratch.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

A = "u2c-accepted-only-original-guard"
B = "u2c-schema-and-acl-postconditions"


class ReviewedCloneSourceTests(unittest.TestCase):
    def setUp(self):
        self.original_pins = review.CHANGES
        self.new_a = (
            b"CREATE FUNCTION fixture_dummy() RETURNS text AS $$ "
            b"SELECT 'U2C_ACCEPTED_RHYTHM_CONTEXT_ONLY' $$; "
            b"-- o.offer_state='accepted' "
            b"atlas.guard_work_growing_object_context_v1 "
            b"physical Work source and exact Ledger custody unproven "
            b"require_accepted_prework_standing_original_v1 "
            + b"bounded " * 45
        )
        self.new_b = (
            b"DO $$ BEGIN "
            b"PERFORM 'work_growing_object_context_guard_v1'; "
            b"PERFORM 'U2C_ACCEPTED_RHYTHM_CONTEXT_ONLY'; "
            b"PERFORM 'physical Work source and exact Ledger custody unproven'; "
            b"PERFORM 'legacy_task_slice'; "
            + b"source-review " * 50 + b" END $;"
        )
        self.old_a = b"-- frozen accepted-first source, not the review"
        self.old_b = b"-- frozen schema contract, not the review"
        review.CHANGES = {
            A: (review.git_blob(self.old_a), review.git_blob(self.new_a), "02.sql"),
            B: (review.git_blob(self.old_b), review.git_blob(self.new_b), "04.sql"),
        }
        self.stage_names = (
            ["history-" + str(i) for i in range(7)]
            + ["fixed-" + str(i) for i in range(9)]
            + [A, B]
        )
        self.stages = []
        self.sql = b"TEST ONLY: synthetic 18-stage assembly\n"
        for stage in self.stage_names:
            if stage in review.CHANGES:
                old, _, _ = review.CHANGES[stage]
                data = self.old_a if stage == A else self.old_b
                checkout = "u2c"
            else:
                data = ("fixed test stage " + stage).encode()
                old = review.git_blob(data)
                checkout = "lifecycle"
            self.stages.append({"stage": stage, "checkout": checkout,
                                "blob": old,
                                "sha256": hashlib.sha256(data).hexdigest()})
            if stage in review.CHANGES:
                self.sql += review.stage_frame(stage, old, data)
            else:
                self.sql += (
                    f"-- BEGIN PINNED STAGE {stage} blob:{old}\n".encode()
                    + data + b"\n"
                    + f"-- END PINNED STAGE {stage}\n\n".encode()
                )
        self.replacement = {A: self.new_a, B: self.new_b}

    def tearDown(self):
        review.CHANGES = self.original_pins

    def test_exact_two_changed_sixteen_stable(self):
        out, entries = review.revised_bytes(
            self.sql, self.stages, self.replacement)
        self.assertEqual(len(entries), 18)
        self.assertEqual(sum(x["checkout"] == "u2c_review" for x in entries), 2)
        self.assertEqual(out.count(b"TEST ONLY: synthetic"), 1)
        for stage in self.stage_names[:-2]:
            prior = next(x for x in self.stages if x["stage"] == stage)
            new = next(x for x in entries if x["stage"] == stage)
            self.assertEqual(prior, new)
            self.assertIn(
                f"-- BEGIN PINNED STAGE {stage} blob:{prior['blob']}\n".encode(),
                out)
        self.assertNotIn(self.old_a, out)
        self.assertNotIn(self.old_b, out)
        self.assertIn(self.new_a.rstrip(), out)
        self.assertIn(self.new_b.rstrip(), out)

    def test_reviewed_blob_cannot_drift(self):
        altered = dict(self.replacement, **{A: self.new_a + b"one byte"})
        with self.assertRaisesRegex(ValueError, "blob mismatch"):
            review.revised_bytes(self.sql, self.stages, altered)

    def test_frozen_stage_manifest_cannot_drift(self):
        changed = [dict(x) for x in self.stages]
        changed[-1]["blob"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "original stage identity"):
            review.revised_bytes(self.sql, changed, self.replacement)

    def test_duplicate_or_missing_original_marker_is_rejected(self):
        header = (f"-- BEGIN PINNED STAGE {A} blob:"
                  f"{review.CHANGES[A][0]}\n").encode()
        with self.assertRaisesRegex(ValueError, "duplicated"):
            review.revised_bytes(self.sql + header, self.stages, self.replacement)
        with self.assertRaisesRegex(ValueError, "absent"):
            review.revised_bytes(self.sql.replace(header, b"", 1),
                                 self.stages, self.replacement)

    def test_ambiguous_extra_stage_is_rejected(self):
        changed = list(self.stages) + [self.stages[0]]
        with self.assertRaisesRegex(ValueError, "18 distinct"):
            review.revised_bytes(self.sql, changed, self.replacement)

    def test_missing_accepted_and_legacy_guard_is_rejected(self):
        missing = self.new_a.replace(b"o.offer_state='accepted'", b"accept=none")
        review.CHANGES = dict(review.CHANGES)
        review.CHANGES[A] = (
            review.CHANGES[A][0], review.git_blob(missing), "02.sql")
        with self.assertRaisesRegex(ValueError, "original writer consent"):
            review.revised_bytes(self.sql, self.stages,
                                 {A: missing, B: self.new_b})

    def test_postconditions_must_preserve_original_legacy_guard(self):
        missing = self.new_b.replace(b"legacy_task_slice", b"missing_legacy")
        review.CHANGES = dict(review.CHANGES)
        review.CHANGES[B] = (
            review.CHANGES[B][0], review.git_blob(missing), "04.sql")
        with self.assertRaisesRegex(ValueError, "review postconditions"):
            review.revised_bytes(self.sql, self.stages,
                                 {A: self.new_a, B: missing})

    def test_additional_source_override_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "exact two"):
            review.revised_bytes(self.sql, self.stages, {A: self.new_a})


if __name__ == "__main__":
    unittest.main()

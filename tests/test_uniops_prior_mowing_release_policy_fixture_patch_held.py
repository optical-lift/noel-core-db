#!/usr/bin/env python3
"""No network/SQL source-and-tamper tests; consume the exact pinned fixture."""
import ast
import os
from pathlib import Path
import unittest
import uniops_prior_mowing_release_policy_fixture_patch_held as patcher

class PriorMowingPhysicalBindingSourceOnly(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=Path(os.environ["UNI_OPS_PINNED_FIXTURE_SOURCE"]).read_bytes()
        cls.staged=Path(os.environ["UNI_OPS_SOURCE_STAGED_DRIVER"]).read_bytes()
        if patcher.git_blob(cls.fixture)!=patcher.FROZEN_FIXTURE_BLOB:
            raise AssertionError("Cannot test against an unreviewed fixture")

    def test_exact_omitted_release_policy_key_is_the_only_fixture_change(self):
        before=self.fixture.decode("utf8")
        after=patcher.patch_fixture(self.fixture).decode("utf8")
        ast.parse(after)
        self.assertNotEqual(before,after)
        original=after.replace(patcher.FIXED_COLUMNS,patcher.ORIGINAL_COLUMNS,1)
        original=original.replace(patcher.FIXED_VALUES,patcher.ORIGINAL_VALUES,1)
        original=original.replace(patcher.FIXED_POSTCONDITION,patcher.ORIGINAL_POSTCONDITION,1)
        original=original.replace(patcher.FIXED_ROW_GUARD,patcher.ORIGINAL_ROW_GUARD,1)
        self.assertEqual(original,before)
        self.assertIn("   planned_occurrence_id,release_policy_id,released_at,metadata)",after)
        self.assertIn(" '{RELEASED}'::uuid,'{POLICY}'::uuid",after)
        self.assertIn("and task.get(\"release_policy_id\")==POLICY",after)
        self.assertIn("and release_policy_id='{POLICY}'::uuid",after)
        self.assertEqual(after.count("INSERT INTO atlas.tasks"),1)
        self.assertEqual(after.count("UPDATE atlas.planned_work_occurrences"),1)
        self.assertEqual(after.count("COMMIT;"),1)

    def test_signed_driver_remains_exact_except_new_frozen_fixture_hash(self):
        corrected=patcher.patch_fixture(self.fixture)
        result=patcher.patch_driver(self.staged,corrected)
        before=self.staged.decode("utf8")
        after=result.decode("utf8")
        new_blob=patcher.git_blob(corrected)
        self.assertNotEqual(new_blob,patcher.FROZEN_FIXTURE_BLOB)
        self.assertEqual(after.replace(new_blob,patcher.FROZEN_FIXTURE_BLOB),before)
        self.assertEqual(after.count("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS"),1)
        self.assertEqual(after.count("history_receipt=hist.prove("),1)
        self.assertEqual(after.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)"),1)
        ast.parse(after)

    def test_refuses_missing_duplicate_tampered_or_double_patched_inputs(self):
        fixed=patcher.patch_fixture(self.fixture)
        malformed=(
          self.fixture[:-1],
          self.fixture.replace(patcher.ORIGINAL_COLUMNS.encode(),b'  planned_occurrence_id,released_at,metadata)\n'),
          self.fixture.replace(patcher.ORIGINAL_COLUMNS.encode(),(patcher.ORIGINAL_COLUMNS*2).encode()),
          fixed,
        )
        for item in malformed:
            with self.subTest(item_size=len(item)):
                with self.assertRaises(patcher.PriorMowingFixturePatchRefusal):
                    patcher.patch_fixture(item)
        for marker in ("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",
                       "history_receipt=hist.prove(",
                       "_legacy.install(a.db_url,_prior_mowing_traced_sql)"):
            tampered=self.staged.replace(marker.encode(),b"UNREVIEWED",1)
            with self.subTest(marker=marker):
                with self.assertRaises(patcher.PriorMowingFixturePatchRefusal):
                    patcher.patch_driver(tampered,fixed)
        with self.assertRaises(patcher.PriorMowingFixturePatchRefusal):
            patcher.patch_driver(patcher.patch_driver(self.staged,fixed),fixed)

if __name__=="__main__":
    unittest.main(verbosity=2)

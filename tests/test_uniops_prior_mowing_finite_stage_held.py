#!/usr/bin/env python3
"""No-network negative tests for exact prior-mowing diagnostic-only stage overlay."""
import ast
import unittest

import uniops_prior_mowing_finite_stage_held as subject

SPECIMEN=b'''#!/usr/bin/env python3
def main():
    _legacy.install(a.db_url,sql)
    _legacy_initial=_legacy.capture(a.db_url,sql)
    print("UNI_OPS_PRIOR_MOWING_FIXTURE=SEEDED_BEFORE_GOVERNANCE")
    _legacy.require_preserved(x,y,before,after)
    print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")
'''

class ExactPriorMowingStage(unittest.TestCase):
    def test_stage_contains_no_new_sql_or_auth_and_compiles(self):
        out=subject.inject(SPECIMEN).decode("utf8")
        ast.parse(out)
        self.assertEqual(out.count("_legacy.install("),1)
        self.assertEqual(out.count("_legacy_initial=_legacy.capture("),1)
        self.assertEqual(out.count("UNI_OPS_PRIOR_MOWING_PHASE="),5)
        self.assertTrue(out.index("PHASE=install_entered")<out.index("PHASE=before_census_called"))
        self.assertTrue(out.index("PHASE=after_census_called")<out.index("PHASE=fixture_install_complete"))
        for token in ("_legacy.NONCARRIER_CENSUS_SQL","_legacy.INSTALL_SQL",
                      "UNI_OPS_PRIOR_MOWING_PHASE=initial_capture_complete",
                      "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS"):
            self.assertIn(token,out)
        for forbidden in ("CREATE ROLE","ALTER ROLE","service_role","db push","subprocess","requests.",
                          "disable row level","SET row_security","auth.sessions"):
            self.assertNotIn(forbidden,out)
        self.assertEqual(out.count("return sql(_db,_statement)"),1)

    def test_duplicate_missing_and_tampered_inputs_fail(self):
        bad=(SPECIMEN.replace(b"    _legacy.install(a.db_url,sql)\n",b""),
             SPECIMEN+SPECIMEN,
             SPECIMEN.replace(b"UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",b"NO"),
             SPECIMEN.replace(b"    _legacy_initial=_legacy.capture(a.db_url,sql)\n",b""),
             subject.inject(SPECIMEN))
        for x in bad:
            with self.subTest(size=len(x)):
                with self.assertRaises(subject.FiniteStageRefusal):
                    subject.inject(x)

    def test_log_reader_returns_only_strict_fixed_labels(self):
        self.assertEqual(subject.extract_stage(""),"not_reported")
        self.assertEqual(subject.extract_stage("private user login\nUNI_OPS_PRIOR_MOWING_PHASE=install_entered\n"),"install_entered")
        self.assertEqual(subject.extract_stage("UNI_OPS_PRIOR_MOWING_PHASE=install_entered\n"
                                                "UNI_OPS_PRIOR_MOWING_PHASE=physical_seed_called\n"
                                                "private SQL never returned\n"),"physical_seed_called")
        self.assertEqual(subject.extract_stage("UNI_OPS_PRIOR_MOWING_PHASE=physical_seed_called; secret=123"),
                         "untrusted_marker")
        self.assertEqual(subject.extract_stage({"raw":"not text"}),"not_reported")
        self.assertEqual(subject.extract_stage("UNI_OPS_PRIOR_MOWING_PHASE=initial_capture_complete\n"),
                         "initial_capture_complete")

if __name__=="__main__":
    unittest.main(verbosity=2)

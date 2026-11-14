#!/usr/bin/env python3
"""No-network held classifier tests: fixed enums, no private exception text."""
import unittest
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("history_failure",
    HERE/"uniops_p3_history_safe_python_failure_held.py")
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class SafeHistoryDiagnostic(unittest.TestCase):
    def test_pre_u4_unverified_python_exception(self):
        log=("PASS unrelated first Work\nTraceback (most recent call last):\n"
             "  File \"secret\", line 5\nNameError: user credentials private\n")
        self.assertEqual(m.classify(log),
            ("mowing_p3_not_proven_in_this_run","python_name_error"))

    def test_genuine_p3_then_history_failed_sql_subprocess(self):
        log=("PASS something\n"+m.P3_MARK+"\n"+
             "Traceback (most recent call last):\n"
             "  File \"/private/secret\", line 22\n"
             "subprocess.CalledProcessError: Command private SQL with token\n")
        self.assertEqual(m.classify(log),
             ("mowing_p3_signed_before_history","local_sql_subprocess_error"))
        self.assertNotIn("token",str(m.classify(log)))
        self.assertNotIn("private",str(m.classify(log)))

    def test_fixed_classes_and_unrecognized_error(self):
        for kind,label in m.EXCEPTION_CLASSES.items():
            with self.subTest(kind=kind):
                self.assertEqual(m.classify("Traceback (most recent call last):\n"+
                    kind+": highly secret SQL")[1],label)
        self.assertEqual(m.classify(
            "Traceback (most recent call last):\nUnknownDanger: private")[1],
            "unknown_or_absent_exception")
        self.assertEqual(m.classify("Nothing happened"),
           ("mowing_p3_not_proven_in_this_run","unknown_or_absent_exception"))

    def test_completed_history_and_replay_branch(self):
        self.assertEqual(m.classify(
            m.P3_MARK+"\n"+m.HISTORY_MARK+"\n"),
            ("mowing_conserved_after_history","unknown_or_absent_exception"))
        self.assertEqual(m.classify(
            m.P3_MARK+"\n"+m.GOVERNOR_MARK+" owner passed\n"),
            ("governor_receipt_before_conservation","unknown_or_absent_exception"))

    def test_refuse_oversize_and_missing_private_log(self):
        self.assertEqual(m.classify(None),("log_unavailable","log_unavailable"))
        self.assertEqual(m.classify("a"*(m.MAX_BYTES+1)),
            ("log_oversize","not_classified"))


    def test_fixed_handoff_and_fixture_stages_are_distinct_from_final_pass(self):
        cases=(
            ("handoff","pre_snapshot_started"),
            ("handoff","pre_snapshot_captured"),
            ("handoff","fixture_adapter_ready"),
            ("handoff","governor_started"),
            ("fixture","membership_preflight"),
            ("fixture","membership_absent"),
            ("fixture","membership_not_exactly_one"),
            ("fixture","membership_query_failed"),
            ("fixture","membership_confirmed"),
            ("fixture","person_identity_preflight"),
            ("fixture","identity_query_failed"),
            ("fixture","person_identity_misaligned"),
            ("fixture","membership_create_authorized"),
            ("fixture","membership_postseed_not_one"),
            ("fixture","membership_created"),
            ("fixture","seed_apply_started"),
            ("fixture","seed_apply_failed"),
            ("fixture","seed_applied"),
            ("fixture","allocation_query_failed"),
            ("fixture","allocation_not_exactly_one"),
            ("fixture","fixture_verified"),
            ("handoff","governor_returned"),
            ("handoff","conservation_started"),
            ("handoff","conservation_verified"),
        )
        for family,value in cases:
            prefix=(m.HANDOFF_PREFIX if family=="handoff"
                    else m.FIXTURE_PREFIX)
            log=(m.P3_MARK+"\nprivate SQL and JWT intentionally withheld\n"
                 +prefix+value+"\n")
            with self.subTest(family=family,stage=value):
                self.assertEqual(m.classify_stage(log),family+"_"+value)
                self.assertNotIn("private",m.classify_stage(log))
                self.assertEqual(m.classify(log)[0],
                                 "mowing_p3_signed_before_history")

    def test_last_stage_must_be_exact_and_unknown_never_leaks(self):
        log=(m.P3_MARK+"\n"+m.HANDOFF_PREFIX+"governor_started\n"
             +m.FIXTURE_PREFIX+"membership_preflight\n"
             +m.FIXTURE_PREFIX+"membership_absent\n")
        self.assertEqual(m.classify_stage(log),"fixture_membership_absent")
        self.assertEqual(m.classify_stage(m.P3_MARK+"\n"),
                         "p3_checkpoint_before_handoff")
        self.assertEqual(m.classify_stage("unrelated"),"history_stage_not_reached")
        self.assertEqual(m.classify_stage(None),"log_unavailable")
        self.assertEqual(m.classify_stage("x"*(m.MAX_BYTES+1)),"log_oversize")
        self.assertEqual(m.classify_stage(
            m.HANDOFF_PREFIX+"secret path and SQL"),"unverified_stage")
        self.assertEqual(m.classify_stage(
            m.FIXTURE_PREFIX+"membership_absent with secret"),"unverified_stage")


    def test_safe_seed_error_markers_reject_arbitrary_private_data(self):
        for kind in m.SEED_SQL_KINDS:
            for progress in m.SEED_PROGRESS:
                with self.subTest(kind=kind,progress=progress):
                    private="PRIVATE_SQL_CREDENTIAL"
                    log=("PRIVATE SQL: "+private+"\n"
                         +m.SEED_KIND_PREFIX+kind+"\n"
                         +m.SEED_PROGRESS_PREFIX+progress+"\n")
                    self.assertEqual(m.classify_seed_detail(log),(kind,progress))
                    self.assertNotIn(private,str(m.classify_seed_detail(log)))
        self.assertEqual(m.classify_seed_detail("No marker"),
                         ("not_reported","not_reported"))
        self.assertEqual(m.classify_seed_detail(None),
                         ("log_unavailable","log_unavailable"))
        self.assertEqual(m.classify_seed_detail("A"*(m.MAX_BYTES+1)),
                         ("log_oversize","log_oversize"))
        self.assertEqual(m.classify_seed_detail(
            m.SEED_KIND_PREFIX+"foreign_key_constraint with secret"),
            ("unverified","unverified"))
        self.assertEqual(m.classify_seed_detail(
            m.SEED_PROGRESS_PREFIX+"after_one_insert_tag with SQL"),
            ("unverified","unverified"))


if __name__=="__main__":
    unittest.main(verbosity=2)

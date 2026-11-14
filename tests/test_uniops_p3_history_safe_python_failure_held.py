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

if __name__=="__main__":
    unittest.main(verbosity=2)

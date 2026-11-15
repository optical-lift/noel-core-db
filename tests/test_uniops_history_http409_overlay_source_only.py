#!/usr/bin/env python3
"""Pure source-only negative tests; no SQL execution, actors or network."""
import importlib.util
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "held_history_override",HERE/"append_uniops_history_http409_disposable_held.py")
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
CANDIDATE=(HERE.parent/"candidates"/
           "atlas_uniops_historical_stale_transport_v3"/"candidate.sql")

def fixture():
    return ("-- BEGIN PINNED STAGE x\n-- END PINNED STAGE x\n"*18
            +"-- BEGIN PINNED P3 6A HELD STAGE x\n"
             "-- END PINNED P3 6A HELD STAGE x\n"*8)

class History409Overlay(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=CANDIDATE.read_bytes()
        cls.base=fixture()

    def test_pinned_source_exactly_once_after_reviewed_stages(self):
        out=m.append_only(self.base,self.source)
        self.assertEqual(out.count(m.BEGIN_MARK),1)
        self.assertEqual(out.count(m.END_MARK),1)
        self.assertEqual(out.count("RAISE SQLSTATE 'PGRST'"),1)
        self.assertIn('DETAIL=\'{"status":409,"headers":{}}\'',out)
        self.assertIn(self.base.rstrip(),out)
        self.assertIn("\nBEGIN;\n",out)
        self.assertIn("\nCOMMIT;\n",out)
        self.assertLess(out.index(m.BEGIN_MARK),out.index("RAISE SQLSTATE 'PGRST'"))
        self.assertLess(out.index("COMMIT;\n"+m.END_MARK),len(out))
        self.assertNotIn("USING ERRCODE='40001'",out)
        self.assertEqual(m.git_blob(self.source),m.CANDIDATE_BLOB)

    def test_rejects_duplicate_or_drifted_source(self):
        good=m.append_only(self.base,self.source)
        for invalid in (
            good,
            self.base.replace("-- BEGIN PINNED STAGE x","-- BEGIN BAD STAGE x",1),
            self.base+"-- BEGIN PINNED P3 6A HELD STAGE x\n",
            self.base.replace("-- END PINNED STAGE x","-- END PINNED OTHER x",1),
            self.base+m.BEGIN_MARK,
            "",
        ):
            with self.subTest(kind=invalid[:25]):
                with self.assertRaises(m.HeldOverlayRefusal):
                    m.append_only(invalid,self.source)

    def test_rejects_unreviewed_candidate_bits(self):
        for invalid in (
            self.source.replace(b'"status":409',b'"status":200',1),
            self.source.replace(b"company_work_native_ledger_owner_self_v1",
                                b"unreviewed_owner",1),
            self.source+b"\nGRANT EXECUTE TO anon;",
            self.source[:-5]
        ):
            with self.subTest(length=len(invalid)):
                with self.assertRaises(m.HeldOverlayRefusal):
                    m.append_only(self.base,invalid)

if __name__=="__main__":
    unittest.main(verbosity=2)

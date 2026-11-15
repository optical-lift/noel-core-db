#!/usr/bin/env python3
"""No-network proof that HELD prior mowing carriers attach to EXACT frozen signed sources.

No SQL is executed. No Auth, actors, production or disposable database is started.
"""
import argparse
import ast
from pathlib import Path
import unittest

import prepare_uniops_preexisting_mowing_signed_held as new
import prepare_uniops_p3_history_signed_followon_held as parent

P=argparse.ArgumentParser(add_help=False)
for name in ("driver","bridge","companion","guard","p3-hook","preparer","compat","fixture"):
    P.add_argument("--"+name,required=True,type=Path)
PATHS=P.parse_args()

def originals():
    files=(PATHS.driver,PATHS.bridge,PATHS.companion,PATHS.guard,PATHS.p3_hook,
           PATHS.preparer,PATHS.compat,PATHS.fixture)
    if any(not x.is_file() or x.is_symlink() for x in files):
        raise AssertionError("Only real regular pinned source inputs allowed")
    return [p.read_bytes() for p in files]

class NoNetworkFrozenSignedComposition(unittest.TestCase):
    def test_real_frozen_composition_only_new_physical_custody(self):
        args=originals()
        output=new.prepare(*args)
        code=output.decode("utf8")
        ast.parse(code)
        self.assertEqual(code.count("_legacy.install(a.db_url,sql)"),1)
        self.assertEqual(code.count("_legacy_initial=_legacy.capture(a.db_url,sql)"),1)
        self.assertEqual(code.count("_legacy_before=_legacy.capture(a.db_url,sql)"),1)
        self.assertEqual(code.count("_legacy_after=_legacy.capture(a.db_url,sql)"),1)
        self.assertEqual(code.count("_legacy.require_rows_unchanged("),1)
        self.assertEqual(code.count("_legacy.require_preserved("),1)
        self.assertEqual(code.count("history_receipt=hist.prove("),1)
        self.assertEqual(code.count("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"),1)
        self.assertEqual(code.count("UNI_OPS_SIGNED_HISTORY_CANCEL=PASS"),1)
        self.assertEqual(code.count("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS"),1)
        self.assertLess(code.index("_legacy.install(a.db_url,sql)"),
                        code.index("count_before=int(sql(a.db_url,"))
        self.assertLess(code.index("_legacy_initial=_legacy.capture"),
                        code.index("_legacy_before=_legacy.capture"))
        self.assertLess(code.index("_legacy_before=_legacy.capture"),
                        code.index("history_receipt=hist.prove("))
        self.assertLess(code.index("history_receipt=hist.prove("),
                        code.index("_legacy_after=_legacy.capture"))
        self.assertLess(code.index("_legacy.require_preserved("),
                        code.index("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"))
        # Composed code still runs frozen actual RPC/denials, not a fake method.
        for fragment in ('sql=_history_sql_probe,rpc=_history_rpc_probe,c1=_history_fixture_c1)',
                         'def _history_rpc_probe(_api,_key,_token,_name,_params):',
                         'signed["no-seat"][0]',
                         'U4_SIGNED_ACTUAL_RESULT_DONE=PASS'):
            self.assertIn(fragment,code)
        # Explicitly no claim of signed completion from a source-only compile.
        self.assertNotIn('UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=SIGNED_PASS',code)

    def test_each_real_immutable_input_fails_closed_on_one_byte_change(self):
        args=originals()
        for i in range(len(args)):
            with self.subTest(input=i):
                bad=args.copy()
                bad[i]+=b"\n# source drift, no authorized signed run"
                with self.assertRaises((new.LegacyCarrierCompositionRefusal,
                                        parent.P3HistoricalRefusal,
                                        parent.original.HeldHookRefusal)):
                    new.prepare(*bad)

    def test_duplicate_injection_refused_and_parent_unchanged(self):
        args=originals()
        reviewed=parent.prepare(*args[:7])
        composed=new.inject(reviewed,args[7])
        with self.assertRaises(new.LegacyCarrierCompositionRefusal):
            new.inject(composed,args[7])
        self.assertTrue(reviewed.startswith(b"#!/usr/bin/env python3"))
        self.assertNotIn(b"UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=",reviewed)
        self.assertIn(b"UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",composed)

if __name__=="__main__":
    unittest.main(verbosity=2)

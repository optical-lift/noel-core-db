#!/usr/bin/env python3
"""No-network source contract for exact frozen U4 -> native worker browser hook."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest

HERE=Path(__file__).resolve().parent
TOOL=HERE/"prepare_uniops_native_worker_actual_hook_held.py"
RUNNER=HERE/"run-uniops-native-worker-actual-local.sh"
spec=importlib.util.spec_from_file_location("native_worker_hook",TOOL)
hook=importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class WorkerActualSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source=os.environ.get("FROZEN_U4_SOURCE","")
        cls.frozen=Path(source)
        if not cls.frozen.is_file():
            raise AssertionError("Immutable frozen U4 source checkout missing")
        cls.original=cls.frozen.read_bytes()
        assert hook.git_blob(cls.original)==hook.FROZEN_SOURCE_BLOB

    def test_exact_one_call_and_all_existing_negatives_retained(self):
        changed=hook.prepare(self.original)
        before=self.original.decode()
        after=changed.decode()
        self.assertEqual(after.count(hook.REPLACEMENT),1)
        self.assertEqual(after.count(hook.NEEDLE),0)
        for source_line in (
            'for actor in ("outsider","owner"):',
            'status, response = call("worker",invalid)',
            'status, replay = call("worker")',
            'U4 signed retry produced a second Result or changed its identity',
            'U4 Result/Done produced an unauthorized successor, task, offer or plan',
            'U4 physical Result and domain acceptance are not exact originals',
            'U4 original Work accepted by the actual canonical Person',
        ):
            if source_line in before:
                self.assertIn(source_line,after)
        self.assertIn('private.unlink(missing_ok=True)',after)
        self.assertIn('payload["p_action_id"]=receipt["actionId"]',after)
        self.assertIn('return 200,receipt["receipt"]',after)
        self.assertIn('subprocess.run(',after)
        self.assertIn('ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED',after)
        self.assertIn('U4_NATIVE_SIGNED_WORKER_BROWSER_ORIGIN=PASS',after)
        compile(after,hook.OUTPUT_FILE,"exec")

    def test_changed_source_or_double_install_refused(self):
        with self.assertRaises(ValueError):
            hook.prepare(self.original+b"# changed")
        changed=hook.prepare(self.original)
        with self.assertRaises(ValueError):
            hook.prepare(changed)
        with self.assertRaises(ValueError):
            hook.prepare(self.original.replace(b'status, response = call("worker")',
                    b'status, response = call("outsider")'))

    def test_runner_is_nonproduction_and_source_sha_pinned(self):
        shell=RUNNER.read_text()
        self.assertIn("159c10041c2167c7dccbe56e397de4db9c33651c",shell)
        self.assertIn("ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED",shell)
        self.assertIn("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",shell)
        self.assertIn("NEXT_PUBLIC_SUPABASE_ANON_KEY",shell)
        self.assertIn("VERCEL_ENV=preview",shell)
        self.assertIn("NOEL_CORE_DATABASE_URL",shell)
        self.assertIn("127[.]0[.]0[.]1",shell)
        self.assertIn("test -s \"$private\"",shell)
        self.assertIn("test ! -L \"$private\"",shell)
        for forbidden in ("supabase db push","apply_migration","DROP TABLE","docker run"):
            self.assertNotIn(forbidden,shell)
        lint=subprocess.run(["bash","-n",str(RUNNER)],capture_output=True,text=True)
        self.assertEqual(lint.returncode,0,lint.stderr)
        denied=subprocess.run(["bash",str(RUNNER)],capture_output=True,text=True)
        self.assertNotEqual(denied.returncode,0)
        self.assertEqual(denied.stdout,
           "BLOCKED ATLAS_NATIVE_WORKER_PHYSICAL_ACTUAL=NOT_VERIFIED\n"
           "ATLAS_NATIVE_WORKER_STAGE=environment\n")
        self.assertEqual(denied.stderr,"")

    def test_existing_private_runner_output_is_allowlisted_only(self):
        shell=RUNNER.read_text()
        self.assertIn('> "$log" 2>&1',shell)
        self.assertNotIn('cat "$log"',shell)
        self.assertNotIn('tail "$log"',shell)
        self.assertIn("ATLAS_NATIVE_WORKER_STAGE=physical_form",shell)
        self.assertIn("ATLAS_PRODUCTION_CHANGE=NONE",shell)


if __name__=="__main__":
    unittest.main()

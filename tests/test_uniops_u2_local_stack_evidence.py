"""Source-only checks for the disposable signed U2 call-stack observer."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location(
    "stack", Path(__file__).with_name("uniops_u2_local_stack_evidence.py"))
stack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stack)

DB = "postgresql://postgres:fictional@127.0.0.1:43876/postgres"
START = "2026-11-08T20:30:00Z"
FUNC = "atlas.establish_continuing_original_work_internal_v1"
ERR = "Fictional governor authorization denied"
CONTAINER = "abcdef123456"


def runner_with(logs):
    seen = []
    def runner(argv, **kwargs):
        seen.append(tuple(argv))
        if argv[:2] == ["docker", "ps"]:
            return SimpleNamespace(returncode=0,
                stdout=CONTAINER+"|0.0.0.0:43876->5432/tcp\n", stderr="")
        if argv[:2] == ["docker", "logs"]:
            return SimpleNamespace(returncode=0, stdout="", stderr=logs)
        raise AssertionError("Unknown command requested")
    return runner, seen


class SourceStackEvidenceTests(unittest.TestCase):
    def test_actual_first_raise_frame(self):
        logs = (
            "2026-11-08 20:30:00 UTC [7] ERROR:  "+ERR+"\n"
            "2026-11-08 20:30:00 UTC [7] CONTEXT:  PL/pgSQL function "
            +FUNC+"(uuid) line 29 at RAISE\n"
            "2026-11-08 20:30:00 UTC [7] SQL statement \"SELECT atlas.other()\"\n")
        runner,commands=runner_with(logs)
        sql_used=[]
        def sql(db,stmt):
            sql_used.append(stmt)
            return FUNC
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,sql,
            runner),("raise_frame_match","canonical_original"))
        self.assertEqual(len(commands),2)
        self.assertNotIn(ERR,sql_used[0])
        self.assertIn("pg_catalog.pg_proc",sql_used[0])
        self.assertNotIn("UPDATE ",sql_used[0])
        self.assertNotIn("DELETE ",sql_used[0])

    def test_existing_function_in_stack_is_not_raise_origin(self):
        logs=(
            "ERROR:  "+ERR+"\n"
            "CONTEXT:  PL/pgSQL function atlas.another_guard() line 3 at RAISE\n"
            "PL/pgSQL function "+FUNC+"(uuid) line 7 at assignment\n")
        runner,_=runner_with(logs)
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("call_path_match","canonical_original"))

    def test_log_context_absent_is_not_proof(self):
        runner,_=runner_with("ERROR:  "+ERR+"\n")
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("unobservable","unverified"))

    def test_wrong_source_frame_is_not_proof(self):
        logs=("ERROR:  "+ERR+"\n"
              "CONTEXT:  PL/pgSQL function atlas.another_guard() line 4 at RAISE\n")
        runner,_=runner_with(logs)
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("different_origin","unverified"))

    def test_remote_database_rejected_before_any_access(self):
        def forbidden(*args,**kwargs):
            raise AssertionError("No remote connection or Docker inspection")
        for db in ("postgresql://postgres:p@db.example.com:43876/postgres",
                   "postgresql://postgres:p@localhost:43876/postgres",
                   "postgresql://postgres:p@127.0.0.1:43876/real_data"):
            self.assertEqual(stack.inspect_signed_denial_stack(db,ERR,START,
                forbidden,forbidden),("unobservable","unverified"))

    def test_missing_or_multiple_catalog_matches_fail_closed(self):
        runner,_=runner_with("ERROR:  "+ERR+"\n")
        for value in ("not_unique","",FUNC+"; DROP TABLE",None):
            self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
                lambda db,stmt:value,runner),("unobservable","unverified"))

    def test_ambiguous_database_container_fails_closed(self):
        calls=[]
        def runner(argv,**kwargs):
            calls.append(argv)
            return SimpleNamespace(returncode=0,stdout=(
                "abcdef123456|0.0.0.0:43876->5432/tcp\n"
                "123456abcdef|0.0.0.0:43876->5432/tcp\n"),stderr="")
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("unobservable","unverified"))
        self.assertEqual(len(calls),1)

    def test_duplicate_identical_error_cannot_assert_origin(self):
        block=("ERROR:  "+ERR+"\n"
               "CONTEXT:  PL/pgSQL function "+FUNC+"(uuid) line 4 at RAISE\n")
        runner,_=runner_with(block+block)
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("unobservable","unverified"))

    def test_precise_call_start_is_utc_microsecond(self):
        started=stack.local_probe_started()
        self.assertEqual(len(started),27)
        self.assertTrue(started.endswith("Z") and "." in started)
        runner,_=runner_with("ERROR:  "+ERR+"\n")
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,started,
            lambda db,stmt:FUNC,runner),("unobservable","unverified"))

    def test_never_echoes_private_docker_errors(self):
        def runner(argv,**kwargs):
            return SimpleNamespace(returncode=1,stdout="private jwt",
                                   stderr="private function name")
        self.assertEqual(stack.inspect_signed_denial_stack(DB,ERR,START,
            lambda db,stmt:FUNC,runner),("unobservable","unverified"))


if __name__=="__main__":
    unittest.main()

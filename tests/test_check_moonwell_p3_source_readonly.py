#!/usr/bin/env python3
"""No-network safety tests for Moonwell's read-only P3 handoff preflight."""
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch

FILE = Path(__file__).resolve().parents[1] / "scripts" / "check-moonwell-p3-source-readonly.py"
SPEC = importlib.util.spec_from_file_location("moonwell_p3_preflight", FILE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
DUMMY = {"NOEL_CORE_DATABASE_URL": "postgresql://fixture:fixture@localhost:5432/fixture"}


class PreflightTests(unittest.TestCase):
    def runner(self, output, status=0):
        def fake(argv, **kwargs):
            self.assertEqual(argv[0:5], ["psql", "-X", "-w", "-A", "-t"])
            self.assertEqual(argv[-2], "-c")
            self.assertEqual(argv[-1], MODULE.SQL)
            self.assertEqual(kwargs["timeout"], 35)
            self.assertFalse(kwargs["check"])
            self.assertTrue(kwargs["capture_output"])
            self.assertIn("default_transaction_read_only=on", kwargs["env"]["PGOPTIONS"])
            self.assertEqual(kwargs["env"]["PGDATABASE"], DUMMY["NOEL_CORE_DATABASE_URL"])
            self.assertNotIn("NOEL_CORE_DATABASE_URL", kwargs["env"])
            return SimpleNamespace(returncode=status, stdout=output, stderr="PRIVATE ERROR")
        return fake

    def test_exact_source_passes(self):
        self.assertEqual(
            MODULE.probe(DUMMY, self.runner(MODULE.EXPECTED_P3_MD5 + "\n")), "match"
        )

    def test_missing_function_denied(self):
        self.assertEqual(MODULE.probe(DUMMY, self.runner("missing\n")), "missing_function")

    def test_drift_denied(self):
        self.assertEqual(MODULE.probe(DUMMY, self.runner("a" * 32 + "\n")), "source_drift")

    def test_unexpected_or_multiline_denied(self):
        for value in ("", "PASS\n", "secret sql\n", MODULE.EXPECTED_P3_MD5 + "\nsecret\n"):
            with self.subTest(value=value):
                self.assertEqual(
                    MODULE.probe(DUMMY, self.runner(value)), "unrecognized_result"
                )

    def test_database_error_denied_without_private_error_details(self):
        self.assertEqual(
            MODULE.probe(DUMMY, self.runner("secret sql\n", status=1)), "query_unavailable"
        )

    def test_unavailable_credential_denied_before_subprocess(self):
        def bad_runner(*args, **kwargs):
            self.fail("Must never connect without a scoped credential")
        for value in ({}, {"NOEL_CORE_DATABASE_URL": " "},
                      {"NOEL_CORE_DATABASE_URL": "file:///tmp/other"}):
            with self.subTest(value=value):
                self.assertNotEqual(MODULE.probe(value, bad_runner), "match")

    def test_timeout_denied(self):
        def timeout(*args, **kwargs):
            raise subprocess.TimeoutExpired("psql", 35)
        self.assertEqual(MODULE.probe(DUMMY, timeout), "query_unavailable")

    def test_error_output_uses_fixed_labels_only(self):
        with patch.object(sys, "argv", [str(FILE)]), \
             patch.object(MODULE, "probe", return_value="source_drift"), \
             redirect_stdout(io.StringIO()) as capture:
            self.assertEqual(MODULE.main(), 1)
        self.assertEqual(
            capture.getvalue(), "BLOCKED moonwell_p3_source_gate=source_drift\n"
        )

    def test_cli_rejects_extra_arguments(self):
        with patch.object(sys, "argv", [str(FILE), "--dump"]), \
             patch.object(MODULE, "probe", side_effect=AssertionError("should not run")), \
             redirect_stdout(io.StringIO()) as capture:
            self.assertEqual(MODULE.main(), 2)
        self.assertIn("unexpected_arguments", capture.getvalue())


if __name__ == "__main__":
    unittest.main()

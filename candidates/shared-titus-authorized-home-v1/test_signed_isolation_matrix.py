#!/usr/bin/env python3
"""Offline contract checks for the isolated signed HTTP harness.

These tests use synthetic JSON only; a green result is NOT signed Person proof.
"""
from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from signed_self_read_test import read_single_environment, validate_single, run as run_single

from signed_isolation_matrix import (
    MatrixFailure, checked_response, read_environment, require_local_origin,
    validate_matrix,
)

TARGET = "75000000-0000-4000-8000-000000000002"
OTHER = "75000000-0000-4000-8000-000000000003"
PERSON = "75000000-0000-4000-8000-000000000001"
OTHER_PERSON = "75000000-0000-4000-8000-000000000010"
WITHDRAWN_PERSON = "75000000-0000-4000-8000-000000000011"


def ready(ids=(), person=PERSON):
    return {
        "contractVersion": "titus_authorized_home_self_v1",
        "state": "ready",
        "personId": person,
        "subjects": [
            {"id": value, "kind": "institutional_course", "title": "Approved study",
             "subtitle": "Fictional unit", "roles": ["learner"]}
            for value in ids
        ],
        "pendingInvitations": [],
    }


def identity_not_ready():
    return {
        "contractVersion": "titus_authorized_home_self_v1",
        "state": "identity_not_ready",
        "subjects": [],
        "pendingInvitations": [],
    }


def matrix():
    return {
        "anonymous": (401, None),
        "learner": (200, ready([TARGET])),
        "other_person": (200, ready([OTHER], person=OTHER_PERSON)),
        "withdrawn": (200, ready([], person=WITHDRAWN_PERSON)),
        "wrong_client": (200, identity_not_ready()),
        "unbound": (200, identity_not_ready()),
        "revoked_session": (401, None),
        "expired": (403, None),
    }


class IsolationSourceTests(unittest.TestCase):
    def test_valid_synthetic_matrix(self):
        validate_matrix(matrix(), TARGET)

    def test_no_missing_case_can_be_silently_ignored(self):
        for label in matrix():
            with self.subTest(label=label):
                v = matrix()
                del v[label]
                with self.assertRaises(KeyError):
                    validate_matrix(v, TARGET)

    def test_target_must_be_authorized_for_real_learner(self):
        v = matrix()
        v["learner"] = (200, ready([OTHER]))
        with self.assertRaises(MatrixFailure):
            validate_matrix(v, TARGET)

    def test_unrelated_and_withdrawn_must_not_see_target(self):
        for label in ("other_person", "withdrawn"):
            with self.subTest(label=label):
                v = matrix()
                v[label] = (200, ready([TARGET]))
                with self.assertRaises(MatrixFailure):
                    validate_matrix(v, TARGET)

    def test_separate_sessions_for_one_canonical_person_are_not_two_people(self):
        v = matrix()
        v["other_person"] = (200, ready([], person=PERSON))
        with self.assertRaises(MatrixFailure):
            validate_matrix(v, TARGET)
        v = matrix()
        v["withdrawn"] = (200, ready([], person=OTHER_PERSON))
        with self.assertRaises(MatrixFailure):
            validate_matrix(v, TARGET)

    def test_revoked_and_wrong_client_cannot_claim_ready_even_with_empty_course(self):
        for label in ("wrong_client", "unbound", "revoked_session", "expired"):
            with self.subTest(label=label):
                v = matrix()
                v[label] = (200, ready([]))
                with self.assertRaises(MatrixFailure):
                    validate_matrix(v, TARGET)

    def test_404_and_missing_rpc_never_count_as_access_denial(self):
        for label in matrix():
            with self.subTest(label=label):
                v = matrix()
                v[label] = (404, None)
                with self.assertRaises(MatrixFailure):
                    validate_matrix(v, TARGET)

    def test_unreviewed_private_fields_and_role_inference_are_rejected(self):
        forbidden = [
            {**ready([TARGET]), "debug": True},
            {**ready([TARGET]), "pendingInvitations": [{"id": OTHER}]},
            {**ready([TARGET]), "subjects": [{**ready([TARGET])["subjects"][0], "email": "not-allowed"}]},
            {**ready([TARGET]), "subjects": [{**ready([TARGET])["subjects"][0], "roles": ["teacher"]}]},
            {**ready([TARGET]), "subjects": [{**ready([TARGET])["subjects"][0], "kind": "titus_program"}]},
            {**ready([TARGET]), "subjects": [{**ready([TARGET])["subjects"][0], "sourceBody": "private"}]},
            ready([TARGET, TARGET]),
            {"contractVersion": "titus_authorized_home_self_v1", "state": "identity_not_ready",
             "personId": PERSON, "subjects": [], "pendingInvitations": []},
        ]
        for item in forbidden:
            with self.subTest(index=forbidden.index(item)):
                with self.assertRaises(MatrixFailure):
                    checked_response(200, item)

    def test_signed_case_requires_exact_ready_fields(self):
        result = checked_response(200, ready([TARGET, OTHER]))
        self.assertEqual(result[0], "ready")
        self.assertEqual(result[1], frozenset([TARGET, OTHER]))

    def test_local_clone_only_never_production_origin(self):
        self.assertEqual(require_local_origin("http://127.0.0.1:54321"), "http://127.0.0.1:54321")
        for url in [
            "https://zirqkouammpwxlqfbsvf.supabase.co",
            "https://titus.opticallift.com",
            "http://evil.invalid:54321",
            "http://localhost",
            "http://localhost:54321/rest/v1",
            "http://localhost:54321?key=x",
            "http://u:p@localhost:54321",
            "http://localhost:54321#fragment",
        ]:
            with self.subTest(url=url):
                with self.assertRaises(MatrixFailure):
                    require_local_origin(url)

    def test_missing_tokens_refuse_success_instead_of_skipping_cases(self):
        env = {
            "TITUS_MATRIX_URL": "http://127.0.0.1:54321",
            "TITUS_MATRIX_PUBLISHABLE_KEY": "local-test-public-key",
            "TITUS_MATRIX_TARGET_COURSE_ID": TARGET,
            "TITUS_MATRIX_LEARNER_BEARER": "one-local-signed-bearer",
        }
        with self.assertRaisesRegex(MatrixFailure, "INCOMPLETE"):
            read_environment(env)

    def test_reused_credentials_not_counted_as_distinct_signed_people(self):
        env = {
            "TITUS_MATRIX_URL": "http://127.0.0.1:54321",
            "TITUS_MATRIX_PUBLISHABLE_KEY": "local-test-public-key",
            "TITUS_MATRIX_TARGET_COURSE_ID": TARGET,
        }
        labels = [
            "LEARNER", "OTHER_PERSON", "WRONG_CLIENT", "UNBOUND",
            "REVOKED_SESSION", "WITHDRAWN", "EXPIRED",
        ]
        for i, label in enumerate(labels):
            env["TITUS_MATRIX_" + label + "_BEARER"] = "synthetic-user-" + str(i)
        self.assertEqual(len(read_environment(env)[3]), 7)
        env["TITUS_MATRIX_OTHER_PERSON_BEARER"] = env["TITUS_MATRIX_LEARNER_BEARER"]
        with self.assertRaises(MatrixFailure):
            read_environment(env)


    def test_legacy_single_reader_cannot_use_production_even_with_override(self):
        env = {
            "TITUS_HOME_TEST_URL": "https://zirqkouammpwxlqfbsvf.supabase.co",
            "TITUS_HOME_TEST_KEY": "synthetic-local-public-key",
            "TITUS_HOME_TEST_BEARER": "synthetic-local-signed-bearer",
            "TITUS_HOME_ALLOW_LIVE_READ": "true",
        }
        with self.assertRaises(MatrixFailure):
            read_single_environment(env)
        env["TITUS_HOME_TEST_URL"] = "http://127.0.0.1:54321"
        self.assertEqual(read_single_environment(env)[0], env["TITUS_HOME_TEST_URL"])

    def test_legacy_single_reader_rejects_invalid_credentials_and_expectation(self):
        env = {
            "TITUS_HOME_TEST_URL": "http://localhost:54321",
            "TITUS_HOME_TEST_KEY": "local-key",
            "TITUS_HOME_TEST_BEARER": "local-token",
        }
        for change in (
            {"TITUS_HOME_TEST_KEY": "sb_secret_private"},
            {"TITUS_HOME_TEST_BEARER": "local-key"},
            {"TITUS_HOME_EXPECT_EMPTY": "unknown"},
            {"TITUS_HOME_TEST_BEARER": ""},
        ):
            with self.subTest(change=change):
                with self.assertRaises(MatrixFailure):
                    read_single_environment({**env, **change})

    def test_legacy_single_reader_refuses_missing_identity_or_false_pass(self):
        cases = [
            ((404, None), (200, ready([])), True),
            ((401, None), (404, None), True),
            ((403, None), (200, identity_not_ready()), True),
            ((403, None), (200, ready([TARGET])), True),
            ((403, None), (200, ready([])), False),
        ]
        for anonymous, signed, expected_empty in cases:
            with self.subTest(anonymous=anonymous[0], expected_empty=expected_empty):
                with self.assertRaises(MatrixFailure):
                    validate_single(anonymous, signed, expected_empty)
        self.assertEqual(validate_single((403, None), (200, ready([])), True), 0)
        self.assertEqual(validate_single((401, None), (200, ready([TARGET])), False), 1)

    def test_legacy_runner_is_local_read_only_and_requires_both_http_cases(self):
        env = {
            "TITUS_HOME_TEST_URL": "http://127.0.0.1:54321",
            "TITUS_HOME_TEST_KEY": "local-key",
            "TITUS_HOME_TEST_BEARER": "distinct-local-bearer",
        }
        with patch("signed_self_read_test.post_rpc",
                   side_effect=[(401, None), (200, ready([]))]) as post:
            run_single(env)
            self.assertEqual(post.call_count, 2)
            self.assertEqual(post.call_args_list[0].args[2], None)
            self.assertEqual(post.call_args_list[1].args[2], env["TITUS_HOME_TEST_BEARER"])


if __name__ == "__main__":
    unittest.main()

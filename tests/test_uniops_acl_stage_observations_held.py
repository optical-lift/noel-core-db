#!/usr/bin/env python3
"""Offline negative gates for held UNI-OPS staged ACL observation classifier."""
import re
import unittest
import uniops_acl_stage_observations_held as s

DIGEST="0123456789abcdef0123456789abcdef"
CANON="postgres|t|"+DIGEST+"|f|f|f|t|t|t"
MANAGED="postgres|t|"+DIGEST+"|f|t|t|t|t|f"
DEFAULT_BEFORE="0|0|0"
DEFAULT_MANAGED="0|2|0"
EXTRAS="2|2|0|0|0"
FIELDS=("anon_exec","authenticated_exec","explicit_grantees_confined")


def check(**overrides):
    args=dict(
        source=CANON,
        before_target="",
        after_roles_target="",
        after_schema_target=MANAGED,
        before_defaults=DEFAULT_MANAGED,
        after_roles_defaults=DEFAULT_MANAGED,
        after_schema_defaults=DEFAULT_MANAGED,
        final_extras=EXTRAS,
        digest=DIGEST,
    )
    args.update(overrides)
    return s.classify_stages(**args)


class StagedAclTest(unittest.TestCase):
    def test_queries_are_read_only_catalog_aggregate_and_exact_function(self):
        for sql in (s.DEFAULTS_SQL,s.EXTRAS_SQL):
            self.assertTrue(sql.startswith("SELECT\n"))
            self.assertNotIn(";",sql)
            self.assertNotRegex(sql,re.compile(
                r"\b(?:UPDATE|INSERT|DELETE|ALTER|CREATE|DROP|REVOKE|GRANT|TRUNCATE|COPY|DO)\b",
                re.I,
            ))
            self.assertIn("pg_catalog.",sql)
            self.assertNotIn("auth.users",sql)
        self.assertIn("public.grant_personal_atlas_access_v1(uuid,text,jsonb)",s.EXTRAS_SQL)
        self.assertIn("defaclnamespace IN (0,p.pronamespace)",s.EXTRAS_SQL)
        self.assertIn("NOT x.is_grantable",s.EXTRAS_SQL)

    def test_compatible_is_not_historical_provenance(self):
        r=check()
        self.assertEqual(r.verdict,"stage_default_compatible_not_provenance")
        self.assertEqual(r.mismatch_fields,FIELDS)
        self.assertEqual(r.safe_line(),
             "UNI_OPS_STAGE_VERDICT=stage_default_compatible_not_provenance;"
             "DIFF=anon_exec,authenticated_exec,explicit_grantees_confined;"
             "ROLE_DEFAULT_CHANGE=false;SCHEMA_DEFAULT_CHANGE=false")

    def test_canonical_parity(self):
        r=check(after_schema_target=CANON,final_extras="0|0|0|0|0")
        self.assertEqual(r.verdict,"stage_canonical_match")
        self.assertEqual(r.mismatch_fields,())

    def test_role_defaults_transition_is_observed_not_assumed_origin(self):
        r=check(before_defaults=DEFAULT_BEFORE)
        self.assertEqual(r.verdict,"stage_default_compatible_not_provenance")
        self.assertTrue(r.role_defaults_changed)
        self.assertFalse(r.schema_defaults_changed)

    def test_schema_defaults_drift_blocks_attribution(self):
        r=check(after_roles_defaults=DEFAULT_BEFORE)
        self.assertEqual(r.verdict,"stage_default_drift_ambiguous")
        self.assertTrue(r.schema_defaults_changed)

    def test_unknown_grantee_refused(self):
        r=check(final_extras="3|2|1|0|0")
        self.assertEqual(r.verdict,"stage_extra_unknown_refused")

    def test_delegable_extra_and_service_are_independent_refusals(self):
        for x in ("2|2|0|1|0","2|2|0|0|1"):
            with self.subTest(x=x):
                self.assertEqual(check(final_extras=x).verdict,
                                 "stage_delegable_refused")

    def test_inconsistent_counts_refused(self):
        for x in ("2|1|0|0|0","2|2|1|0|0","2|2|0|3|0",
                  "2|2|0|0|2","9999|9999|0|0|0","2|-1|3|0|0",
                  "0|0|0|0|0|0"):
            with self.subTest(x=x):
                self.assertEqual(check(final_extras=x).verdict,
                                 "stage_metadata_refused")

    def test_other_access_difference_refused(self):
        r=check(final_extras="0|0|0|0|0")
        self.assertEqual(r.verdict,"stage_other_mismatch_refused")

    def test_preexisting_target_blocks_at_every_earlier_stage(self):
        for kw in ({"before_target":MANAGED},{"after_roles_target":MANAGED}):
            self.assertEqual(check(**kw).verdict,
                             "stage_preexisting_target_refused")

    def test_missing_target_and_wrong_source_refuse(self):
        self.assertEqual(check(after_schema_target="").verdict,
                         "stage_target_missing_refused")
        self.assertEqual(check(source=MANAGED).verdict,
                         "stage_source_unverified")
        changed=MANAGED.replace("postgres|t|","anon|t|")
        self.assertEqual(check(after_schema_target=changed).verdict,
                         "stage_source_unverified")
        self.assertEqual(check(digest="bad").verdict,"stage_metadata_refused")

    def test_incorrect_data_shapes_refuse_without_private_output(self):
        for raw in ("","-1|2|0","0|NaN|0","0|2000|0","0|1|NULL","01|0|0"):
            with self.subTest(raw=raw):
                self.assertEqual(check(after_roles_defaults=raw).verdict,
                                 "stage_metadata_refused")
        self.assertTrue(s.VERDICTS)
        for result in (check(),check(final_extras="3|2|1|0|0")):
            self.assertRegex(result.safe_line(),r"^UNI_OPS_STAGE_VERDICT=stage_[a-z_]+;DIFF=")
            self.assertNotIn("postgres",result.safe_line())
            self.assertNotIn(DIGEST,result.safe_line())


if __name__=="__main__":
    unittest.main()

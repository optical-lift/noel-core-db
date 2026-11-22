import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts/check-universal-person-authority.py"
spec = importlib.util.spec_from_file_location("person_authority", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PersonAuthorityGuardTest(unittest.TestCase):
    def test_bans_new_membership_authority(self):
        src = """CREATE OR REPLACE FUNCTION atlas.new_employee_reader_v1()
RETURNS boolean LANGUAGE sql AS $f$
SELECT EXISTS(SELECT 1 FROM atlas.organization_memberships);
$f$;"""
        self.assertTrue(module.violations(src, set()))

    def test_allows_retirement_of_legacy_function(self):
        src = """CREATE OR REPLACE FUNCTION atlas.old_read_v1()
RETURNS boolean LANGUAGE sql AS $f$
SELECT EXISTS(SELECT 1 FROM ledger.seats);
$f$;"""
        self.assertEqual(module.violations(src, {"old_read_v1"}), [])

    def test_prevents_reintroduction_even_to_preexisting_func(self):
        src = """CREATE OR REPLACE FUNCTION atlas.list_foundry_source_custody_reviewers_self_api_v1(text)
RETURNS jsonb LANGUAGE sql AS $f$
SELECT to_jsonb(om) FROM atlas.organization_memberships om;
$f$;"""
        self.assertTrue(module.violations(src, {"list_foundry_source_custody_reviewers_self_api_v1"}))

    def test_historical_reader_only_survives_with_explicit_inventory(self):
        src = """CREATE OR REPLACE FUNCTION atlas.historical_member_provenance_v1()
RETURNS int LANGUAGE sql AS $f$
SELECT count(*) FROM atlas.organization_memberships;
$f$;"""
        self.assertEqual(module.violations(src, {"historical_member_provenance_v1"}), [])

    def test_member_only_reader_followed_by_legacy_table_guard_is_not_new_access(self):
        # Exact failure mode in versioned prelaunch retirement: the existing
        # owner reader has NO Organization membership reference; later DO
        # postconditions merely count unchanged Organization members.
        src = """CREATE OR REPLACE FUNCTION atlas.owner_list_farm_members_v1(uuid)
RETURNS TABLE(role text) LANGUAGE plpgsql AS $member_list$
BEGIN
  RETURN QUERY SELECT fm.role FROM atlas.farm_memberships fm;
END $member_list$;
DO $guard$ BEGIN
  PERFORM count(*) FROM atlas.organization_memberships;
END $guard$;"""
        self.assertEqual(module.violations(src, set()), [])

    def test_new_legacy_reader_inside_tagged_body_still_fails(self):
        src = """CREATE OR REPLACE FUNCTION atlas.unsafe_new_reader()
RETURNS int LANGUAGE plpgsql AS $reader$
BEGIN
  RETURN (SELECT count(*)::int FROM atlas.organization_memberships);
END $reader$;
DO $guard$ BEGIN PERFORM 1; END $guard$;"""
        self.assertIn("New function derives from legacy membership: unsafe_new_reader",
                      module.violations(src, set()))

    def test_new_legacy_reader_inside_untagged_body_still_fails(self):
        src = """CREATE OR REPLACE FUNCTION atlas.unsafe_untagged_reader()
RETURNS int LANGUAGE sql AS $$
SELECT count(*)::int FROM atlas.organization_memberships;
$$;"""
        self.assertTrue(module.violations(src, set()))

    def test_sequential_functions_are_independently_adjudicated(self):
        src = """CREATE OR REPLACE FUNCTION atlas.clean_farm_reader()
RETURNS int LANGUAGE sql AS $f$
SELECT count(*)::int FROM atlas.farm_memberships;
$f$;
DO $guard$ BEGIN PERFORM count(*) FROM atlas.organization_memberships; END $guard$;
CREATE OR REPLACE FUNCTION atlas.unsafe_reader()
RETURNS int LANGUAGE sql AS $g$
SELECT count(*)::int FROM atlas.organization_memberships;
$g$;"""
        self.assertEqual(module.violations(src, set()),
                         ["New function derives from legacy membership: unsafe_reader"])

    def test_no_physical_employee_seats(self):
        self.assertTrue(module.violations("CREATE TABLE atlas.organization_employee_seats(id uuid);", set()))


if __name__ == "__main__":
    unittest.main()

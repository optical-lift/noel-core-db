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

    def test_no_physical_employee_seats(self):
        self.assertTrue(module.violations("CREATE TABLE atlas.organization_employee_seats(id uuid);", set()))


if __name__ == "__main__":
    unittest.main()

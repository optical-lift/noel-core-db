create index ledger_exposures_summary_idx
  on ledger.exposures(summary_id);

create index ledger_onboarding_cases_requested_by_idx
  on ledger.onboarding_cases(requested_by_person_entity_id)
  where requested_by_person_entity_id is not null;

create index reality_entity_claim_challenges_contact_route_idx
  on reality.entity_claim_challenges(contact_route_id);

revoke all on function reality.assert_person_entity_v1(uuid) from public,anon,authenticated;
revoke all on function reality.guard_auth_person_binding_v1() from public,anon,authenticated;
revoke all on function personal.ensure_native_atlas_from_auth_binding_v1() from public,anon,authenticated;
revoke all on function reality.guard_entity_claim_v1() from public,anon,authenticated;
revoke all on function reality.guard_entity_claim_challenge_v1() from public,anon,authenticated;
revoke all on function ledger.guard_onboarding_case_v1() from public,anon,authenticated;
revoke all on function ledger.guard_ledger_activation_v1() from public,anon,authenticated;
revoke all on function ledger.complete_onboarding_after_activation_v1() from public,anon,authenticated;
revoke all on function ledger.guard_seat_v1() from public,anon,authenticated;
revoke all on function ledger.guard_summary_authorship_v1() from public,anon,authenticated;
revoke all on function ledger.guard_exposure_v1() from public,anon,authenticated;

grant execute on function reality.assert_person_entity_v1(uuid) to service_role;
grant execute on function reality.guard_auth_person_binding_v1() to service_role;
grant execute on function personal.ensure_native_atlas_from_auth_binding_v1() to service_role;
grant execute on function reality.guard_entity_claim_v1() to service_role;
grant execute on function reality.guard_entity_claim_challenge_v1() to service_role;
grant execute on function ledger.guard_onboarding_case_v1() to service_role;
grant execute on function ledger.guard_ledger_activation_v1() to service_role;
grant execute on function ledger.complete_onboarding_after_activation_v1() to service_role;
grant execute on function ledger.guard_seat_v1() to service_role;
grant execute on function ledger.guard_summary_authorship_v1() to service_role;
grant execute on function ledger.guard_exposure_v1() to service_role;

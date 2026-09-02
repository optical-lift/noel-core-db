-- Immediate Atlas security hardening before multi-customer rebuild.
-- 1) Internalize the source-custody release packet.
-- 2) Remove direct authenticated reads from four legacy definer-semantic views.

revoke execute on function atlas.source_custody_release_packet_v1() from anon, authenticated;

update atlas.authenticated_rpc_registry
set classification = 'service_internal',
    authenticated_execute_expected = false,
    anonymous_execute_expected = false,
    service_execute_expected = true,
    review_status = 'active',
    confidence = 'verified',
    evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object(
      'securityHardening', '2026-09-02',
      'reason', 'Internal migration and source-custody metadata is not a public product surface.',
      'customerLaunchDisposition', 'service_only'
    ),
    reviewed_at = now()
where signature = 'atlas.source_custody_release_packet_v1()';

revoke select on atlas.crop_cycle_yield_forecast from authenticated;
revoke select on atlas.flower_demand_coverage_v1 from authenticated;
revoke select on atlas.flower_demand_line_position_v1 from authenticated;
revoke select on atlas.principal_authority_position_v1 from authenticated;

comment on view atlas.crop_cycle_yield_forecast is
  'Internal Atlas read model. Direct authenticated access revoked 2026-09-02 pending tenant-safe surface adjudication.';
comment on view atlas.flower_demand_coverage_v1 is
  'Internal Atlas read model. Direct authenticated access revoked 2026-09-02 pending tenant-safe surface adjudication.';
comment on view atlas.flower_demand_line_position_v1 is
  'Internal Atlas read model. Direct authenticated access revoked 2026-09-02 pending tenant-safe surface adjudication.';
comment on view atlas.principal_authority_position_v1 is
  'Internal Atlas read model. Direct authenticated access revoked 2026-09-02 pending tenant-safe surface adjudication.';
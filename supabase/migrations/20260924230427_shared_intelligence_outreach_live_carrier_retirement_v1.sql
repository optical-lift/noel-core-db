-- Retire the live mixed-custody carrier after archive and one-to-one routing proof.

do $block$
declare
  v_live integer;
  v_archive integer;
  v_mapped integer;
begin
  select count(*) into v_live from local_intel.outreach_targets;
  select count(*) into v_archive from local_intel.legacy_outreach_targets_archive_v1;
  select count(*) into v_mapped from atlas.legacy_local_intel_outreach_target_mappings;

  if v_live<>69 or v_archive<>69 or v_mapped<>69 then
    raise exception 'Refusing retirement: live %, archive %, mapped %.',v_live,v_archive,v_mapped;
  end if;

  if exists (
    select 1
    from local_intel.legacy_outreach_targets_archive_v1 a
    left join atlas.legacy_local_intel_outreach_target_mappings m
      on m.legacy_outreach_target_id=a.id
    where m.id is null
  ) then
    raise exception 'Refusing retirement: one or more archived rows lacks a custody receipt.';
  end if;
end
$block$;

delete from local_intel.outreach_targets;

comment on table local_intel.outreach_targets is
  'RETIRED mixed-custody compatibility shell. Do not write. Organization-private concepts live in Atlas purpose contexts; universal acquisition/verification work lives in entity_enrichment_targets. Historical rows are retained in legacy_outreach_targets_archive_v1 with one-to-one custody receipts.';

create or replace function local_intel.reject_retired_outreach_target_write_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  raise exception
    'local_intel.outreach_targets is retired. Write Organization concepts through Atlas purpose contexts or universal research through entity_enrichment_targets.'
    using errcode='55000';
end
$function$;

drop trigger if exists outreach_targets_retired_write_guard_v1
  on local_intel.outreach_targets;

create trigger outreach_targets_retired_write_guard_v1
before insert or update or delete on local_intel.outreach_targets
for each statement
execute function local_intel.reject_retired_outreach_target_write_v1();

comment on view local_intel.v_outreach_contact_resolution_v1 is
  'Retired compatibility projection. Mixed-custody outreach targets no longer exist as live Shared Intelligence work.';

comment on view local_intel.v_person_discovery_targets_v1 is
  'Compatibility person-discovery projection. Its legacy outreach contribution is now empty; Organization-private concepts no longer influence Shared Intelligence person discovery.';

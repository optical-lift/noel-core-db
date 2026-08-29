do $migration$
declare
  v_definition text;
  v_old text := $old$  elsif v_cycle.cycle_state='establishing' then
    v_issue_key:='establishment_observation_required';$old$;
  v_new text := $new$  elsif v_cycle.cycle_state='germinated'
        and v_profile.default_planting_method='direct_sow' then
    v_issue_key:='field_care_observation_required';
    v_state:='field_care_observation_required';
    v_operation:='inspect_field_care_and_growth';
    v_reason:='A direct-sown crop has physically germinated and has no current operation carrier. Germination establishes biological presence, not continued crop condition or harvestability; a current field-care/growth observation must preserve continuity until a later physical stage or readiness observation supersedes it.';
    v_severity:=case when v_boundary_passed then 'high' else 'medium' end;
    v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='establishing' then
    v_issue_key:='establishment_observation_required';$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='crop_cycle_stage_continuity_state_v1'
    and pg_get_function_identity_arguments(p.oid)='p_crop_cycle_id uuid, p_as_of_date date';

  if v_definition is null then
    raise exception 'Crop-cycle continuity contract was not found.' using errcode='P0002';
  end if;
  if position(v_old in v_definition)=0 then
    raise exception 'Crop-cycle continuity contract no longer matches the expected pre-fix source.' using errcode='23514';
  end if;

  execute replace(v_definition,v_old,v_new);
end;
$migration$;
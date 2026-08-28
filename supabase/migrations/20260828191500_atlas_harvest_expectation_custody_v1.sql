-- Atlas Harvest expectation custody v1
--
-- Forward-looking human field knowledge belongs beside Harvest without being
-- misrepresented as a physical observation that already happened.

create table atlas.crop_harvest_expectations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  crop_cycle_id uuid not null references atlas.crop_cycles(id) on delete restrict,
  expected_date date not null,
  estimated_quantity numeric,
  unit text,
  source_kind text not null,
  source_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  confidence text not null default 'likely',
  note text,
  idempotency_key text not null,
  request_fingerprint text not null,
  created_by_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint crop_harvest_expectations_farm_idempotency_unique unique (farm_id, idempotency_key),
  constraint crop_harvest_expectations_source_kind_check
    check (source_kind in ('worker_assertion', 'owner_assertion', 'manager_assertion')),
  constraint crop_harvest_expectations_confidence_check
    check (confidence in ('possible', 'likely', 'confident')),
  constraint crop_harvest_expectations_quantity_check
    check (estimated_quantity is null or estimated_quantity > 0),
  constraint crop_harvest_expectations_quantity_unit_check
    check ((estimated_quantity is null and unit is null)
      or (estimated_quantity is not null and unit is not null and char_length(btrim(unit)) between 1 and 40)),
  constraint crop_harvest_expectations_note_check
    check (note is null or char_length(btrim(note)) between 1 and 1000),
  constraint crop_harvest_expectations_idempotency_check
    check (char_length(btrim(idempotency_key)) between 1 and 160),
  constraint crop_harvest_expectations_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint crop_harvest_expectations_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.crop_harvest_expectations is
  'Append-only human assertions about the next harvest/check date for a canonical crop cycle. These rows do not claim future physical harvest occurred.';

create index crop_harvest_expectations_cycle_date_idx
  on atlas.crop_harvest_expectations(crop_cycle_id, expected_date desc, created_at desc);
create index crop_harvest_expectations_farm_date_idx
  on atlas.crop_harvest_expectations(farm_id, expected_date, created_at desc);

alter table atlas.crop_harvest_expectations enable row level security;
grant select on atlas.crop_harvest_expectations to authenticated;
grant all on atlas.crop_harvest_expectations to service_role;

create policy crop_harvest_expectations_member_read_v1
  on atlas.crop_harvest_expectations
  for select to authenticated
  using (atlas.is_farm_member(farm_id));

create or replace function atlas.record_crop_harvest_expectation_core_v1(
  p_crop_cycle_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_expected_date date,
  p_estimated_quantity numeric,
  p_unit text,
  p_confidence text,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_existing atlas.crop_harvest_expectations%rowtype;
  v_row atlas.crop_harvest_expectations%rowtype;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_role text := lower(btrim(coalesce(p_effective_role, '')));
  v_source_kind text;
  v_unit text := nullif(btrim(coalesce(p_unit, '')), '');
  v_confidence text := lower(btrim(coalesce(p_confidence, 'likely')));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_fingerprint text;
begin
  if p_crop_cycle_id is null then
    raise exception 'Choose a crop for the expected harvest.' using errcode='22023';
  end if;
  if p_expected_date is null or p_expected_date < v_today or p_expected_date > v_today + 60 then
    raise exception 'Expected harvest date must be today or within the next 60 days.' using errcode='22023';
  end if;
  if p_estimated_quantity is not null and p_estimated_quantity <= 0 then
    raise exception 'Expected quantity must be greater than zero.' using errcode='22023';
  end if;
  if (p_estimated_quantity is not null and v_unit is null)
     or (p_estimated_quantity is null and v_unit is not null) then
    raise exception 'Expected quantity and unit must be recorded together.' using errcode='22023';
  end if;
  if v_unit is not null and char_length(v_unit) > 40 then
    raise exception 'Expected quantity unit is too long.' using errcode='22023';
  end if;
  if v_confidence not in ('possible', 'likely', 'confident') then
    raise exception 'Expected harvest confidence must be possible, likely, or confident.' using errcode='22023';
  end if;
  if v_note is not null and char_length(v_note) > 1000 then
    raise exception 'Expected harvest note must be 1000 characters or fewer.' using errcode='22023';
  end if;
  if v_key is null or char_length(v_key) > 160 then
    raise exception 'A valid expected harvest idempotency key is required.' using errcode='22023';
  end if;
  if v_role not in ('owner', 'manager', 'farm_hand') then
    raise exception 'Selected account cannot record expected harvests.' using errcode='42501';
  end if;

  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then
    raise exception 'Crop cycle was not found.' using errcode='P0002';
  end if;
  if v_cycle.farm_id is distinct from v_member.farm_id then
    raise exception 'Crop cycle is outside the active farm.' using errcode='42501';
  end if;
  if v_cycle.lifecycle_status <> 'active'
     or lower(coalesce(v_cycle.cycle_state, '')) in ('failed','cleared','finished','finished_harvest') then
    raise exception 'Expected harvest can only be recorded for an active crop cycle.' using errcode='22023';
  end if;

  v_source_kind := case v_role
    when 'owner' then 'owner_assertion'
    when 'manager' then 'manager_assertion'
    else 'worker_assertion'
  end;

  v_fingerprint := md5(jsonb_build_object(
    'cropCycleId',p_crop_cycle_id,
    'membershipId',p_effective_membership_id,
    'expectedDate',p_expected_date,
    'estimatedQuantity',p_estimated_quantity,
    'unit',v_unit,
    'confidence',v_confidence,
    'note',v_note
  )::text);

  select * into v_existing
  from atlas.crop_harvest_expectations
  where farm_id=v_cycle.farm_id and idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Expected harvest idempotency key was already used for a different request.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'contractVersion','crop_harvest_expectation_v1','deduplicated',true,
      'expectationId',v_existing.id,'cropCycleId',v_existing.crop_cycle_id,
      'expectedDate',v_existing.expected_date,'estimatedQuantity',v_existing.estimated_quantity,
      'unit',v_existing.unit,'sourceKind',v_existing.source_kind,
      'confidence',v_existing.confidence,'note',v_existing.note
    );
  end if;

  insert into atlas.crop_harvest_expectations(
    farm_id,crop_cycle_id,expected_date,estimated_quantity,unit,source_kind,
    source_membership_id,confidence,note,idempotency_key,request_fingerprint,
    created_by_user_id,metadata
  ) values (
    v_cycle.farm_id,v_cycle.id,p_expected_date,p_estimated_quantity,v_unit,v_source_kind,
    p_effective_membership_id,v_confidence,v_note,v_key,v_fingerprint,auth.uid(),
    jsonb_build_object(
      'operatorMode',p_operator_mode,
      'effectiveMembershipId',p_effective_membership_id,
      'timeClaimsPhysicalCondition',false,
      'truthBoundary','forward_looking_human_harvest_expectation'
    )
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','crop_harvest_expectation_v1','deduplicated',false,
    'expectationId',v_row.id,'cropCycleId',v_row.crop_cycle_id,
    'expectedDate',v_row.expected_date,'estimatedQuantity',v_row.estimated_quantity,
    'unit',v_row.unit,'sourceKind',v_row.source_kind,
    'confidence',v_row.confidence,'note',v_row.note
  );
end;
$function$;

create or replace function atlas.record_crop_harvest_expectation_for_member_v1(
  p_farm_id uuid,
  p_crop_cycle_id uuid,
  p_expected_date date,
  p_estimated_quantity numeric,
  p_unit text,
  p_confidence text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_role text;
  v_membership uuid;
begin
  v_role := atlas.current_farm_role(p_farm_id);
  v_membership := atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  return atlas.record_crop_harvest_expectation_core_v1(
    p_crop_cycle_id,v_membership,v_role,p_expected_date,p_estimated_quantity,p_unit,
    p_confidence,p_note,p_idempotency_key,false
  );
end;
$function$;

create or replace function atlas.owner_operator_record_crop_harvest_expectation_v1(
  p_effective_membership_id uuid,
  p_crop_cycle_id uuid,
  p_expected_date date,
  p_estimated_quantity numeric,
  p_unit text,
  p_confidence text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_context jsonb;
begin
  v_context := atlas.owner_operator_context_v1(p_effective_membership_id);
  return atlas.record_crop_harvest_expectation_core_v1(
    p_crop_cycle_id,
    (v_context #>> '{effective,membershipId}')::uuid,
    v_context #>> '{effective,role}',
    p_expected_date,p_estimated_quantity,p_unit,p_confidence,p_note,p_idempotency_key,true
  );
end;
$function$;

revoke all on function atlas.record_crop_harvest_expectation_core_v1(uuid,uuid,text,date,numeric,text,text,text,text,boolean) from public,anon,authenticated,service_role;
revoke all on function atlas.record_crop_harvest_expectation_for_member_v1(uuid,uuid,date,numeric,text,text,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.owner_operator_record_crop_harvest_expectation_v1(uuid,uuid,date,numeric,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function atlas.record_crop_harvest_expectation_for_member_v1(uuid,uuid,date,numeric,text,text,text,text) to authenticated;
grant execute on function atlas.owner_operator_record_crop_harvest_expectation_v1(uuid,uuid,date,numeric,text,text,text,text) to authenticated;

with targets as (
  select
    p.oid,
    format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
    (
      select count(*)::integer from pg_proc caller
      join pg_namespace cn on cn.oid=caller.pronamespace and cn.nspname='atlas'
      where caller.oid<>p.oid and caller.prokind='f'
        and (position(lower(p.proname)||'(' in lower(pg_get_functiondef(caller.oid)))>0
          or position(lower(p.proname)||' (' in lower(pg_get_functiondef(caller.oid)))>0)
    ) as caller_count,
    (
      select count(*)::integer from pg_policies policy
      where position(lower(p.proname)||'(' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0
         or position(lower(p.proname)||' (' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0
    ) as policy_reference_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and (
    (p.proname='record_crop_harvest_expectation_for_member_v1' and oidvectortypes(p.proargtypes)='uuid, uuid, date, numeric, text, text, text, text')
    or (p.proname='owner_operator_record_crop_harvest_expectation_v1' and oidvectortypes(p.proargtypes)='uuid, uuid, date, numeric, text, text, text, text')
  )
)
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
)
select
  signature,'app_endpoint','verified','active',
  authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_harvest_expectation_custody_v1',
    'reason','harvest_tab_forward_looking_field_assertion',
    'functionOid',oid,
    'classificationRuleVersion',3,
    'truthBoundary','Authenticated farm members may append forward-looking harvest expectations for active crop cycles. This does not create a physical harvest event, Ready inventory, or task completion.'
  ),now(),now()
from targets
on conflict(signature) do update
set classification=excluded.classification,
    confidence=excluded.confidence,
    review_status=excluded.review_status,
    authenticated_execute_expected=excluded.authenticated_execute_expected,
    anonymous_execute_expected=excluded.anonymous_execute_expected,
    security_definer_expected=excluded.security_definer_expected,
    service_execute_expected=excluded.service_execute_expected,
    caller_count=excluded.caller_count,
    policy_reference_count=excluded.policy_reference_count,
    evidence=coalesce(atlas.authenticated_rpc_registry.evidence,'{}'::jsonb)||excluded.evidence,
    reviewed_at=now();

do $verification$
declare
  v_count integer;
  v_drift integer;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname in ('record_crop_harvest_expectation_for_member_v1','owner_operator_record_crop_harvest_expectation_v1')
    and has_function_privilege('authenticated',p.oid,'EXECUTE')
    and not has_function_privilege('anon',p.oid,'EXECUTE')
    and not has_function_privilege('service_role',p.oid,'EXECUTE');
  if v_count<>2 then
    raise exception 'Harvest expectation RPC custody verification failed.';
  end if;

  select count(*) into v_drift
  from atlas.authenticated_rpc_registry_drift_v1()
  where signature in (
    'atlas.record_crop_harvest_expectation_for_member_v1(uuid, uuid, date, numeric, text, text, text, text)',
    'atlas.owner_operator_record_crop_harvest_expectation_v1(uuid, uuid, date, numeric, text, text, text, text)'
  );
  if v_drift<>0 then
    raise exception 'Harvest expectation endpoints ended with % custody drift rows.',v_drift;
  end if;
end
$verification$;

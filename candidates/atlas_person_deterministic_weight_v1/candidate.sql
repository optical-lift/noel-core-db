-- SOURCE CANDIDATE ONLY -- no automatic live migration or personal data changes.
-- One deterministic body-weight sentence rule; personal approval controls source projections.
begin;

create table if not exists atlas.person_recognition_rule_permissions_v1 (
  owner_user_id uuid not null references auth.users(id),
  rule_key text not null,
  rule_version integer not null,
  approved_capture_id uuid not null references atlas.personal_reality_captures(id),
  approved_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key(owner_user_id,rule_key,rule_version),
  constraint person_recognition_rule_key_v1 check(rule_key='measure.body_weight.reported'),
  constraint person_recognition_rule_version_v1 check(rule_version=1)
);
comment on table atlas.person_recognition_rule_permissions_v1 is
  'Signed-in Person approval for deterministic interpretation of already-captured personal text. Not a measurement table, not a clinical claim, and not shared permission.';
alter table atlas.person_recognition_rule_permissions_v1 enable row level security;
revoke all on atlas.person_recognition_rule_permissions_v1 from public,anon,authenticated;

create or replace function atlas.recognize_body_weight_sentence_v1(p_text text)
returns jsonb language plpgsql immutable
set search_path to ''
as $body$
declare v_match text[]; v_unit text; v_weight numeric; v_kg numeric;
begin
  if p_text is null or length(p_text)>500 then return null; end if;
  -- Anchored, first-person/owner assertion only; never generalize "weighed the dog".
  -- Explicit unit required. Time words are retained, not promoted to onset.
  v_match:=regexp_match(lower(btrim(p_text)),
    '^(?:i weighed|weighed|i weigh|my weight is|my weight was|weight is|weight was)[[:space:]]+([0-9]{1,3}(?:[.][0-9]{1,2})?)[[:space:]]+(pounds?|lbs?|kilograms?|kg)(?:[[:space:]]+(this morning|today))?[.]?$');
  if v_match is null then return null; end if;
  v_weight:=v_match[1]::numeric;
  if v_weight<=0 or v_weight>=1000 then return null; end if;
  v_unit:=case when v_match[2] in('pound','pounds','lb','lbs') then 'lb' else 'kg' end;
  v_kg:=case when v_unit='lb' then v_weight*0.45359237 else v_weight end;
  return jsonb_build_object(
    'contractVersion','deterministic_person_measurement_v1',
    'ruleKey','measure.body_weight.reported','ruleVersion',1,
    'measurementKind','body_weight','subjectKind','person_body',
    'value',v_weight,'unit',v_unit,'canonicalValueKg',v_kg,
    'statedTimeWords',nullif(v_match[3],''),
    'observedAt',null,'timeStanding','unresolved_original_source',
    'standing','first_party_report_derived_by_approved_rule',
    'derivedNotIndependentlyMeasured',true
  );
end;
$body$;
revoke all on function atlas.recognize_body_weight_sentence_v1(text) from public,anon,authenticated;

-- Signed-in Person requests an interpretation preview for one existing note.
create or replace function atlas.person_measurement_recognition_self_api_v1(p_capture_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare v_user uuid:=auth.uid(); v_principal uuid; v_cap atlas.personal_reality_captures%rowtype;
v_interpretation jsonb; v_permission atlas.person_recognition_rule_permissions_v1%rowtype;
begin
  if v_user is null then raise exception 'Signed-in Person required.' using errcode='42501'; end if;
  v_principal:=atlas.require_active_task_principal_v1();
  select * into v_cap from atlas.personal_reality_captures c
  where c.id=p_capture_id and c.owner_user_id=v_user and c.principal_id=v_principal
    and c.source_surface='personal_notebook_daily_log'
    and c.metadata->>'notebookEntryKind'='raw_note';
  if v_cap.id is null then raise exception 'Owned notebook capture required.' using errcode='42501'; end if;
  v_interpretation:=atlas.recognize_body_weight_sentence_v1(v_cap.testimony);
  if v_interpretation is null then
    return jsonb_build_object('ok',true,'contractVersion','person_measurement_recognition_v1',
      'captureId',v_cap.id,'recognition','unmatched','originalPreserved',true);
  end if;
  select * into v_permission from atlas.person_recognition_rule_permissions_v1 p
  where p.owner_user_id=v_user and p.rule_key='measure.body_weight.reported' and p.rule_version=1
    and p.revoked_at is null;
  return jsonb_build_object('ok',true,'contractVersion','person_measurement_recognition_v1',
    'captureId',v_cap.id,'recognition',
       case when v_permission.owner_user_id is not null then 'approved_rule' else 'approval_required' end,
    'interpretation',v_interpretation,'approvedAt',v_permission.approved_at,
    'originalPreserved',true,'notAClaimOrMedicalDiagnosis',true);
end;
$body$;

-- First deliberate human approval grants standing use of one exact, versioned
-- deterministic read rule. Revoke requires the same owner; no automatic claim write.
create or replace function atlas.set_person_measurement_rule_self_api_v1(
  p_capture_id uuid,p_approve boolean
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare v_user uuid:=auth.uid();v_principal uuid;v_cap atlas.personal_reality_captures%rowtype;
v_rule jsonb;v_row atlas.person_recognition_rule_permissions_v1%rowtype;
begin
  if v_user is null then raise exception 'Signed-in Person required.' using errcode='42501'; end if;
  if p_approve is null then raise exception 'Explicit approval or revocation required.' using errcode='22023'; end if;
  v_principal:=atlas.require_active_task_principal_v1();
  select * into v_cap from atlas.personal_reality_captures c
    where c.id=p_capture_id and c.owner_user_id=v_user and c.principal_id=v_principal
      and c.source_surface='personal_notebook_daily_log'
      and c.metadata->>'notebookEntryKind'='raw_note';
  if v_cap.id is null then raise exception 'Owned notebook capture required.' using errcode='42501'; end if;
  v_rule:=atlas.recognize_body_weight_sentence_v1(v_cap.testimony);
  if v_rule is null then raise exception 'Capture does not satisfy the exact versioned rule.' using errcode='22023'; end if;
  if p_approve then
    insert into atlas.person_recognition_rule_permissions_v1(
      owner_user_id,rule_key,rule_version,approved_capture_id,approved_at,revoked_at
    ) values(v_user,'measure.body_weight.reported',1,v_cap.id,now(),null)
    on conflict(owner_user_id,rule_key,rule_version) do update
      set approved_capture_id=excluded.approved_capture_id,
        approved_at=excluded.approved_at,revoked_at=null;
  else
    update atlas.person_recognition_rule_permissions_v1
      set revoked_at=now()
      where owner_user_id=v_user and rule_key='measure.body_weight.reported'
        and rule_version=1 and revoked_at is null;
  end if;
  select * into v_row from atlas.person_recognition_rule_permissions_v1
    where owner_user_id=v_user and rule_key='measure.body_weight.reported' and rule_version=1;
  return jsonb_build_object('ok',true,'contractVersion','person_measurement_rule_v1',
    'ruleKey','measure.body_weight.reported','ruleVersion',1,'approved',p_approve,
    'approvalSourceCaptureId',v_row.approved_capture_id,
    'approvalAt',v_row.approved_at,'revokedAt',v_row.revoked_at,
    'projectionOnly',true,'doesNotCreateClaim',true);
end;
$body$;

-- Longitudinal projection: the original capture is the only measurement testimony.
-- Permission is itself source evidence of human interpretation choice, not medical consent.
create or replace function atlas.person_body_weight_history_self_api_v1(
  p_days integer default 30,p_timezone text default 'UTC'
) returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare v_user uuid:=auth.uid();v_principal uuid;v_grant timestamptz;v_items jsonb;
v_total integer:=0;v_first date;v_today date;
begin
  if v_user is null then raise exception 'Signed-in Person required.' using errcode='42501'; end if;
  if p_days is null or p_days<1 or p_days>365 then
    raise exception 'Window must be 1 through 365 calendar dates.' using errcode='22023';
  end if;
  if p_timezone is null or not exists(
    select 1 from pg_catalog.pg_timezone_names where name=p_timezone
  ) then raise exception 'Recognized named timezone required.' using errcode='22023'; end if;
  v_principal:=atlas.require_active_task_principal_v1();
  v_today:=(now() at time zone p_timezone)::date;v_first:=v_today-(p_days-1);
  select p.approved_at into v_grant from atlas.person_recognition_rule_permissions_v1 p
    where p.owner_user_id=v_user and p.rule_key='measure.body_weight.reported'
      and p.rule_version=1 and p.revoked_at is null;
  if v_grant is null then return jsonb_build_object(
    'ok',true,'contractVersion','person_body_weight_history_v1',
    'fromDate',v_first,'throughDate',v_today,'items','[]'::jsonb,
    'count',0,'truncated',false,'ruleApproved',false,
    'coverage','rule_not_approved','noSourceAbsenceClaim',true);
  end if;
  with source_rows as (
    select c.id as capture_id,c.evidence_id,c.testimony,c.captured_at,
      c.capture_context->>'notebookDate' as notebook_day,
      atlas.recognize_body_weight_sentence_v1(c.testimony) as parsed
    from atlas.personal_reality_captures c
    where c.owner_user_id=v_user and c.principal_id=v_principal
      and c.source_surface='personal_notebook_daily_log'
      and c.metadata->>'notebookEntryKind'='raw_note'
      and c.capture_context->>'notebookDate' between v_first::text and v_today::text
      and c.capture_context->>'notebookDate' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  ), classified as (
    select * from source_rows where parsed is not null
  ), limited as (
    select * from classified order by notebook_day desc,captured_at desc,capture_id desc limit 101
  ), numbered as (
    select *,row_number() over(order by notebook_day desc,captured_at desc,capture_id desc) as rn
    from limited
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'captureId',capture_id,'evidenceId',evidence_id,
    'originalText',testimony,'notebookDate',notebook_day,
    'recordedAt',captured_at,'interpretation',parsed,
    'ruleApprovedAt',v_grant
  ) order by notebook_day desc,captured_at desc,capture_id desc)
  filter(where rn<=100),'[]'::jsonb),count(*)::integer
  into v_items,v_total
  from numbered;
  return jsonb_build_object(
    'ok',true,'contractVersion','person_body_weight_history_v1',
    'fromDate',v_first,'throughDate',v_today,'items',v_items,
    'count',case when v_total>100 then null else v_total end,
    'truncated',v_total>100,'ruleApproved',true,
    'coverage','only_matching_personal_notebook_weight_sentences',
    'truthBoundary',jsonb_build_object(
      'derivedReadOnly',true,'noMeasurementCopy',true,
      'noInferredMeasurementOnset',true,'notClinicalClaim',true,
      'notAllWeightMeasurements',true,'originalSourceIdentityRetained',true,
      'priorNotesInterpretedAtRuleApprovalNotRetroactivelyKnown',true));
end;
$body$;

create or replace function public.person_measurement_recognition_self_api_v1(p_capture_id uuid)
returns jsonb language sql stable security definer set search_path to ''
as $body$ select atlas.person_measurement_recognition_self_api_v1(p_capture_id); $body$;
create or replace function public.set_person_measurement_rule_self_api_v1(
 p_capture_id uuid,p_approve boolean)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.set_person_measurement_rule_self_api_v1(p_capture_id,p_approve); $body$;
create or replace function public.person_body_weight_history_self_api_v1(
 p_days integer default 30,p_timezone text default 'UTC')
returns jsonb language sql stable security definer set search_path to ''
as $body$ select atlas.person_body_weight_history_self_api_v1(p_days,p_timezone); $body$;

revoke all on function atlas.person_measurement_recognition_self_api_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.set_person_measurement_rule_self_api_v1(uuid,boolean) from public,anon,authenticated;
revoke all on function atlas.person_body_weight_history_self_api_v1(integer,text) from public,anon,authenticated;
revoke all on function public.person_measurement_recognition_self_api_v1(uuid) from public,anon;
revoke all on function public.set_person_measurement_rule_self_api_v1(uuid,boolean) from public,anon;
revoke all on function public.person_body_weight_history_self_api_v1(integer,text) from public,anon;
grant execute on function public.person_measurement_recognition_self_api_v1(uuid) to authenticated;
grant execute on function public.set_person_measurement_rule_self_api_v1(uuid,boolean) to authenticated;
grant execute on function public.person_body_weight_history_self_api_v1(integer,text) to authenticated;
commit;
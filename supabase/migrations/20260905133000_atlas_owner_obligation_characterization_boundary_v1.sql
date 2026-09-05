-- Atlas Owner Obligation / Clock Characterization Boundary v1
--
-- Compatibility repair discovered while wiring freeform capture:
-- a real first-person obligation may be established before Atlas lawfully knows
-- the duration/floor/protection/capability metadata required by Principal Clock.
--
-- This migration keeps the existing atlas.owner_obligations authority/table.
-- It does NOT create a second obligation truth system. Instead it permits a
-- real obligation to exist in pending_characterization state with Clock-only
-- fields null. Existing fully-characterized authoring remains compatible.
--
-- Depends on 20260905124000_atlas_capture_intelligence_kernel_v1.sql.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Make Clock characterization explicitly partial/complete on the existing
--    obligation row while preserving existing rows as complete.
-- ---------------------------------------------------------------------------

alter table atlas.owner_obligations
  alter column expected_minutes drop not null,
  alter column protection_level drop not null,
  alter column floor_class drop not null,
  alter column owner_capability drop not null,
  alter column consequence_of_delay drop not null,
  alter column reason_for_floor drop not null;

alter table atlas.owner_obligations
  add column if not exists clock_characterization_state text not null default 'complete',
  add column if not exists clock_characterization_metadata jsonb not null default '{}'::jsonb;

alter table atlas.owner_obligations
  drop constraint if exists owner_obligations_clock_characterization_state_check;
alter table atlas.owner_obligations
  add constraint owner_obligations_clock_characterization_state_check
  check (clock_characterization_state in ('partial','complete'));

alter table atlas.owner_obligations
  drop constraint if exists owner_obligations_clock_characterization_metadata_check;
alter table atlas.owner_obligations
  add constraint owner_obligations_clock_characterization_metadata_check
  check (jsonb_typeof(clock_characterization_metadata)='object');

alter table atlas.owner_obligations
  drop constraint if exists owner_obligations_status_check;
alter table atlas.owner_obligations
  add constraint owner_obligations_status_check
  check (status in ('pending_characterization','open','in_progress','paused','completed','cancelled'));

comment on column atlas.owner_obligations.clock_characterization_state is
  'Whether all Clock-facing fields required by the current Principal Clock adapter are established. Obligation truth may exist while this is partial.';
comment on column atlas.owner_obligations.clock_characterization_metadata is
  'Provenance/warrant metadata for Clock characterization. This is distinct from obligation-source metadata.';

-- Existing rows predate the split and were structurally required to carry all
-- Clock fields, so preserve them as complete.
update atlas.owner_obligations
set clock_characterization_state='complete'
where clock_characterization_state is distinct from 'complete'
   or clock_characterization_state is null;

-- ---------------------------------------------------------------------------
-- 2. Derived state trigger.
--    No caller may label a row complete while required Clock fields are absent.
--    A partial obligation cannot remain open/in_progress and leak into current
--    Clock/claim projections, which already filter by status.
-- ---------------------------------------------------------------------------

create or replace function atlas.normalize_owner_obligation_characterization_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
declare
  v_complete boolean;
begin
  v_complete :=
    new.expected_minutes is not null
    and new.protection_level is not null
    and new.floor_class is not null
    and new.owner_capability is not null
    and new.consequence_of_delay is not null
    and btrim(new.consequence_of_delay)<>''
    and new.reason_for_floor is not null
    and btrim(new.reason_for_floor)<>'';

  if v_complete then
    new.clock_characterization_state := 'complete';
    if new.status='pending_characterization' then
      new.status := 'open';
    end if;
  else
    new.clock_characterization_state := 'partial';
    if new.status in ('open','in_progress') then
      new.status := 'pending_characterization';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists owner_obligations_characterization_normalize on atlas.owner_obligations;
create trigger owner_obligations_characterization_normalize
before insert or update of
  expected_minutes,
  protection_level,
  floor_class,
  owner_capability,
  consequence_of_delay,
  reason_for_floor,
  status
on atlas.owner_obligations
for each row execute function atlas.normalize_owner_obligation_characterization_v1();

-- ---------------------------------------------------------------------------
-- 3. Capture promotion: accepted/corrected Owner Obligation candidate -> real
--    obligation truth with partial Clock characterization.
--
--    Candidate payload contract v1:
--      title             required string
--      description       optional string
--      mustFinishBy      optional absolute timestamptz string
--      mustBeginBy       optional absolute timestamptz string
--      becomesRelevantAt optional absolute timestamptz string
--      domain            optional string; defaults to 'personal'
--
--    The function intentionally does not accept Clock characterization fields.
-- ---------------------------------------------------------------------------

create or replace function atlas.principal_promote_capture_owner_obligation_api_v1(
  p_adjudication_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_item atlas.human_adjudication_items%rowtype;
  v_adjudication atlas.human_adjudications%rowtype;
  v_observation atlas.capture_observations%rowtype;
  v_inference atlas.model_inferences%rowtype;
  v_payload jsonb;
  v_title text;
  v_domain text;
  v_stable_key text;
  v_row atlas.owner_obligations%rowtype;
  v_must_finish_by timestamptz;
  v_must_begin_by timestamptz;
  v_becomes_relevant_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Active Principal context required.' using errcode='42501';
  end if;

  select * into v_item
  from atlas.human_adjudication_items i
  where i.id=p_adjudication_item_id;

  if not found then
    raise exception 'Adjudication item not found.' using errcode='P0002';
  end if;

  if v_item.decision not in ('accepted','corrected') then
    raise exception 'Only accepted/corrected candidates may be promoted.' using errcode='22023';
  end if;

  if v_item.model_inference_id is null then
    raise exception 'Owner Obligation promotion requires a reviewed model inference candidate.' using errcode='22023';
  end if;

  select * into v_adjudication
  from atlas.human_adjudications a
  where a.id=v_item.adjudication_id
    and a.actor_user_id=v_user_id;

  if not found then
    raise exception 'Adjudication is not owned by the authenticated reviewer.' using errcode='42501';
  end if;

  select * into v_observation
  from atlas.capture_observations o
  where o.id=v_adjudication.observation_id
    and o.created_by_user_id=v_user_id
    and atlas.can_use_capture_scope_v1(o.scope_kind,o.scope_id);

  if not found then
    raise exception 'Source observation is not available to this Principal.' using errcode='42501';
  end if;

  select * into v_inference
  from atlas.model_inferences mi
  where mi.id=v_item.model_inference_id
    and mi.observation_id=v_observation.id
    and mi.candidate_key=v_item.candidate_key
    and mi.candidate_type='owner_obligation_candidate';

  if not found then
    raise exception 'Candidate is not a reviewed Owner Obligation candidate.' using errcode='22023';
  end if;

  v_payload := case
    when v_item.decision='corrected' then v_item.corrected_payload
    else v_item.presented_payload
  end;

  if v_payload is null or jsonb_typeof(v_payload)<>'object' then
    raise exception 'Reviewed Owner Obligation payload is invalid.' using errcode='22023';
  end if;

  v_title := nullif(btrim(v_payload->>'title'),'');
  v_domain := coalesce(nullif(btrim(v_payload->>'domain'),''),'personal');

  if v_title is null then
    raise exception 'Owner Obligation candidate title is required.' using errcode='22023';
  end if;

  begin
    v_must_finish_by := case when nullif(v_payload->>'mustFinishBy','') is null then null else (v_payload->>'mustFinishBy')::timestamptz end;
    v_must_begin_by := case when nullif(v_payload->>'mustBeginBy','') is null then null else (v_payload->>'mustBeginBy')::timestamptz end;
    v_becomes_relevant_at := case when nullif(v_payload->>'becomesRelevantAt','') is null then null else (v_payload->>'becomesRelevantAt')::timestamptz end;
  exception when others then
    raise exception 'Owner Obligation candidate contains invalid absolute timing.' using errcode='22023';
  end;

  if v_must_finish_by is not null and v_must_begin_by is not null and v_must_finish_by<v_must_begin_by then
    raise exception 'Owner Obligation finish cannot precede begin.' using errcode='22023';
  end if;

  v_stable_key := 'capture:' || v_observation.id::text || ':' || v_item.candidate_key;

  insert into atlas.owner_obligations (
    principal_id,
    stable_key,
    domain,
    title,
    description,
    becomes_relevant_at,
    must_begin_by,
    must_finish_by,
    expected_minutes,
    protection_level,
    floor_class,
    owner_capability,
    consequence_of_delay,
    reason_for_floor,
    status,
    source,
    metadata,
    clock_characterization_state,
    clock_characterization_metadata
  ) values (
    v_principal_id,
    v_stable_key,
    v_domain,
    v_title,
    nullif(v_payload->>'description',''),
    v_becomes_relevant_at,
    v_must_begin_by,
    v_must_finish_by,
    null,
    null,
    null,
    null,
    null,
    null,
    'pending_characterization',
    'capture',
    jsonb_build_object(
      'authoringContract','principal_promote_capture_owner_obligation_api_v1',
      'sourceObservationId',v_observation.id,
      'reasoningRunId',v_inference.reasoning_run_id,
      'modelInferenceId',v_inference.id,
      'humanAdjudicationId',v_adjudication.id,
      'humanAdjudicationItemId',v_item.id,
      'candidateKey',v_item.candidate_key,
      'captureLineagePreserved',true
    ),
    'partial',
    jsonb_build_object(
      'state','source_required',
      'missing',jsonb_build_array(
        'expected_minutes',
        'protection_level',
        'floor_class',
        'owner_capability',
        'consequence_of_delay',
        'reason_for_floor'
      ),
      'source','capture_not_yet_characterized'
    )
  )
  on conflict (principal_id,stable_key) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row
    from atlas.owner_obligations o
    where o.principal_id=v_principal_id
      and o.stable_key=v_stable_key;
  end if;

  return jsonb_build_object(
    'contractVersion','capture_owner_obligation_promotion_v1',
    'obligation',to_jsonb(v_row),
    'clockCharacterizationRequired',v_row.clock_characterization_state<>'complete',
    'clockCandidate',null,
    'truthBoundary',jsonb_build_object(
      'obligationTruthEstablished',true,
      'clockCharacterizationEstablished',false,
      'noSyntheticClockDefaults',true
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Explicit Clock characterization authoring.
--    The RPC accepts a complete characterization packet only. Callers may
--    gather it through human input, Company Operating Knowledge, deterministic
--    policy, measured evidence, or separately adjudicated model proposals.
-- ---------------------------------------------------------------------------

create or replace function atlas.principal_characterize_owner_obligation_api_v1(
  p_obligation_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_expected integer;
  v_protection text;
  v_floor smallint;
  v_capability text;
  v_consequence text;
  v_reason text;
  v_interruptibility text;
  v_source_kind text;
  v_source_ref text;
  v_row atlas.owner_obligations%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Active Principal context required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Clock characterization input must be an object.' using errcode='22023';
  end if;

  begin
    v_expected := (p_input->>'expectedMinutes')::integer;
    v_floor := (p_input->>'floorClass')::smallint;
  exception when others then
    raise exception 'expectedMinutes and floorClass must be valid integers.' using errcode='22023';
  end;

  v_protection := nullif(btrim(p_input->>'protectionLevel'),'');
  v_capability := nullif(btrim(p_input->>'ownerCapability'),'');
  v_consequence := nullif(btrim(p_input->>'consequenceOfDelay'),'');
  v_reason := nullif(btrim(p_input->>'reasonForFloor'),'');
  v_interruptibility := coalesce(nullif(btrim(p_input->>'interruptibility'),''),'low_interruptibility');
  v_source_kind := nullif(btrim(p_input->>'sourceKind'),'');
  v_source_ref := nullif(btrim(p_input->>'sourceRef'),'');

  if v_expected is null or v_expected<=0
     or v_protection is null
     or v_floor is null
     or v_capability is null
     or v_consequence is null
     or v_reason is null
     or v_source_kind is null then
    raise exception 'Complete Clock characterization and sourceKind are required.' using errcode='22023';
  end if;

  update atlas.owner_obligations o
     set expected_minutes=v_expected,
         protection_level=v_protection,
         floor_class=v_floor,
         owner_capability=v_capability,
         interruptibility=v_interruptibility,
         consequence_of_delay=v_consequence,
         reason_for_floor=v_reason,
         clock_characterization_metadata=coalesce(o.clock_characterization_metadata,'{}'::jsonb)
           || jsonb_strip_nulls(jsonb_build_object(
             'sourceKind',v_source_kind,
             'sourceRef',v_source_ref,
             'characterizedByUserId',v_user_id,
             'characterizedAt',now(),
             'contractVersion','principal_owner_obligation_clock_characterization_v1'
           )),
         updated_at=now()
   where o.id=p_obligation_id
     and o.principal_id=v_principal_id
     and o.status not in ('completed','cancelled')
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Open Owner Obligation not found for this Principal.' using errcode='P0002';
  end if;

  if v_row.clock_characterization_state<>'complete' or v_row.status='pending_characterization' then
    raise exception 'Clock characterization did not reach complete state.' using errcode='55000';
  end if;

  return jsonb_build_object(
    'contractVersion','principal_owner_obligation_clock_characterization_v1',
    'obligation',to_jsonb(v_row),
    'candidate',(select to_jsonb(c)
                 from atlas.principal_clock_candidates_v1 c
                 where c.source_type='owner_obligation' and c.source_id=v_row.id),
    'truthBoundary',jsonb_build_object(
      'characterizationIsNotObligationSource',true,
      'characterizationWasExplicitlyAuthored',true
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Principal-facing gap read. This keeps partial obligations visible as real
--    obligations that still require planning truth, without putting them on
--    the current Clock.
-- ---------------------------------------------------------------------------

create or replace function atlas.principal_owner_obligation_characterization_gaps_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_items jsonb;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Active Principal context required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'obligationId',o.id,
    'stableKey',o.stable_key,
    'domain',o.domain,
    'title',o.title,
    'description',o.description,
    'becomesRelevantAt',o.becomes_relevant_at,
    'mustBeginBy',o.must_begin_by,
    'mustFinishBy',o.must_finish_by,
    'source',o.source,
    'metadata',o.metadata,
    'clockCharacterizationState',o.clock_characterization_state,
    'clockCharacterizationMetadata',o.clock_characterization_metadata,
    'missingFields',jsonb_build_array(
      case when o.expected_minutes is null then 'expected_minutes' end,
      case when o.protection_level is null then 'protection_level' end,
      case when o.floor_class is null then 'floor_class' end,
      case when o.owner_capability is null then 'owner_capability' end,
      case when o.consequence_of_delay is null or btrim(o.consequence_of_delay)='' then 'consequence_of_delay' end,
      case when o.reason_for_floor is null or btrim(o.reason_for_floor)='' then 'reason_for_floor' end
    ) - 'null'::jsonb
  ) order by coalesce(o.must_finish_by,o.must_begin_by,o.becomes_relevant_at) nulls last,o.created_at,o.id),'[]'::jsonb)
  into v_items
  from atlas.owner_obligations o
  where o.principal_id=v_principal_id
    and o.status='pending_characterization';

  return jsonb_build_object(
    'contractVersion','principal_owner_obligation_characterization_gaps_v1',
    'state',case when jsonb_array_length(v_items)=0 then 'clear' else 'source_required' end,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'obligationExistsWhileCharacterizationIncomplete',true,
      'partialObligationIsNotClockCandidate',true,
      'noSyntheticDefaults',true
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Permissions.
-- ---------------------------------------------------------------------------

revoke all on function atlas.normalize_owner_obligation_characterization_v1() from public, anon, authenticated;
revoke all on function atlas.principal_promote_capture_owner_obligation_api_v1(uuid) from public, anon;
revoke all on function atlas.principal_characterize_owner_obligation_api_v1(uuid,jsonb) from public, anon;
revoke all on function atlas.principal_owner_obligation_characterization_gaps_api_v1() from public, anon;

grant execute on function atlas.normalize_owner_obligation_characterization_v1() to service_role;
grant execute on function atlas.principal_promote_capture_owner_obligation_api_v1(uuid) to authenticated;
grant execute on function atlas.principal_characterize_owner_obligation_api_v1(uuid,jsonb) to authenticated;
grant execute on function atlas.principal_owner_obligation_characterization_gaps_api_v1() to authenticated;

comment on function atlas.principal_promote_capture_owner_obligation_api_v1(uuid) is
  'Promotes one accepted/corrected owner_obligation_candidate from the capture adjudication ledger into real Owner Obligation truth without inventing Clock characterization.';
comment on function atlas.principal_characterize_owner_obligation_api_v1(uuid,jsonb) is
  'Explicitly establishes the Clock-facing characterization required before a pending Owner Obligation may enter the existing Principal Clock candidate path.';
comment on function atlas.principal_owner_obligation_characterization_gaps_api_v1() is
  'Returns real Owner Obligations whose Clock characterization remains incomplete; these obligations are intentionally absent from current Clock candidates.';

COMMIT;

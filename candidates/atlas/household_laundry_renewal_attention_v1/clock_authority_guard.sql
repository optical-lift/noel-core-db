-- Held source: reserve the original Laundry Rhythm, not a new scheduler.
-- No row rewrite, no table replacement, no alteration of unrelated rhythm authority.
BEGIN;
DO $check$ BEGIN
 IF md5(pg_get_functiondef('atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure)) IS DISTINCT FROM '1370fe5f42871133a7075912e4ea18c2' THEN RAISE EXCEPTION 'Original personal_upsert_household_rhythm_local_self_api_v1 drift; re-review exact source'; END IF;
 IF md5(pg_get_functiondef('atlas.principal_upsert_household_rhythm_api_v1(jsonb)'::regprocedure)) IS DISTINCT FROM '6f8f93a1961ee292d996d938c5c3b3de' THEN RAISE EXCEPTION 'Original principal_upsert_household_rhythm_api_v1 drift; re-review exact source'; END IF;
 IF md5(pg_get_viewdef('atlas.principal_capacity_blocks_v1'::regclass,true)) IS DISTINCT FROM '7cc0ca1c3fbbd579726c57d0949a1bf5' THEN RAISE EXCEPTION 'Original principal_capacity_blocks_v1 drift; re-review exact source'; END IF;
 IF md5(pg_get_viewdef('atlas.principal_clock_candidates_v1'::regclass,true)) IS DISTINCT FROM '82b742c1a312451567a0e377326440b8' THEN RAISE EXCEPTION 'Original principal_clock_candidates_v1 drift; re-review exact source'; END IF;
END $check$;
CREATE OR REPLACE FUNCTION atlas.personal_upsert_household_rhythm_local_self_api_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth', 'personal'
AS $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_stable_key text;
  v_area text;
  v_title text;
  v_cadence text;
  v_expected integer;
  v_protection text;
  v_floor smallint;
  v_interruptibility text;
  v_consequence text;
  v_reason text;
  v_start_local timestamp without time zone;
  v_end_local timestamp without time zone;
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean;
  v_blocks_capacity boolean;
  v_metadata jsonb;
  v_row atlas.household_rhythms%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal household compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  select p.active_household_id,h.timezone
  into v_household_id,v_timezone
  from atlas.principals p
  join atlas.households h
    on h.id=p.active_household_id
   and h.status='active'
  where p.id=v_compat_principal_id
    and p.status='active';

  if v_household_id is null or v_timezone is null then
    raise exception 'Active household required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Household rhythm input must be an object.' using errcode='22023';
  end if;

  v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
  IF v_stable_key='kernel:household.laundry:general' THEN
    RAISE EXCEPTION 'Use the original governed Laundry Rhythm decision.' USING ERRCODE='42501';
  END IF;
  v_area:=nullif(trim(p_input->>'area'),'');
  v_title:=nullif(trim(p_input->>'title'),'');
  v_cadence:=nullif(trim(p_input->>'cadenceRule'),'');
  v_protection:=coalesce(nullif(trim(p_input->>'protectionLevel'),''),'protected');
  v_interruptibility:=coalesce(
    nullif(trim(p_input->>'interruptibility'),''),
    'interruptible'
  );
  v_consequence:=nullif(trim(p_input->>'consequence'),'');
  v_reason:=coalesce(
    nullif(trim(p_input->>'reasonForFloor'),''),
    'Protected household rhythm.'
  );

  begin
    v_expected:=(p_input->>'expectedMinutes')::integer;
    v_floor:=coalesce(nullif(p_input->>'floorClass','')::smallint,3);
  exception when others then
    raise exception 'expectedMinutes and floorClass must be integers.'
      using errcode='22023';
  end;

  if v_stable_key is null or v_area is null or v_title is null
     or v_expected is null or v_expected<=0 then
    raise exception 'stableKey, area, title, and positive expectedMinutes are required.'
      using errcode='22023';
  end if;

  if v_cadence not in ('once','daily','weekly','every_5_weeks') then
    raise exception 'Unsupported household cadence.' using errcode='22023';
  end if;

  if v_protection not in ('critical','protected','standard','optional') then
    raise exception 'Unsupported household protection level.' using errcode='22023';
  end if;

  if v_floor<1 or v_floor>7 then
    raise exception 'floorClass must be between 1 and 7.' using errcode='22023';
  end if;

  if v_interruptibility not in (
    'interruptible','low_interruptibility','should_not_interrupt'
  ) then
    raise exception 'Unsupported household interruptibility.'
      using errcode='22023';
  end if;

  if v_consequence is null then
    raise exception 'consequence is required.' using errcode='22023';
  end if;

  if nullif(trim(p_input->>'nextWindowStartLocal'),'') is null
     or nullif(trim(p_input->>'nextWindowEndLocal'),'') is null then
    raise exception 'Local household window start and end are required.'
      using errcode='22023';
  end if;

  begin
    v_start_local:=(p_input->>'nextWindowStartLocal')::timestamp;
    v_end_local:=(p_input->>'nextWindowEndLocal')::timestamp;
  exception when others then
    raise exception 'Household window must use valid local date/time values.'
      using errcode='22023';
  end;

  if v_end_local<=v_start_local then
    raise exception 'Household window end must be after its start.'
      using errcode='22023';
  end if;

  v_start:=v_start_local at time zone v_timezone;
  v_end:=v_end_local at time zone v_timezone;
  v_active:=coalesce((p_input->>'active')::boolean,true);
  v_blocks_capacity:=coalesce((p_input->>'blocksCapacity')::boolean,true);
  v_metadata:=coalesce(
    case
      when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata'
    end,
    '{}'::jsonb
  )||jsonb_build_object(
    'source','personal_upsert_household_rhythm_local_self_api_v1',
    'authoringTimezone',v_timezone,
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'legacyPrincipalStorageOnly',true,
    'legacyPrincipalRequiredCompatibility',true
  );

  insert into atlas.household_rhythms(
    household_id,stable_key,area,title,cadence_rule,
    next_window_start,next_window_end,expected_minutes,
    protection_level,floor_class,interruptibility,
    principal_required,consequence,reason_for_floor,
    active,blocks_capacity,metadata
  ) values (
    v_household_id,v_stable_key,v_area,v_title,v_cadence,
    v_start,v_end,v_expected,
    v_protection,v_floor,v_interruptibility,
    true,v_consequence,v_reason,
    v_active,v_blocks_capacity,v_metadata
  )
  on conflict(household_id,stable_key) do update set
    area=excluded.area,
    title=excluded.title,
    cadence_rule=excluded.cadence_rule,
    next_window_start=excluded.next_window_start,
    next_window_end=excluded.next_window_end,
    expected_minutes=excluded.expected_minutes,
    protection_level=excluded.protection_level,
    floor_class=excluded.floor_class,
    interruptibility=excluded.interruptibility,
    principal_required=true,
    consequence=excluded.consequence,
    reason_for_floor=excluded.reason_for_floor,
    active=excluded.active,
    blocks_capacity=excluded.blocks_capacity,
    metadata=atlas.household_rhythms.metadata||excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','personal_household_rhythm_authoring_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'rhythm',to_jsonb(v_row)-'principal_required',
    'candidate',(
      select to_jsonb(c)
      from atlas.principal_clock_candidates_v1 c
      where c.source_type='household_rhythm'
        and c.source_id=v_row.id
    ),
    'authoringTimezone',v_timezone,
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'legacyPrincipalRequiredFieldIsStorageCompatibility',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;
CREATE OR REPLACE FUNCTION atlas.principal_upsert_household_rhythm_api_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal atlas.principals%rowtype;
  v_household_id uuid;
  v_stable_key text;
  v_area text;
  v_title text;
  v_expected integer;
  v_start timestamptz;
  v_end timestamptz;
  v_row atlas.household_rhythms%rowtype;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals p where p.user_id=auth.uid() and p.status='active' limit 1;
  if v_principal.id is null or v_principal.active_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  v_household_id:=v_principal.active_household_id;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Household rhythm input must be an object.' using errcode='22023'; end if;

  v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
  IF v_stable_key='kernel:household.laundry:general' THEN
    RAISE EXCEPTION 'Use the original governed Laundry Rhythm decision.' USING ERRCODE='42501';
  END IF;
  v_area:=nullif(trim(p_input->>'area'),'');
  v_title:=nullif(trim(p_input->>'title'),'');
  v_expected:=(p_input->>'expectedMinutes')::integer;
  if v_stable_key is null or v_area is null or v_title is null or v_expected<=0 then
    raise exception 'stableKey, area, title, and positive expectedMinutes are required.' using errcode='22023';
  end if;
  v_start:=case when nullif(p_input->>'nextWindowStart','') is null then null else (p_input->>'nextWindowStart')::timestamptz end;
  v_end:=case when nullif(p_input->>'nextWindowEnd','') is null then null else (p_input->>'nextWindowEnd')::timestamptz end;

  insert into atlas.household_rhythms(
    household_id,stable_key,area,title,cadence_rule,next_window_start,next_window_end,expected_minutes,
    protection_level,floor_class,interruptibility,principal_required,consequence,reason_for_floor,
    active,blocks_capacity,metadata
  ) values (
    v_household_id,v_stable_key,v_area,v_title,nullif(p_input->>'cadenceRule',''),v_start,v_end,v_expected,
    coalesce(nullif(p_input->>'protectionLevel',''),'protected'),
    coalesce(nullif(p_input->>'floorClass','')::smallint,3),
    coalesce(nullif(p_input->>'interruptibility',''),'interruptible'),
    coalesce((p_input->>'principalRequired')::boolean,true),
    nullif(p_input->>'consequence',''),
    coalesce(nullif(p_input->>'reasonForFloor',''),'Protected household rhythm.'),
    coalesce((p_input->>'active')::boolean,true),
    coalesce((p_input->>'blocksCapacity')::boolean,true),
    (case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' else '{}'::jsonb end)
      ||jsonb_build_object('source','principal_upsert_household_rhythm_api_v1')
  )
  on conflict (household_id,stable_key) do update set
    area=excluded.area,title=excluded.title,cadence_rule=excluded.cadence_rule,
    next_window_start=excluded.next_window_start,next_window_end=excluded.next_window_end,
    expected_minutes=excluded.expected_minutes,protection_level=excluded.protection_level,
    floor_class=excluded.floor_class,interruptibility=excluded.interruptibility,
    principal_required=excluded.principal_required,consequence=excluded.consequence,
    reason_for_floor=excluded.reason_for_floor,active=excluded.active,blocks_capacity=excluded.blocks_capacity,
    metadata=atlas.household_rhythms.metadata||excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','principal_household_rhythm_authoring_v1',
    'rhythm',to_jsonb(v_row),
    'candidate',(select to_jsonb(c) from atlas.principal_clock_candidates_v1 c where c.source_type='household_rhythm' and c.source_id=v_row.id)
  );
end;
$function$;
CREATE OR REPLACE VIEW atlas.principal_capacity_blocks_v1 AS
SELECT b.principal_id,
    'principal_capacity_block'::text AS source_type,
    b.id AS source_id,
    b.title,
    b.starts_at,
    b.ends_at,
    b.block_kind,
    b.floor_class,
    b.protection_level,
    b.interruptibility,
    b.reason_for_floor,
    b.consequence,
    b.metadata
   FROM atlas.principal_capacity_blocks b
  WHERE b.blocks_capacity
UNION ALL
 SELECT h.principal_id,
    'household_event'::text AS source_type,
    e.id AS source_id,
    e.title,
    e.starts_at,
    e.ends_at,
    e.event_kind AS block_kind,
    e.floor_class,
    e.protection_level,
    e.interruptibility,
    e.reason_for_floor,
    e.consequence,
    e.metadata
   FROM (atlas.household_events e
     JOIN atlas.households h ON ((h.id = e.household_id)))
  WHERE e.blocks_capacity
UNION ALL
 SELECT h.principal_id,
    'household_rhythm'::text AS source_type,
    r.id AS source_id,
    r.title,
    r.next_window_start AS starts_at,
    r.next_window_end AS ends_at,
    'household_rhythm'::text AS block_kind,
    r.floor_class,
    r.protection_level,
    r.interruptibility,
    r.reason_for_floor,
    r.consequence,
    r.metadata
   FROM (atlas.household_rhythms r
     JOIN atlas.households h ON ((h.id = r.household_id)))
  WHERE (r.stable_key IS DISTINCT FROM 'kernel:household.laundry:general'::text AND r.active AND r.blocks_capacity AND (r.next_window_start IS NOT NULL) AND (r.next_window_end IS NOT NULL) AND (NOT (r.metadata @> '{"policyKey": "atlas_household_five_zone_attention", "releaseKind": "protected_attention", "executionGenerated": false}'::jsonb)));
CREATE OR REPLACE VIEW atlas.principal_clock_candidates_v1 AS
SELECT o.principal_id,
    o.domain,
    'owner_obligation'::text AS source_type,
    o.id AS source_id,
    o.title,
    o.floor_class,
    o.becomes_relevant_at AS window_start,
    COALESCE(o.expires_at, o.must_finish_by) AS window_end,
    o.fixed_at AS fixed_start,
    o.must_begin_by,
    o.must_finish_by,
    o.expected_minutes,
    o.protection_level,
    o.interruptibility,
    o.delegable,
    o.owner_required,
    o.consequence_of_delay AS consequence,
    o.reason_for_floor,
    o.portfolio_unit_id,
    o.horizon,
    o.metadata
   FROM atlas.owner_obligations o
  WHERE (o.status = ANY (ARRAY['open'::text, 'in_progress'::text]))
UNION ALL
 SELECT h.principal_id,
    'household'::text AS domain,
    'household_event'::text AS source_type,
    e.id AS source_id,
    e.title,
    e.floor_class,
    e.starts_at AS window_start,
    e.ends_at AS window_end,
        CASE
            WHEN e.fixed THEN e.starts_at
            ELSE NULL::timestamp with time zone
        END AS fixed_start,
    NULL::timestamp with time zone AS must_begin_by,
    e.ends_at AS must_finish_by,
    COALESCE(e.expected_minutes, GREATEST(1, (round((EXTRACT(epoch FROM (e.ends_at - e.starts_at)) / 60.0)))::integer)) AS expected_minutes,
    e.protection_level,
    e.interruptibility,
    false AS delegable,
    e.principal_required AS owner_required,
    e.consequence,
    e.reason_for_floor,
    NULL::uuid AS portfolio_unit_id,
    NULL::text AS horizon,
    e.metadata
   FROM (atlas.household_events e
     JOIN atlas.households h ON ((h.id = e.household_id)))
  WHERE e.principal_required
UNION ALL
 SELECT h.principal_id,
    'household'::text AS domain,
    'household_rhythm'::text AS source_type,
    r.id AS source_id,
    r.title,
    r.floor_class,
    r.next_window_start AS window_start,
    r.next_window_end AS window_end,
    NULL::timestamp with time zone AS fixed_start,
    r.next_window_start AS must_begin_by,
    r.next_window_end AS must_finish_by,
    r.expected_minutes,
    r.protection_level,
    r.interruptibility,
    false AS delegable,
    r.principal_required AS owner_required,
    r.consequence,
    r.reason_for_floor,
    NULL::uuid AS portfolio_unit_id,
    NULL::text AS horizon,
    r.metadata
   FROM (atlas.household_rhythms r
     JOIN atlas.households h ON ((h.id = r.household_id)))
  WHERE (r.stable_key IS DISTINCT FROM 'kernel:household.laundry:general'::text AND r.active AND r.principal_required AND (r.next_window_start IS NOT NULL))
UNION ALL
 SELECT e.principal_id,
    'operations'::text AS domain,
    'operational_escalation'::text AS source_type,
    e.id AS source_id,
    initcap(replace(e.escalation_kind, '_'::text, ' '::text)) AS title,
    e.floor_class,
    e.window_start,
    e.window_end,
    NULL::timestamp with time zone AS fixed_start,
    e.window_start AS must_begin_by,
    e.window_end AS must_finish_by,
    e.expected_owner_minutes AS expected_minutes,
    e.protection_level,
    e.interruptibility,
    false AS delegable,
    true AS owner_required,
    e.consequence,
    e.reason_for_floor,
    e.portfolio_unit_id,
    e.horizon,
    (e.metadata || jsonb_build_object('sourceSystem', e.source_system, 'sourceType', e.source_type, 'sourceId', e.source_id, 'thresholdCrossed', e.threshold_crossed, 'ownerDecisionRequired', e.owner_decision_required, 'severity', e.severity, 'options', e.options_json)) AS metadata
   FROM atlas.operational_escalations e
  WHERE (e.status = ANY (ARRAY['open'::text, 'acknowledged'::text]))
UNION ALL
 SELECT b.principal_id,
    'principal_capacity'::text AS domain,
    'capacity_block'::text AS source_type,
    b.id AS source_id,
    b.title,
    b.floor_class,
    b.starts_at AS window_start,
    b.ends_at AS window_end,
    b.starts_at AS fixed_start,
    b.starts_at AS must_begin_by,
    b.ends_at AS must_finish_by,
    GREATEST(1, (round((EXTRACT(epoch FROM (b.ends_at - b.starts_at)) / 60.0)))::integer) AS expected_minutes,
    b.protection_level,
    b.interruptibility,
    false AS delegable,
    true AS owner_required,
    b.consequence,
    b.reason_for_floor,
    NULL::uuid AS portfolio_unit_id,
    NULL::text AS horizon,
    b.metadata
   FROM atlas.principal_capacity_blocks b
  WHERE b.blocks_capacity
UNION ALL
 SELECT a.principal_id,
    'attention'::text AS domain,
    'attention_debt'::text AS source_type,
    a.subject_id AS source_id,
    a.title,
    a.floor_class,
    a.next_due_at AS window_start,
    NULL::timestamp with time zone AS window_end,
    NULL::timestamp with time zone AS fixed_start,
    a.next_due_at AS must_begin_by,
    NULL::timestamp with time zone AS must_finish_by,
    a.protected_owner_minutes AS expected_minutes,
    a.protection_level,
    a.interruptibility,
    false AS delegable,
    true AS owner_required,
    a.consequence,
    a.reason_for_floor,
    a.portfolio_unit_id,
    a.horizon,
    (a.metadata || jsonb_build_object('attentionState', a.attention_state, 'attentionDebtDays', a.attention_debt_days, 'lastMeaningfulAt', a.last_meaningful_at, 'nextDueAt', a.next_due_at, 'policyId', a.policy_id)) AS metadata
   FROM atlas.attention_debt_v1 a
  WHERE (a.attention_state = 'needs_attention'::text)
UNION ALL
 SELECT c.principal_id,
    c.domain,
    c.source_type,
    c.source_id,
    c.title,
    c.floor_class,
    c.window_start,
    c.window_end,
    c.fixed_start,
    c.must_begin_by,
    c.must_finish_by,
    c.expected_minutes,
    c.protection_level,
    c.interruptibility,
    c.delegable,
    c.owner_required,
    c.consequence,
    c.reason_for_floor,
    c.portfolio_unit_id,
    c.horizon,
    c.metadata
   FROM atlas.principal_requirement_acquisition_clock_candidates_v1 c;
COMMIT;

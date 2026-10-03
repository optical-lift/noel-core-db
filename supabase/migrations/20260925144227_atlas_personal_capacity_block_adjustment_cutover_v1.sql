create or replace function atlas.personal_capacity_blocks_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_start_at is not null and p_end_at is not null and p_end_at<=p_start_at then
    raise exception 'endAt must be later than startAt.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'title',b.title,'blockKind',b.block_kind,'startsAt',b.starts_at,'endsAt',b.ends_at,
    'blocksCapacity',b.blocks_capacity,'context',nullif(b.metadata->>'userContext',''),
    'sourceKey',b.source_id,'sourceEvidenceId',nullif(b.metadata->>'sourceEvidenceId',''),
    'createdAt',b.created_at,'updatedAt',b.updated_at
  ) order by b.starts_at,b.created_at,b.id),'[]'::jsonb)
  into v_items
  from atlas.principal_capacity_blocks b
  where b.principal_id=v_compat_principal_id
    and b.source_type='principal_self_capacity_v1'
    and (p_include_inactive or b.blocks_capacity)
    and (p_start_at is null or b.ends_at>p_start_at)
    and (p_end_at is null or b.starts_at<p_end_at);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_capacity_blocks_self_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'listIsCapacityTruthNotPriorityOrder',true,
      'contextIsNotConsequence',true,
      'inactiveRowsRemainHistoricalEvidence',true,
      'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.personal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean)
  from public,anon;
grant execute on function atlas.personal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean)
  to authenticated,service_role;

create or replace function atlas.personal_capacity_adjustments_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_start_at is not null and p_end_at is not null and p_end_at<=p_start_at then
    raise exception 'endAt must be later than startAt.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'title',a.title,'adjustmentKind',a.adjustment_kind,'startsAt',a.starts_at,'endsAt',a.ends_at,
    'availabilityFraction',a.availability_fraction,'active',a.active,
    'context',nullif(a.metadata->>'userContext',''),'sourceKey',a.source_id,
    'sourceEvidenceId',nullif(a.metadata->>'sourceEvidenceId',''),
    'createdAt',a.created_at,'updatedAt',a.updated_at
  ) order by a.starts_at,a.created_at,a.id),'[]'::jsonb)
  into v_items
  from atlas.principal_capacity_adjustments a
  where a.principal_id=v_compat_principal_id
    and a.source_type='principal_self_capacity_adjustment_v1'
    and (p_include_inactive or a.active)
    and (p_start_at is null or a.ends_at>p_start_at)
    and (p_end_at is null or a.starts_at<p_end_at);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_capacity_adjustments_self_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'adjustmentsAreCapacityBudgetTruthNotPriorityOrder',true,
      'inactiveRowsRemainHistorical',true,
      'adjustmentsAreNotClockCandidates',true,
      'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.personal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean)
  from public,anon;
grant execute on function atlas.personal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean)
  to authenticated,service_role;

create or replace function atlas.record_personal_capacity_block_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_source_key text;
  v_title text;
  v_block_kind text;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_context text;
  v_source_evidence_id uuid;
  v_metadata jsonb;
  v_expected_metadata jsonb;
  v_row atlas.principal_capacity_blocks%rowtype;
  v_existing atlas.principal_capacity_blocks%rowtype;
  v_timezone text;
  v_created boolean:=false;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Personal capacity input must be an object.' using errcode='22023';
  end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_block_kind:=nullif(btrim(p_input->>'blockKind'),'');
  v_context:=nullif(btrim(p_input->>'context'),'');
  v_source_evidence_id:=nullif(btrim(p_input->>'sourceEvidenceId'),'')::uuid;
  v_metadata:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);

  begin
    v_starts_at:=nullif(btrim(p_input->>'startsAt'),'')::timestamptz;
    v_ends_at:=nullif(btrim(p_input->>'endsAt'),'')::timestamptz;
  exception when others then
    raise exception 'startsAt and endsAt must be valid timestamps.' using errcode='22023';
  end;

  if v_source_key is null or v_title is null or v_block_kind is null or v_starts_at is null or v_ends_at is null then
    raise exception 'sourceKey, title, blockKind, startsAt, and endsAt are required.' using errcode='22023';
  end if;
  if v_ends_at<=v_starts_at then raise exception 'endsAt must be later than startsAt.' using errcode='22023'; end if;
  if v_block_kind not in ('human_fixed','household','family','travel','appointment','recovery','other') then
    raise exception 'Unsupported personal capacity block kind.' using errcode='22023';
  end if;

  if v_source_evidence_id is not null and not exists(
    select 1 from atlas.evidence_records e
    where e.id=v_source_evidence_id and e.scope_kind='person' and e.scope_id=v_person_id
  ) then
    raise exception 'sourceEvidenceId must identify evidence owned by the Reality Person.' using errcode='42501';
  end if;

  v_timezone:=atlas.principal_authoritative_timezone_v1(v_compat_principal_id);

  v_expected_metadata:=v_metadata
    ||case when v_source_evidence_id is null then '{}'::jsonb else jsonb_build_object('sourceEvidenceId',v_source_evidence_id) end
    ||case when v_context is null then '{}'::jsonb else jsonb_build_object('userContext',v_context) end
    ||jsonb_build_object(
      'authoringContract','personal_capacity_block_self_writer_v1',
      'authoritativeTimezone',v_timezone,
      'personEntityId',v_person_id,
      'personalAtlasId',v_personal_atlas_id,
      'legacyPrincipalStorageOnly',true,
      'truthBoundary',jsonb_build_object(
        'intervalExplicitlyConfirmed',true,'completeUnavailabilityExplicitlyConfirmed',true,
        'diagnosisNotInferred',true,'causeNotInferred',true,'contextIsNotConsequence',true,
        'priorityScoreNotCreated',true,'taskNotCreated',true,'clockPlacementNotCreatedByWriter',true,
        'unavailableMinutesAreNotDiscretionaryCapacity',true,'protectedStrategyIsNotCapacityBlock',true
      )
    );

  select * into v_existing
  from atlas.principal_capacity_blocks b
  where b.principal_id=v_compat_principal_id
    and b.source_type='principal_self_capacity_v1'
    and b.source_id=v_source_key;

  if v_existing.id is not null then
    if v_existing.title is distinct from v_title
       or v_existing.block_kind is distinct from v_block_kind
       or v_existing.starts_at is distinct from v_starts_at
       or v_existing.ends_at is distinct from v_ends_at
       or v_existing.blocks_capacity is distinct from true
       or v_existing.floor_class is distinct from 1
       or v_existing.protection_level is distinct from 'critical'
       or v_existing.interruptibility is distinct from 'should_not_interrupt'
       or v_existing.metadata is distinct from v_expected_metadata then
      raise exception 'sourceKey retry does not match existing personal capacity block.' using errcode='23505';
    end if;
    v_row:=v_existing;
  else
    insert into atlas.principal_capacity_blocks(
      principal_id,title,block_kind,starts_at,ends_at,blocks_capacity,
      floor_class,protection_level,interruptibility,reason_for_floor,
      source_type,source_id,consequence,metadata
    ) values (
      v_compat_principal_id,v_title,v_block_kind,v_starts_at,v_ends_at,true,
      1,'critical','should_not_interrupt',
      'User-confirmed fixed interval in which personal capacity is unavailable.',
      'principal_self_capacity_v1',v_source_key,null,v_expected_metadata
    )
    returning * into v_row;
    v_created:=true;

    insert into atlas.principal_capacity_block_events(
      capacity_block_id,principal_id,actor_user_id,event_kind,
      from_blocks_capacity,to_blocks_capacity,reason,metadata
    ) values (
      v_row.id,v_compat_principal_id,v_user_id,'recorded',null,true,null,
      jsonb_build_object(
        'sourceKey',v_source_key,
        'authoringContract','personal_capacity_block_self_writer_v1',
        'personEntityId',v_person_id
      )
    );
  end if;

  return jsonb_build_object(
    'ok',true,'created',v_created,
    'contractVersion','personal_capacity_block_self_writer_v1',
    'personEntityId',v_person_id,'personalAtlasId',v_personal_atlas_id,
    'capacityBlock',jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'blockKind',v_row.block_kind,
      'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,'blocksCapacity',v_row.blocks_capacity,
      'context',nullif(v_row.metadata->>'userContext',''),'sourceKey',v_row.source_id,
      'sourceEvidenceId',nullif(v_row.metadata->>'sourceEvidenceId','')
    ),
    'capacityStateOnStartDate',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,(v_starts_at at time zone v_timezone)::date
    ),
    'truthBoundary',jsonb_build_object(
      'writerOwnsOnlyExplicitCompleteTemporaryUnavailability',true,
      'doesNotCreateTask',true,'doesNotCreateOwnerObligation',true,
      'writerDoesNotPlaceClockWork',true,'doesNotInferCause',true,
      'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.record_personal_capacity_block_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.record_personal_capacity_block_self_api_v1(jsonb) to authenticated;

create or replace function atlas.record_personal_capacity_adjustment_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_source_key text;
  v_title text;
  v_kind text;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_fraction numeric;
  v_context text;
  v_source_evidence_id uuid;
  v_metadata jsonb;
  v_expected_metadata jsonb;
  v_row atlas.principal_capacity_adjustments%rowtype;
  v_existing atlas.principal_capacity_adjustments%rowtype;
  v_timezone text;
  v_created boolean:=false;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Personal capacity adjustment input must be an object.' using errcode='22023';
  end if;

  v_source_key:=nullif(btrim(p_input->>'sourceKey'),'');
  v_title:=nullif(btrim(p_input->>'title'),'');
  v_kind:=coalesce(nullif(btrim(p_input->>'adjustmentKind'),''),'reduced_capacity');
  v_context:=nullif(btrim(p_input->>'context'),'');
  v_source_evidence_id:=nullif(btrim(p_input->>'sourceEvidenceId'),'')::uuid;
  v_metadata:=coalesce(case when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata' end,'{}'::jsonb);

  begin
    v_starts_at:=nullif(btrim(p_input->>'startsAt'),'')::timestamptz;
    v_ends_at:=nullif(btrim(p_input->>'endsAt'),'')::timestamptz;
  exception when others then
    raise exception 'startsAt and endsAt must be valid timestamps.' using errcode='22023';
  end;

  if v_source_key is null or v_title is null or v_starts_at is null or v_ends_at is null or not(p_input?'availabilityFraction') then
    raise exception 'sourceKey, title, startsAt, endsAt, and availabilityFraction are required.' using errcode='22023';
  end if;
  if jsonb_typeof(p_input->'availabilityFraction')<>'number' then
    raise exception 'availabilityFraction must be numeric.' using errcode='22023';
  end if;

  v_fraction:=(p_input->>'availabilityFraction')::numeric;
  if v_ends_at<=v_starts_at then raise exception 'endsAt must be later than startsAt.' using errcode='22023'; end if;
  if v_fraction<=0 or v_fraction>=1 then
    raise exception 'availabilityFraction must be greater than 0 and less than 1.' using errcode='22023';
  end if;
  if v_kind not in ('reduced_capacity','recovery','caregiving','travel','appointment','other') then
    raise exception 'Unsupported capacity adjustment kind.' using errcode='22023';
  end if;

  if v_source_evidence_id is not null and not exists(
    select 1 from atlas.evidence_records e
    where e.id=v_source_evidence_id and e.scope_kind='person' and e.scope_id=v_person_id
  ) then
    raise exception 'sourceEvidenceId must identify evidence owned by the Reality Person.' using errcode='42501';
  end if;

  v_timezone:=atlas.principal_authoritative_timezone_v1(v_compat_principal_id);

  v_expected_metadata:=v_metadata
    ||case when v_source_evidence_id is null then '{}'::jsonb else jsonb_build_object('sourceEvidenceId',v_source_evidence_id) end
    ||case when v_context is null then '{}'::jsonb else jsonb_build_object('userContext',v_context) end
    ||jsonb_build_object(
      'authoringContract','personal_capacity_adjustment_self_writer_v1',
      'authoritativeTimezone',v_timezone,
      'personEntityId',v_person_id,
      'personalAtlasId',v_personal_atlas_id,
      'legacyPrincipalStorageOnly',true,
      'truthBoundary',jsonb_build_object(
        'partialAvailabilityExplicitlyConfirmed',true,'zeroAvailabilityRejected',true,
        'fullAvailabilityRejected',true,'diagnosisNotInferred',true,'causeNotInferred',true,
        'taskNotCreated',true,'clockCandidateNotCreated',true,'priorityScoreNotCreated',true
      )
    );

  select * into v_existing
  from atlas.principal_capacity_adjustments a
  where a.principal_id=v_compat_principal_id
    and a.source_type='principal_self_capacity_adjustment_v1'
    and a.source_id=v_source_key;

  if v_existing.id is not null then
    if v_existing.title is distinct from v_title
       or v_existing.adjustment_kind is distinct from v_kind
       or v_existing.starts_at is distinct from v_starts_at
       or v_existing.ends_at is distinct from v_ends_at
       or v_existing.availability_fraction is distinct from v_fraction
       or v_existing.metadata is distinct from v_expected_metadata then
      raise exception 'sourceKey retry does not match existing personal capacity adjustment.' using errcode='23505';
    end if;
    v_row:=v_existing;
  else
    insert into atlas.principal_capacity_adjustments(
      principal_id,title,adjustment_kind,starts_at,ends_at,
      availability_fraction,active,source_type,source_id,metadata
    ) values (
      v_compat_principal_id,v_title,v_kind,v_starts_at,v_ends_at,
      v_fraction,true,'principal_self_capacity_adjustment_v1',v_source_key,v_expected_metadata
    )
    returning * into v_row;
    v_created:=true;

    insert into atlas.principal_capacity_adjustment_events(
      capacity_adjustment_id,principal_id,actor_user_id,event_kind,
      from_active,to_active,reason,metadata
    ) values (
      v_row.id,v_compat_principal_id,v_user_id,'recorded',null,true,null,
      jsonb_build_object(
        'sourceKey',v_source_key,
        'authoringContract','personal_capacity_adjustment_self_writer_v1',
        'personEntityId',v_person_id
      )
    );
  end if;

  return jsonb_build_object(
    'ok',true,'created',v_created,
    'contractVersion','personal_capacity_adjustment_self_writer_v1',
    'personEntityId',v_person_id,'personalAtlasId',v_personal_atlas_id,
    'capacityAdjustment',jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'adjustmentKind',v_row.adjustment_kind,
      'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,
      'availabilityFraction',v_row.availability_fraction,'active',v_row.active,
      'context',nullif(v_row.metadata->>'userContext',''),'sourceKey',v_row.source_id,
      'sourceEvidenceId',nullif(v_row.metadata->>'sourceEvidenceId','')
    ),
    'capacityStateOnStartDate',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,(v_starts_at at time zone v_timezone)::date
    ),
    'truthBoundary',jsonb_build_object(
      'adjustmentChangesCapacityBudgetNotClock',true,
      'zeroAvailabilityBelongsInCapacityBlock',true,
      'doesNotCreateTask',true,'doesNotCreateOwnerObligation',true,
      'doesNotInferCause',true,'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.record_personal_capacity_adjustment_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.record_personal_capacity_adjustment_self_api_v1(jsonb) to authenticated;

create or replace function atlas.transition_personal_capacity_block_self_api_v1(
  p_capacity_block_id uuid,
  p_transition text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_row atlas.principal_capacity_blocks%rowtype;
  v_transition text:=lower(nullif(btrim(p_transition),''));
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_target boolean;
  v_event text;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_capacity_block_id is null or v_transition is null then
    raise exception 'capacityBlockId and transition are required.' using errcode='22023';
  end if;
  if v_transition not in ('cancel','reopen') then
    raise exception 'transition must be cancel or reopen.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.principal_capacity_blocks b
  where b.id=p_capacity_block_id
    and b.principal_id=v_compat_principal_id
    and b.source_type='principal_self_capacity_v1'
  for update;

  if v_row.id is null then raise exception 'Personal capacity block not found.' using errcode='P0002'; end if;

  v_target:=v_transition='reopen';
  v_event:=case when v_target then 'reopened' else 'cancelled' end;

  if v_row.blocks_capacity is distinct from v_target then
    insert into atlas.principal_capacity_block_events(
      capacity_block_id,principal_id,actor_user_id,event_kind,
      from_blocks_capacity,to_blocks_capacity,reason,metadata
    ) values (
      v_row.id,v_compat_principal_id,v_user_id,v_event,
      v_row.blocks_capacity,v_target,v_reason,
      jsonb_build_object(
        'transitionContract','personal_capacity_block_self_transition_v1',
        'personEntityId',v_person_id
      )
    );
    update atlas.principal_capacity_blocks
    set blocks_capacity=v_target,updated_at=now()
    where id=v_row.id returning * into v_row;
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_capacity_block_self_transition_v1',
    'personEntityId',v_person_id,'personalAtlasId',v_personal_atlas_id,
    'capacityBlock',jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,
      'blocksCapacity',v_row.blocks_capacity,'sourceKey',v_row.source_id
    ),
    'transition',v_transition,
    'truthBoundary',jsonb_build_object(
      'cancelDoesNotDeleteHistory',true,'transitionHistoryLivesInEvents',true,
      'reopenRestoresOnlyCapacityBlockingState',true,'transitionDoesNotCreateTask',true,
      'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.transition_personal_capacity_block_self_api_v1(uuid,text,text) from public,anon;
grant execute on function atlas.transition_personal_capacity_block_self_api_v1(uuid,text,text) to authenticated;

create or replace function atlas.transition_personal_capacity_adjustment_self_api_v1(
  p_capacity_adjustment_id uuid,
  p_transition text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_row atlas.principal_capacity_adjustments%rowtype;
  v_transition text:=lower(nullif(btrim(p_transition),''));
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_target boolean;
  v_event text;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id and pa.atlas_state='active' and pa.native;
  if v_personal_atlas_id is null then raise exception 'Active Personal Atlas required.' using errcode='42501'; end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then raise exception 'Personal capacity compatibility carrier unavailable.' using errcode='42501'; end if;

  if p_capacity_adjustment_id is null or v_transition is null then
    raise exception 'capacityAdjustmentId and transition are required.' using errcode='22023';
  end if;
  if v_transition not in ('cancel','reopen') then
    raise exception 'transition must be cancel or reopen.' using errcode='22023';
  end if;

  select * into v_row
  from atlas.principal_capacity_adjustments a
  where a.id=p_capacity_adjustment_id
    and a.principal_id=v_compat_principal_id
    and a.source_type='principal_self_capacity_adjustment_v1'
  for update;

  if v_row.id is null then raise exception 'Personal capacity adjustment not found.' using errcode='P0002'; end if;

  v_target:=v_transition='reopen';
  v_event:=case when v_target then 'reopened' else 'cancelled' end;

  if v_row.active is distinct from v_target then
    insert into atlas.principal_capacity_adjustment_events(
      capacity_adjustment_id,principal_id,actor_user_id,event_kind,
      from_active,to_active,reason,metadata
    ) values (
      v_row.id,v_compat_principal_id,v_user_id,v_event,
      v_row.active,v_target,v_reason,
      jsonb_build_object(
        'transitionContract','personal_capacity_adjustment_self_transition_v1',
        'personEntityId',v_person_id
      )
    );
    update atlas.principal_capacity_adjustments
    set active=v_target,updated_at=now()
    where id=v_row.id returning * into v_row;
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_capacity_adjustment_self_transition_v1',
    'personEntityId',v_person_id,'personalAtlasId',v_personal_atlas_id,
    'capacityAdjustment',jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'startsAt',v_row.starts_at,'endsAt',v_row.ends_at,
      'availabilityFraction',v_row.availability_fraction,'active',v_row.active,'sourceKey',v_row.source_id
    ),
    'transition',v_transition,
    'truthBoundary',jsonb_build_object(
      'cancelDoesNotDeleteHistory',true,'reopenRestoresOnlyAdjustmentState',true,
      'transitionDoesNotCreateClockPlacement',true,'legacyPrincipalStorageOnly',true
    )
  );
end
$function$;

revoke all on function atlas.transition_personal_capacity_adjustment_self_api_v1(uuid,text,text) from public,anon;
grant execute on function atlas.transition_personal_capacity_adjustment_self_api_v1(uuid,text,text) to authenticated;

-- Principal-named self-capacity endpoints are now compatibility aliases.
create or replace function atlas.principal_capacity_policies_self_api_v1()
returns jsonb language sql stable security definer set search_path=''
as $function$ select atlas.personal_capacity_policies_self_api_v1(); $function$;

create or replace function atlas.principal_set_capacity_policy_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$ select atlas.personal_set_capacity_policy_self_api_v1(p_input); $function$;

create or replace function atlas.principal_upsert_household_rhythm_local_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$ select atlas.personal_upsert_household_rhythm_local_self_api_v1(p_input); $function$;

create or replace function atlas.principal_capacity_blocks_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb language sql stable security definer set search_path=''
as $function$
  select atlas.personal_capacity_blocks_self_api_v1(p_start_at,p_end_at,p_include_inactive);
$function$;

create or replace function atlas.principal_capacity_adjustments_self_api_v1(
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_include_inactive boolean default false
)
returns jsonb language sql stable security definer set search_path=''
as $function$
  select atlas.personal_capacity_adjustments_self_api_v1(p_start_at,p_end_at,p_include_inactive);
$function$;

create or replace function atlas.record_principal_capacity_block_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$ select atlas.record_personal_capacity_block_self_api_v1(p_input); $function$;

create or replace function atlas.record_principal_capacity_adjustment_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$ select atlas.record_personal_capacity_adjustment_self_api_v1(p_input); $function$;

create or replace function atlas.transition_principal_capacity_block_self_api_v1(
  p_capacity_block_id uuid,p_transition text,p_reason text default null
)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.transition_personal_capacity_block_self_api_v1(
    p_capacity_block_id,p_transition,p_reason
  );
$function$;

create or replace function atlas.transition_principal_capacity_adjustment_self_api_v1(
  p_capacity_adjustment_id uuid,p_transition text,p_reason text default null
)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.transition_personal_capacity_adjustment_self_api_v1(
    p_capacity_adjustment_id,p_transition,p_reason
  );
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.personal_capacity_blocks_self_api_v1(timestamp with time zone, timestamp with time zone, boolean)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Read self-authored complete-unavailability intervals through Reality Person and Personal Atlas.',
    'storageCompatibility','atlas.principal_capacity_blocks'
  ),now(),false
),
(
  'atlas.personal_capacity_adjustments_self_api_v1(timestamp with time zone, timestamp with time zone, boolean)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Read self-authored partial-capacity intervals through Reality Person and Personal Atlas.',
    'storageCompatibility','atlas.principal_capacity_adjustments'
  ),now(),false
),
(
  'atlas.record_personal_capacity_block_self_api_v1(jsonb)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Record explicit complete temporary unavailability for the signed-in Reality Person.',
    'evidenceBoundary','Person evidence is keyed to Reality Person UUID, not Auth UUID.'
  ),now(),false
),
(
  'atlas.record_personal_capacity_adjustment_self_api_v1(jsonb)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Record explicit partial availability for the signed-in Reality Person.',
    'evidenceBoundary','Person evidence is keyed to Reality Person UUID, not Auth UUID.'
  ),now(),false
),
(
  'atlas.transition_personal_capacity_block_self_api_v1(uuid, text, text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Cancel or reopen the signed-in Person own capacity block without deleting history.'
  ),now(),false
),
(
  'atlas.transition_personal_capacity_adjustment_self_api_v1(uuid, text, text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Cancel or reopen the signed-in Person own capacity adjustment without deleting history.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

update atlas.authenticated_rpc_registry
set evidence=evidence||jsonb_build_object(
      'compatibilityAliasTo','Personal Atlas self-capacity API',
      'identityRoot','Reality Person + native Personal Atlas',
      'legacyPrincipalStorageOnly',true
    ),
    reviewed_at=now()
where signature like 'atlas.principal_capacity_policies_self_api_v1(%'
   or signature like 'atlas.principal_set_capacity_policy_api_v1(%'
   or signature like 'atlas.principal_upsert_household_rhythm_local_api_v1(%'
   or signature like 'atlas.principal_capacity_blocks_self_api_v1(%'
   or signature like 'atlas.principal_capacity_adjustments_self_api_v1(%'
   or signature like 'atlas.record_principal_capacity_block_self_api_v1(%'
   or signature like 'atlas.record_principal_capacity_adjustment_self_api_v1(%'
   or signature like 'atlas.transition_principal_capacity_block_self_api_v1(%'
   or signature like 'atlas.transition_principal_capacity_adjustment_self_api_v1(%';

comment on function atlas.record_personal_capacity_block_self_api_v1(jsonb) is
  'Reality Person + Personal Atlas writer for explicit complete temporary unavailability. Person evidence is scoped by Reality Person UUID.';
comment on function atlas.record_personal_capacity_adjustment_self_api_v1(jsonb) is
  'Reality Person + Personal Atlas writer for explicit partial availability. Person evidence is scoped by Reality Person UUID.';
comment on function atlas.principal_capacity_policies_self_api_v1() is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity policy read.';
comment on function atlas.principal_set_capacity_policy_api_v1(jsonb) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity policy writer.';
comment on function atlas.principal_upsert_household_rhythm_local_api_v1(jsonb) is
  'Compatibility alias to the Reality-rooted Personal Atlas household rhythm writer.';
comment on function atlas.principal_capacity_blocks_self_api_v1(timestamptz,timestamptz,boolean) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity block read.';
comment on function atlas.principal_capacity_adjustments_self_api_v1(timestamptz,timestamptz,boolean) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity adjustment read.';
comment on function atlas.record_principal_capacity_block_self_api_v1(jsonb) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity block writer.';
comment on function atlas.record_principal_capacity_adjustment_self_api_v1(jsonb) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity adjustment writer.';
comment on function atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity block transition.';
comment on function atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text) is
  'Compatibility alias to the Reality-rooted Personal Atlas capacity adjustment transition.';

do $validation$
begin
  if pg_get_functiondef('atlas.principal_capacity_policies_self_api_v1()'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.principal_set_capacity_policy_api_v1(jsonb)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.principal_capacity_blocks_self_api_v1(timestamp with time zone,timestamp with time zone,boolean)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.principal_capacity_adjustments_self_api_v1(timestamp with time zone,timestamp with time zone,boolean)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.record_principal_capacity_block_self_api_v1(jsonb)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.record_principal_capacity_adjustment_self_api_v1(jsonb)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text)'::regprocedure) ilike '%current_principal_id_v1%'
     or pg_get_functiondef('atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text)'::regprocedure) ilike '%current_principal_id_v1%' then
    raise exception 'A Principal-named self-capacity compatibility endpoint still establishes identity through current_principal_id_v1.';
  end if;

  if pg_get_functiondef('atlas.record_personal_capacity_block_self_api_v1(jsonb)'::regprocedure) not ilike '%scope_id=v_person_id%'
     or pg_get_functiondef('atlas.record_personal_capacity_adjustment_self_api_v1(jsonb)'::regprocedure) not ilike '%scope_id=v_person_id%' then
    raise exception 'Personal capacity evidence is not bound to Reality Person identity.';
  end if;
end
$validation$;

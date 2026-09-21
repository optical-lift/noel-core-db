begin;

do $validation$
declare
  v_gap jsonb:='{
    "gapKind":"entity_field_gap",
    "entityId":"f4000000-0000-4000-8000-000000000131",
    "organizationEntityId":"f4000000-0000-4000-8000-000000000121",
    "missingFields":["email"],
    "reason":"Canonical subject exists but required email is missing."
  }'::jsonb;
  v_queue jsonb;
  v_retry jsonb;
  v_attempt_id uuid;
  v_work_id uuid;
  v_context_id uuid;
  v_origin_context uuid;
  v_bad_rejected boolean:=false;
  v_record jsonb;
  v_refresh jsonb;
  v_entity_count_before integer;
  v_entity_count_after integer;
  v_binding_count integer;
begin
  if to_regclass('atlas.contact_set_acquisition_attempts') is null then
    raise exception 'contact_set_acquisition_attempts table is missing';
  end if;
  if to_regprocedure('atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb)') is null then
    raise exception 'contact gap queue service is missing';
  end if;
  if to_regprocedure('atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb)') is null then
    raise exception 'contact gap record service is missing';
  end if;
  if to_regprocedure('atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid)') is null then
    raise exception 'contact execution refresh service is missing';
  end if;

  select count(*)::integer into v_entity_count_before
  from local_intel.entities
  where id in (
    'f4000000-0000-4000-8000-000000000121'::uuid,
    'f4000000-0000-4000-8000-000000000131'::uuid
  );

  select local_context_id into v_origin_context
  from local_intel.entities
  where id='f4000000-0000-4000-8000-000000000131'::uuid;

  v_queue:=atlas.queue_contact_gap_acquisition_service_v1(
    'f4000000-0000-4000-8000-000000000161'::uuid,
    v_gap
  );

  v_attempt_id:=(v_queue->>'attemptId')::uuid;
  v_work_id:=(v_queue->>'discoveryWorkId')::uuid;
  v_context_id:=(v_queue->>'localContextId')::uuid;

  if v_context_id=v_origin_context then
    raise exception 'Atlas research context should be distinct research provenance, not legacy identity origin';
  end if;

  if not exists(
    select 1 from local_intel.local_contexts c
    where c.id=v_context_id
      and c.organization_id='f4000000-0000-4000-8000-000000000101'::uuid
      and c.metadata->>'purpose'='atlas_shared_intelligence_research'
  ) then
    raise exception 'Deterministic Atlas research context was not established';
  end if;

  v_retry:=atlas.queue_contact_gap_acquisition_service_v1(
    'f4000000-0000-4000-8000-000000000161'::uuid,
    v_gap
  );

  if (v_retry->>'attemptId')::uuid<>v_attempt_id
     or (v_retry->>'discoveryWorkId')::uuid<>v_work_id
     or coalesce((v_retry->>'changed')::boolean,true) then
    raise exception 'Exact gap queue retry was not idempotent';
  end if;

  begin
    perform atlas.record_contact_gap_acquisition_service_v1(
      'f4000000-0000-4000-8000-000000000161'::uuid,
      v_work_id,
      '{
        "providerKey":"validation",
        "modelRef":"validation-web-model",
        "providerResponseId":"validation-bad-source",
        "outcome":"evidence_found",
        "sources":[
          {
            "url":"https://source-set.example.invalid/allowed",
            "sourceKind":"official_business_website",
            "title":"Allowed validation source"
          }
        ],
        "findings":[
          {
            "sourceUrl":"https://source-set.example.invalid/not-returned",
            "subjectKind":"person",
            "entityId":"f4000000-0000-4000-8000-000000000131",
            "organizationEntityId":"f4000000-0000-4000-8000-000000000121",
            "observedName":"Avery Reed",
            "email":"avery@river-bank-gap.example.invalid",
            "fields":{"email":"avery@river-bank-gap.example.invalid"}
          }
        ]
      }'::jsonb
    );
  exception when sqlstate '23514' then
    v_bad_rejected:=true;
  end;

  if not v_bad_rejected then
    raise exception 'Finding outside machine source set was not rejected';
  end if;

  v_record:=atlas.record_contact_gap_acquisition_service_v1(
    'f4000000-0000-4000-8000-000000000161'::uuid,
    v_work_id,
    '{
      "providerKey":"validation",
      "modelRef":"validation-web-model",
      "providerResponseId":"validation-good-source",
      "outcome":"evidence_found",
      "sources":[
        {
          "url":"https://source-set.example.invalid/allowed",
          "sourceKind":"official_business_website",
          "title":"Allowed validation source",
          "publisher":"Validation River Bank"
        }
      ],
      "findings":[
        {
          "sourceUrl":"https://source-set.example.invalid/allowed",
          "subjectKind":"person",
          "entityId":"f4000000-0000-4000-8000-000000000131",
          "organizationEntityId":"f4000000-0000-4000-8000-000000000121",
          "organizationName":"Validation River Bank",
          "observedName":"Avery Reed",
          "roleTitle":"Branch Director",
          "roleFunction":"management",
          "email":"avery@river-bank-gap.example.invalid",
          "fields":{"email":"avery@river-bank-gap.example.invalid"}
        }
      ]
    }'::jsonb
  );

  if v_record->>'status'<>'complete' then
    raise exception 'Valid acquisition result did not complete attempt: %',v_record;
  end if;

  if not exists(
    select 1 from local_intel.contact_points cp
    where cp.entity_id='f4000000-0000-4000-8000-000000000131'::uuid
      and cp.contact_type='email'
      and cp.normalized_value='avery@river-bank-gap.example.invalid'
  ) then
    raise exception 'Source-backed email did not enrich the canonical person';
  end if;

  if not exists(
    select 1 from local_intel.entity_context_memberships m
    where m.entity_id='f4000000-0000-4000-8000-000000000131'::uuid
      and m.local_context_id=v_context_id
      and m.status='active'
  ) then
    raise exception 'Research relevance membership was not established for canonical person';
  end if;

  if exists(
    select 1 from local_intel.entities e
    where e.id='f4000000-0000-4000-8000-000000000131'::uuid
      and e.local_context_id<>v_origin_context
  ) then
    raise exception 'Canonical person legacy origin pointer was rewritten by research';
  end if;

  if not exists(
    select 1 from local_intel.search_discovery_queue w
    where w.id=v_work_id and w.status='complete' and w.completed_at is not null
  ) then
    raise exception 'Shared discovery work did not complete';
  end if;

  v_refresh:=atlas.refresh_contact_set_execution_after_acquisition_service_v1(
    'f4000000-0000-4000-8000-000000000161'::uuid
  );

  if v_refresh->>'executionState'<>'ready' then
    raise exception 'Source-backed resolved email should make validation run ready: %',v_refresh;
  end if;

  select count(*)::integer into v_binding_count
  from atlas.identity_subject_external_identifiers i
  where i.organization_id='f4000000-0000-4000-8000-000000000101'::uuid
    and i.provider_key='local_intel'
    and i.identifier_type='entity_id'
    and i.identifier_normalized='f4000000-0000-4000-8000-000000000131'
    and i.is_current;

  if v_binding_count<>1 then
    raise exception 'Requesting Ledger did not bind exactly once to canonical person';
  end if;

  select count(*)::integer into v_entity_count_after
  from local_intel.entities
  where id in (
    'f4000000-0000-4000-8000-000000000121'::uuid,
    'f4000000-0000-4000-8000-000000000131'::uuid
  );

  if v_entity_count_after<>v_entity_count_before then
    raise exception 'Gap acquisition created unexpected canonical entities';
  end if;

  if exists(
    select 1 from information_schema.role_table_grants
    where table_schema='atlas'
      and table_name='contact_set_acquisition_attempts'
      and grantee in ('anon','authenticated','service_role')
  ) then
    raise exception 'Acquisition attempt table leaked direct application-role grants';
  end if;

  if has_function_privilege('authenticated','atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role unexpectedly has direct acquisition mutation service access';
  end if;

  if not has_function_privilege('service_role','atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid)','EXECUTE') then
    raise exception 'Service role lacks governed acquisition membrane access';
  end if;
end;
$validation$;

rollback;

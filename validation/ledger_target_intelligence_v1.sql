-- Atlas Ledger Target Intelligence v1 validation
-- Run after candidates/atlas-ledger-target-intelligence-v1/candidate.sql in a disposable production-schema clone.

begin;

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
values
  ('10000000-0000-4000-8000-000000000001','__target_intel_practitioner','person','Fixture Practitioner','canonical','{}'),
  ('10000000-0000-4000-8000-000000000002','__target_intel_ledger_subject','organization','Fixture Ledger Subject','canonical','{}'),
  ('20000000-0000-4000-8000-000000000001','__target_intel_region_a','place','Fixture Region A','canonical','{}'),
  ('20000000-0000-4000-8000-000000000002','__target_intel_region_b','place','Fixture Region B','canonical','{}'),
  ('30000000-0000-4000-8000-000000000001','__target_intel_business_x','business','Fixture Business X','canonical','{}'),
  ('30000000-0000-4000-8000-000000000002','__target_intel_business_y','business','Fixture Business Y','canonical','{}'),
  ('30000000-0000-4000-8000-000000000003','__target_intel_person_z','person','Fixture Person Z','canonical','{}'),
  ('30000000-0000-4000-8000-000000000004','__target_intel_business_w','business','Fixture Business W','canonical','{}');

insert into ledger.onboarding_cases(
  id,subject_entity_id,practitioner_person_entity_id,desired_ledger_name,onboarding_state,ready_at,onboarding_basis
) values (
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  'Fixture Ledger',
  'ready_to_activate',
  now(),
  '{"fixture":true}'::jsonb
);

insert into ledger.ledgers(
  id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata
) values (
  '40000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000001',
  '__target_intel_ledger',
  'Fixture Ledger',
  'active',
  '{"fixture":true}'::jsonb
);

insert into reality.entity_relationships(
  id,subject_entity_id,relationship_kind,object_entity_id,relationship_state,evidence,metadata
) values
  (
    '60000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'operates_in',
    '20000000-0000-4000-8000-000000000001',
    'established',
    '{"fixture":true}',
    '{}'
  ),
  (
    '60000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'operates_in',
    '20000000-0000-4000-8000-000000000002',
    'observed',
    '{"fixture":true}',
    '{}'
  ),
  (
    '60000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000002',
    'operates_in',
    '20000000-0000-4000-8000-000000000001',
    'established',
    '{"fixture":true}',
    '{}'
  ),
  (
    '60000000-0000-4000-8000-000000000004',
    '30000000-0000-4000-8000-000000000004',
    'operates_in',
    '20000000-0000-4000-8000-000000000002',
    'disputed',
    '{"fixture":true}',
    '{}'
  );

insert into ledger.target_purposes(
  id,ledger_id,stable_key,name,purpose_statement,purpose_state,basis
) values (
  '50000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000002',
  'fixture_purpose',
  'Fixture Purpose',
  'Identify Reality subjects satisfying a governed two-region operating-presence rule.',
  'active',
  '{"fixture":true}'::jsonb
);

insert into ledger.target_definitions(
  id,purpose_id,stable_key,name,definition_state,basis
) values (
  '50000000-0000-4000-8000-000000000002',
  '50000000-0000-4000-8000-000000000001',
  'fixture_target',
  'Fixture Target',
  'active',
  '{"fixture":true}'::jsonb
);

insert into ledger.target_definition_versions(
  id,target_definition_id,version_number,predicate,version_state,definition_basis
) values (
  '50000000-0000-4000-8000-000000000003',
  '50000000-0000-4000-8000-000000000002',
  1,
  jsonb_build_object(
    'op','all',
    'predicates',jsonb_build_array(
      jsonb_build_object('op','entity_kind_is','entityKind','business'),
      jsonb_build_object(
        'op','relationship_exists',
        'relationshipKind','operates_in',
        'direction','outbound',
        'counterpartyEntityId','20000000-0000-4000-8000-000000000001'
      ),
      jsonb_build_object(
        'op','relationship_exists',
        'relationshipKind','operates_in',
        'direction','outbound',
        'counterpartyEntityId','20000000-0000-4000-8000-000000000002'
      )
    )
  ),
  'active',
  '{"fixture":true}'::jsonb
);

-- Grammar validation: valid composition succeeds.
select ledger.validate_target_predicate_v1(
  '{"op":"any","predicates":[{"op":"entity_kind_is","entityKind":"business"},{"op":"entity_id_is","entityId":"30000000-0000-4000-8000-000000000001"}]}'::jsonb,
  0
);

-- Grammar validation: unknown operator, malformed UUID, empty composition and excessive depth fail closed.
do $validation$
declare
  v_rejected boolean;
  v_deep jsonb:='{"op":"entity_kind_is","entityKind":"business"}'::jsonb;
  i integer;
begin
  v_rejected:=false;
  begin
    perform ledger.validate_target_predicate_v1('{"op":"invented_operator"}'::jsonb,0);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Unknown Target predicate operator did not fail closed.'; end if;

  v_rejected:=false;
  begin
    perform ledger.validate_target_predicate_v1('{"op":"entity_id_is","entityId":"not-a-uuid"}'::jsonb,0);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Malformed Target entity UUID did not fail closed.'; end if;

  v_rejected:=false;
  begin
    perform ledger.validate_target_predicate_v1('{"op":"all","predicates":[]}'::jsonb,0);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Empty all predicate did not fail closed.'; end if;

  for i in 1..13 loop
    v_deep:=jsonb_build_object('op','not','predicate',v_deep);
  end loop;
  v_rejected:=false;
  begin
    perform ledger.validate_target_predicate_v1(v_deep,0);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Excessive Target predicate nesting did not fail closed.'; end if;
end
$validation$;

-- Version content is immutable and active-version uniqueness fails closed.
do $validation$
declare
  v_rejected boolean;
begin
  v_rejected:=false;
  begin
    update ledger.target_definition_versions
    set predicate='{"op":"entity_kind_is","entityKind":"person"}'::jsonb
    where id='50000000-0000-4000-8000-000000000003';
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Active Target Definition Version predicate was mutable.'; end if;

  insert into ledger.target_definition_versions(
    id,target_definition_id,version_number,predicate,version_state,definition_basis
  ) values (
    '50000000-0000-4000-8000-000000000004',
    '50000000-0000-4000-8000-000000000002',
    2,
    '{"op":"entity_kind_is","entityKind":"business"}'::jsonb,
    'draft',
    '{"fixture":true}'::jsonb
  );

  v_rejected:=false;
  begin
    update ledger.target_definition_versions
    set version_state='active'
    where id='50000000-0000-4000-8000-000000000004';
  exception when unique_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'Second active Target Definition Version was admitted.'; end if;
end
$validation$;

-- Leaf and composition laws.
do $validation$
declare
  v jsonb;
begin
  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000001',
    '{"op":"entity_kind_is","entityKind":"business"}'::jsonb
  );
  if v->>'state'<>'true' then raise exception 'entity_kind_is true case failed: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000003',
    '{"op":"entity_kind_is","entityKind":"business"}'::jsonb
  );
  if v->>'state'<>'false' then raise exception 'entity_kind_is false case failed: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000001',
    '{"op":"entity_id_is","entityId":"30000000-0000-4000-8000-000000000001"}'::jsonb
  );
  if v->>'state'<>'true' then raise exception 'entity_id_is true case failed: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000001',
    '{"op":"relationship_exists","relationshipKind":"operates_in","direction":"outbound","counterpartyEntityId":"20000000-0000-4000-8000-000000000001"}'::jsonb
  );
  if v->>'state'<>'true' then raise exception 'Established relationship did not evaluate true: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000001',
    '{"op":"relationship_exists","relationshipKind":"operates_in","direction":"outbound","counterpartyEntityId":"20000000-0000-4000-8000-000000000002"}'::jsonb
  );
  if v->>'state'<>'true' then raise exception 'Observed relationship did not evaluate true: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000002',
    '{"op":"relationship_exists","relationshipKind":"operates_in","direction":"outbound","counterpartyEntityId":"20000000-0000-4000-8000-000000000002"}'::jsonb
  );
  if v->>'state'<>'unknown' or jsonb_array_length(v->'obligations')<>1 then
    raise exception 'Absent open-world relationship did not evaluate unknown with one obligation: %',v;
  end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000004',
    '{"op":"relationship_exists","relationshipKind":"operates_in","direction":"outbound","counterpartyEntityId":"20000000-0000-4000-8000-000000000002"}'::jsonb
  );
  if v->>'state'<>'unknown' or v->>'reason'<>'relationship_disputed' then
    raise exception 'Disputed relationship did not remain unknown: %',v;
  end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000001',
    '{"op":"any","predicates":[{"op":"entity_kind_is","entityKind":"person"},{"op":"entity_id_is","entityId":"30000000-0000-4000-8000-000000000001"}]}'::jsonb
  );
  if v->>'state'<>'true' then raise exception 'any three-valued composition failed: %',v; end if;

  v:=ledger.evaluate_target_predicate_v1(
    '30000000-0000-4000-8000-000000000002',
    '{"op":"not","predicate":{"op":"relationship_exists","relationshipKind":"operates_in","direction":"outbound","counterpartyEntityId":"20000000-0000-4000-8000-000000000002"}}'::jsonb
  );
  if v->>'state'<>'unknown' then raise exception 'not did not preserve unknown: %',v; end if;
end
$validation$;

-- Evaluate the three canonical fixture outcomes while proving Evaluation creates no Reality/action truth.
do $validation$
declare
  v_entity_count bigint;
  v_relationship_count bigint;
  v_action_count bigint;
  v_after_entity_count bigint;
  v_after_relationship_count bigint;
  v_after_action_count bigint;
  v jsonb;
begin
  select count(*) into v_entity_count from reality.entities;
  select count(*) into v_relationship_count from reality.entity_relationships;
  select count(*) into v_action_count from ledger.actions;

  v:=ledger.evaluate_target_definition_service_v1(
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000001',
    'deterministic_target_predicate_v1','1','fixture-x-1','{"fixture":true}'::jsonb
  );
  if v->>'evaluationState'<>'qualified' then raise exception 'Business X did not qualify: %',v; end if;

  v:=ledger.evaluate_target_definition_service_v1(
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000002',
    'deterministic_target_predicate_v1','1','fixture-y-1','{"fixture":true}'::jsonb
  );
  if v->>'evaluationState'<>'indeterminate' then raise exception 'Business Y was not indeterminate: %',v; end if;

  v:=ledger.evaluate_target_definition_service_v1(
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000003',
    'deterministic_target_predicate_v1','1','fixture-z-1','{"fixture":true}'::jsonb
  );
  if v->>'evaluationState'<>'not_qualified' then raise exception 'Person Z was not not_qualified: %',v; end if;

  select count(*) into v_after_entity_count from reality.entities;
  select count(*) into v_after_relationship_count from reality.entity_relationships;
  select count(*) into v_after_action_count from ledger.actions;

  if v_after_entity_count<>v_entity_count then raise exception 'Target evaluation mutated Reality Entity count.'; end if;
  if v_after_relationship_count<>v_relationship_count then raise exception 'Target evaluation mutated Reality relationship count.'; end if;
  if v_after_action_count<>v_action_count then raise exception 'Target evaluation created Ledger actions.'; end if;
end
$validation$;

-- The indeterminate fixture has exactly one precise Evidence Obligation.
do $validation$
declare
  v_eval uuid;
  v_count integer;
  v_obligation ledger.target_evidence_obligations%rowtype;
begin
  select id into v_eval
  from ledger.target_evaluations
  where idempotency_key='fixture-y-1';

  select count(*) into v_count
  from ledger.target_evidence_obligations
  where evaluation_id=v_eval;
  if v_count<>1 then raise exception 'Expected exactly one Evidence Obligation, got %.',v_count; end if;

  select * into v_obligation
  from ledger.target_evidence_obligations
  where evaluation_id=v_eval;

  if v_obligation.predicate_path<>'$.predicates[2]'
     or v_obligation.obligation_kind<>'resolve_relationship_proposition'
     or v_obligation.proposition->>'subjectEntityId'<>'30000000-0000-4000-8000-000000000002'
     or v_obligation.proposition->>'counterpartyEntityId'<>'20000000-0000-4000-8000-000000000002' then
    raise exception 'Evidence Obligation is not exact: %',row_to_json(v_obligation);
  end if;
end
$validation$;

-- Determinate fixture creates no Evidence Obligation.
do $validation$
declare
  v_eval uuid;
  v_count integer;
begin
  select id into v_eval from ledger.target_evaluations where idempotency_key='fixture-x-1';
  select count(*) into v_count from ledger.target_evidence_obligations where evaluation_id=v_eval;
  if v_count<>0 then raise exception 'Qualified evaluation created unexpected Evidence Obligations.'; end if;
end
$validation$;

-- Idempotency reuses the same Evaluation; a fresh evaluation preserves new history.
do $validation$
declare
  v_before integer;
  v_after integer;
  v_history integer;
begin
  select count(*) into v_before
  from ledger.target_evaluations
  where ledger_id='40000000-0000-4000-8000-000000000002'
    and idempotency_key='fixture-x-1';

  perform ledger.evaluate_target_definition_service_v1(
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000001',
    'deterministic_target_predicate_v1','1','fixture-x-1','{"fixture":true}'::jsonb
  );

  select count(*) into v_after
  from ledger.target_evaluations
  where ledger_id='40000000-0000-4000-8000-000000000002'
    and idempotency_key='fixture-x-1';
  if v_before<>1 or v_after<>1 then raise exception 'Evaluation idempotency failed.'; end if;

  perform ledger.evaluate_target_definition_service_v1(
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000001',
    'deterministic_target_predicate_v1','1',null,'{"fixture":true,"reevaluation":true}'::jsonb
  );

  select count(*) into v_history
  from ledger.target_evaluations
  where subject_entity_id='30000000-0000-4000-8000-000000000001'
    and target_definition_version_id='50000000-0000-4000-8000-000000000003';
  if v_history<2 then raise exception 'Reevaluation did not preserve append-oriented history.'; end if;
end
$validation$;

-- Receipt explains exact version, subject, evaluator and truth boundary.
do $validation$
declare
  v_eval uuid;
  v jsonb;
begin
  select id into v_eval from ledger.target_evaluations where idempotency_key='fixture-y-1';
  v:=ledger.target_evaluation_receipt_v1(v_eval);
  if v->'targetDefinition'->>'versionNumber'<>'1'
     or v->'subjectEntity'->>'id'<>'30000000-0000-4000-8000-000000000002'
     or v->'evaluator'->>'version'<>'1'
     or coalesce((v->'truthBoundary'->>'doesNotEstablishReality')::boolean,false) is not true
     or coalesce((v->'truthBoundary'->>'doesNotAuthorizeCommunication')::boolean,false) is not true then
    raise exception 'Target Evaluation receipt is incomplete: %',v;
  end if;
end
$validation$;

-- Private custody: no direct browser table or function execution grants.
do $validation$
declare
  v_grants integer;
begin
  select count(*) into v_grants
  from information_schema.role_table_grants g
  where g.table_schema='ledger'
    and g.table_name in (
      'target_purposes',
      'target_definitions',
      'target_definition_versions',
      'target_evaluations',
      'target_evidence_obligations'
    )
    and g.grantee in ('anon','authenticated');
  if v_grants<>0 then raise exception 'Browser roles received direct Target Intelligence table grants.'; end if;

  if has_function_privilege('anon','ledger.evaluate_target_definition_service_v1(uuid,uuid,text,text,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','ledger.evaluate_target_definition_service_v1(uuid,uuid,text,text,text,jsonb)','EXECUTE') then
    raise exception 'Browser role can execute Target Intelligence mutation service.';
  end if;
end
$validation$;

rollback;

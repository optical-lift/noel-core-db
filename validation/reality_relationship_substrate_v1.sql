-- Rollback-only acceptance fixture for ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1.
-- Requires the candidate migration plus Ledger Target Intelligence v1.
-- Synthetic universal entities only. Leaves no fixture data behind.

begin;

set local lock_timeout='3s';
set local statement_timeout='30s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('10000000-0000-4000-8000-000000000001','rrs-v1-subject-a','test_subject','Relationship Fixture Subject A','canonical','{}'),
  ('10000000-0000-4000-8000-000000000002','rrs-v1-subject-b','wrong_subject','Relationship Fixture Subject B','canonical','{}'),
  ('20000000-0000-4000-8000-000000000001','rrs-v1-object-a','test_object','Relationship Fixture Object A','canonical','{}'),
  ('20000000-0000-4000-8000-000000000002','rrs-v1-object-b','test_object','Relationship Fixture Object B','canonical','{}'),
  ('20000000-0000-4000-8000-000000000003','rrs-v1-object-c','test_object','Relationship Fixture Object C','canonical','{}');

select reality.register_relationship_kind_service_v1(
  'fixture_relates_to',
  'Fixture relates to',
  'Synthetic universal validation relationship.',
  null,
  false,
  array['test_subject'],
  array['test_object'],
  jsonb_build_object('fixture',true)
);

-- Registration must be idempotent when semantics are identical.
select reality.register_relationship_kind_service_v1(
  'fixture_relates_to',
  'Fixture relates to',
  'Synthetic universal validation relationship.',
  null,
  false,
  array['test_subject'],
  array['test_object'],
  jsonb_build_object('fixture',true)
);

do $fixture$
declare
  v_accept jsonb;
  v_accept_repeat jsonb;
  v_accept_id uuid;
  v_reject jsonb;
  v_reject_id uuid;
  v_dispute jsonb;
  v_dispute_id uuid;
  v_eval jsonb;
  v_count integer;
  v_failed boolean;
begin
  -- Unknown relationship kind fails closed.
  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1(
      '10000000-0000-4000-8000-000000000001',
      'fixture_unknown_kind',
      '20000000-0000-4000-8000-000000000001',
      'observed',null,null,'{}','{}','rrs-v1-unknown-kind'
    );
  exception when others then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Validation failed: unknown relationship kind did not fail closed.';
  end if;

  -- Endpoint-kind restrictions fail closed.
  v_failed:=false;
  begin
    perform reality.record_relationship_proposition_service_v1(
      '10000000-0000-4000-8000-000000000002',
      'fixture_relates_to',
      '20000000-0000-4000-8000-000000000001',
      'observed',null,null,'{}','{}','rrs-v1-wrong-endpoint'
    );
  exception when others then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Validation failed: invalid endpoint kind did not fail closed.';
  end if;

  -- Accepted path.
  v_accept:=reality.record_relationship_proposition_service_v1(
    '10000000-0000-4000-8000-000000000001',
    'fixture_relates_to',
    '20000000-0000-4000-8000-000000000001',
    'established',null,null,
    jsonb_build_object('fixtureCase','accept'),
    jsonb_build_object('fixture',true),
    'rrs-v1-accept'
  );
  v_accept_id:=(v_accept->>'propositionId')::uuid;

  v_accept_repeat:=reality.record_relationship_proposition_service_v1(
    '10000000-0000-4000-8000-000000000001',
    'fixture_relates_to',
    '20000000-0000-4000-8000-000000000001',
    'established',null,null,
    jsonb_build_object('fixtureCase','accept'),
    jsonb_build_object('fixture',true),
    'rrs-v1-accept'
  );
  if (v_accept_repeat->>'propositionId')::uuid<>v_accept_id then
    raise exception 'Validation failed: proposition idempotency did not reuse proposition.';
  end if;

  perform reality.add_relationship_proposition_evidence_service_v1(
    v_accept_id,
    'fixture_evidence',
    jsonb_build_object('source','synthetic'),
    jsonb_build_object('supports',true),
    'Synthetic evidence for accepted proposition.',
    now(),
    jsonb_build_object('fixture',true)
  );

  perform reality.adjudicate_relationship_proposition_service_v1(
    v_accept_id,'accept','Synthetic accepted proposition.',jsonb_build_object('authority','validation_fixture'),null
  );

  select count(*) into v_count
  from reality.entity_relationships
  where subject_entity_id='10000000-0000-4000-8000-000000000001'
    and relationship_kind='fixture_relates_to'
    and object_entity_id='20000000-0000-4000-8000-000000000001'
    and relationship_state='established';
  if v_count<>1 then
    raise exception 'Validation failed: accepted proposition did not materialize exactly one canonical relationship.';
  end if;

  v_eval:=ledger.evaluate_target_predicate_v1(
    '10000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','relationship_exists',
      'relationshipKind','fixture_relates_to',
      'direction','outbound',
      'counterpartyEntityId','20000000-0000-4000-8000-000000000001'
    ),
    '$',0
  );
  if v_eval->>'state'<>'true' then
    raise exception 'Validation failed: Target Intelligence did not read accepted canonical relationship as TRUE.';
  end if;

  -- Rejected path creates no canonical row and requires no evidence.
  v_reject:=reality.record_relationship_proposition_service_v1(
    '10000000-0000-4000-8000-000000000001',
    'fixture_relates_to',
    '20000000-0000-4000-8000-000000000002',
    'observed',null,null,
    jsonb_build_object('fixtureCase','reject'),
    jsonb_build_object('fixture',true),
    'rrs-v1-reject'
  );
  v_reject_id:=(v_reject->>'propositionId')::uuid;

  perform reality.adjudicate_relationship_proposition_service_v1(
    v_reject_id,'reject','Synthetic rejected proposition.',jsonb_build_object('authority','validation_fixture'),null
  );

  select count(*) into v_count
  from reality.entity_relationships
  where subject_entity_id='10000000-0000-4000-8000-000000000001'
    and relationship_kind='fixture_relates_to'
    and object_entity_id='20000000-0000-4000-8000-000000000002';
  if v_count<>0 then
    raise exception 'Validation failed: rejected proposition created canonical relationship.';
  end if;

  -- Disputed path creates explicit canonical disputed state.
  v_dispute:=reality.record_relationship_proposition_service_v1(
    '10000000-0000-4000-8000-000000000001',
    'fixture_relates_to',
    '20000000-0000-4000-8000-000000000003',
    'observed',null,null,
    jsonb_build_object('fixtureCase','dispute'),
    jsonb_build_object('fixture',true),
    'rrs-v1-dispute'
  );
  v_dispute_id:=(v_dispute->>'propositionId')::uuid;

  perform reality.add_relationship_proposition_evidence_service_v1(
    v_dispute_id,
    'fixture_evidence',
    jsonb_build_object('source','synthetic'),
    jsonb_build_object('contested',true),
    'Synthetic contested evidence.',
    now(),
    jsonb_build_object('fixture',true)
  );

  perform reality.adjudicate_relationship_proposition_service_v1(
    v_dispute_id,'dispute','Synthetic disputed proposition.',jsonb_build_object('authority','validation_fixture'),null
  );

  select count(*) into v_count
  from reality.entity_relationships
  where subject_entity_id='10000000-0000-4000-8000-000000000001'
    and relationship_kind='fixture_relates_to'
    and object_entity_id='20000000-0000-4000-8000-000000000003'
    and relationship_state='disputed';
  if v_count<>1 then
    raise exception 'Validation failed: dispute did not materialize canonical disputed relationship.';
  end if;

  v_eval:=ledger.evaluate_target_predicate_v1(
    '10000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','relationship_exists',
      'relationshipKind','fixture_relates_to',
      'direction','outbound',
      'counterpartyEntityId','20000000-0000-4000-8000-000000000003'
    ),
    '$',0
  );
  if v_eval->>'state'<>'unknown' then
    raise exception 'Validation failed: Target Intelligence did not read disputed relationship as UNKNOWN.';
  end if;
  if jsonb_array_length(coalesce(v_eval->'obligations','[]'::jsonb))<>1 then
    raise exception 'Validation failed: disputed relationship did not produce one Evidence Obligation.';
  end if;

  -- Accepted/disputed propositions require evidence.
  v_accept:=reality.record_relationship_proposition_service_v1(
    '10000000-0000-4000-8000-000000000001',
    'fixture_relates_to',
    '20000000-0000-4000-8000-000000000002',
    'observed',now(),now()+interval '1 day',
    jsonb_build_object('fixtureCase','missing_evidence'),
    jsonb_build_object('fixture',true),
    'rrs-v1-missing-evidence'
  );
  v_failed:=false;
  begin
    perform reality.adjudicate_relationship_proposition_service_v1(
      (v_accept->>'propositionId')::uuid,'accept','Must fail without evidence.',jsonb_build_object('authority','validation_fixture'),null
    );
  exception when others then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Validation failed: accepted proposition without evidence did not fail closed.';
  end if;
end
$fixture$;

select jsonb_build_object(
  'contractVersion','ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1',
  'result','PASS',
  'canonicalRelationshipCount',(
    select count(*) from reality.entity_relationships
    where relationship_kind='fixture_relates_to'
  ),
  'note','Transaction rolls back after this receipt.'
) as validation_receipt;

rollback;
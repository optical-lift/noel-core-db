-- Atlas Ledger Target Intelligence v1
-- Evidence Obligation relevance validation.
-- Run after candidate.sql + candidate_obligation_relevance_fix.sql.
-- Intended for a disposable/rollback validation context.

begin;

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
values
  ('21000000-0000-4000-8000-000000000001','__target_relevance_region_a','place','Target Relevance Region A','canonical','{}'),
  ('21000000-0000-4000-8000-000000000002','__target_relevance_region_b','place','Target Relevance Region B','canonical','{}'),
  ('31000000-0000-4000-8000-000000000001','__target_relevance_business','business','Target Relevance Business','canonical','{}'),
  ('31000000-0000-4000-8000-000000000002','__target_relevance_person','person','Target Relevance Person','canonical','{}');

-- One positive relationship is enough to make the ANY fixture true.
insert into reality.entity_relationships(
  id,subject_entity_id,relationship_kind,object_entity_id,relationship_state,evidence,metadata
) values (
  '61000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001',
  'operates_in',
  '21000000-0000-4000-8000-000000000001',
  'established',
  '{"fixture":true}',
  '{}'
);

-- ALL: a definitive false child makes the root false. Unknown siblings remain in
-- the trace but must not become root Evidence Obligations because they cannot
-- change this evaluation's membership decision.
do $validation$
declare
  v jsonb;
begin
  v:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'op','all',
      'predicates',jsonb_build_array(
        jsonb_build_object('op','entity_kind_is','entityKind','business'),
        jsonb_build_object(
          'op','relationship_exists',
          'relationshipKind','operates_in',
          'direction','outbound',
          'counterpartyEntityId','21000000-0000-4000-8000-000000000001'
        ),
        jsonb_build_object(
          'op','relationship_exists',
          'relationshipKind','operates_in',
          'direction','outbound',
          'counterpartyEntityId','21000000-0000-4000-8000-000000000002'
        )
      )
    )
  );

  if v->>'state'<>'false' then
    raise exception 'Determinate ALL false state failed: %',v;
  end if;
  if jsonb_array_length(v->'obligations')<>0 then
    raise exception 'Determinate ALL false leaked irrelevant root Evidence Obligations: %',v;
  end if;
  if v->'children'->1->>'state'<>'unknown'
     or jsonb_array_length(v->'children'->1->'obligations')<>1 then
    raise exception 'ALL false pruning erased unknown child trace: %',v;
  end if;
end
$validation$;

-- ANY: a definitive true child makes the root true. An unknown sibling remains
-- explainable but does not create active acquisition work.
do $validation$
declare
  v jsonb;
begin
  v:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','any',
      'predicates',jsonb_build_array(
        jsonb_build_object(
          'op','relationship_exists',
          'relationshipKind','operates_in',
          'direction','outbound',
          'counterpartyEntityId','21000000-0000-4000-8000-000000000001'
        ),
        jsonb_build_object(
          'op','relationship_exists',
          'relationshipKind','operates_in',
          'direction','outbound',
          'counterpartyEntityId','21000000-0000-4000-8000-000000000002'
        )
      )
    )
  );

  if v->>'state'<>'true' then
    raise exception 'Determinate ANY true state failed: %',v;
  end if;
  if jsonb_array_length(v->'obligations')<>0 then
    raise exception 'Determinate ANY true leaked irrelevant root Evidence Obligations: %',v;
  end if;
  if v->'children'->1->>'state'<>'unknown'
     or jsonb_array_length(v->'children'->1->'obligations')<>1 then
    raise exception 'ANY true pruning erased unknown child trace: %',v;
  end if;
end
$validation$;

-- NOT propagates acquisition work only while the child remains unknown.
do $validation$
declare
  v_unknown jsonb;
  v_determinate jsonb;
begin
  v_unknown:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','not',
      'predicate',jsonb_build_object(
        'op','relationship_exists',
        'relationshipKind','operates_in',
        'direction','outbound',
        'counterpartyEntityId','21000000-0000-4000-8000-000000000002'
      )
    )
  );
  if v_unknown->>'state'<>'unknown'
     or jsonb_array_length(v_unknown->'obligations')<>1 then
    raise exception 'NOT unknown did not preserve decision-blocking obligation: %',v_unknown;
  end if;

  v_determinate:=ledger.evaluate_target_predicate_v1(
    '31000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'op','not',
      'predicate',jsonb_build_object(
        'op','relationship_exists',
        'relationshipKind','operates_in',
        'direction','outbound',
        'counterpartyEntityId','21000000-0000-4000-8000-000000000001'
      )
    )
  );
  if v_determinate->>'state'<>'false'
     or jsonb_array_length(v_determinate->'obligations')<>0 then
    raise exception 'Determinate NOT retained irrelevant obligations: %',v_determinate;
  end if;
end
$validation$;

rollback;
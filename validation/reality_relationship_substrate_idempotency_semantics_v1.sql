-- Focused rollback proof: one idempotency key cannot name two relationship propositions.
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata) values
  ('30000000-0000-4000-8000-000000000001','rrs-idem-subject','idem_subject','Idempotency Subject','canonical','{}'),
  ('40000000-0000-4000-8000-000000000001','rrs-idem-object-a','idem_object','Idempotency Object A','canonical','{}'),
  ('40000000-0000-4000-8000-000000000002','rrs-idem-object-b','idem_object','Idempotency Object B','canonical','{}');

select reality.register_relationship_kind_service_v1(
  'fixture_idempotent_relation','Fixture idempotent relation','Synthetic validation kind.',null,false,
  array['idem_subject'],array['idem_object'],jsonb_build_object('fixture',true)
);

select reality.record_relationship_proposition_service_v1(
  '30000000-0000-4000-8000-000000000001','fixture_idempotent_relation','40000000-0000-4000-8000-000000000001',
  'observed',null,null,jsonb_build_object('case','same'),jsonb_build_object('fixture',true),'rrs-idem-key'
);

-- Exact replay is stable.
select reality.record_relationship_proposition_service_v1(
  '30000000-0000-4000-8000-000000000001','fixture_idempotent_relation','40000000-0000-4000-8000-000000000001',
  'observed',null,null,jsonb_build_object('case','same'),jsonb_build_object('fixture',true),'rrs-idem-key'
);

do $fixture$
declare v_failed boolean:=false;
begin
  begin
    perform reality.record_relationship_proposition_service_v1(
      '30000000-0000-4000-8000-000000000001','fixture_idempotent_relation','40000000-0000-4000-8000-000000000002',
      'observed',null,null,jsonb_build_object('case','different'),jsonb_build_object('fixture',true),'rrs-idem-key'
    );
  exception when others then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Validation failed: semantic idempotency collision did not fail closed.';
  end if;
end
$fixture$;

select jsonb_build_object('contractVersion','ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1','result','PASS','case','idempotency_semantics') as validation_receipt;
rollback;
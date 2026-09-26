-- Read-only dependency preflight for root Reality promotion v1.

begin;

do $fixture$
begin
  if to_regclass('atlas.implementation_cases') is null
     or to_regclass('atlas.implementation_case_participants') is null
     or to_regclass('atlas.implementation_reality_candidates') is null
     or to_regclass('atlas.ledger_entitlement_bindings') is null
     or to_regclass('reality.entities') is null
     or to_regclass('reality.entity_relationships') is null
     or to_regclass('reality.responsibility_relations') is null
     or to_regclass('reality.auth_person_bindings') is null
     or to_regclass('ledger.ledgers') is null then
    raise exception 'Root Reality promotion dependency table is missing.';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null
     or to_regprocedure('atlas.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)') is null
     or to_regprocedure('atlas.implementation_reality_candidates_self_api_v2(uuid)') is null
     or to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') is null then
    raise exception 'Root Reality promotion dependency function is missing.';
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.implementation_reality_candidates'::regclass
      and conname='implementation_reality_candidates_operation_check'
  ) or not exists(
    select 1 from pg_constraint
    where conrelid='atlas.implementation_reality_candidates'::regclass
      and conname='implementation_reality_candidates_operation_shape'
  ) then
    raise exception 'Implementation Reality Candidate operation constraints are missing.';
  end if;
end
$fixture$;

rollback;

-- Post-migration contract fixture for root Reality promotion v1.
-- No canonical Reality data is created by this fixture.

begin;

do $fixture$
declare
  v_operation_constraint text;
  v_shape_constraint text;
  v_guard_count integer;
begin
  if to_regprocedure('atlas.preview_implementation_reality_entity_promotion_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.promote_implementation_reality_entity_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.promote_implementation_reality_entity_relationship_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.promote_implementation_reality_responsibility_self_api_v1(uuid)') is null
     or to_regprocedure('atlas.implementation_reality_scope_options_self_api_v1(uuid,text,text,integer)') is null then
    raise exception 'Root Reality promotion function is missing after migration.';
  end if;

  select pg_get_constraintdef(oid) into v_operation_constraint
  from pg_constraint
  where conrelid='atlas.implementation_reality_candidates'::regclass
    and conname='implementation_reality_candidates_operation_check';

  select pg_get_constraintdef(oid) into v_shape_constraint
  from pg_constraint
  where conrelid='atlas.implementation_reality_candidates'::regclass
    and conname='implementation_reality_candidates_operation_shape';

  if v_operation_constraint not like '%reality_entity.establish%'
     or v_operation_constraint not like '%reality_entity_relationship.establish%'
     or v_operation_constraint not like '%reality_responsibility.establish%' then
    raise exception 'Root Reality operations are not admitted by the candidate operation constraint.';
  end if;

  if v_shape_constraint not like '%reality_entity%'
     or v_shape_constraint not like '%reality_responsibility.establish%' then
    raise exception 'Root Reality operation shapes are not governed by the candidate shape constraint.';
  end if;

  select count(*)::integer into v_guard_count
  from pg_trigger trigger
  where trigger.tgrelid='reality.responsibility_relations'::regclass
    and trigger.tgname='guard_implementation_setup_sponsor_responsibility_v1'
    and not trigger.tgisinternal;

  if v_guard_count<>1 then
    raise exception 'Setup-sponsor responsibility guard trigger is missing.';
  end if;

  if not ('{financial_source.custody_bind,financial_source.read}'::text[] @> '{financial_source.custody_bind}'::text[]) then
    raise exception 'Responsibility permitted-operation containment semantics changed.';
  end if;

  if ('{financial_source.custody_bind}'::text[] @> '{financial_source.custody_bind,financial_source.read}'::text[]) then
    raise exception 'Responsibility containment must not treat a narrower grant as a broader one.';
  end if;
end
$fixture$;

rollback;

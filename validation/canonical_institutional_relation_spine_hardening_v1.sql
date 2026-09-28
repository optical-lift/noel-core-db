-- Contract validation: Canonical Institutional Relation Spine hardening v1.

do $block$
declare
  v_count integer;
  v_def text;
begin
  select count(*)::integer into v_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='reality'
    and c.relname='entity_relationships'
    and t.tgname='reality_institution_relation_spine_hardening_v1';

  if v_count<>1 then
    raise exception 'Institutional relation hardening trigger is missing.';
  end if;

  select pg_get_functiondef(
    'reality.guard_institution_relation_spine_hardening_v1()'::regprocedure
  ) into v_def;

  if position('assert_canonical_entity_kind_v1(new.subject_entity_id, ''person'')' in v_def)=0
     or position('Position identity cannot change its institution-local positionKey across history.' in v_def)=0
     or position('Responsibility identity cannot change its institution-local responsibilityKey across history.' in v_def)=0
     or position('created_at is immutable' in v_def)=0 then
    raise exception 'Institutional relation hardening is missing canonical Person, durable key, or audit immutability protection.';
  end if;

  select pg_get_functiondef(
    'atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)'::regprocedure
  ) into v_def;

  if position('require_institution_structure_authority_v1' in v_def)=0
     or position('if v_relation.valid_until is not null' in lower(v_def))=0 then
    raise exception 'End operation is missing authority or idempotent replay handling.';
  end if;

  if position('require_institution_structure_authority_v1' in v_def)
     > position('if v_relation.valid_until is not null' in lower(v_def)) then
    raise exception 'Idempotent end replay returns before institution authority is checked.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role can execute human institutional relation ending.';
  end if;
end
$block$;

select
  'canonical_institutional_relation_spine_hardening_v1' as contract,
  'pass' as result,
  true as target_person_must_be_canonical,
  true as position_and_responsibility_keys_are_durable,
  true as idempotent_end_rechecks_authority;

begin;

-- Canonical postconditions for Mark Operational Grammar Kernel v1.

do $$
declare
  role_name text;
  banned_count integer;
begin
  if to_regclass('mark.delta_registry') is null
     or to_regclass('mark.transformation_registry') is null
     or to_regclass('mark.contrast_pairs') is null
     or to_regclass('mark.contrast_deltas') is null
     or to_regclass('mark.contrast_transformations') is null then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: required table missing';
  end if;

  if to_regclass('mark.blind_contrast_pairs_v1') is null
     or to_regclass('mark.blind_contrast_deltas_v1') is null
     or to_regclass('mark.blind_contrast_transformations_v1') is null
     or to_regclass('mark.blind_transformation_recurrence_v1') is null then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: required blind view missing';
  end if;

  if (select count(*) from mark.delta_registry where strict_blind_allowed) <> 18 then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: expected 18 blind delta definitions';
  end if;

  if (select count(*) from mark.transformation_registry where strict_blind_allowed) <> 19 then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: expected 19 blind transformation definitions';
  end if;

  if not exists (
    select 1 from mark.transformation_registry
    where transformation_key='TX_ADD_ATTACHMENT' and operator_key='OP_ATTACH'
  ) or not exists (
    select 1 from mark.transformation_registry
    where transformation_key='TX_ADD_ENCLOSURE' and operator_key='OP_ENCLOSE'
  ) or not exists (
    select 1 from mark.transformation_registry
    where transformation_key='TX_GEOMETRIC_VARIANT' and direction_mode='symmetric'
  ) then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: required transformation mapping missing';
  end if;

  select count(*) into banned_count
  from information_schema.columns
  where table_schema='mark'
    and table_name in (
      'blind_contrast_pairs_v1','blind_contrast_deltas_v1',
      'blind_contrast_transformations_v1','blind_transformation_recurrence_v1'
    )
    and (
      column_name ilike '%system%'
      or column_name ilike '%culture%'
      or column_name ilike '%language%'
      or column_name ilike '%reading%'
      or column_name ilike '%meaning%'
      or column_name ilike '%sign_name%'
    );
  if banned_count <> 0 then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: context-bearing column leaked into blind view';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='mark.contrast_pairs'::regclass
      and tgname='validate_contrast_pair_v1'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid='mark.contrast_deltas'::regclass
      and tgname='validate_contrast_delta_v1'
      and not tgisinternal
  ) then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: validation trigger missing';
  end if;

  if not (select relrowsecurity from pg_class where oid='mark.contrast_pairs'::regclass)
     or not (select relrowsecurity from pg_class where oid='mark.contrast_deltas'::regclass)
     or not (select relrowsecurity from pg_class where oid='mark.contrast_transformations'::regclass) then
    raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: RLS not enabled';
  end if;

  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark_context','USAGE')
       or has_table_privilege(role_name,'mark.contrast_pairs','SELECT')
       or has_table_privilege(role_name,'mark.blind_contrast_pairs_v1','SELECT') then
      raise exception 'MARK_OPERATIONAL_GRAMMAR_POSTCONDITION: runtime role % reaches contrast authority',role_name;
    end if;
  end loop;
end
$$;

rollback;

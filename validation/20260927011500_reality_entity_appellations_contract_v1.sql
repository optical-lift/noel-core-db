-- Reality entity appellations v1 contract validation.
-- Uses synthetic names only. All data writes are rolled back.

begin;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_result jsonb;
  v_literal text;
  v_normalized text;
begin
  if to_regclass('reality.entity_appellations') is null then
    raise exception 'reality.entity_appellations is missing';
  end if;

  if to_regprocedure('reality.normalize_entity_appellation_v1(text)') is null
     or to_regprocedure('reality.record_entity_appellation_v1(uuid,text,text,text,text,jsonb,text,numeric,timestamptz,jsonb,jsonb)') is null
     or to_regprocedure('reality.resolve_entity_appellation_v1(text,text,uuid[])') is null then
    raise exception 'Reality appellation function contract is incomplete';
  end if;

  if not exists(
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='reality'
      and c.relname='entity_appellations'
      and c.relrowsecurity
  ) then
    raise exception 'Reality appellations must have row level security enabled';
  end if;

  insert into reality.entities(stable_key,entity_kind,display_name,metadata)
  values ('validation:entity-appellation:v1:a','Person','Validation Alpha','{}'::jsonb)
  returning id into v_a;

  insert into reality.entities(stable_key,entity_kind,display_name,metadata)
  values ('validation:entity-appellation:v1:b','Person','Validation Beta','{}'::jsonb)
  returning id into v_b;

  perform reality.record_entity_appellation_v1(
    v_a,
    'source_observed_name',
    '  Shared Source Name  ',
    'validation_source',
    'row-a',
    jsonb_build_object('fixture','a'),
    'verified',
    1,
    now(),
    jsonb_build_object('basis','synthetic validation'),
    '{}'::jsonb
  );

  select literal_value, normalized_value
  into v_literal, v_normalized
  from reality.entity_appellations
  where entity_id=v_a and source_key='row-a';

  if v_literal <> '  Shared Source Name  ' then
    raise exception 'Literal source appellation was not preserved exactly';
  end if;

  if v_normalized <> 'shared source name' then
    raise exception 'Appellation normalization contract failed: %',v_normalized;
  end if;

  v_result := reality.resolve_entity_appellation_v1(
    'shared   source name',
    'Person',
    array[v_a]
  );

  if v_result->>'resolutionState' <> 'resolved'
     or (v_result->>'resolvedEntityId')::uuid <> v_a
     or coalesce((v_result->>'automaticMerge')::boolean,true) then
    raise exception 'Scoped appellation resolution failed: %',v_result;
  end if;

  perform reality.record_entity_appellation_v1(
    v_b,
    'source_observed_name',
    'Shared Source Name',
    'validation_source',
    'row-b',
    jsonb_build_object('fixture','b'),
    'observed',
    0.8,
    now(),
    jsonb_build_object('basis','synthetic validation'),
    '{}'::jsonb
  );

  v_result := reality.resolve_entity_appellation_v1('Shared Source Name','Person',null);

  if v_result->>'resolutionState' <> 'ambiguous'
     or (v_result->>'matchCount')::integer <> 2
     or v_result->>'resolvedEntityId' is not null then
    raise exception 'Ambiguous names must fail closed: %',v_result;
  end if;

  v_result := reality.resolve_entity_appellation_v1('Validation Alpha','Person',array[v_a]);
  if v_result->>'resolutionState' <> 'resolved'
     or (v_result->>'resolvedEntityId')::uuid <> v_a then
    raise exception 'Canonical display-name resolution failed: %',v_result;
  end if;

  v_result := reality.resolve_entity_appellation_v1('No Matching Synthetic Name','Person',array[v_a,v_b]);
  if v_result->>'resolutionState' <> 'unresolved'
     or (v_result->>'matchCount')::integer <> 0 then
    raise exception 'Unmatched appellations must stay unresolved: %',v_result;
  end if;
end;
$$;

rollback;

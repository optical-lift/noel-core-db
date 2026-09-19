begin;

create or replace function atlas.ensure_person_life_notebook_spread_v1(
  p_definition_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_definition atlas.person_life_definitions%rowtype;
  v_spread_id uuid;
  v_recipe_key text;
  v_relationship_kind text;
  v_title text;
  v_contract jsonb;
  v_spread_state text;
begin
  if p_definition_id is null then
    raise exception 'person-life definition id is required' using errcode='22023';
  end if;

  select * into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id;

  if v_definition.id is null then
    raise exception 'person-life definition not found' using errcode='P0002';
  end if;

  if not exists (
    select 1
    from atlas.principals p
    where p.id=v_definition.principal_id
      and p.user_id=v_definition.owner_user_id
      and p.status='active'
  ) then
    raise exception 'active Person / Principal custody required' using errcode='42501';
  end if;

  v_recipe_key := case v_definition.signal_kind
    when 'goal' then 'life-progress'
    when 'rhythm' then 'life-occurrence'
    else 'life-log'
  end;

  v_relationship_kind := case v_definition.signal_kind
    when 'goal' then 'progress'
    when 'rhythm' then 'cadence'
    else 'state'
  end;

  v_title := coalesce(
    nullif(v_definition.life_signal->>'title',''),
    nullif(v_definition.life_signal->>'label',''),
    initcap(replace(v_definition.signal_kind,'_',' '))
  );

  v_contract := case v_recipe_key
    when 'life-progress' then jsonb_build_object(
      'contractVersion','notebook_spread_composition_v1',
      'patternKey','dominant-supporting-pair',
      'forms',jsonb_build_array(
        jsonb_build_object(
          'formFamily','free-field','role','anchor','order',1,
          'supportedRelationships',jsonb_build_array('progress'),
          'emptyBehavior','show-quiet-geometry',
          'phoneRule','Keep the explicit Goal orientation, status, and latest evidence together.'
        ),
        jsonb_build_object(
          'formFamily','path','role','supporting','order',2,
          'supportedRelationships',jsonb_build_array('progress'),
          'emptyBehavior','show-established-future-space',
          'phoneRule','Preserve explicit requirements or milestones in source order; never invent a plan.'
        ),
        jsonb_build_object(
          'formFamily','ledger','role','supporting','order',3,
          'supportedRelationships',jsonb_build_array('progress'),
          'emptyBehavior','omit',
          'phoneRule','Show only established open consequences beneath Goal reality.'
        )
      ),
      'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true),
      'phoneLinearization',jsonb_build_array('free-field','path','ledger'),
      'stability',jsonb_build_object('meaningPositionsAreStable',true,'historyPreservedByRevision',true),
      'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true),
      'compilerBasis',jsonb_build_object('migration','person-life-durable-spread-v1','recipe','progress')
    )
    when 'life-occurrence' then jsonb_build_object(
      'contractVersion','notebook_spread_composition_v1',
      'patternKey','dominant-supporting-pair',
      'forms',jsonb_build_array(
        jsonb_build_object(
          'formFamily','free-field','role','anchor','order',1,
          'supportedRelationships',jsonb_build_array('cadence'),
          'emptyBehavior','show-quiet-geometry',
          'phoneRule','Keep the explicit Rhythm orientation and supported cadence visible first.'
        ),
        jsonb_build_object(
          'formFamily','timeline','role','supporting','order',2,
          'supportedRelationships',jsonb_build_array('cadence'),
          'emptyBehavior','show-established-future-space',
          'phoneRule','Keep recorded occurrence/state evidence chronological; do not infer missing occurrences.'
        ),
        jsonb_build_object(
          'formFamily','ledger','role','supporting','order',3,
          'supportedRelationships',jsonb_build_array('cadence'),
          'emptyBehavior','omit',
          'phoneRule','Show only established open consequences beneath Rhythm reality.'
        )
      ),
      'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true),
      'phoneLinearization',jsonb_build_array('free-field','timeline','ledger'),
      'stability',jsonb_build_object('meaningPositionsAreStable',true,'historyPreservedByRevision',true),
      'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true),
      'compilerBasis',jsonb_build_object('migration','person-life-durable-spread-v1','recipe','occurrence')
    )
    else jsonb_build_object(
      'contractVersion','notebook_spread_composition_v1',
      'patternKey','dominant-supporting-pair',
      'forms',jsonb_build_array(
        jsonb_build_object(
          'formFamily','free-field','role','anchor','order',1,
          'supportedRelationships',jsonb_build_array('state'),
          'emptyBehavior','show-quiet-geometry',
          'phoneRule','Keep the explicit Life signal orientation visible first.'
        ),
        jsonb_build_object(
          'formFamily','log','role','supporting','order',2,
          'supportedRelationships',jsonb_build_array('state'),
          'emptyBehavior','show-established-future-space',
          'phoneRule','Preserve recorded state evidence chronologically without inventing interpretation.'
        ),
        jsonb_build_object(
          'formFamily','ledger','role','supporting','order',3,
          'supportedRelationships',jsonb_build_array('state'),
          'emptyBehavior','omit',
          'phoneRule','Show only established consequence instances; carrier and Clock authority stay separate.'
        )
      ),
      'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true),
      'phoneLinearization',jsonb_build_array('free-field','log','ledger'),
      'stability',jsonb_build_object('meaningPositionsAreStable',true,'historyPreservedByRevision',true),
      'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true),
      'compilerBasis',jsonb_build_object('migration','person-life-durable-spread-v1','recipe','life-log')
    )
  end;

  v_spread_state := case when v_definition.status='retired' then 'closed' else 'open' end;

  v_spread_id := atlas.set_notebook_spread_instance_v2(
    v_definition.principal_id,
    'life:'||v_definition.id::text,
    'person',
    v_definition.owner_user_id::text,
    'person',
    'person_life_definition',
    v_definition.id::text,
    'life-orientation',
    'current',
    'thread:life:'||v_definition.id::text,
    v_title,
    'Life',
    v_recipe_key,
    'resolved',
    v_spread_state,
    v_contract,
    jsonb_build_object(
      'kind','governed_projection',
      'definitionId',v_definition.id,
      'signalKind',v_definition.signal_kind
    ),
    jsonb_build_object(
      'source','person_life_definition',
      'definitionStatus',v_definition.status,
      'signalKind',v_definition.signal_kind
    )
  );

  update atlas.notebook_spread_source_bindings
  set binding_state='retired',
      retired_at=coalesce(retired_at,now()),
      updated_at=now()
  where spread_instance_id=v_spread_id
    and source_domain='person'
    and source_kind='life_definition_v1'
    and source_id=v_definition.id::text
    and relationship_kind<>v_relationship_kind
    and binding_state='active';

  perform atlas.bind_notebook_spread_source_v1(
    v_spread_id,
    'person',
    'life_definition_v1',
    v_definition.id::text,
    v_relationship_kind,
    'active',
    jsonb_build_object(
      'kind','governed_projection',
      'readSeam','person_life_state_api_v1',
      'definitionId',v_definition.id,
      'signalKind',v_definition.signal_kind,
      'recipeKey',v_recipe_key
    ),
    '{}'::jsonb
  );

  return jsonb_build_object(
    'ok',true,
    'definitionId',v_definition.id,
    'spreadInstanceId',v_spread_id,
    'spreadKey','life:'||v_definition.id::text,
    'recipeKey',v_recipe_key,
    'spreadState',v_spread_state
  );
end;
$function$;

revoke all on function atlas.ensure_person_life_notebook_spread_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.ensure_person_life_notebook_spread_v1(uuid)
  to service_role;

create or replace function atlas.sync_person_life_notebook_spread_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
begin
  perform atlas.ensure_person_life_notebook_spread_v1(new.id);
  return new;
end;
$function$;

drop trigger if exists trg_sync_person_life_notebook_spread_v1 on atlas.person_life_definitions;
create trigger trg_sync_person_life_notebook_spread_v1
after insert or update of status,signal_kind,life_signal on atlas.person_life_definitions
for each row execute function atlas.sync_person_life_notebook_spread_v1();

do $backfill$
declare
  r record;
begin
  for r in
    select d.id
    from atlas.person_life_definitions d
    join atlas.principals p on p.id=d.principal_id
    where p.status='active'
      and d.status='active'
  loop
    perform atlas.ensure_person_life_notebook_spread_v1(r.id);
  end loop;
end;
$backfill$;

commit;

begin;

create or replace function atlas.ensure_principal_default_home_spreads_v1(
  p_principal_id uuid,
  p_household_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_spread_id uuid;
  v_rhythm_seeded boolean := false;
  v_laundry_seeded boolean := false;
  v_home_care_seeded boolean := false;
  v_rhythm_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('cadence','window','sequence'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Preserve rhythm identity and keep the next established window inline.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object(
      'meaningPositionsAreStable',true,
      'recomposeOnlyForMeaningfulPhaseChange',true,
      'historyPreservedByRevision',true
    ),
    'sourceBindingPolicy',jsonb_build_object(
      'sourceTruthExternal',true,
      'missingSourceDoesNotCreateEmptyIntegrationTile',true,
      'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
    ),
    'compilerBasis',jsonb_build_object(
      'migration','principal-default-home-spread-seed-v1',
      'page','household-rhythm'
    )
  );
  v_laundry_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','path','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('sequence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep the source-defined laundry sequence in order without inventing a household routine.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('path'),
    'stability',jsonb_build_object(
      'meaningPositionsAreStable',true,
      'recomposeOnlyForMeaningfulPhaseChange',true,
      'historyPreservedByRevision',true
    ),
    'sourceBindingPolicy',jsonb_build_object(
      'sourceTruthExternal',true,
      'missingSourceDoesNotCreateEmptyIntegrationTile',true,
      'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
    ),
    'compilerBasis',jsonb_build_object(
      'migration','principal-default-home-spread-seed-v1',
      'page','laundry'
    )
  );
  v_home_care_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('state','evidence'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Preserve row identity; collapse lower-value attributes into secondary inline ink.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object(
      'meaningPositionsAreStable',true,
      'recomposeOnlyForMeaningfulPhaseChange',true,
      'historyPreservedByRevision',true
    ),
    'sourceBindingPolicy',jsonb_build_object(
      'sourceTruthExternal',true,
      'missingSourceDoesNotCreateEmptyIntegrationTile',true,
      'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
    ),
    'compilerBasis',jsonb_build_object(
      'migration','principal-default-home-spread-seed-v1',
      'page','home-care'
    )
  );
begin
  if p_principal_id is null or p_household_id is null then
    raise exception 'principal and household are required' using errcode='22023';
  end if;

  if not exists (
    select 1
    from atlas.principals p
    where p.id=p_principal_id
      and p.status='active'
      and p.active_household_id=p_household_id
  ) then
    raise exception 'active Principal / household binding not found' using errcode='42501';
  end if;

  -- Household rhythm.
  if not exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id and s.spread_key='household-rhythm'
     )
     or exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id
         and s.spread_key='household-rhythm'
         and s.scope_kind='household'
         and s.scope_id=p_household_id::text
         and s.subject_domain='household'
         and s.subject_kind='household_rhythm'
         and s.subject_id=p_household_id::text
     ) then
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      p_principal_id,
      'household-rhythm',
      'household',
      p_household_id::text,
      'household',
      'household_rhythm',
      p_household_id::text,
      'cadence-orientation',
      'current',
      'thread:household-rhythm:'||p_household_id::text,
      'Household rhythm',
      'Home',
      null,
      'resolved',
      'open',
      v_rhythm_contract,
      jsonb_build_object('kind','principal_bootstrap_default','seed','default-home-spreads-v1'),
      jsonb_build_object('seed','default-home-spreads-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,
      'household',
      'rhythm_snapshot_v1',
      p_household_id::text,
      'cadence',
      'active',
      jsonb_build_object('kind','governed_projection','readSeam','personal_setup_self_api_v1'),
      '{}'::jsonb
    );
    v_rhythm_seeded := true;
  end if;

  -- Laundry.
  if not exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id and s.spread_key='laundry'
     )
     or exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id
         and s.spread_key='laundry'
         and s.scope_kind='household'
         and s.scope_id=p_household_id::text
         and s.subject_domain='household'
         and s.subject_kind='world_kernel'
         and s.subject_id='household.laundry'
     ) then
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      p_principal_id,
      'laundry',
      'household',
      p_household_id::text,
      'household',
      'world_kernel',
      'household.laundry',
      'laundry-orientation',
      'current',
      'thread:laundry:'||p_household_id::text,
      'Laundry',
      'Home',
      null,
      'resolved',
      'open',
      v_laundry_contract,
      jsonb_build_object('kind','principal_bootstrap_default','seed','default-home-spreads-v1'),
      jsonb_build_object('seed','default-home-spreads-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,
      'household',
      'laundry_kernel_v1',
      p_household_id::text,
      'sequence',
      'active',
      jsonb_build_object('kind','governed_projection','readSeam','personal_laundry_kernel_self_api_v1'),
      '{}'::jsonb
    );
    v_laundry_seeded := true;
  end if;

  -- Home care.
  if not exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id and s.spread_key='home-care'
     )
     or exists (
       select 1 from atlas.notebook_spread_instances s
       where s.principal_id=p_principal_id
         and s.spread_key='home-care'
         and s.scope_kind='household'
         and s.scope_id=p_household_id::text
         and s.subject_domain='household'
         and s.subject_kind='household_care'
         and s.subject_id=p_household_id::text
     ) then
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      p_principal_id,
      'home-care',
      'household',
      p_household_id::text,
      'household',
      'household_care',
      p_household_id::text,
      'current-care-orientation',
      'current',
      'thread:home-care:'||p_household_id::text,
      'Home care',
      'Home',
      null,
      'resolved',
      'open',
      v_home_care_contract,
      jsonb_build_object('kind','principal_bootstrap_default','seed','default-home-spreads-v1'),
      jsonb_build_object('seed','default-home-spreads-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,
      'household',
      'care_snapshot_v1',
      p_household_id::text,
      'state',
      'active',
      jsonb_build_object('kind','governed_projection','readSeam','principal_household_care_snapshot_v1'),
      '{}'::jsonb
    );
    v_home_care_seeded := true;
  end if;

  return jsonb_build_object(
    'ok',true,
    'principalId',p_principal_id,
    'householdId',p_household_id,
    'householdRhythmSeeded',v_rhythm_seeded,
    'laundrySeeded',v_laundry_seeded,
    'homeCareSeeded',v_home_care_seeded
  );
end;
$function$;

revoke all on function atlas.ensure_principal_default_home_spreads_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.ensure_principal_default_home_spreads_v1(uuid,uuid)
  to service_role;

create or replace function atlas.seed_default_home_spreads_for_principal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
begin
  if new.status='active'
     and new.active_household_id is not null
     and (
       tg_op='INSERT'
       or old.status is distinct from new.status
       or old.active_household_id is distinct from new.active_household_id
     ) then
    perform atlas.ensure_principal_default_home_spreads_v1(
      new.id,
      new.active_household_id
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_seed_default_home_spreads_for_principal_v1 on atlas.principals;
create trigger trg_seed_default_home_spreads_for_principal_v1
after insert or update of status,active_household_id on atlas.principals
for each row execute function atlas.seed_default_home_spreads_for_principal_v1();

-- Backfill/refresh only matching current-household identities. The helper
-- deliberately skips any historical default key that already belongs to a
-- different household rather than silently moving durable identity.
do $backfill$
declare
  r record;
begin
  for r in
    select p.id as principal_id,p.active_household_id
    from atlas.principals p
    where p.status='active'
      and p.active_household_id is not null
  loop
    perform atlas.ensure_principal_default_home_spreads_v1(
      r.principal_id,
      r.active_household_id
    );
  end loop;
end;
$backfill$;

commit;

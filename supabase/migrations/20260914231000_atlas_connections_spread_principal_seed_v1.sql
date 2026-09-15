begin;

-- Package 1: Connections is a permanent Principal-scoped notebook orientation.
-- The spread projects governed connected-source state; it does not own provider,
-- credential, authorization, or downstream life truth.

create or replace function atlas.establish_connections_spread_v1(p_principal_id uuid)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_spread_id uuid;
  v_contract jsonb;
begin
  if p_principal_id is null then raise exception 'Principal required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.principals p where p.id=p_principal_id and p.status='active') then
    raise exception 'Active Principal required.' using errcode='P0002';
  end if;

  v_contract:=jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('evidence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep outlet identity and source authorization state visible; collapse provider detail before hiding state.'
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
      'missingSourceDoesNotCreateSourceTruth',true,
      'connectionStateDoesNotGrantAuthority',true,
      'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
    ),
    'compilerBasis',jsonb_build_object('screenId','CFG-07','systemSpread','connections')
  );

  v_spread_id:=atlas.set_notebook_spread_instance_v2(
    p_principal_id,'connections','person',p_principal_id::text,
    'principal','connections',p_principal_id::text,
    'source-coverage-orientation','current','connections',
    'Connections','Connections',null,'resolved','open',
    v_contract,
    jsonb_build_object('screenId','CFG-07','establishedBy','establish_connections_spread_v1'),
    jsonb_build_object('permanent',true,'truthOwner',false)
  );

  perform atlas.bind_notebook_spread_source_v1(
    v_spread_id,'principal','connected_sources_v1',p_principal_id::text,'evidence','active',
    jsonb_build_object('screenId','CFG-07','authority','connected_sources_self_api_v1'),
    jsonb_build_object('projection','connections-ledger-v1')
  );

  return v_spread_id;
end;
$function$;

revoke all on function atlas.establish_connections_spread_v1(uuid) from public,anon,authenticated;

create or replace function atlas.ensure_connections_spread_self_api_v1()
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  perform atlas.establish_connections_spread_v1(v_principal_id);
  return atlas.notebook_spread_instance_self_api_v1('connections');
end;
$function$;

revoke all on function atlas.ensure_connections_spread_self_api_v1() from public,anon;
grant execute on function atlas.ensure_connections_spread_self_api_v1() to authenticated,service_role;

create or replace function atlas.seed_connections_spread_for_principal_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.status='active'
     and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform atlas.establish_connections_spread_v1(new.id);
  end if;
  return new;
end;
$function$;

revoke all on function atlas.seed_connections_spread_for_principal_v1() from public,anon,authenticated;

drop trigger if exists trg_seed_connections_spread_for_principal_v1 on atlas.principals;
create trigger trg_seed_connections_spread_for_principal_v1
after insert or update of status on atlas.principals
for each row
execute function atlas.seed_connections_spread_for_principal_v1();

-- Backfill the permanent page for every currently active Principal. This creates
-- notebook identity/binding only; it does not create a Connected Source or claim
-- that any provider is authorized, synced, or truthful.
do $do$
declare
  r record;
begin
  for r in select p.id from atlas.principals p where p.status='active' loop
    perform atlas.establish_connections_spread_v1(r.id);
  end loop;
end;
$do$;

commit;
-- Disposable schema-clone postconditions.
do $post$
declare
  v_public text;
  v_safe text;
  v_old text;
  v_entity_safe text;
  v_temporal_safe text;
  v_temporal_old text;
begin
  if to_regprocedure('atlas.ledger_workspace_self_api_v1(uuid)') is null
    or to_regprocedure('atlas.ledger_workspace_unfiltered_internal_v1(uuid)') is null
    or to_regprocedure('public.ledger_workspace_self_api_v1(uuid)') is null then
    raise exception 'Safe Ledger workspace chain incomplete';
  end if;
  if to_regprocedure('atlas.ledger_entity_contexts_self_api_v1(uuid,text)') is null
    or to_regprocedure('atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)') is null then
    raise exception 'Safe Ledger entity-context chain incomplete';
  end if;
  if to_regprocedure('atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)') is null
    or to_regprocedure('atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)') is null then
    raise exception 'Safe Ledger temporal-composer chain incomplete';
  end if;
  if has_function_privilege('anon',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('service_role',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('anon',
      'public.ledger_workspace_self_api_v1(uuid)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)','EXECUTE')
    or has_function_privilege('anon',
      'atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or has_function_privilege('anon',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or has_function_privilege('service_role',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
      'atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.ledger_workspace_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Internal full Ledger reader exposes unsafe EXECUTE grants';
  end if;
  select pg_get_functiondef('public.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    into v_public;
  select pg_get_functiondef('atlas.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    into v_safe;
  select pg_get_functiondef('atlas.ledger_workspace_unfiltered_internal_v1(uuid)'::regprocedure)
    into v_old;
  select pg_get_functiondef('atlas.ledger_entity_contexts_self_api_v1(uuid,text)'::regprocedure)
    into v_entity_safe;
  select pg_get_functiondef('atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)'::regprocedure)
    into v_temporal_safe;
  select pg_get_functiondef('atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)'::regprocedure)
    into v_temporal_old;
  if (select p.prosecdef from pg_proc p
      where p.oid='public.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    or position('capability_root_authority_context_self_v1' in v_safe)=0
    or position('ledger_workspace_unfiltered_internal_v1' in v_safe)=0
    or position('No current authorized Ledger seat' in v_safe)=0
    or position('seat_only' in v_safe)=0
    or position('nativeFullHistoryRequiresExactRootAuthority' in v_safe)=0
    or position('ledger.actions' in v_old)=0 then
    raise exception 'Safe native Ledger reader contract not preserved';
  end if;
  if position('ledger_workspace_unfiltered_internal_v1' in v_public)>0 then
    raise exception 'Public wrapper directly invokes unsafe private reader';
  end if;
  if position('capability_root_authority_context_self_v1' in v_entity_safe)=0
    or position('ledger_entity_contexts_unfiltered_internal_v1' in v_entity_safe)=0 then
    raise exception 'Entity-context API still trusts seat without root authority';
  end if;
  if position('capability_root_authority_context_self_v1' in v_temporal_safe)=0
    or position('ledger_temporal_composer_unfiltered_internal_v1' in v_temporal_safe)=0
    or position('current_active_ledger_seat_v1' in v_temporal_old)=0 then
    raise exception 'Temporal composer still trusts seat without root authority';
  end if;
end
$post$;

-- Authenticated clone matrix: fixture identities are never production users.
-- The authenticated database role plus session claims models the direct RPC
-- boundary; production JWT signature verification remains an API-layer proof.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000011"}',true);
do $owner$
declare v jsonb;
begin
  v:=public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
  if v->>'operationalScope' is distinct from 'native'
    or jsonb_array_length(v->'actions')<>1
    or v->'actions'->0->>'title' is distinct from 'Owner-only validation movement'
    or v->'truthBoundary'->>'nativeFullHistoryRequiresExactRootAuthority' is distinct from 'true' then
    raise exception 'Current root lost legitimate native action history';
  end if;
  perform atlas.ledger_entity_contexts_self_api_v1('e5100000-0000-4000-8000-000000000401',null);
  perform atlas.ledger_temporal_composer_self_api_v1(
    'e5100000-0000-4000-8000-000000000401',current_date,current_date,'UTC',50);
end
$owner$;

select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000012","user_metadata":{"is_owner":true,"role":"root_governing"}}',true);
do $seat$
declare v jsonb;
begin
  v:=public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
  if v->>'operationalScope' is distinct from 'seat_only'
    or v->'ledger'->>'id' is distinct from 'e5100000-0000-4000-8000-000000000401'
    or v->'farm' is distinct from 'null'::jsonb
    or jsonb_array_length(v->'actions')<>0
    or jsonb_array_length(v->'tasks')<>0
    or jsonb_array_length(v->'sales')<>0
    or jsonb_array_length(v->'demand')<>0
    or jsonb_array_length(v->'events')<>0
    or jsonb_array_length(v->'registrations')<>0
    or position('Owner-only validation movement' in v::text)>0 then
    raise exception 'Seat-only actor received owner native details';
  end if;
  begin
    perform atlas.ledger_entity_contexts_self_api_v1(
      'e5100000-0000-4000-8000-000000000401',null);
    raise exception 'Nonroot entity-context read was accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform atlas.ledger_temporal_composer_self_api_v1(
      'e5100000-0000-4000-8000-000000000401',current_date,current_date,'UTC',50);
    raise exception 'Nonroot temporal read was accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform atlas.ledger_workspace_unfiltered_internal_v1(
      'e5100000-0000-4000-8000-000000000401');
    raise exception 'Authenticated actor invoked private workspace';
  exception when insufficient_privilege then null;
  end;
end
$seat$;

select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000003","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000013"}',true);
do $cross$
declare v jsonb;
begin
  begin
    perform public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
    raise exception 'Other-Ledger seat opened protected Ledger';
  exception when insufficient_privilege then null;
  end;
  v:=public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000402');
  if v->>'operationalScope' is distinct from 'seat_only'
    or v->'ledger'->>'id' is distinct from 'e5100000-0000-4000-8000-000000000402' then
    raise exception 'Other-Ledger identity was not narrowly admitted';
  end if;
end
$cross$;

-- A real signed-in Person with no native Ledger seat is denied outright.
select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000004","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000014"}',true);
do $no_seat$
begin
  begin
    perform public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
    raise exception 'Valid signed-in Person without a seat opened Ledger';
  exception when insufficient_privilege then null;
  end;
end
$no_seat$;

-- An invalid session cannot be promoted by an otherwise real Person/seat.
select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000099"}',true);
do $session$
begin
  begin
    perform public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
    raise exception 'Invalid auth session opened Ledger';
  exception when insufficient_privilege then null;
  end;
end
$session$;
rollback;

-- Revocation is tested in a rolled-back clone transaction, never against live
-- seats or authorities.
begin;
update atlas.principal_ledger_authorities
set status='ended',ended_at=now()
where id='e5100000-0000-4000-8000-000000000601';
set local role authenticated;
select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000011"}',true);
do $revoked_root$
declare v jsonb;
begin
  v:=public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
  if v->>'operationalScope' is distinct from 'seat_only'
    or jsonb_array_length(v->'actions')<>0 then
    raise exception 'Ended root authority still released history';
  end if;
end
$revoked_root$;
rollback;

begin;
update ledger.seats
set seat_state='ended',ended_at=now()
where id='e5100000-0000-4000-8000-000000000502';
set local role authenticated;
select set_config('request.jwt.claim.sub','e5100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',
 '{"sub":"e5100000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5100000-0000-4000-8000-000000000012"}',true);
do $revoked_seat$
begin
  begin
    perform public.ledger_workspace_self_api_v1('e5100000-0000-4000-8000-000000000401');
    raise exception 'Ended seat still opened Ledger';
  exception when insufficient_privilege then null;
  end;
end
$revoked_seat$;
rollback;

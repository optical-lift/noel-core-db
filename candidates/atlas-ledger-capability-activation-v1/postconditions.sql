-- Behavioral postconditions for Atlas Ledger Capability Activation v1 candidate.
-- Runs only in a disposable production-schema clone after fixture + candidate SQL.

do $proof$
declare
  root_uid constant uuid := 'a1000000-0000-4000-8000-000000000001'::uuid;
  owner_uid constant uuid := 'b1000000-0000-4000-8000-000000000001'::uuid;
  root_person constant uuid := 'a1000000-0000-4000-8000-000000000011'::uuid;
  root_principal constant uuid := 'a1000000-0000-4000-8000-000000000031'::uuid;
  root_ledger constant uuid := 'a2000000-0000-4000-8000-000000000001'::uuid;
  other_ledger constant uuid := 'b2000000-0000-4000-8000-000000000001'::uuid;
  root_authority constant uuid := 'a3000000-0000-4000-8000-000000000001'::uuid;
  entitlement_binding constant uuid := 'c1000000-0000-4000-8000-000000000041'::uuid;
  v_result jsonb;
  v_retry jsonb;
  v_transition jsonb;
  v_activation uuid;
  v_activation2 uuid;
  v_grant uuid;
  v_event uuid;
  v_before bigint;
  v_after bigint;
  v_failed boolean;
begin
  -- 1. Teaching v1 is seeded, active, and Ledger-only.
  if not exists (
    select 1 from atlas.capability_definitions d
    where d.capability_key='teaching' and d.capability_version=1 and d.status='active'
      and d.eligible_subject_kinds=array['ledger']::text[]
  ) then raise exception 'Teaching v1 capability definition missing or malformed.'; end if;
  if has_table_privilege('authenticated','atlas.capability_definitions','INSERT')
     or has_table_privilege('authenticated','atlas.capability_definitions','UPDATE')
     or has_table_privilege('authenticated','atlas.capability_definitions','DELETE') then
    raise exception 'Authenticated browser can mutate capability definition registry.';
  end if;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);

  -- 2. Unknown capability keys/versions fail closed.
  v_failed:=false;
  begin
    perform atlas.create_capability_activation_self_api_v1(root_ledger,'unknown_capability',1,root_ledger,'ledger',root_ledger,null,null);
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Unknown capability key was accepted.'; end if;

  -- 3. Teaching v1 accepts the exact Ledger subject and rejects unsupported shapes.
  if not atlas.capability_subject_valid_v1('teaching',1,root_ledger,'ledger',root_ledger,null,null) then
    raise exception 'Exact Teaching v1 Ledger subject was rejected.';
  end if;
  if atlas.capability_subject_valid_v1('teaching',1,root_ledger,'project',root_ledger,null,null)
     or atlas.capability_subject_valid_v1('teaching',1,root_ledger,'ledger',root_ledger,'shadow-key',null)
     or atlas.capability_subject_valid_v1('teaching',1,root_ledger,'ledger',other_ledger,null,null) then
    raise exception 'Unsupported Teaching v1 subject shape was accepted.';
  end if;

  -- 4. Root Principal creates exactly one draft activation and exact authority evidence.
  v_result:=atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  v_activation:=(v_result->>'activationId')::uuid;
  if v_activation is null or v_result->>'activationState'<>'draft' then
    raise exception 'Authorized root Principal could not create draft capability activation: %',v_result;
  end if;
  if not exists (
    select 1 from atlas.capability_activations a
    where a.id=v_activation and a.ledger_id=root_ledger and a.capability_key='teaching' and a.capability_version=1
      and a.subject_ledger_id=root_ledger and a.subject_kind='ledger' and a.subject_id=root_ledger and a.state='draft'
      and a.created_by_person_id=root_person and a.created_by_principal_id=root_principal
  ) then raise exception 'Draft activation durable identity/evidence is malformed.'; end if;
  if not exists (
    select 1 from atlas.capability_activation_events e
    where e.capability_activation_id=v_activation and e.event_kind='created' and e.from_state is null and e.to_state='draft'
      and e.actor_person_id=root_person and e.actor_principal_id=root_principal and e.principal_ledger_authority_id=root_authority
  ) then raise exception 'Creation event did not record exact root authority evidence.'; end if;

  -- 5. Exact creation retry is idempotent: same activation, no duplicate event.
  select count(*) into v_before from atlas.capability_activation_events where capability_activation_id=v_activation;
  v_retry:=atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  select count(*) into v_after from atlas.capability_activation_events where capability_activation_id=v_activation;
  if (v_retry->>'activationId')::uuid<>v_activation
     or coalesce((v_retry->>'alreadyExists')::boolean,false) is not true or v_after<>v_before then
    raise exception 'Capability creation retry was not idempotent: first %, retry %.',v_result,v_retry;
  end if;

  -- 6/7/8. Organization owner, known Ledger UUID, and live commercial binding do not substitute for root authority.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_failed:=false;
  begin
    perform atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  exception when sqlstate '42501' then v_failed:=true; end;
  if not v_failed then raise exception 'Organization owner without root Ledger authority created capability activation.'; end if;
  if not exists (
    select 1 from atlas.organization_memberships m
    join atlas.ledger_organization_participations p on p.organization_id=m.organization_id
    where m.user_id=owner_uid and m.role='owner' and m.active and p.ledger_id=root_ledger and p.status='active'
  ) then raise exception 'Negative owner-authority fixture is malformed.'; end if;
  if not exists (
    select 1 from atlas.ledger_entitlement_bindings b where b.id=entitlement_binding and b.ledger_id=root_ledger and b.state='activated'
  ) then raise exception 'Negative commercial-entitlement fixture is malformed.'; end if;

  select count(*) into v_before from atlas.capability_activations where ledger_id=root_ledger;
  v_result:=atlas.establish_capability_entitlement_grant_serv_v1(
    root_ledger,entitlement_binding,'teaching',1,'{"source":"capability_activation_postcondition"}'::jsonb
  );
  v_grant:=(v_result->>'grantId')::uuid;
  select count(*) into v_after from atlas.capability_activations where ledger_id=root_ledger;
  if v_grant is null or v_after<>v_before or not atlas.capability_entitlement_grant_live_v1(root_ledger,'teaching',1) then
    raise exception 'Commercial grant did not remain separate from activation truth: %',v_result;
  end if;
  v_failed:=false;
  begin
    perform atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  exception when sqlstate '42501' then v_failed:=true; end;
  if not v_failed then raise exception 'Commercial capability grant substituted for root Ledger authority.'; end if;

  perform set_config('request.jwt.claim.sub',root_uid::text,true);

  -- 9. draft -> active records exact root authority and exposes active helper truth.
  v_transition:=atlas.transition_capability_activation_self_api_v1(v_activation,'active','proof activation');
  if v_transition->>'activationState'<>'active'
     or not atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null) then
    raise exception 'Authorized draft -> active transition failed: %',v_transition;
  end if;
  if not exists (
    select 1 from atlas.capability_activation_events e
    where e.capability_activation_id=v_activation and e.event_kind='activated' and e.from_state='draft' and e.to_state='active'
      and e.principal_ledger_authority_id=root_authority
  ) then raise exception 'Activation transition lacks exact authority evidence.'; end if;

  -- 10. active -> paused suppresses runtime active truth.
  perform atlas.transition_capability_activation_self_api_v1(v_activation,'paused','proof pause');
  if atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null)
     or not exists (
       select 1 from atlas.capability_activation_events e
       where e.capability_activation_id=v_activation and e.event_kind='paused' and e.from_state='active' and e.to_state='paused'
     ) then raise exception 'Pause transition did not suppress active capability truth.'; end if;

  -- 11. paused -> active resumes the same activation; exact retry is a no-op.
  perform atlas.transition_capability_activation_self_api_v1(v_activation,'active','proof resume');
  if not atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null)
     or not exists (
       select 1 from atlas.capability_activation_events e
       where e.capability_activation_id=v_activation and e.event_kind='resumed' and e.from_state='paused' and e.to_state='active'
     ) then raise exception 'Resume transition did not restore same active capability.'; end if;
  select count(*) into v_before from atlas.capability_activation_events where capability_activation_id=v_activation;
  v_retry:=atlas.transition_capability_activation_self_api_v1(v_activation,'active','retry should be no-op');
  select count(*) into v_after from atlas.capability_activation_events where capability_activation_id=v_activation;
  if coalesce((v_retry->>'alreadyInState')::boolean,false) is not true or v_after<>v_before then
    raise exception 'Exact transition retry manufactured duplicate evidence.';
  end if;

  -- 12/13. Retirement is durable and terminal.
  perform atlas.transition_capability_activation_self_api_v1(v_activation,'retired','proof retirement');
  if exists(select 1 from atlas.capability_activations where id=v_activation and (state<>'retired' or retired_at is null))
     or atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null) then
    raise exception 'Retirement did not preserve correct terminal state.';
  end if;
  v_failed:=false;
  begin perform atlas.transition_capability_activation_self_api_v1(v_activation,'active','illegal resurrection');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'Retired activation was resurrected.'; end if;

  -- 14. New activation after retirement gets new identity while old history remains.
  v_result:=atlas.create_capability_activation_self_api_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null);
  v_activation2:=(v_result->>'activationId')::uuid;
  if v_activation2 is null or v_activation2=v_activation
     or not exists(select 1 from atlas.capability_activations where id=v_activation and state='retired') then
    raise exception 'Post-retirement activation did not create new durable history.';
  end if;

  -- 15. Lifecycle evidence is append-only.
  select id into v_event from atlas.capability_activation_events
  where capability_activation_id=v_activation and event_kind='created' limit 1;
  v_failed:=false;
  begin update atlas.capability_activation_events set reason='illegal rewrite' where id=v_event;
  exception when sqlstate '55000' then v_failed:=true; end;
  if not v_failed then raise exception 'Capability lifecycle evidence was mutable.'; end if;

  -- 16. Read API is Ledger-root scoped and returns durable history.
  v_result:=atlas.capability_activations_self_api_v1(root_ledger);
  if v_result->>'state'<>'ready' or jsonb_array_length(v_result->'items')<>2 then
    raise exception 'Root-scoped capability read did not return both durable activations: %',v_result;
  end if;
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_failed:=false;
  begin perform atlas.capability_activations_self_api_v1(root_ledger);
  exception when sqlstate '42501' then v_failed:=true; end;
  if not v_failed then raise exception 'Non-root Organization owner could read root-scoped capability administration.'; end if;

  -- 17/18. Commercial grant lifecycle is independent of governed activation lifecycle.
  perform set_config('request.jwt.claim.sub',root_uid::text,true);
  perform atlas.transition_capability_activation_self_api_v1(v_activation2,'active','second activation proof');
  if not atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null) then
    raise exception 'Second activation did not become active.';
  end if;
  perform atlas.end_capability_entitlement_grant_serv_v1(v_grant,'{"source":"capability_activation_postcondition_end"}'::jsonb);
  if atlas.capability_entitlement_grant_live_v1(root_ledger,'teaching',1) then raise exception 'Ended commercial grant still reports live.'; end if;
  if not atlas.capability_active_for_subject_v1(root_ledger,'teaching',1,root_ledger,'ledger',root_ledger,null,null) then
    raise exception 'Ending commercial grant rewrote governed activation truth.';
  end if;

  -- 19. Browser privilege membrane.
  if has_table_privilege('authenticated','atlas.capability_activations','SELECT')
     or has_table_privilege('authenticated','atlas.capability_activations','INSERT')
     or has_table_privilege('authenticated','atlas.capability_activation_events','SELECT')
     or has_table_privilege('authenticated','atlas.capability_entitlement_grants','SELECT')
     or has_table_privilege('anon','atlas.capability_activations','SELECT') then
    raise exception 'Capability runtime tables are directly exposed to browser roles.';
  end if;
  if not has_function_privilege('authenticated','atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.transition_capability_activation_self_api_v1(uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.capability_activations_self_api_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.establish_capability_entitlement_grant_serv_v1(uuid,uuid,text,integer,jsonb)','EXECUTE') then
    raise exception 'Capability function privilege membrane is incorrect.';
  end if;
end;
$proof$;

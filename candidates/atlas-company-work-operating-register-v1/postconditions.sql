-- Disposable schema-clone postconditions; no production fixture mutation.
do $post$
declare
  v_doc jsonb := jsonb_build_object(
    'requiredOutcome','Animals have water and feed',
    'instructions','Confirm both sources safely',
    'prerequisites','[]'::jsonb,
    'resources','[]'::jsonb,
    'reporting','{}'::jsonb,
    'escalation','{}'::jsonb);
  v_source text;
begin
  if to_regclass('atlas.company_work_operating_register_entries') is null
    or to_regclass('atlas.company_work_operating_register_revisions') is null then
    raise exception 'Operating register source tables missing';
  end if;
  if not atlas.operating_requirement_document_valid_v1(v_doc)
    or atlas.operating_requirement_document_valid_v1(v_doc - 'requiredOutcome')
    or atlas.operating_requirement_document_valid_v1(
      v_doc||'{"extraAuthority":true}'::jsonb) then
    raise exception 'Operating document validator failed open or rejected a valid value';
  end if;
  if has_table_privilege('authenticated',
       'atlas.company_work_operating_register_entries','SELECT')
    or has_table_privilege('authenticated',
       'atlas.company_work_operating_register_revisions','INSERT')
    or has_table_privilege('anon',
       'atlas.company_work_operating_register_entries','SELECT') then
    raise exception 'Unsafe direct register table privileges';
  end if;
  if exists (
    select 1 from pg_class c where c.oid in (
      'atlas.company_work_operating_register_entries'::regclass,
      'atlas.company_work_operating_register_revisions'::regclass)
      and not c.relrowsecurity
  ) then raise exception 'Register RLS disabled'; end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='atlas.company_work_operating_register_revisions'::regclass
      and tgname='operating_register_revision_immutable_v1' and not tgisinternal
  ) then raise exception 'Append-only register revisions not guarded'; end if;
  if has_function_privilege('anon',
       'public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)','EXECUTE')
    or has_function_privilege('anon',
       'public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
       'public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)','EXECUTE') then
    raise exception 'Register RPC role grants incorrect'; end if;
  select pg_get_functiondef(
    'atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure)
    into v_source;
  if position('company_work_native_ledger_owner_self_v1' in v_source)=0
    or position('insert into atlas.work_requirements' in lower(v_source))=0
    or position('insert into atlas.work_items' in lower(v_source))>0
    or position('instancesGenerated' in v_source)=0 then
    raise exception 'Exact owner/canonical requirement/no instance generation contract missing';
  end if;
  if exists (
    select 1 from atlas.company_work_operating_register_entries e
    join atlas.work_requirements w on w.id=e.requirement_id
    join atlas.ledgers l on l.id=e.ledger_id
    where e.organization_id<>w.organization_id
      or e.organization_id is distinct from l.organization_id
  ) then raise exception 'Cross-organization register entry found'; end if;
end
$post$;


-- C1 disposable authentication matrix. The fixture above contains only
-- synthetic clone-local identities and an exact institution/Ledger/unit.
-- Role+session-claim simulation runs through real database RPC guards;
-- JWT signature verification and signed HTTP/API behavior remain distinct.
do $c1_grants$
begin
  if has_table_privilege('authenticated',
      'atlas.company_work_operating_register_entries','INSERT')
    or has_table_privilege('authenticated',
      'atlas.company_work_operating_register_revisions','SELECT')
    or has_function_privilege('anon',
      'public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)','EXECUTE') then
    raise exception 'C1 writer or direct-table privilege contract failed';
  end if;
  if (select p.prosecdef from pg_proc p
      where p.oid='public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure)
    or (select p.prosecdef from pg_proc p
      where p.oid='public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure)
    or (select p.prosecdef from pg_proc p
      where p.oid='public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'::regprocedure) then
    raise exception 'C1 public API must be security invoker';
  end if;
end
$c1_grants$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);

do $c1_owner$
declare
  v_doc jsonb := jsonb_build_object(
    'requiredOutcome','Every animal has the required feed and water',
    'instructions','Observe supply and record exceptions',
    'prerequisites','[]'::jsonb,'resources','[]'::jsonb,
    'reporting','{}'::jsonb,'escalation','{}'::jsonb);
  v_receipt jsonb;
  v_revision jsonb;
  v_view jsonb;
begin
  v_view:=public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
  if v_view->>'contractVersion' is distinct from 'operating_requirements_owner_v1'
    or coalesce(jsonb_array_length(v_view->'registerEntries'),-1)<>0 then
    raise exception 'Owner initial register read invalid';
  end if;
  v_receipt:=public.establish_operating_requirement_owner_self_api_v1(
    'e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000802',
    'daily_animal_care','Synthetic daily animal care',v_doc,
    'Synthetic source-only owner establishment proof');
  perform set_config('atlas.c1_test_entry_id',v_receipt->>'entryId',true);
  if v_receipt->>'contractVersion' is distinct from 'operating_requirement_establishment_v1'
    or v_receipt->>'ok' is distinct from 'true'
    or v_receipt->>'instancesGenerated' is distinct from '0'
    or v_receipt->>'allocationChanged' is distinct from 'false'
    or v_receipt->>'scheduled' is distinct from 'false'
    or coalesce(jsonb_array_length(v_receipt->'workItemIds'),-1)<>0 then
    raise exception 'Owner establishment receipt is not non-materializing';
  end if;
  v_view:=public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
  if coalesce(jsonb_array_length(v_view->'registerEntries'),-1)<>1
    or v_view->'registerEntries'->0->>'requirement_id' is distinct from v_receipt->>'requirementId'
    or v_view->'registerEntries'->0->>'summary' is distinct from 'Synthetic daily animal care'
    or coalesce(jsonb_array_length(v_view->'registerEntries'->0->'canonical_work'),-1)<>0 then
    raise exception 'Canonical requirement not recovered from exact owner register';
  end if;
  v_revision:=public.revise_operating_requirement_owner_self_api_v1(
    (v_receipt->>'entryId')::uuid,'e5200000-0000-4000-8000-000000000401',
    v_doc||'{"instructions":"Record exceptions; verify again"}'::jsonb,
    'paused',null,null,1,'Synthetic operating revision proof');
  if v_revision->>'contractVersion' is distinct from 'operating_requirement_revision_v1'
    or v_revision->>'revision' is distinct from '2'
    or v_revision->>'instancesGenerated' is distinct from '0'
    or v_revision->>'workAllocationChanged' is distinct from 'false'
    or v_revision->>'canonicalRequirementStateChanged' is distinct from 'false' then
    raise exception 'Owner revision changed Work or returned wrong receipt';
  end if;
  v_view:=public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
  if v_view->'registerEntries'->0->>'revision_no' is distinct from '2'
    or v_view->'registerEntries'->0->>'policy_state' is distinct from 'paused'
    or v_view->'registerEntries'->0->>'requirement_state' is distinct from 'active' then
    raise exception 'Paused policy improperly retired or concealed canonical requirement';
  end if;
  begin
    perform public.revise_operating_requirement_owner_self_api_v1(
      (v_receipt->>'entryId')::uuid,'e5200000-0000-4000-8000-000000000401',v_doc,
      'active',null,null,1,'Stale revision must fail');
    raise exception 'Stale C1 revision was accepted';
  exception when serialization_failure then null;
  end;
end
$c1_owner$;

-- The creator was admitted through authenticated RPCs. Privileged readback
-- checks the separate underlying facts, inside the same rolled-back clone.
reset role;
do $c1_invariants$
begin
  if (select count(*) from atlas.work_requirements
      where organization_id='e5200000-0000-4000-8000-000000000801'
        and stable_key='company_work_operating:e5200000-0000-4000-8000-000000000401:daily_animal_care')<>1
    or (select count(*) from atlas.company_work_operating_register_entries
      where organization_id='e5200000-0000-4000-8000-000000000801' and ledger_id='e5200000-0000-4000-8000-000000000401')<>1
    or (select count(*) from atlas.company_work_operating_register_revisions
      where entry_id in (select id from atlas.company_work_operating_register_entries
        where organization_id='e5200000-0000-4000-8000-000000000801'))<>2
    or exists(select 1 from atlas.work_items where organization_id='e5200000-0000-4000-8000-000000000801')
    or exists(select 1 from atlas.work_allocations where organization_id='e5200000-0000-4000-8000-000000000801') then
    raise exception 'C1 generated Work, allocation, or duplicate requirement';
  end if;
end
$c1_invariants$;

set local role authenticated;
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000012","user_metadata":{"is_owner":true,"role":"root_governing"}}',true);
do $c1_nonowner$
declare v_doc jsonb := jsonb_build_object(
    'requiredOutcome','Every animal has the required feed and water',
    'instructions','Observe supply and record exceptions',
    'prerequisites','[]'::jsonb,'resources','[]'::jsonb,
    'reporting','{}'::jsonb,'escalation','{}'::jsonb);
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Seat-only actor read owner operating register';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.establish_operating_requirement_owner_self_api_v1(
      'e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000802',
      'spoof_owner_request','Unpermitted source',v_doc,'Spoofed owner attempt');
    raise exception 'Seat-only actor authored institutional requirement';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.revise_operating_requirement_owner_self_api_v1(
      current_setting('atlas.c1_test_entry_id')::uuid,
      'e5200000-0000-4000-8000-000000000401',v_doc,'active',null,null,2,'Spoofed owner revision');
    raise exception 'Seat-only actor revised institutional requirement';
  exception when insufficient_privilege then null;
  end;
end
$c1_nonowner$;

select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000003","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000013"}',true);
do $c1_outsider$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Other-Ledger seat opened C1 register';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000402',100);
    raise exception 'Unrelated native Ledger opened C1 register';
  exception when insufficient_privilege then null;
  end;
end
$c1_outsider$;

select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000004","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000014"}',true);
do $c1_no_seat$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'No-seat signed-in Person read institutional register';
  exception when insufficient_privilege then null;
  end;
end
$c1_no_seat$;

-- Valid owner identity but invalid auth session must fail.
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000099"}',true);
do $c1_invalid_session$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Expired/nonexistent session retained owner access';
  exception when insufficient_privilege then null;
  end;
end
$c1_invalid_session$;
rollback;

-- Ended root authority and ended native seat must each deny the owner.
-- Both changes are rolled back before the clone is discarded.
begin;
update atlas.principal_ledger_authorities
set status='ended',ended_at=now()
where id='e5200000-0000-4000-8000-000000000601';
set local role authenticated;
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);
do $c1_root_revoked$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Revoked owner authority still read C1 register';
  exception when insufficient_privilege then null;
  end;
end
$c1_root_revoked$;
rollback;

begin;
update ledger.seats set seat_state='ended',ended_at=now()
where id='e5200000-0000-4000-8000-000000000501';
set local role authenticated;
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);
do $c1_seat_revoked$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Revoked native seat still read C1 register';
  exception when insufficient_privilege then null;
  end;
end
$c1_seat_revoked$;
rollback;

begin;
set local role anon;
do $c1_anonymous$
begin
  begin
    perform public.operating_requirements_owner_self_api_v1('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000401',100);
    raise exception 'Anonymous actor invoked protected C1 API';
  exception when insufficient_privilege then null;
  end;
end
$c1_anonymous$;
rollback;

-- Disposable-schema validation for the native Ledger participation guard.
do $post$
declare
  v_source text;
begin
  select pg_get_functiondef('atlas.guard_operating_register_identity_v1()'::regprocedure)
    into v_source;
  if position('ledger_organization_participations' in v_source)=0
    or position('lop.ledger_id=new.ledger_id' in v_source)=0
    or position('lop.organization_id=new.organization_id' in v_source)=0
    or position('lop.participation_kind' in v_source)=0
    or position('w.source_object_id=new.id' in v_source)=0
    or position('al.organization_id' in v_source)>0 then
    raise exception 'Operating register must require exact native participation and preserved requirement source match';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='atlas.company_work_operating_register_entries'::regclass
      and tgname='operating_register_identity_scope_v1'
      and not tgisinternal
      and tgfoid='atlas.guard_operating_register_identity_v1()'::regprocedure
  ) then
    raise exception 'Operating-register immutable identity trigger missing';
  end if;
  if has_function_privilege('anon','atlas.guard_operating_register_identity_v1()','EXECUTE')
    or has_table_privilege('authenticated','atlas.company_work_operating_register_entries','INSERT')
    or has_table_privilege('anon','atlas.company_work_operating_register_entries','SELECT') then
    raise exception 'Register guard or table privilege broadened';
  end if;
  if exists (
    select 1 from pg_class
    where oid='atlas.company_work_operating_register_entries'::regclass
      and not relrowsecurity
  ) then
    raise exception 'Operating-register RLS disabled';
  end if;
end
$post$;


-- Behavioral regression: the real signed-in-equivalent database role must
-- establish one institutional requirement when the exact native Ledger's
-- governing participation is active but its legacy organization_id is NULL.
-- The entire test transaction is rolled back in the disposable clone.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);
do $native_ledger_establishment$
declare
  v_document jsonb := jsonb_build_object(
    'requiredOutcome','Animals have daily water and feed',
    'instructions','Check daily and preserve exceptions',
    'prerequisites','[]'::jsonb,'resources','[]'::jsonb,
    'reporting','{}'::jsonb,'escalation','{}'::jsonb);
  v_receipt jsonb;
  v_readback jsonb;
begin
  if (select organization_id is not null
      from atlas.ledgers
      where id='e5200000-0000-4000-8000-000000000401') then
    raise exception 'Clone fixture did not reproduce NULL legacy organization_id';
  end if;

  v_receipt:=public.establish_operating_requirement_owner_self_api_v1(
    'e5200000-0000-4000-8000-000000000801',
    'e5200000-0000-4000-8000-000000000401',
    'e5200000-0000-4000-8000-000000000802',
    'native_null_org_regression','Synthetic native Ledger operating need',
    v_document,'Confirm exact native Ledger participation permits establishment');

  if v_receipt->>'ok' is distinct from 'true'
    or v_receipt->>'instancesGenerated' is distinct from '0'
    or v_receipt->>'allocationChanged' is distinct from 'false'
    or v_receipt->>'scheduled' is distinct from 'false'
    or coalesce(jsonb_array_length(v_receipt->'workItemIds'),-1)<>0 then
    raise exception 'Native Ledger establishment materialized Work or failed';
  end if;
  v_readback:=public.operating_requirements_owner_self_api_v1(
    'e5200000-0000-4000-8000-000000000801',
    'e5200000-0000-4000-8000-000000000401',100);
  if coalesce(jsonb_array_length(v_readback->'registerEntries'),-1)<>1
    or v_readback->'registerEntries'->0->>'requirement_id'
       is distinct from v_receipt->>'requirementId' then
    raise exception 'Established requirement not visible exactly once to owner';
  end if;

  begin
    perform public.establish_operating_requirement_owner_self_api_v1(
      'e5200000-0000-4000-8000-000000000801',
      'e5200000-0000-4000-8000-000000000402',
      'e5200000-0000-4000-8000-000000000802',
      'forbidden_other_ledger','Must not appear',v_document,
      'Unrelated native Ledger denial proof');
    raise exception 'Unrelated native Ledger established operating requirement';
  exception when insufficient_privilege then null;
  end;
end
$native_ledger_establishment$;
rollback;

-- Read-only schema/privilege preflight (privileged clone test only).
do $pre$
begin
 if not exists(select 1 from pg_proc
      where oid='public.adopt_existing_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,uuid)'::regprocedure
      and not prosecdef) then
   raise exception 'Public adoption transport must remain security invoker';
 end if;
 if not exists(select 1 from pg_proc
      where oid='atlas.adopt_existing_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,uuid)'::regprocedure
      and prosecdef) then
   raise exception 'Owner adoption command must be security definer and owner guarded';
 end if;
 if has_function_privilege('anon',
    'public.adopt_existing_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,uuid)','EXECUTE')
    or has_table_privilege('authenticated','atlas.company_work_operating_register_entries','INSERT')
    or has_table_privilege('anon','atlas.company_work_operating_register_entries','SELECT') then
   raise exception 'Adoption expanded table privileges';
 end if;
 if not exists(select 1 from atlas.work_requirements
      where id='e5300000-0000-4000-8000-000000000002'
        and source_object_type='legacy_task'
        and source_object_id='e5300000-0000-4000-8000-000000000011') then
   raise exception 'Existing source fixture missing';
 end if;
end
$pre$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',
 'e5200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);

do $owner_adopt$
declare
 v_document jsonb := jsonb_build_object(
   'requiredOutcome','Animals have fresh water and sufficient feed',
   'instructions','Check and maintain daily; report exceptions',
   'prerequisites','[]'::jsonb,'resources','[]'::jsonb,
   'reporting','{}'::jsonb,'escalation','{}'::jsonb);
 v_receipt jsonb;
 v_page jsonb;
 v_count_before integer;
 v_blocked boolean;
begin
 v_page := public.operating_requirements_owner_self_api_v1(
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000401',100);
 if coalesce(jsonb_array_length(v_page->'registerEntries'),-1)<>0
    or coalesce(jsonb_array_length(v_page->'legacyLinkedRequirements'),-1)<>1 then
   raise exception 'Existing exact Ledger requirement not seen as unreconciled';
 end if;

 v_receipt := public.adopt_existing_operating_requirement_owner_self_api_v1(
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000401',
   'e5300000-0000-4000-8000-000000000002',
   v_document,'Owner confirms this existing need must continue as farm care');
 if v_receipt->>'ok' is distinct from 'true'
    or v_receipt->>'contractVersion' is distinct from 'existing_operating_requirement_adoption_v1'
    or v_receipt->>'requirementId' is distinct from 'e5300000-0000-4000-8000-000000000002'
    or v_receipt->>'canonicalRequirementReused' is distinct from 'true'
    or v_receipt->>'sourceIdentityChanged' is distinct from 'false'
    or v_receipt->>'instancesGenerated' is distinct from '0'
    or v_receipt->>'allocationChanged' is distinct from 'false'
    or v_receipt->>'scheduled' is distinct from 'false'
    or v_receipt->>'existingWorkEvidenceCount' is distinct from '1'
    or coalesce(jsonb_array_length(v_receipt->'workItemIdsCreated'),-1)<>0 then
   raise exception 'Adoption receipt changed or failed to preserve canonical Work';
 end if;

 v_page := public.operating_requirements_owner_self_api_v1(
   'e5200000-0000-4000-8000-000000000801',
   'e5200000-0000-4000-8000-000000000401',100);
 if coalesce(jsonb_array_length(v_page->'registerEntries'),-1)<>1
    or v_page->'registerEntries'->0->>'requirement_id' is distinct from
       'e5300000-0000-4000-8000-000000000002'
    or coalesce(jsonb_array_length(v_page->'registerEntries'->0->'canonical_work'),-1)<>1
    or coalesce(jsonb_array_length(v_page->'legacyLinkedRequirements'),-1)<>0 then
   raise exception 'Adoption not visible exactly once with pre-existing Work';
 end if;

 v_blocked:=false;
 begin
   perform public.adopt_existing_operating_requirement_owner_self_api_v1(
     'e5200000-0000-4000-8000-000000000801',
     'e5200000-0000-4000-8000-000000000401',
     'e5300000-0000-4000-8000-000000000002',
     v_document,'Duplicate adoption must fail explicitly');
 exception when unique_violation then v_blocked:=true;
 end;
 if not v_blocked then raise exception 'Second adoption not rejected'; end if;

 v_blocked:=false;
 begin
   perform public.adopt_existing_operating_requirement_owner_self_api_v1(
     'e5200000-0000-4000-8000-000000000801',
     'e5200000-0000-4000-8000-000000000402',
     'e5300000-0000-4000-8000-000000000002',
     v_document,'Wrong native Ledger must fail');
 exception when insufficient_privilege then v_blocked:=true;
 end;
 if not v_blocked then raise exception 'Other Ledger obtained an adoption'; end if;
end
$owner_adopt$;

-- Signed-in worker lacks governing authority, even when seat is active.
select set_config('request.jwt.claim.sub',
 'e5200000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',
 '{"sub":"e5200000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000012"}',true);
do $worker_denial$
declare blocked boolean:=false;
begin
 begin
   perform public.adopt_existing_operating_requirement_owner_self_api_v1(
     'e5200000-0000-4000-8000-000000000801',
     'e5200000-0000-4000-8000-000000000401',
     'e5300000-0000-4000-8000-000000000002',
     '{"requiredOutcome":"Some continuing need","instructions":"Review daily","prerequisites":[],"resources":[],"reporting":{},"escalation":{}}'::jsonb,
     'Worker is not allowed to change the institution');
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Worker obtained owner adoption authority'; end if;
end
$worker_denial$;

reset role;
do $source_preservation$
begin
 if not exists(select 1 from atlas.work_requirements
   where id='e5300000-0000-4000-8000-000000000002'
     and source_object_type='legacy_task'
     and source_object_id='e5300000-0000-4000-8000-000000000011')
   or (select count(*) from atlas.work_requirements
       where organization_id='e5200000-0000-4000-8000-000000000801')<>1
   or (select count(*) from atlas.work_items
       where organization_id='e5200000-0000-4000-8000-000000000801')<>1
   or (select count(*) from atlas.work_allocations
       where organization_id='e5200000-0000-4000-8000-000000000801')<>0 then
   raise exception 'Adoption duplicated a requirement or modified Work/source allocation';
 end if;
end
$source_preservation$;
rollback;

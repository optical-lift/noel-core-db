-- Atlas Work Focus: source-owned instruction read and audited owner revision.
-- Source-only migration candidate. Not for direct production SQL execution.
-- The original atlas.work_items row remains the one canonical Work identity.
begin;

create table atlas.work_focus_instruction_revisions_v1 (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 ledger_id uuid not null,
 work_item_id uuid not null references atlas.work_items(id),
 actor_person_id uuid not null,
 source_action_id text not null,
 previous_instructions text,
 revised_instructions text,
 reason text not null,
 prior_work_updated_at timestamptz not null,
 resulting_work_updated_at timestamptz not null,
 changed_at timestamptz not null default now(),
 constraint work_focus_instruction_action_unique_v1 unique(organization_id,work_item_id,source_action_id),
 constraint work_focus_instruction_source_action_v1 check(length(source_action_id) between 1 and 128),
 constraint work_focus_instruction_reason_v1 check(length(btrim(reason)) between 8 and 1200)
);
create index work_focus_instruction_revision_order_v1
 on atlas.work_focus_instruction_revisions_v1(work_item_id,changed_at desc);
alter table atlas.work_focus_instruction_revisions_v1 enable row level security;
revoke all on atlas.work_focus_instruction_revisions_v1 from public,anon,authenticated;

create function atlas.work_focus_owner_detail_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare v_actor uuid;v_work atlas.work_items%rowtype;
begin
 if auth.uid() is null or p_organization_id is null or p_ledger_id is null
   or p_work_item_id is null then
   raise exception 'Signed original Ledger Work identity required' using errcode='42501';
 end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 select * into v_work from atlas.work_items w
 where w.id=p_work_item_id and w.organization_id=p_organization_id;
 if v_work.id is null or not exists (
  select 1 from atlas.company_work_native_ledger_relevance rel
  where rel.organization_id=p_organization_id and rel.work_item_id=p_work_item_id
    and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
    and (rel.evidence_kind in ('owner_attested','participant_attested') or
      (rel.evidence_kind='source_verified' and exists(
       select 1 from atlas.company_work_native_ledger_exact_source_v1(
        p_work_item_id,p_ledger_id) proof
       where proof.source_schema=rel.source_schema
         and proof.source_table=rel.source_table and proof.source_id=rel.source_id
      )))
 ) then
   raise exception 'Original Work not established for selected native Ledger' using errcode='42501';
 end if;
 return jsonb_build_object(
  'ok',true,'contractVersion','canonical_work_owner_details_v1',
  'workItemId',v_work.id,'organizationId',v_work.organization_id,
  'ledgerId',p_ledger_id,'title',v_work.title,
  'instructions',v_work.instructions,'updatedAt',v_work.updated_at,
  'canReviseInstructions',v_work.work_state='open',
  'sourceOwned',true
 );
end
$fn$;
revoke all on function atlas.work_focus_owner_detail_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function atlas.work_focus_owner_detail_self_api_v1(uuid,uuid,uuid) to authenticated;
create function public.work_focus_owner_detail_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) returns jsonb language sql stable set search_path to ''
as $fn$
 select atlas.work_focus_owner_detail_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id)
$fn$;
revoke all on function public.work_focus_owner_detail_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.work_focus_owner_detail_self_api_v1(uuid,uuid,uuid) to authenticated;

create function atlas.work_focus_owner_revise_instructions_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_expected_updated_at timestamptz,p_instructions text,p_reason text,p_source_action_id text
) returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
 v_actor uuid;v_work atlas.work_items%rowtype;v_receipt atlas.work_focus_instruction_revisions_v1%rowtype;
 v_new_updated_at timestamptz;
begin
 if auth.uid() is null or p_organization_id is null or p_ledger_id is null
   or p_work_item_id is null or p_expected_updated_at is null
   or length(btrim(coalesce(p_reason,''))) not between 8 and 1200
   or length(btrim(coalesce(p_source_action_id,''))) not between 1 and 128
   or length(coalesce(p_instructions,''))>12000 then
   raise exception 'Exact Work, expected revision, bounded reason and action ID required' using errcode='22023';
 end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 perform pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('atlas.work-focus.edit:'||p_work_item_id::text,0));
 select * into v_work from atlas.work_items w
 where w.id=p_work_item_id and w.organization_id=p_organization_id for update;
 if v_work.id is null or v_work.work_state<>'open' or not exists (
  select 1 from atlas.company_work_native_ledger_relevance rel
  where rel.organization_id=p_organization_id and rel.work_item_id=p_work_item_id
    and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
    and (rel.evidence_kind in ('owner_attested','participant_attested') or
      (rel.evidence_kind='source_verified' and exists(
       select 1 from atlas.company_work_native_ledger_exact_source_v1(
        p_work_item_id,p_ledger_id) proof
       where proof.source_schema=rel.source_schema
         and proof.source_table=rel.source_table and proof.source_id=rel.source_id
      )))
 ) then
   raise exception 'Open original Work and exact Ledger authority required' using errcode='42501';
 end if;
 select * into v_receipt from atlas.work_focus_instruction_revisions_v1 r
 where r.organization_id=p_organization_id and r.work_item_id=p_work_item_id
   and r.source_action_id=p_source_action_id;
 if v_receipt.id is not null then
   if v_receipt.actor_person_id is distinct from v_actor or
      v_receipt.ledger_id is distinct from p_ledger_id or
      v_receipt.prior_work_updated_at is distinct from p_expected_updated_at or
      v_receipt.revised_instructions is distinct from p_instructions then
      raise exception 'Revision action ID collision' using errcode='23505';
   end if;
   return jsonb_build_object('ok',true,'idempotent',true,
     'contractVersion','canonical_work_owner_instruction_revision_v1',
     'workItemId',v_work.id,'revisionId',v_receipt.id,
     'updatedAt',v_receipt.resulting_work_updated_at,'newWorkCreated',false);
 end if;
 if v_work.updated_at is distinct from p_expected_updated_at then
   raise exception 'Task instructions changed since they were opened; reload first' using errcode='40001';
 end if;
 if v_work.instructions is not distinct from p_instructions then
   return jsonb_build_object('ok',true,'unchanged',true,
    'contractVersion','canonical_work_owner_instruction_revision_v1',
    'workItemId',v_work.id,'updatedAt',v_work.updated_at,'newWorkCreated',false);
 end if;
 update atlas.work_items set instructions=p_instructions,updated_at=pg_catalog.clock_timestamp()
 where id=v_work.id and organization_id=p_organization_id
 returning updated_at into v_new_updated_at;
 insert into atlas.work_focus_instruction_revisions_v1(
  organization_id,ledger_id,work_item_id,actor_person_id,source_action_id,
  previous_instructions,revised_instructions,reason,
  prior_work_updated_at,resulting_work_updated_at
 ) values(
  p_organization_id,p_ledger_id,p_work_item_id,v_actor,p_source_action_id,
  v_work.instructions,p_instructions,btrim(p_reason),
  v_work.updated_at,v_new_updated_at
 ) returning * into v_receipt;
 return jsonb_build_object('ok',true,'idempotent',false,
  'contractVersion','canonical_work_owner_instruction_revision_v1',
  'workItemId',v_work.id,'revisionId',v_receipt.id,
  'updatedAt',v_new_updated_at,'newWorkCreated',false);
end
$fn$;
revoke all on function atlas.work_focus_owner_revise_instructions_self_api_v1(uuid,uuid,uuid,timestamptz,text,text,text)
 from public,anon;
grant execute on function atlas.work_focus_owner_revise_instructions_self_api_v1(uuid,uuid,uuid,timestamptz,text,text,text)
 to authenticated;
create function public.work_focus_owner_revise_instructions_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_expected_updated_at timestamptz,p_instructions text,p_reason text,p_source_action_id text
) returns jsonb language sql volatile set search_path to ''
as $fn$
 select atlas.work_focus_owner_revise_instructions_self_api_v1(
  p_organization_id,p_ledger_id,p_work_item_id,p_expected_updated_at,
  p_instructions,p_reason,p_source_action_id)
$fn$;
revoke all on function public.work_focus_owner_revise_instructions_self_api_v1(uuid,uuid,uuid,timestamptz,text,text,text)
 from public,anon;
grant execute on function public.work_focus_owner_revise_instructions_self_api_v1(uuid,uuid,uuid,timestamptz,text,text,text)
 to authenticated;

commit;

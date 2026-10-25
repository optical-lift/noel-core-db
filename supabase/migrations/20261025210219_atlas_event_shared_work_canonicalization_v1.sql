-- In-place rehabilitation of ordinary Event-born Work.
-- No row is cloned, title rewritten, assignment invented or historical completion changed.
begin;

create table atlas.event_shared_work_canonicalization_receipts_v1 (
 work_item_id uuid primary key references atlas.work_items(id),
 organization_id uuid not null,
 ledger_id uuid not null,
 occurrence_id uuid not null,
 original_source_object_type text not null,
 original_result_contract_key text not null,
 original_metadata jsonb not null,
 corrected_result_contract_key text not null,
 corrected_at timestamptz not null default now(),
 conversion_contract text not null default 'event_shared_to_canonical_company_work_v1'
);
alter table atlas.event_shared_work_canonicalization_receipts_v1 enable row level security;
revoke all on atlas.event_shared_work_canonicalization_receipts_v1 from public,anon,authenticated;

-- This is a scoped, verifiable legacy repair, NOT a universal rule for changing
-- result contracts with existing reports. Only outstanding records with no
-- execution results can be re-contracted; completed historical records remain.
insert into atlas.event_shared_work_canonicalization_receipts_v1(
 work_item_id,organization_id,ledger_id,occurrence_id,
 original_source_object_type,original_result_contract_key,original_metadata,
 corrected_result_contract_key
)
select w.id,w.organization_id,(w.metadata->>'ledgerId')::uuid,w.source_object_id,
 w.source_object_type,w.result_contract_key,w.metadata,
 'ordinary_company_work_worker_attestation_v1'
from atlas.work_items w
where w.source_object_type='ledger_occurrence_shared_work'
 and w.work_state='open'
 and w.result_contract_key='ledger_occurrence_shared_confirmation_v1'
 and w.metadata->>'sourceContract'='ledger_occurrence_shared_work_v1'
 and w.metadata->>'ledgerId' is not null
 and w.source_object_id is not null
 and exists (select 1 from atlas.company_work_native_ledger_relevance rel
  where rel.work_item_id=w.id and rel.organization_id=w.organization_id
    and rel.ledger_id=(w.metadata->>'ledgerId')::uuid
    and rel.attribution_state='active' and rel.evidence_kind='participant_attested')
 and exists (select 1 from atlas.work_item_context_links ctx
  where ctx.work_item_id=w.id and ctx.organization_id=w.organization_id
    and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
    and ctx.subject_id=w.source_object_id)
 and not exists(select 1 from atlas.work_execution_results r where r.work_item_id=w.id)
 and not exists(select 1 from atlas.work_allocations a
  where a.work_item_id=w.id and a.state='active' and a.allocation_role='responsible')
 and exists(select 1 from atlas.work_result_contract_policies p
  where p.contract_key='ordinary_company_work_worker_attestation_v1'
    and p.active and p.source_domain='organization'
    and p.acceptance_mode='worker_attestation')
on conflict (work_item_id) do nothing;

-- Source Object Type is historical *creation provenance*, not an employee
-- classification. Preserve it exactly; update current operating contract.
update atlas.work_items w set
 result_contract_key='ordinary_company_work_worker_attestation_v1',
 metadata=w.metadata||jsonb_build_object(
  'canonicalWorkUpgrade','event_shared_to_canonical_company_work_v1',
  'ordinarySharedChecklist',false,
  'exclusiveAssigneeAuthority',true,
  'workerDayRequired',true,
  'historicalSharedChecklistOrigin',true),
 updated_at=now()
from atlas.event_shared_work_canonicalization_receipts_v1 rec
where w.id=rec.work_item_id and w.organization_id=rec.organization_id
 and w.work_state='open'
 and w.source_object_type=rec.original_source_object_type
 and w.result_contract_key=rec.original_result_contract_key
 and w.metadata=rec.original_metadata;

-- Retire the Event-only shortcut, INCLUDING old clients with saved URLs.
-- The historical definition and read operations remain for the audit.
revoke execute on function public.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)
 from public,anon,authenticated;
revoke execute on function atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)
 from public,anon,authenticated;

commit;

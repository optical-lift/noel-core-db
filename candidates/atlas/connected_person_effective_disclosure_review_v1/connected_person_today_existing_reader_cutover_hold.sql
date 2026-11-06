-- HELD / REVIEW ONLY, NOT AUTHORIZED FOR PRODUCTION, Noel #2255/#2263.
-- Same-signature replacement of existing connected Person all-date Today reader.
-- Prevents bypass of native connection and verified Work relevance through
-- the older Today RPC. No new roles, table grants, assignment or Work rows.
-- Redacts instructions, original source UUID/type/date until per-field
-- source disclosure is explicitly approved. Existing UI needs worker-positive
-- instructions parity; DO NOT release this patch by itself.
-- Protected full-schema clone + genuine signed scenarios required.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_today_self_api_v1(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_access jsonb;
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  v_access:=atlas.reality_access_self_api_v1();
  if v_access->>'state' is distinct from 'ready'
    or v_access->>'authenticated' is distinct from 'true'
    or v_access->'person'->>'id' is distinct from v_self::text then
    raise exception 'Source authorization unavailable' using errcode='42501';
  end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Page size must be between 1 and 100' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',row.work_id,'allocationId',row.allocation_id,
    'organizationId',row.organization_id,'ledgerId',row.ledger_id,
    'title',row.title,'instructions',row.instructions,
    'sourceType',row.source_type,'sourceId',row.source_id,
    'sourceDate',row.source_date,'sourceDateIsNotScheduledDay',true,
    'resultContractKey',row.result_contract,
    'canReportOrdinaryCompletion',row.result_contract=
      'ordinary_company_work_worker_attestation_v1',
    'uptakeKind',row.uptake_kind,'establishmentBasisKind',row.basis_kind,'employeeSeatRequired',false)
    order by row.allocated_at,row.work_id),'[]'::jsonb) into v_items
  from (
    select w.id work_id,a.id allocation_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      -- These are separate source/field disclosures, not implicitly
      -- licensed by Work allocation. Keep the old JSON keys nullable.
      w.title,
      CASE WHEN atlas.connected_person_work_field_currently_approved_v1(
        (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,
        'instructions') THEN w.instructions ELSE NULL::text END AS instructions,
      NULL::text AS source_type,
      NULL::uuid AS source_id,NULL::text AS source_date,
      w.result_contract_key result_contract,
      a.establishment_basis->>'uptakeKind' uptake_kind,a.establishment_basis_kind basis_kind,a.allocated_at
    from atlas.work_allocations a
    join atlas.work_items w on w.id=a.work_item_id
      and w.organization_id=a.organization_id
    where a.allocation_role='responsible' and a.state='active'
      and a.assignee_canonical_person_id=v_self
      and a.assignee_membership_id IS NULL
      and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment')
      and w.work_state='open'
      -- An original allocation does not authorize stale, unrelated Ledger Work.
      -- Resolve a current native Ledger seat and a verified original Work
      -- attribution for the SAME Ledger before returning the title.
      and exists (
        select 1 from atlas.company_work_native_ledger_relevance rel
        where rel.organization_id=w.organization_id
          and rel.work_item_id=w.id
          and rel.ledger_id::text=a.establishment_basis->>'nativeLedgerId'
          and rel.attribution_state='active'
          and atlas.person_has_native_ledger_connection_v1(
            w.organization_id,rel.ledger_id,v_self)
          and (
            rel.evidence_kind in ('owner_attested','participant_attested')
            or (rel.evidence_kind='source_verified' and exists (
              select 1 from atlas.company_work_native_ledger_exact_source_v1(
                w.id,rel.ledger_id) proof
              where proof.source_schema=rel.source_schema
                and proof.source_table=rel.source_table
                and proof.source_id=rel.source_id
            ))
          )
      )
      and atlas.connected_person_work_field_currently_approved_v1(
        (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,'title')
    order by a.allocated_at,a.id
    limit p_limit
  ) row;
  return jsonb_build_object('ok',true,
    'contractVersion','connected_person_company_work_today_v1',
    'personId',v_self,'items',v_items,
    'sourceDateIsNotAWorkSchedule',true,'employeeSeatRequired',false);
end
$function$
;
COMMIT;

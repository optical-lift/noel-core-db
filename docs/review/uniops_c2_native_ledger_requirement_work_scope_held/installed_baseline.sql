CREATE OR REPLACE FUNCTION atlas.operating_requirements_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_owner uuid;
  v_entries jsonb;
  v_legacy jsonb;
begin
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact native Ledger owner required' using errcode='42501';
  end if;
  if p_limit is null or p_limit<1 or p_limit>200 then
    raise exception 'Limit must be 1..200' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.established_at,e.entry_id),'[]'::jsonb)
  into v_entries from (
    select r.id as entry_id,r.established_at,r.stable_key,
      w.id as requirement_id,w.summary,w.state as requirement_state,
      w.organization_unit_id,
      latest.revision_no,latest.policy_state,latest.document,
      latest.accountable_position_id,latest.recurrence_rule_id,
      latest.effective_at,
      case when latest.accountable_position_id is null then false
        else exists (
          select 1 from atlas.organization_position_appointments a
          where a.position_id=latest.accountable_position_id
            and a.organization_id=r.organization_id and a.status='active'
            and a.begins_at<=now() and (a.ends_at is null or a.ends_at>now())
        ) end as position_has_current_appointment_window,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'workItemId',i.id,'title',i.title,'state',i.work_state,
          'responsiblyAllocated',exists (
            select 1 from atlas.work_allocations a
            where a.work_item_id=i.id and a.organization_id=r.organization_id
              and a.allocation_role='responsible' and a.state='active'))
          order by i.created_at,i.id)
        from atlas.work_requirement_links l
        join atlas.work_items i on i.id=l.work_item_id
          and i.organization_id=r.organization_id
        where l.requirement_id=w.id and l.organization_id=r.organization_id
          and l.active
      ),'[]'::jsonb) as canonical_work
    from atlas.company_work_operating_register_entries r
    join atlas.work_requirements w on w.id=r.requirement_id
      and w.organization_id=r.organization_id
    left join lateral (
      select v.* from atlas.company_work_operating_register_revisions v
      where v.entry_id=r.id and v.effective_at<=now()
      order by v.effective_at desc,v.revision_no desc limit 1
    ) latest on true
    where r.organization_id=p_organization_id and r.ledger_id=p_ledger_id
    order by r.established_at,r.id limit p_limit
  ) e;
  -- Existing legacy-linked requirements remain visible for reconciliation,
  -- but only with exact current native Ledger relevance evidence.
  select coalesce(jsonb_agg(to_jsonb(x) order by x.requirement_id),'[]'::jsonb)
  into v_legacy from (
    select distinct w.id as requirement_id,w.summary,w.state as requirement_state
    from atlas.work_requirements w
    join atlas.work_requirement_links l on l.requirement_id=w.id
      and l.organization_id=w.organization_id and l.active
    join atlas.company_work_native_ledger_relevance n
      on n.work_item_id=l.work_item_id and n.organization_id=w.organization_id
      and n.ledger_id=p_ledger_id and n.attribution_state='active'
    where w.organization_id=p_organization_id
      and not exists (
        select 1 from atlas.company_work_operating_register_entries e
        where e.requirement_id=w.id
      )
      and (n.evidence_kind='owner_attested'
        or (n.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            n.work_item_id,n.ledger_id) s
          where s.source_schema=n.source_schema and s.source_table=n.source_table
            and s.source_id=n.source_id)))
    order by w.id limit p_limit
  ) x;
  return jsonb_build_object(
    'contractVersion','operating_requirements_owner_v1',
    'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
    'registerEntries',v_entries,'legacyLinkedRequirements',v_legacy,
    'positionDoesNotAllocateWork',true,
    'recurrenceRuleDoesNotMaterializeWorkHere',true,
    'unlinkedLegacyRequirementsAreUnattributed',true);
end
$function$

-- REVIEW-ONLY source candidate: worker-visible original Work prerequisites.
-- NOT A NUMBERED MIGRATION. Never apply directly through production SQL.
-- Reuses the existing canonical atlas.work_item_relations graph and unchanged
-- owner-only prerequisite writer. No new table, task, or relationship created.

create or replace function atlas.connected_person_work_prerequisites_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_downstream_work_item_id uuid
)
returns jsonb
language plpgsql stable security definer
set search_path=''
as $worker$
declare
  v_person uuid;
  v_items jsonb := '[]'::jsonb;
begin
  -- auth.uid() alone is insufficient: require a live, genuine Auth session
  -- and ready canonical Personal Atlas, not a forged or expired JWT.
  if auth.uid() is null
     or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
    raise exception 'Current signed-in Atlas Person required.'
      using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  if v_person is null or p_organization_id is null or p_ledger_id is null
     or p_downstream_work_item_id is null then
    raise exception 'Exact connected Person and original Work source required.'
      using errcode='42501';
  end if;

  -- The member's Ledger seat alone NEVER grants an institution-wide read.
  -- An original, current responsible allocation to this exact downstream
  -- Work and this exact native Ledger is required. Keep the person-only
  -- carrier, no employee seats and no optional proposed work requests.
  if not atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_person)
     or not atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,p_downstream_work_item_id)
     or not exists (
       select 1
       from atlas.work_allocations a
       join atlas.work_items w
         on w.id=a.work_item_id and w.organization_id=a.organization_id
       where a.organization_id=p_organization_id
         and a.work_item_id=p_downstream_work_item_id
         and a.assignee_canonical_person_id=v_person
         and a.assignee_membership_id is null
         and a.allocation_role='responsible'
         and a.establishment_basis_kind in (
           'person_connection_receiver_uptake',
           'delegated_under_standing_scope',
           'ledger_connection_direct_assignment'
         )
         and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
         and (
           (a.state='active' and w.work_state='open')
           or (a.state='completed' and w.work_state='completed')
         )
     ) then
    raise exception 'Current responsibility for this exact Ledger Work required.'
      using errcode='42501';
  end if;

  -- Only original active depends_on edges for the Work the person actually
  -- owns responsibility for. A prerequisite's title is included strictly
  -- because this original edge, authorized downstream allocation and
  -- independently evidenced relevance to the SAME native Ledger all exist.
  -- No unrelated Work listing, assignment/person identity, source metadata,
  -- private action-history, or institutional owner privileges are exposed.
  select coalesce(jsonb_agg(jsonb_build_object(
    'relationId',r.id,
    'relationKind','depends_on',
    'downstreamWorkItemId',r.from_work_item_id,
    'prerequisiteWorkItemId',r.to_work_item_id,
    'title',p.title,
    'prerequisiteWorkState',p.work_state,
    'active',r.active,
    'recordedSatisfiedAt',r.satisfied_at
  ) order by r.id),'[]'::jsonb)
  into v_items
  from atlas.work_item_relations r
  join atlas.work_items p
    on p.id=r.to_work_item_id and p.organization_id=r.organization_id
  where r.organization_id=p_organization_id
    and r.from_work_item_id=p_downstream_work_item_id
    and r.relation_kind='depends_on'
    and r.active
    and atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,r.to_work_item_id);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','connected_person_work_prerequisites_v1',
    'organizationId',p_organization_id,
    'ledgerId',p_ledger_id,
    'downstreamWorkItemId',p_downstream_work_item_id,
    'personId',v_person,
    'relations',v_items,
    'sourceScope','original_responsible_person_downstream_work',
    'onlyCurrentLedgerEvidence',true,
    'activeRelationsOnly',true,
    'doesNotAuthorizeRelationChanges',true,
    'doesNotInferCompletionOrSatisfaction',true
  );
end;
$worker$;

-- Internal database implementation cannot be called directly by browser
-- roles; the only public entrypoint rechecks identity in the function above.
revoke all on function atlas.connected_person_work_prerequisites_self_api_v1(
  uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.connected_person_work_prerequisites_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_downstream_work_item_id uuid
)
returns jsonb
language sql stable security definer
set search_path=''
as $wrapper$
  select atlas.connected_person_work_prerequisites_self_api_v1(
    p_organization_id,p_ledger_id,p_downstream_work_item_id);
$wrapper$;

revoke all on function public.connected_person_work_prerequisites_self_api_v1(
  uuid,uuid,uuid) from public,anon;
grant execute on function public.connected_person_work_prerequisites_self_api_v1(
  uuid,uuid,uuid) to authenticated;

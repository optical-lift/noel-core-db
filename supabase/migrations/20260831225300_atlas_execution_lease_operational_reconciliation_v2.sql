BEGIN;

-- Operational reconciliation v2.
-- Shadow leases are historical evidence and must never participate in the
-- operational planner diff once a live execution handoff exists. Lease kind is
-- explicit so unrelated human commitments in the same recipient/window cannot
-- contaminate one another.

create or replace function atlas.execution_lease_reconciliation_proposal_v2(
  p_custody_kind text,
  p_organization_id uuid,
  p_principal_id uuid,
  p_recipient_kind text,
  p_recipient_id uuid,
  p_lease_kind text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_candidates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_candidate jsonb;
  v_key text;
  v_seen text[]:=array[]::text[];
  v_add jsonb;
  v_retain jsonb;
  v_withdraw jsonb;
begin
  if p_custody_kind not in ('organization','principal')
     or nullif(btrim(p_recipient_kind),'') is null
     or p_recipient_id is null
     or nullif(btrim(p_lease_kind),'') is null
     or p_window_start is null
     or p_window_end is null
     or p_window_end<=p_window_start
     or p_candidates is null
     or jsonb_typeof(p_candidates)<>'array' then
    raise exception 'Operational lease reconciliation requires custody, recipient, lease kind, window, and candidate array.' using errcode='22023';
  end if;
  if (p_custody_kind='organization' and (p_organization_id is null or p_principal_id is not null))
     or (p_custody_kind='principal' and (p_principal_id is null or p_organization_id is not null)) then
    raise exception 'Lease reconciliation custody reference does not match custody kind.' using errcode='22023';
  end if;

  for v_candidate in select value from jsonb_array_elements(p_candidates)
  loop
    if jsonb_typeof(v_candidate)<>'object'
       or nullif(btrim(v_candidate->>'executionKind'),'') is null
       or coalesce(v_candidate->>'executionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or nullif(btrim(v_candidate->>'title'),'') is null then
      raise exception 'Every lease candidate requires executionKind, UUID executionId, and title.' using errcode='22023';
    end if;
    v_key:=btrim(v_candidate->>'executionKind')||':'||lower(v_candidate->>'executionId');
    if v_key=any(v_seen) then
      raise exception 'Duplicate execution candidate: %',v_key using errcode='23505';
    end if;
    v_seen:=array_append(v_seen,v_key);
  end loop;

  with current_leases as (
    select l.*,e.resulting_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state
      from atlas.execution_lease_events x
      where x.lease_id=l.id
      order by x.occurred_at desc,x.id desc
      limit 1
    ) e on true
    where l.custody_kind=p_custody_kind
      and l.organization_id is not distinct from p_organization_id
      and l.principal_id is not distinct from p_principal_id
      and l.recipient_kind=btrim(p_recipient_kind)
      and l.recipient_id=p_recipient_id
      and l.lease_kind=btrim(p_lease_kind)
      and l.shadow_only=false
      and l.lease_start<p_window_end
      and l.lease_end>p_window_start
      and e.resulting_state not in ('completed','withdrawn','expired')
  ), candidates as (
    select c.value,c.ord
    from jsonb_array_elements(p_candidates) with ordinality c(value,ord)
  )
  select
    coalesce((select jsonb_agg(c.value order by c.ord)
      from candidates c
      where not exists (
        select 1 from current_leases l
        where l.execution_kind=btrim(c.value->>'executionKind')
          and l.execution_id=(c.value->>'executionId')::uuid
      )),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'leaseId',l.id,'leaseKey',l.lease_key,'currentState',l.resulting_state,
        'executionKind',l.execution_kind,'executionId',l.execution_id,'title',l.title_snapshot
      ) order by c.ord)
      from candidates c
      join current_leases l
        on l.execution_kind=btrim(c.value->>'executionKind')
       and l.execution_id=(c.value->>'executionId')::uuid),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'leaseId',l.id,'leaseKey',l.lease_key,'currentState',l.resulting_state,
        'executionKind',l.execution_kind,'executionId',l.execution_id,'title',l.title_snapshot,
        'proposedAction','withdraw'
      ) order by l.lease_start,l.id)
      from current_leases l
      where not exists (
        select 1 from candidates c
        where l.execution_kind=btrim(c.value->>'executionKind')
          and l.execution_id=(c.value->>'executionId')::uuid
      )),'[]'::jsonb)
  into v_add,v_retain,v_withdraw;

  return jsonb_build_object(
    'contractVersion','execution_lease_reconciliation_proposal_v2',
    'leaseKind',btrim(p_lease_kind),
    'mutationAuthority',false,
    'proposalOnly',true,
    'add',v_add,
    'retain',v_retain,
    'withdraw',v_withdraw,
    'trustBoundary',jsonb_build_object(
      'plannerMayPropose',true,
      'proposalDoesNotAlterLease',true,
      'leaseChangeRequiresExplicitTransition',true,
      'shadowEvidenceExcluded',true,
      'leaseKindScoped',true
    )
  );
end;
$$;

comment on function atlas.execution_lease_reconciliation_proposal_v2(text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,jsonb) is
  'Operational planner diff over one explicit live lease kind. Shadow leases are evidence only and are excluded. The returned proposal has no mutation authority.';

revoke all on function atlas.execution_lease_reconciliation_proposal_v2(text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function atlas.execution_lease_reconciliation_proposal_v2(text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,jsonb) to service_role;

-- Normalize operational metadata at the read membrane. Immutable lease rows may
-- retain source-era metadata for custody; live readers receive authoritative
-- lease-state flags from columns/contracts, never contradictory source hints.
create or replace function atlas.worker_day_live_execution_lease_packet_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_leases jsonb;
  v_count integer;
begin
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'leaseId',l.id,
      'leaseKey',l.lease_key,
      'executionKind',l.execution_kind,
      'executionId',l.execution_id,
      'title',l.title_snapshot,
      'leaseStart',l.lease_start,
      'leaseEnd',l.lease_end,
      'state',e.resulting_state,
      'actionable',e.resulting_state in ('leased','started'),
      'interrupted',e.resulting_state='interrupted',
      'terminal',e.resulting_state in ('completed','withdrawn','expired'),
      'lastEventKind',e.event_kind,
      'lastEventReason',e.reason,
      'lastEventAt',e.occurred_at,
      'admissionWarrant',l.admission_warrant,
      'metadata',(coalesce(l.metadata,'{}'::jsonb)-'shadowOnly'-'doesNotDrivePresentation'-'doesDrivePresentation')
        ||jsonb_build_object('shadowOnly',false,'doesDrivePresentation',true)
    ) order by coalesce(nullif(l.metadata->>'admissionRank','')::integer,2147483647),l.created_at,l.id),'[]'::jsonb),
    count(*)::integer
  into v_leases,v_count
  from atlas.execution_leases l
  join lateral (
    select x.event_kind,x.resulting_state,x.reason,x.occurred_at
    from atlas.execution_lease_events x
    where x.lease_id=l.id
    order by x.occurred_at desc,x.id desc
    limit 1
  ) e on true
  where l.custody_kind='organization'
    and l.organization_id=v_org_id
    and l.recipient_kind='farm_membership'
    and l.recipient_id=p_membership_id
    and l.lease_kind='work_execution'
    and l.shadow_only=false
    and l.lease_start<v_end
    and l.lease_end>v_start;

  return jsonb_build_object(
    'contractVersion','worker_day_live_execution_lease_packet_v1',
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_day,
    'liveLeaseMode',coalesce(v_count,0)>0,
    'leaseCount',coalesce(v_count,0),
    'leases',v_leases,
    'truthBoundary',jsonb_build_object(
      'plannerIsAdvisory',true,
      'leaseIsExecutionAuthority',true,
      'leaseRemovalRequiresEvent',true,
      'operationalMetadataNormalized',true,
      'immutableSourceMetadataPreservedOnLeaseRow',true
    )
  );
end;
$$;

create or replace function atlas.reconcile_worker_day_execution_leases_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_org_id uuid;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_rec record;
  v_readiness jsonb;
  v_fit jsonb;
  v_reason text;
  v_events jsonb:='[]'::jsonb;
  v_candidates jsonb;
  v_proposal jsonb;
begin
  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true;
  if v_org_id is null then
    raise exception 'Active worker membership required.' using errcode='42501';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  for v_rec in
    select l.*,e.resulting_state as current_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state
      from atlas.execution_lease_events x
      where x.lease_id=l.id
      order by x.occurred_at desc,x.id desc
      limit 1
    ) e on true
    where l.custody_kind='organization'
      and l.organization_id=v_org_id
      and l.recipient_kind='farm_membership'
      and l.recipient_id=p_membership_id
      and l.lease_kind='work_execution'
      and l.shadow_only=false
      and l.lease_start<v_end and l.lease_end>v_start
      and e.resulting_state not in ('completed','withdrawn','expired')
    order by l.created_at,l.id
  loop
    if v_rec.execution_kind<>'task' then
      continue;
    end if;

    if exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='done') then
      v_events:=v_events||jsonb_build_array(atlas.transition_execution_lease_v1(
        v_rec.id,'task-done-reconcile:'||v_rec.execution_id::text,
        'completed','Underlying execution is already complete.',
        'worker_day_lease_reconciliation',v_rec.execution_id,p_actor_user_id,
        jsonb_build_object('taskStatus','done'),'{}'::jsonb,now()
      ));
      continue;
    end if;

    v_readiness:=atlas.task_execution_readiness_v1(v_rec.execution_id);
    v_fit:=atlas.task_operation_fit_warrant_v1(v_rec.execution_id);

    if v_rec.current_state in ('leased','started')
       and (
         not coalesce((v_readiness->>'executionReady')::boolean,false)
         or not coalesce((v_fit->>'exactIdentitySupported')::boolean,false)
         or not exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='open')
       ) then
      v_reason:=case
        when not exists(select 1 from atlas.tasks t where t.id=v_rec.execution_id and t.status='open') then 'Underlying obligation is no longer open.'
        when not coalesce((v_readiness->>'executionReady')::boolean,false) then 'Current execution requirements are no longer satisfied.'
        else 'Current operation identity is no longer supported.'
      end;
      v_events:=v_events||jsonb_build_array(atlas.transition_execution_lease_v1(
        v_rec.id,
        'reality-interruption:'||md5(coalesce(v_readiness::text,'')||coalesce(v_fit::text,'')||v_reason),
        'interrupted',v_reason,
        'worker_day_lease_reconciliation',v_rec.execution_id,p_actor_user_id,
        jsonb_build_object('executionReadiness',v_readiness,'operationFit',v_fit),
        jsonb_build_object('automaticInterruption',true,'automaticResume',false),now()
      ));
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'executionKind','task',
    'executionId',c.task_id,
    'title',t.title,
    'plannerRank',c.planner_rank,
    'plannerReason',c.planner_reason,
    'admissionRank',c.admission_rank,
    'admissionReason',c.admission_reason
  ) order by c.admission_rank,c.task_id),'[]'::jsonb)
  into v_candidates
  from atlas.worker_day_lease_candidate_selection_v1(p_farm_id,p_membership_id,p_day) c
  join atlas.tasks t on t.id=c.task_id;

  v_proposal:=atlas.execution_lease_reconciliation_proposal_v2(
    'organization',v_org_id,null,'farm_membership',p_membership_id,'work_execution',
    v_start,v_end,v_candidates
  );

  return atlas.worker_day_live_execution_lease_packet_v1(p_farm_id,p_membership_id,p_day)
    || jsonb_build_object(
      'reconciliationEvents',v_events,
      'plannerProposal',v_proposal,
      'truthBoundary',jsonb_build_object(
        'realityLossMayInterruptLease',true,
        'interruptedLeaseRemainsHistoricalHandoff',true,
        'plannerProposalHasNoMutationAuthority',true,
        'interruptedLeaseNeverAutoResumes',true,
        'replacementRequiresExplicitGrant',true,
        'shadowEvidenceExcludedFromOperationalProposal',true
      )
    );
end;
$$;

comment on function atlas.reconcile_worker_day_execution_leases_v1(uuid,uuid,date,uuid) is
  'Reconciles reality against live Worker Day work_execution leases only. May interrupt live leases when reality loses its warrant; planner differences remain non-mutating proposals and shadow evidence is excluded.';

COMMIT;

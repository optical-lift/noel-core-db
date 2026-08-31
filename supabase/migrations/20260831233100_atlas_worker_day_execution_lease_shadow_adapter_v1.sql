BEGIN;

-- Worker Day -> neutral Execution Lease shadow adapter v1.
--
-- This adapter proves the lease kernel without changing worker-facing behavior.
-- The first run freezes one already-recorded Commitment Ledger generation as
-- the baseline promise. Later planner output is comparison-only and cannot
-- grant or withdraw leases.

create or replace function atlas.bootstrap_worker_day_execution_leases_shadow_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date,
  p_reason text,
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
  v_plan atlas.commitment_plans%rowtype;
  v_generation atlas.commitment_plan_generations%rowtype;
  v_existing_generation_id uuid;
  v_existing_generation_count integer;
  v_item atlas.commitment_items%rowtype;
  v_authorized boolean;
  v_grant jsonb;
  v_grants jsonb:='[]'::jsonb;
  v_candidates jsonb;
  v_proposal jsonb;
  v_leases jsonb;
begin
  if p_farm_id is null
     or p_membership_id is null
     or p_day is null
     or nullif(btrim(p_reason),'') is null then
    raise exception 'Worker Day lease shadow bootstrap requires farm, membership, day, and explicit reason.' using errcode='22023';
  end if;

  select f.organization_id,coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_org_id,v_timezone
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.id=p_membership_id
    and fm.farm_id=p_farm_id
    and fm.active=true;

  if v_org_id is null then
    raise exception 'Active membership on farm is required.' using errcode='42501';
  end if;
  if not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Farm timezone is not recognized by PostgreSQL.' using errcode='22023';
  end if;

  v_start:=p_day::timestamp at time zone v_timezone;
  v_end:=(p_day+1)::timestamp at time zone v_timezone;

  select p.* into v_plan
  from atlas.commitment_plans p
  where p.custody_kind='organization'
    and p.organization_id=v_org_id
    and p.plan_key='worker_day:'||p_farm_id::text||':'||p_membership_id::text||':'||p_day::text
  limit 1;

  if v_plan.id is null then
    raise exception 'Worker Day Commitment Ledger baseline is required before lease shadow bootstrap.' using errcode='23514';
  end if;

  -- Once leases exist for this day, their original commitment generation is
  -- the frozen bootstrap authority. A later planner generation cannot silently
  -- become the source of new leases.
  select min(nullif(l.metadata->>'commitmentGenerationId','')::uuid),
         count(distinct nullif(l.metadata->>'commitmentGenerationId','')::uuid)
    into v_existing_generation_id,v_existing_generation_count
  from atlas.execution_leases l
  where l.custody_kind='organization'
    and l.organization_id=v_org_id
    and l.recipient_kind='farm_membership'
    and l.recipient_id=p_membership_id
    and l.lease_kind='work_execution'
    and l.metadata->>'farmId'=p_farm_id::text
    and l.metadata->>'serviceDate'=p_day::text;

  if coalesce(v_existing_generation_count,0)>1 then
    raise exception 'Worker Day shadow leases disagree about their bootstrap commitment generation.' using errcode='23514';
  end if;

  if v_existing_generation_id is not null then
    select g.* into v_generation
    from atlas.commitment_plan_generations g
    where g.id=v_existing_generation_id
      and g.plan_id=v_plan.id;
    if v_generation.id is null then
      raise exception 'Existing Worker Day lease bootstrap generation is not part of the expected commitment plan.' using errcode='23514';
    end if;
  else
    select g.* into v_generation
    from atlas.commitment_plan_generations g
    where g.plan_id=v_plan.id
    order by g.generation_number desc
    limit 1;
    if v_generation.id is null then
      raise exception 'Worker Day Commitment Ledger baseline has no generation.' using errcode='23514';
    end if;
  end if;

  for v_item in
    select i.*
    from atlas.commitment_items i
    where i.generation_id=v_generation.id
    order by i.sequence_number,i.id
  loop
    if v_item.execution_kind is null or v_item.execution_id is null then
      raise exception 'Commitment item % cannot become an execution lease because it has no execution identity.',v_item.id using errcode='23514';
    end if;

    v_authorized:=
      coalesce((v_item.execution_warrant #>> '{executionReadiness,executionReady}')::boolean,false)
      and coalesce((v_item.execution_warrant #>> '{operationFit,exactIdentitySupported}')::boolean,false);

    if not v_authorized then
      raise exception 'Commitment item % does not carry a valid execution + operation identity warrant.',v_item.id using errcode='23514';
    end if;

    v_grant:=atlas.grant_execution_lease_v1(
      'worker_day:'||p_membership_id::text||':'||p_day::text||':'||v_item.stable_item_key,
      'work_execution',
      'organization',
      v_org_id,
      null,
      'farm_membership',
      p_membership_id,
      null,
      null,
      v_item.execution_kind,
      v_item.execution_id,
      v_item.title_snapshot,
      v_plan.effective_start,
      v_plan.effective_end,
      'worker_day_commitment_item_execution_warrant_v1',
      jsonb_build_object(
        'authorized',true,
        'commitmentPlanId',v_plan.id,
        'commitmentGenerationId',v_generation.id,
        'commitmentItemId',v_item.id,
        'domainWarrant',v_item.execution_warrant
      ),
      p_reason,
      'commitment_item',
      v_item.id,
      p_actor_user_id,
      true,
      jsonb_build_object(
        'farmId',p_farm_id,
        'serviceDate',p_day,
        'timezone',v_timezone,
        'commitmentPlanId',v_plan.id,
        'commitmentGenerationId',v_generation.id,
        'commitmentItemId',v_item.id,
        'shadowOnly',true,
        'doesNotDrivePresentation',true
      )
    );
    v_grants:=v_grants||jsonb_build_array(v_grant);
  end loop;

  -- The current planner is advisory only. It can produce a diff against the
  -- frozen leases, but this function never applies that diff.
  select coalesce(jsonb_agg(jsonb_build_object(
    'executionKind','task',
    'executionId',t.id,
    'title',t.title,
    'plannerRank',projection.selection_rank,
    'presentationReason',projection.presentation_reason
  ) order by projection.selection_rank,t.id),'[]'::jsonb)
  into v_candidates
  from atlas.worker_day_work_projection_v1(p_farm_id,p_membership_id,p_day) projection
  join atlas.tasks t on t.id=projection.task_id;

  v_proposal:=atlas.execution_lease_reconciliation_proposal_v1(
    'organization',v_org_id,null,'farm_membership',p_membership_id,
    v_start,v_end,v_candidates
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'leaseId',l.id,
    'leaseKey',l.lease_key,
    'executionKind',l.execution_kind,
    'executionId',l.execution_id,
    'title',l.title_snapshot,
    'state',e.resulting_state,
    'actionable',e.resulting_state in ('leased','started'),
    'shadowOnly',l.shadow_only
  ) order by l.created_at,l.id),'[]'::jsonb)
  into v_leases
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
    and l.metadata->>'farmId'=p_farm_id::text
    and l.metadata->>'serviceDate'=p_day::text;

  return jsonb_build_object(
    'contractVersion','bootstrap_worker_day_execution_leases_shadow_v1',
    'shadowOnly',true,
    'doesNotDrivePresentation',true,
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_day,
    'commitmentPlanId',v_plan.id,
    'bootstrapGenerationId',v_generation.id,
    'bootstrapGenerationNumber',v_generation.generation_number,
    'grantResults',v_grants,
    'leases',v_leases,
    'plannerProposal',v_proposal,
    'trustBoundary',jsonb_build_object(
      'commitmentGenerationFrozenAtBootstrap',true,
      'plannerRecomputeCannotChangeLease',true,
      'proposalHasNoMutationAuthority',true,
      'workerFeedStillUsesExistingProjection',true
    )
  );
end;
$$;

comment on function atlas.bootstrap_worker_day_execution_leases_shadow_v1(uuid,uuid,date,text,uuid) is
  'Shadow-only Worker Day adapter. Freezes one existing Commitment Ledger generation into item-level execution leases; later Worker Day planner output is comparison-only and cannot mutate those leases or the current worker feed.';

revoke all on function atlas.bootstrap_worker_day_execution_leases_shadow_v1(uuid,uuid,date,text,uuid) from public, anon, authenticated;
grant execute on function atlas.bootstrap_worker_day_execution_leases_shadow_v1(uuid,uuid,date,text,uuid) to service_role;

COMMIT;

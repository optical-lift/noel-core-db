begin;

-- Flower Preparation Owner-review notebook command context v1.
--
-- This is a read membrane only. It does not create Harvest, Preparation, Ready,
-- Company Work, Task, or Operating Knowledge truth.
--
-- Governing boundary:
--   * physical Harvest evidence remains source-owned;
--   * the transitional Owner review Task is exposed only as the command address
--     required by record_flower_preparation_directive_v2;
--   * the waiting Preparation occurrence remains hidden from the application;
--   * canonical crop_profile_id is exposed only where it is already present on a
--     harvested crop cycle, so Operating Knowledge never resolves from a label;
--   * record_flower_preparation_directive_v2 / unchanged v1 remain the only write
--     path that can establish the directive, complete review, and release work.

do $preflight$
begin
  if to_regprocedure('atlas.current_farm_role(uuid)') is null
     or to_regprocedure('atlas.current_membership_id(uuid)') is null then
    raise exception 'Farm membership read authority is missing.';
  end if;
  if to_regprocedure('atlas.is_organization_member(uuid)') is null then
    raise exception 'Organization membership authority is missing.';
  end if;
  if to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v2 command authority is missing.';
  end if;
  if to_regclass('atlas.tasks') is null
     or to_regclass('atlas.farms') is null
     or to_regclass('atlas.flower_harvest_batches') is null
     or to_regclass('atlas.flower_harvest_bucket_observations') is null
     or to_regclass('atlas.crop_cycles') is null then
    raise exception 'Flower Preparation Owner-review source custody is missing.';
  end if;
end
$preflight$;

create or replace function atlas.flower_preparation_owner_review_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 29),
  p_through_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_role text;
  v_membership_id uuid;
  v_farm atlas.farms%rowtype;
  v_reviews jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  if p_farm_id is null then
    raise exception 'Farm is required.' using errcode = '22023';
  end if;

  if p_from_date is null or p_through_date is null or p_through_date < p_from_date then
    raise exception 'A valid Harvest date window is required.' using errcode = '22023';
  end if;

  if p_through_date - p_from_date > 366 then
    raise exception 'Harvest notebook windows may not exceed 367 days.' using errcode = '22023';
  end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);

  if v_membership_id is null or v_role not in ('owner', 'manager') then
    raise exception 'Owner or manager authority is required to inspect Flower Preparation review.'
      using errcode = '42501';
  end if;

  select * into v_farm
  from atlas.farms f
  where f.id = p_farm_id
    and f.status = 'active';

  if v_farm.id is null then
    raise exception 'Active farm not found.' using errcode = 'P0002';
  end if;

  if v_farm.organization_id is null or v_farm.organization_unit_id is null then
    raise exception 'Flower Preparation requires canonical Organization and Organization Unit custody.'
      using errcode = '22023';
  end if;

  if not atlas.is_organization_member(v_farm.organization_id) then
    raise exception 'Organization membership is required to inspect Flower Preparation review.'
      using errcode = '42501';
  end if;

  with eligible_reviews as (
    select
      t.id as owner_review_task_id,
      b.id as harvest_batch_id,
      b.harvest_date
    from atlas.tasks t
    join atlas.flower_harvest_batches b
      on b.farm_id = t.farm_id
     and t.metadata ->> 'flower_harvest_batch_id' = b.id::text
    where t.farm_id = p_farm_id
      and b.harvest_date between p_from_date and p_through_date
      and t.status in ('open', 'blocked')
      and t.visibility_scope in ('owner', 'management')
      and coalesce(t.work_class, '') = 'owner_decision'
      and t.metadata ->> 'task_style' = 'flower_preparation_directive_review'
      and t.metadata ->> 'flower_preparation_directive_review_version' = '1'
      and nullif(t.metadata ->> 'flower_preparation_occurrence_id', '') is not null
      and exists (
        select 1
        from atlas.flower_harvest_bucket_observations o
        where o.farm_id = p_farm_id
          and o.batch_id = b.id
      )
  ),
  crop_rows as (
    select
      r.owner_review_task_id,
      c.crop_profile_id,
      c.crop_label,
      c.variety,
      count(*)::integer as harvest_observation_count
    from eligible_reviews r
    join atlas.flower_harvest_bucket_observations o
      on o.farm_id = p_farm_id
     and o.batch_id = r.harvest_batch_id
    left join atlas.crop_cycles c
      on c.id = o.crop_cycle_id
     and c.farm_id = p_farm_id
    where c.crop_label is not null
    group by r.owner_review_task_id, c.crop_profile_id, c.crop_label, c.variety
  ),
  review_rows as (
    select
      r.owner_review_task_id,
      r.harvest_batch_id,
      r.harvest_date,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'cropProfileId', cr.crop_profile_id,
            'cropLabel', cr.crop_label,
            'variety', cr.variety,
            'harvestObservationCount', cr.harvest_observation_count
          )
          order by lower(cr.crop_label), lower(coalesce(cr.variety, '')), cr.crop_profile_id
        )
        from crop_rows cr
        where cr.owner_review_task_id = r.owner_review_task_id
      ), '[]'::jsonb) as crop_options
    from eligible_reviews r
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'ownerReviewTaskId', r.owner_review_task_id,
      'harvestBatchId', r.harvest_batch_id,
      'harvestDate', r.harvest_date,
      'cropOptions', r.crop_options
    )
    order by r.harvest_date desc, r.owner_review_task_id
  ), '[]'::jsonb)
  into v_reviews
  from review_rows r;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'flower_preparation_owner_review_notebook_self_api_v1',
    'farm', jsonb_build_object(
      'id', v_farm.id,
      'stableKey', v_farm.stable_key,
      'name', v_farm.name,
      'organizationId', v_farm.organization_id,
      'organizationUnitId', v_farm.organization_unit_id
    ),
    'audience', jsonb_build_object(
      'membershipId', v_membership_id,
      'role', v_role
    ),
    'fromDate', p_from_date,
    'throughDate', p_through_date,
    'reviews', v_reviews,
    'truthBoundary', jsonb_build_object(
      'ownerReviewTaskIsCommandAddressOnly', true,
      'preparationOccurrenceRemainsServerOwned', true,
      'cropProfileIdentityIsSourceOwned', true,
      'directiveWriterOwnsReviewCompletionAndRelease', true,
      'workerDayIsNotMutatedByThisRead', true
    )
  );
end;
$function$;

comment on function atlas.flower_preparation_owner_review_notebook_self_api_v1(uuid,date,date) is
  'Owner/manager-only read membrane for unresolved Flower Preparation review actions in the Harvest notebook horizon. Exposes only the review command address, Harvest batch association/date, and canonical crop options needed to author a v2 directive; the waiting Preparation occurrence remains server-owned.';

revoke all on function atlas.flower_preparation_owner_review_notebook_self_api_v1(uuid,date,date)
  from public, anon, authenticated, service_role;
grant execute on function atlas.flower_preparation_owner_review_notebook_self_api_v1(uuid,date,date)
  to service_role;

create or replace function public.flower_preparation_owner_review_notebook_self_api_v1(
  p_farm_id uuid,
  p_from_date date default (current_date - 29),
  p_through_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.flower_preparation_owner_review_notebook_self_api_v1(p_farm_id, p_from_date, p_through_date);
$function$;

revoke all on function public.flower_preparation_owner_review_notebook_self_api_v1(uuid,date,date)
  from public, anon;
grant execute on function public.flower_preparation_owner_review_notebook_self_api_v1(uuid,date,date)
  to authenticated, service_role;

commit;

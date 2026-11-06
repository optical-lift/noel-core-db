-- HELD P3 harvest-output successor issuer cutover, exact live
-- pg_get_functiondef MD5 b2425633eefe7bee95221be6f96079a8, source only, not a migration.
-- A harvest-output Result may establish physical inventory evidence,
-- but does not authorize the next preparation Work. Existing source
-- observation inserts and pre-existing Work are unchanged.
-- One owner-only attention Journal per nonweekly harvest batch, no Task;
-- the existing owner-review notebook currently reads Task only and needs
-- a separate governed reader before any rollout.
BEGIN;
DO $pin$
BEGIN
 IF (SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
     FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas'
       AND p.proname='queue_flower_preparation_after_harvest_v1')
     IS DISTINCT FROM 'b2425633eefe7bee95221be6f96079a8' THEN
  RAISE EXCEPTION 'Harvest-output task-trigger source drift';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgrelid='atlas.flower_harvest_bucket_observations'::regclass
     AND t.tgname='flower_harvest_bucket_observations_queue_preparation_v1'
     AND t.tgenabled<>'D'
 ) THEN
  RAISE EXCEPTION 'Actual harvest-output trigger attachment changed';
 END IF;
END;
$pin$;

CREATE OR REPLACE FUNCTION atlas.queue_flower_preparation_after_harvest_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_task atlas.tasks%rowtype;
  v_batch atlas.flower_harvest_batches%rowtype;
  v_farm atlas.farms%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_observation_count integer;
  v_attention_id uuid;
begin
  -- This trigger is attached to actual newly inserted bucket observations.
  -- A trigger is an evidence carrier, never a human instruction issuer.
  select * into v_task from atlas.tasks t where t.id=new.task_id;
  select * into v_batch from atlas.flower_harvest_batches b
    where b.id=new.batch_id;
  select * into v_farm from atlas.farms f where f.id=new.farm_id;
  select * into v_member from atlas.farm_memberships m
    where m.id=new.recorded_by_membership_id;
  if v_task.id is null or v_batch.id is null or v_farm.id is null
    or v_member.id is null
    or v_task.farm_id is distinct from new.farm_id
    or v_batch.farm_id is distinct from new.farm_id
    or v_member.farm_id is distinct from new.farm_id
    or v_farm.organization_id is null
  then
    raise exception 'Harvest output cannot cross original Farm custody'
      using errcode='42501';
  end if;

  if v_task.task_series_key='anna_harvest_thursday_weekly' then
    -- Weekly Harvest has its separate, source-qualified P3 10 owner
    -- attention AFTER real canonical Harvest Done; never duplicate.
    return new;
  end if;

  -- A genuine owner directive already exists for the batch. Do not
  -- reopen an already decided owner instruction on another bucket insert.
  if exists (
    select 1 from atlas.flower_preparation_directives d
    where d.farm_id=new.farm_id and d.harvest_batch_id=new.batch_id
  ) then return new; end if;

  select count(*)::integer into v_observation_count
  from atlas.flower_harvest_bucket_observations h
  where h.batch_id=v_batch.id and h.farm_id=new.farm_id;

  -- One source-keyed, owner-only ATTENTION for the whole original batch.
  -- No task_id, recipient assignment, queue, occurrence or fabricated
  -- acceptance. Journal itself is NOT the future authorized Work.
  v_attention_id:=atlas.upsert_journal_event_v1(
    p_organization_id=>v_farm.organization_id,
    p_farm_id=>v_farm.id,
    p_event_key=>'harvest-preparation-needs-owner-direction:'||
      v_batch.id::text,
    p_event_kind=>'owner_decision',
    p_source_kind=>'flower_harvest_batch',
    p_source_id=>v_batch.id,
    p_source_event=>'harvest_output_recorded',
    p_occurred_at=>new.created_at,
    p_journal_date=>new.observed_date,
    p_title=>'Review harvested flowers for preparation',
    p_detail=>'Physical harvest output is recorded. An independent owner direction and accepted original are required before preparation Work.',
    p_visibility_scope=>'owner',
    p_importance=>'attention',
    p_actor_user_id=>new.created_by_user_id,
    p_assigned_user_id=>null,
    p_task_id=>null,
    p_payload=>pg_catalog.jsonb_build_object(
      'contractVersion','harvest_output_owner_attention_6a_v1',
      'harvestBatchId',v_batch.id,
      'sourceBucketObservationId',new.id,
      'sourceHarvestTaskId',v_task.id,
      'sourceObservationCount',v_observation_count,
      'ownerDirectionStillRequired',true,
      'originalWorkOffered',false,
      'workerAccepted',false,
      'preparationTaskCreated',false
    ),
    p_provenance=>pg_catalog.jsonb_build_object(
      'sourceTable','atlas.flower_harvest_bucket_observations',
      'sourceObservationId',new.id,
      'sourceObservedDate',new.observed_date,
      'recordedAt',new.created_at,
      'truthBoundary','observation_not_authorization',
      'noAutomaticSuccessorWork',true
    )
  );
  if v_attention_id is null then
    raise exception 'Owner attention provenance was not established'
      using errcode='23514';
  end if;
  return new;
end;
$function$
COMMIT;

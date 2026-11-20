-- Held source only. Existing Personal original, no new task model.
-- NULL date means not scheduled, never a sentinel or implied Today.
BEGIN;
ALTER TABLE atlas.task_entries ALTER COLUMN due_date DROP NOT NULL;
ALTER TABLE atlas.personal_task_amendment_events_v1 ALTER COLUMN before_due_date DROP NOT NULL, ALTER COLUMN after_due_date DROP NOT NULL;
CREATE OR REPLACE FUNCTION atlas.create_atlas_task_self_api_v1(p_sentence text, p_due_date date, p_source_action_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_user uuid := auth.uid();
  v_sentence text := btrim(coalesce(p_sentence,''));
  v_key text := btrim(coalesce(p_source_action_id,''));
  v_task atlas.task_entries%rowtype;
begin
  if length(v_sentence) not between 1 and 500 then
    raise exception 'Enter one sentence (1-500 characters).' using errcode='22023';
  end if;
  if length(v_key) not between 1 and 128 then
    raise exception 'Source action ID is required.' using errcode='22023';
  end if;

  insert into atlas.task_entries(owner_user_id,principal_id,sentence,due_date,source_action_id)
  values (v_user,v_principal,v_sentence,p_due_date,v_key)
  on conflict (owner_user_id,source_action_id) do nothing
  returning * into v_task;

  if v_task.id is null then
    select * into v_task from atlas.task_entries
      where owner_user_id=v_user and source_action_id=v_key;
    if v_task.id is null or v_task.principal_id<>v_principal
       or v_task.sentence<>v_sentence or v_task.due_date IS DISTINCT FROM p_due_date then
      raise exception 'The submission key belongs to a different task.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.atlas_task_day_self_api_v1(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'institutionalWorkItemId',wi.id,
    'institutionalWorkState',wi.work_state,
    'institutionalTransfer',wi.id is not null,
    'isOriginalOwner',t.owner_user_id=auth.uid() AND t.principal_id=v_principal,
    'assignedToSelf',true
  )) || jsonb_build_object('dueDate',t.due_date) order by case when t.status='open' then 0 else 1 end,
    t.created_at,t.id),'[]'::jsonb)
  into v_rows
  from atlas.task_entries t
  left join lateral (
    select w.id,w.work_state from atlas.work_items w
    where w.source_object_type='personal_dated_task' and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
  ) wi on true
  where atlas.personal_task_assigned_actor_v1(t.id,auth.uid(),v_principal)
    and t.due_date IS NOT DISTINCT FROM p_date
    and t.archived_at is null;
  return jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.amend_personal_task_text_date_self_api_v1(p_task_id uuid, p_expected_revision bigint, p_new_sentence text, p_new_due_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_principal uuid := atlas.require_active_task_principal_v1();
 v_old atlas.task_entries%ROWTYPE;
 v_new atlas.task_entries%ROWTYPE;
 v_sentence text := btrim(coalesce(p_new_sentence,''));
 v_event uuid;
 v_original_day date;
BEGIN
 IF p_task_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
   OR char_length(v_sentence) NOT BETWEEN 1 AND 500 THEN
   RAISE EXCEPTION 'Exact task, revision and text required' USING ERRCODE='22023';
 END IF;
 -- Company Work promotion locks this same original row before linking it.
 SELECT * INTO v_old FROM atlas.task_entries t
 WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned task unavailable' USING ERRCODE='42501';
 END IF;
 IF v_old.status<>'open' OR v_old.archived_at IS NOT NULL THEN
   RAISE EXCEPTION 'Only open unarchived tasks may be amended' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_items w
   WHERE w.source_object_type='personal_dated_task'
   AND w.source_object_id=v_old.id) THEN
   RAISE EXCEPTION 'Transferred task text and date remain source evidence'
     USING ERRCODE='23514';
 END IF;
 IF v_old.amendment_revision<>p_expected_revision THEN
   -- Lost-response retry: only the IMMEDIATELY prior revision, the exact
   -- desired state, and its recorded original event may replay as success.
   -- A later mutation, changed payload or different actor cannot replay.
   IF v_old.amendment_revision=p_expected_revision+1
      AND v_old.sentence IS NOT DISTINCT FROM v_sentence
      AND v_old.due_date IS NOT DISTINCT FROM p_new_due_date THEN
     SELECT e.id,e.before_due_date INTO v_event,v_original_day
     FROM atlas.personal_task_amendment_events_v1 e
     WHERE e.task_id=v_old.id
       AND e.owner_user_id=v_old.owner_user_id
       AND e.principal_id=v_old.principal_id
       AND e.before_revision=p_expected_revision
       AND e.after_revision=v_old.amendment_revision
       AND e.after_sentence IS NOT DISTINCT FROM v_sentence
       AND e.after_due_date IS NOT DISTINCT FROM p_new_due_date;
     IF v_event IS NOT NULL THEN
       RETURN jsonb_build_object(
         'ok',true,'contractVersion','personal_task_text_date_amend_v1',
         'taskId',v_old.id,'sentence',v_old.sentence,
         'oldDueDate',v_original_day,'dueDate',v_old.due_date,
         'amendmentRevision',v_old.amendment_revision,
         'changed',true,'idempotent',true,
         'amendmentEventId',v_event,
         'oneOriginalTaskId',true,'noInstitutionalWorkChanged',true);
     END IF;
   END IF;
   RAISE EXCEPTION 'Task changed; read again before editing' USING ERRCODE='PT409';
 END IF;
 IF v_old.sentence IS NOT DISTINCT FROM v_sentence
    AND v_old.due_date IS NOT DISTINCT FROM p_new_due_date THEN
   RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_task_text_date_amend_v1',
    'taskId',v_old.id,'sentence',v_old.sentence,'dueDate',v_old.due_date,
    'amendmentRevision',v_old.amendment_revision,'changed',false,'idempotent',true,
    'oneOriginalTaskId',true,'noInstitutionalWorkChanged',true);
 END IF;
 UPDATE atlas.task_entries t
 SET sentence=v_sentence,due_date=p_new_due_date,
     amendment_revision=v_old.amendment_revision+1
 WHERE t.id=v_old.id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal
 RETURNING * INTO v_new;
 IF v_new.id IS NULL THEN
   RAISE EXCEPTION 'Original task write unavailable' USING ERRCODE='PT409';
 END IF;
 INSERT INTO atlas.personal_task_amendment_events_v1 (
  task_id,owner_user_id,principal_id,before_sentence,after_sentence,
  before_due_date,after_due_date,before_revision,after_revision)
 VALUES (v_old.id,v_old.owner_user_id,v_old.principal_id,
  v_old.sentence,v_new.sentence,v_old.due_date,v_new.due_date,
  v_old.amendment_revision,v_new.amendment_revision)
 RETURNING id INTO v_event;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','personal_task_text_date_amend_v1',
  'taskId',v_new.id,'sentence',v_new.sentence,
  'oldDueDate',v_old.due_date,'dueDate',v_new.due_date,
  'amendmentRevision',v_new.amendment_revision,'changed',true,'idempotent',false,
  'amendmentEventId',v_event,'oneOriginalTaskId',true,
  'noInstitutionalWorkChanged',true);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.personal_archived_tasks_day_self_api_v1(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Signed-in original owner required.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'archivedAt',t.archived_at,'institutionalWorkItemId',w.id)
    order by t.archived_at desc,t.id),'[]'::jsonb) into v_items
  from atlas.task_entries t
  left join lateral (
    select id from atlas.work_items w
    where w.source_object_type='personal_dated_task'
      and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
  ) w on true
  where t.owner_user_id=auth.uid() and t.principal_id=v_principal
    and t.due_date IS NOT DISTINCT FROM p_date and t.archived_at is not null;
  return jsonb_build_object('ok',true,
    'contractVersion','personal_task_archive_day_v1',
    'date',p_date,'items',v_items);
end
$function$;

COMMIT;

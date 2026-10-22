-- Build 5: personal Today task Trash, separate from institutional Work.
-- The original entry remains durable; its date page no longer projects it.
BEGIN;

ALTER TABLE atlas.task_entries
  ADD COLUMN deleted_at timestamptz;
CREATE INDEX task_entries_visible_owner_day_v1
  ON atlas.task_entries(owner_user_id,due_date,id)
  WHERE deleted_at IS NULL;

CREATE TABLE atlas.personal_task_trash_decisions_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL,
  principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  task_entry_id uuid NOT NULL UNIQUE REFERENCES atlas.task_entries(id) ON DELETE RESTRICT,
  original_task_snapshot jsonb NOT NULL,
  trashed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE atlas.personal_task_trash_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.personal_task_trash_decisions_v1
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE atlas.personal_task_trash_decisions_v1 TO service_role;

-- A removed personal source cannot later be promoted into new Company Work.
CREATE OR REPLACE FUNCTION atlas.guard_deleted_personal_task_promotion_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF new.source_object_type='personal_dated_task'
     AND new.source_object_id IS NOT NULL AND EXISTS(
       SELECT 1 FROM atlas.task_entries t
       WHERE t.id=new.source_object_id AND t.deleted_at IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Deleted personal task cannot be promoted into Company Work'
      USING ERRCODE='23514';
  END IF;
  RETURN new;
END;
$fn$;
CREATE TRIGGER guard_deleted_personal_task_promotion_v1
  BEFORE INSERT OR UPDATE OF source_object_type,source_object_id
  ON atlas.work_items FOR EACH ROW
  EXECUTE FUNCTION atlas.guard_deleted_personal_task_promotion_v1();

CREATE OR REPLACE FUNCTION atlas.delete_atlas_task_self_api_v1(
  p_task_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%ROWTYPE;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_task_id IS NULL THEN
    RAISE EXCEPTION 'Sign in and select a task' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_task FROM atlas.task_entries
    WHERE id=p_task_id AND owner_user_id=auth.uid()
      AND principal_id=v_principal FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Personal task not found' USING ERRCODE='42501';
  END IF;
  IF v_task.deleted_at IS NOT NULL THEN
    SELECT id INTO v_id FROM atlas.personal_task_trash_decisions_v1
      WHERE task_entry_id=v_task.id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Task Trash evidence missing' USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object('ok',true,'contractVersion','personal_task_trash_v1',
      'state','already_trashed','taskId',v_task.id,'trashDecisionId',v_id);
  END IF;
  IF EXISTS (SELECT 1 FROM atlas.work_items w
       WHERE w.source_object_type='personal_dated_task'
         AND w.source_object_id=v_task.id) THEN
    RAISE EXCEPTION 'This task belongs to Company Work; delete through its Ledger'
      USING ERRCODE='23514';
  END IF;
  INSERT INTO atlas.personal_task_trash_decisions_v1(
    owner_user_id,principal_id,task_entry_id,original_task_snapshot
  ) VALUES (auth.uid(),v_principal,v_task.id,to_jsonb(v_task))
  RETURNING id INTO v_id;
  UPDATE atlas.task_entries SET deleted_at=now()
    WHERE id=v_task.id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Personal task deletion not confirmed' USING ERRCODE='40001';
  END IF;
  RETURN jsonb_build_object('ok',true,'contractVersion','personal_task_trash_v1',
    'state','trashed','taskId',v_task.id,'trashDecisionId',v_id,
    'originalEvidencePreserved',true,'workCreated',false,'completed',false);
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.delete_atlas_task_self_api_v1(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.delete_atlas_task_self_api_v1(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.personal_task_trash_self_api_v1(
  p_limit integer DEFAULT 100
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
BEGIN
  IF auth.uid() IS NULL OR p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION 'Sign in and choose a valid Trash page limit' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_task_trash_v1',
    'items',coalesce((
      SELECT jsonb_agg(row_data ORDER BY trashed_at DESC,task_entry_id)
      FROM (SELECT d.task_entry_id,d.trashed_at,
        jsonb_build_object('taskId',d.task_entry_id,
          'sentence',t.sentence,'dueDate',t.due_date,
          'trashedAt',d.trashed_at,'sourceEvidencePreserved',true) row_data
        FROM atlas.personal_task_trash_decisions_v1 d
        JOIN atlas.task_entries t ON t.id=d.task_entry_id
        WHERE d.owner_user_id=auth.uid() AND d.principal_id=v_principal
        ORDER BY d.trashed_at DESC,d.task_entry_id LIMIT p_limit) x
    ),'[]'::jsonb));
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_trash_self_api_v1(integer)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.personal_task_trash_self_api_v1(integer)
  TO authenticated;

-- Retain all existing client fields; exclude only owner-deleted source rows.
CREATE OR REPLACE FUNCTION atlas.atlas_task_day_self_api_v1(p_date date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog','atlas','auth'
AS $fn$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_rows jsonb;
BEGIN
  IF p_date IS NULL THEN RAISE EXCEPTION 'Date required.' USING ERRCODE='22023'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'institutionalWorkItemId',wi.id,
    'institutionalWorkState',wi.work_state,
    'institutionalTransfer',wi.id IS NOT NULL
  )) ORDER BY CASE WHEN t.status='open' THEN 0 ELSE 1 END,t.created_at,t.id),'[]'::jsonb)
  INTO v_rows
  FROM atlas.task_entries t
  LEFT JOIN LATERAL (
    SELECT w.id,w.work_state FROM atlas.work_items w
    WHERE w.source_object_type='personal_dated_task'
      AND w.source_object_id=t.id
    ORDER BY w.created_at,w.id LIMIT 1
  ) wi ON true
  WHERE t.owner_user_id=auth.uid()
    AND t.principal_id=v_principal AND t.due_date=p_date
    AND t.deleted_at IS NULL;
  RETURN jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
END
$fn$;

-- Explicitly refuse completion of a source already deleted from the log.
CREATE OR REPLACE FUNCTION atlas.set_atlas_task_done_self_api_v1(
  p_task_id uuid,p_done boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','atlas','auth'
AS $fn$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%ROWTYPE;
BEGIN
  IF p_task_id IS NULL OR p_done IS NULL THEN
    RAISE EXCEPTION 'Task and completion state required.' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_task FROM atlas.task_entries t
  WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
    AND t.principal_id=v_principal AND t.deleted_at IS NULL FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Active task not found.' USING ERRCODE='42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM atlas.work_items w
    WHERE w.source_object_type='personal_dated_task'
      AND w.source_object_id=v_task.id
  ) THEN
    RAISE EXCEPTION 'Transferred Company Work cannot be completed as a personal dated task.'
      USING ERRCODE='23514';
  END IF;
  UPDATE atlas.task_entries
    SET status=CASE WHEN p_done THEN 'done' ELSE 'open' END,
        completed_at=CASE WHEN p_done THEN now() ELSE NULL END
  WHERE id=p_task_id AND owner_user_id=auth.uid()
    AND principal_id=v_principal AND deleted_at IS NULL
  RETURNING * INTO v_task;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Active task not found.' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.delete_atlas_task_self_api_v1(
  p_task_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.delete_atlas_task_self_api_v1(p_task_id); $fn$;
REVOKE ALL ON FUNCTION public.delete_atlas_task_self_api_v1(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_atlas_task_self_api_v1(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.personal_task_trash_self_api_v1(
  p_limit integer DEFAULT 100
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.personal_task_trash_self_api_v1(p_limit); $fn$;
REVOKE ALL ON FUNCTION public.personal_task_trash_self_api_v1(integer)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.personal_task_trash_self_api_v1(integer) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
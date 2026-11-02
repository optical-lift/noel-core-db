-- Source-only candidate: atlas_ lane, never apply as live SQL.
BEGIN;
ALTER TABLE atlas.task_entries ADD COLUMN amendment_revision bigint NOT NULL DEFAULT 0;
ALTER TABLE atlas.task_entries ADD CONSTRAINT task_entries_amendment_revision_nonnegative
  CHECK (amendment_revision >= 0);
CREATE TABLE atlas.personal_task_amendment_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 task_id uuid NOT NULL REFERENCES atlas.task_entries(id) ON DELETE CASCADE,
 owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 before_sentence text NOT NULL,after_sentence text NOT NULL,
 before_due_date date NOT NULL,after_due_date date NOT NULL,
 before_revision bigint NOT NULL,after_revision bigint NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK (before_sentence IS DISTINCT FROM after_sentence
        OR before_due_date IS DISTINCT FROM after_due_date),
 CHECK (after_revision=before_revision+1 AND before_revision>=0)
);
CREATE INDEX personal_task_amendment_events_original_v1
 ON atlas.personal_task_amendment_events_v1(task_id,recorded_at,id);
ALTER TABLE atlas.personal_task_amendment_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_task_amendment_events_v1 FROM PUBLIC,anon,authenticated;
-- UPDATE of an event is disallowed. DELETE through ON DELETE CASCADE is
-- intentional: permanent deletion of the source also removes private history.
CREATE FUNCTION atlas.prevent_personal_task_amendment_update_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
 RAISE EXCEPTION 'Task amendment event cannot be rewritten' USING ERRCODE='42501';
END
$fn$;
CREATE TRIGGER personal_task_amendment_unchangeable_v1
 BEFORE UPDATE ON atlas.personal_task_amendment_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.prevent_personal_task_amendment_update_v1();
REVOKE ALL ON FUNCTION atlas.prevent_personal_task_amendment_update_v1()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.read_personal_task_text_date_self_api_v1(p_task_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid := atlas.require_active_task_principal_v1();
 v_task atlas.task_entries%ROWTYPE;
 v_linked boolean;
BEGIN
 IF p_task_id IS NULL THEN
   RAISE EXCEPTION 'Exact task required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_task FROM atlas.task_entries t
 WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned task unavailable' USING ERRCODE='42501';
 END IF;
 SELECT EXISTS(SELECT 1 FROM atlas.work_items w
  WHERE w.source_object_type='personal_dated_task'
    AND w.source_object_id=v_task.id) INTO v_linked;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','personal_task_text_date_read_v1',
  'taskId',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
  'status',v_task.status,'amendmentRevision',v_task.amendment_revision,
  'archived',v_task.archived_at IS NOT NULL,'linkedCompanyWork',v_linked,
  'canEdit',v_task.status='open' AND v_task.archived_at IS NULL AND NOT v_linked,
  'oneOriginalTaskId',true);
END
$fn$;

CREATE FUNCTION atlas.amend_personal_task_text_date_self_api_v1(
 p_task_id uuid,p_expected_revision bigint,p_new_sentence text,p_new_due_date date
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid := atlas.require_active_task_principal_v1();
 v_old atlas.task_entries%ROWTYPE;
 v_new atlas.task_entries%ROWTYPE;
 v_sentence text := btrim(coalesce(p_new_sentence,''));
 v_event uuid;
BEGIN
 IF p_task_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
   OR p_new_due_date IS NULL OR char_length(v_sentence) NOT BETWEEN 1 AND 500 THEN
   RAISE EXCEPTION 'Exact task, revision, text and date required' USING ERRCODE='22023';
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
   RAISE EXCEPTION 'Task changed; read again before editing' USING ERRCODE='40001';
 END IF;
 IF v_old.sentence IS NOT DISTINCT FROM v_sentence
    AND v_old.due_date IS NOT DISTINCT FROM p_new_due_date THEN
   RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_task_text_date_amend_v1',
    'taskId',v_old.id,'sentence',v_old.sentence,'dueDate',v_old.due_date,
    'amendmentRevision',v_old.amendment_revision,'changed',false,
    'oneOriginalTaskId',true,'noInstitutionalWorkChanged',true);
 END IF;
 UPDATE atlas.task_entries t
 SET sentence=v_sentence,due_date=p_new_due_date,
     amendment_revision=v_old.amendment_revision+1
 WHERE t.id=v_old.id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal
 RETURNING * INTO v_new;
 IF v_new.id IS NULL THEN
   RAISE EXCEPTION 'Original task write unavailable' USING ERRCODE='40001';
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
  'amendmentRevision',v_new.amendment_revision,'changed',true,
  'amendmentEventId',v_event,'oneOriginalTaskId',true,
  'noInstitutionalWorkChanged',true);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.read_personal_task_text_date_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.read_personal_task_text_date_self_api_v1(uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)
 TO authenticated;

CREATE FUNCTION public.read_personal_task_text_date_self_api_v1(p_task_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.read_personal_task_text_date_self_api_v1(p_task_id);
$fn$;
CREATE FUNCTION public.amend_personal_task_text_date_self_api_v1(
 p_task_id uuid,p_expected_revision bigint,p_new_sentence text,p_new_due_date date
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.amend_personal_task_text_date_self_api_v1(
  p_task_id,p_expected_revision,p_new_sentence,p_new_due_date);
$fn$;
REVOKE ALL ON FUNCTION public.read_personal_task_text_date_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_personal_task_text_date_self_api_v1(uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)
 TO authenticated;
COMMIT;

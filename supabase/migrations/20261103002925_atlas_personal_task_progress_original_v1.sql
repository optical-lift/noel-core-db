-- Source-only Atlas original personal-task progress; no production release.
BEGIN;

CREATE TABLE atlas.personal_task_progress_events_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES atlas.task_entries(id) ON DELETE CASCADE,
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  source_action_id uuid NOT NULL,
  note text NOT NULL CHECK (char_length(note) BETWEEN 1 AND 2000 AND note=btrim(note)),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT personal_task_progress_owner_action_v1 UNIQUE(owner_user_id,source_action_id)
);
CREATE INDEX personal_task_progress_original_order_v1
  ON atlas.personal_task_progress_events_v1(task_id,recorded_at DESC,id DESC);
ALTER TABLE atlas.personal_task_progress_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_task_progress_events_v1 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.prevent_personal_task_progress_rewrite_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
 RAISE EXCEPTION 'Recorded original progress cannot be rewritten' USING ERRCODE='42501';
END
$fn$;
CREATE TRIGGER personal_task_progress_immutable_v1
  BEFORE UPDATE ON atlas.personal_task_progress_events_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.prevent_personal_task_progress_rewrite_v1();
REVOKE ALL ON FUNCTION atlas.prevent_personal_task_progress_rewrite_v1()
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.append_personal_task_progress_self_api_v1(
 p_task_id uuid,p_source_action_id uuid,p_note text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_task atlas.task_entries%ROWTYPE;
 v_text text:=btrim(coalesce(p_note,''));
 v_prior atlas.personal_task_progress_events_v1%ROWTYPE;
 v_inserted atlas.personal_task_progress_events_v1%ROWTYPE;
BEGIN
 IF p_task_id IS NULL OR p_source_action_id IS NULL
   OR char_length(v_text) NOT BETWEEN 1 AND 2000 THEN
   RAISE EXCEPTION 'Exact original, action and 1–2000 character note required'
     USING ERRCODE='22023';
 END IF;
 -- This lock serializes progress against promotion and completion of the
 -- same original, so we never append to obsolete personal execution custody.
 SELECT * INTO v_task FROM atlas.task_entries t
 WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned original personal task unavailable'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.personal_task_progress_events_v1 e
 WHERE e.owner_user_id=auth.uid() AND e.source_action_id=p_source_action_id;
 IF FOUND THEN
   IF v_prior.task_id=v_task.id AND v_prior.principal_id=v_principal
     AND v_prior.note=v_text THEN
     RETURN jsonb_build_object(
       'ok',true,'contractVersion','personal_task_progress_append_v1',
       'taskId',v_task.id,'progressId',v_prior.id,'recordedAt',v_prior.recorded_at,
       'note',v_prior.note,'idempotent',true,
       'oneOriginalTaskId',true,'noInstitutionalWorkChanged',true);
   END IF;
   RAISE EXCEPTION 'Action already used for a different original or note'
     USING ERRCODE='PT409';
 END IF;
 IF v_task.status<>'open' OR v_task.archived_at IS NOT NULL THEN
   RAISE EXCEPTION 'Progress requires one open, unarchived original'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_items w
   WHERE w.source_object_type='personal_dated_task'
     AND w.source_object_id=v_task.id) THEN
   RAISE EXCEPTION 'Company Work retains execution custody'
     USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.personal_task_progress_events_v1
   (task_id,owner_user_id,principal_id,source_action_id,note)
 VALUES (v_task.id,v_task.owner_user_id,v_principal,p_source_action_id,v_text)
 RETURNING * INTO v_inserted;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','personal_task_progress_append_v1',
   'taskId',v_task.id,'progressId',v_inserted.id,
   'recordedAt',v_inserted.recorded_at,'note',v_inserted.note,
   'idempotent',false,'oneOriginalTaskId',true,
   'noInstitutionalWorkChanged',true);
END
$fn$;

CREATE FUNCTION atlas.read_personal_task_progress_self_api_v1(
 p_task_id uuid,p_limit integer DEFAULT 50,
 p_before_recorded_at timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_task atlas.task_entries%ROWTYPE;
 v_rows jsonb;
 v_more boolean;
 v_count integer;
BEGIN
 IF p_task_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
    OR ((p_before_recorded_at IS NULL)<>(p_before_id IS NULL)) THEN
    RAISE EXCEPTION 'Exact original, bounded page and complete cursor required'
      USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_task FROM atlas.task_entries t
 WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned original personal task unavailable'
     USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'progressId',q.id,'note',q.note,'recordedAt',q.recorded_at
 ) ORDER BY q.recorded_at DESC,q.id DESC),'[]'::jsonb)
 INTO v_rows
 FROM (
   SELECT e.id,e.note,e.recorded_at FROM atlas.personal_task_progress_events_v1 e
   WHERE e.task_id=v_task.id AND e.owner_user_id=auth.uid()
     AND e.principal_id=v_principal
     AND (p_before_recorded_at IS NULL
       OR (e.recorded_at,e.id)<(p_before_recorded_at,p_before_id))
   ORDER BY e.recorded_at DESC,e.id DESC LIMIT p_limit+1
 ) q;
 v_count:=jsonb_array_length(v_rows);
 v_more:=v_count>p_limit;
 IF v_more THEN
   SELECT coalesce(jsonb_agg(x.value ORDER BY x.ordinality),'[]'::jsonb)
     INTO v_rows
   FROM jsonb_array_elements(v_rows) WITH ORDINALITY x(value,ordinality)
   WHERE x.ordinality<=p_limit;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','personal_task_progress_read_v1',
   'taskId',v_task.id,'items',v_rows,'hasMore',v_more,
   'nextCursor',CASE WHEN v_more THEN
      jsonb_build_object('beforeRecordedAt',
        v_rows->(jsonb_array_length(v_rows)-1)->>'recordedAt',
        'beforeId',v_rows->(jsonb_array_length(v_rows)-1)->>'progressId')
     ELSE NULL END,
   'oneOriginalTaskId',true);
END
$fn$;

REVOKE ALL ON FUNCTION atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.read_personal_task_progress_self_api_v1(uuid,integer,timestamptz,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.read_personal_task_progress_self_api_v1(uuid,integer,timestamptz,uuid)
 TO authenticated;

CREATE FUNCTION public.append_personal_task_progress_self_api_v1(
 p_task_id uuid,p_source_action_id uuid,p_note text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.append_personal_task_progress_self_api_v1(
    p_task_id,p_source_action_id,p_note);
$fn$;
CREATE FUNCTION public.read_personal_task_progress_self_api_v1(
 p_task_id uuid,p_limit integer DEFAULT 50,
 p_before_recorded_at timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.read_personal_task_progress_self_api_v1(
    p_task_id,p_limit,p_before_recorded_at,p_before_id);
$fn$;
REVOKE ALL ON FUNCTION public.append_personal_task_progress_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.read_personal_task_progress_self_api_v1(uuid,integer,timestamptz,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.append_personal_task_progress_self_api_v1(uuid,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.read_personal_task_progress_self_api_v1(uuid,integer,timestamptz,uuid)
 TO authenticated;
COMMIT;

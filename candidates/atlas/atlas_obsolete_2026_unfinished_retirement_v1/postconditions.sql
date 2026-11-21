-- HELD TEST ONLY: exact post-retirement clone result; source DML was tested
-- on a disposable schema clone. No live physical work is completed here.
DO $held_retirement_post$
DECLARE
  v_queue_count integer;
  v_active_queue integer;
  v_unfinished_occ integer;
  v_linked_open_tasks integer;
  v_archived_tasks integer;
  v_terminal_released_occ integer;
  v_work_count integer;
  v_requirement_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE state IN ('active','queued'))
    INTO v_queue_count,v_active_queue
  FROM atlas.task_release_queue_items;
  SELECT count(*) INTO v_unfinished_occ
  FROM atlas.task_release_queue_items q
  JOIN atlas.planned_work_occurrences o ON o.id=q.planned_occurrence_id
  WHERE o.state IN ('planned','eligible');
  SELECT count(*) INTO v_linked_open_tasks
  FROM atlas.task_release_queue_items q
  JOIN atlas.tasks t ON t.id=q.task_id
  WHERE t.status IN ('open','blocked');
  SELECT count(*) INTO v_archived_tasks
  FROM atlas.tasks t
  WHERE t.id IN (
    'e05f3870-7c74-47d5-9998-483aa238f115'::uuid,
    'd1bb49af-667f-47e6-b03b-06d75c6e93e6'::uuid,
    '63ade0e9-28bc-4543-805f-d2c82d678315'::uuid
  )
  AND t.status='archived' AND t.completed_at IS NULL;
  SELECT count(*) INTO v_terminal_released_occ
  FROM atlas.planned_work_occurrences o
  JOIN atlas.tasks t ON t.id=o.released_task_id
  WHERE o.id IN (
    '5d6123f4-ba5d-43c6-9185-816143bcc754'::uuid,
    '70909d03-21f8-4d22-975c-bff8a428f8be'::uuid
  )
  AND o.state='cancelled'
  AND o.metadata->>'terminal_task_status'='archived'
  AND o.metadata->>'terminal_task_id'=t.id::text
  AND t.status='archived' AND t.completed_at IS NULL;
  SELECT count(*) INTO v_work_count FROM atlas.work_items;
  SELECT count(*) INTO v_requirement_count FROM atlas.work_requirements;
  IF v_queue_count<>97 OR v_active_queue<>0 OR v_unfinished_occ<>0
     OR v_linked_open_tasks<>0 OR v_archived_tasks<>3 OR v_terminal_released_occ<>2
     OR v_work_count=0 THEN
    RAISE EXCEPTION 'Historical unfinished clone retirement failed: source or Work postconditions';
  END IF;
  RAISE NOTICE 'PASS disposable 97-row legacy queue: 0 open pointers, 0 unfinished linked occurrences, 0 linked open historical Tasks, 3 archived without Done; canonical Work remains.';
END
$held_retirement_post$;

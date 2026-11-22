-- HELD fictional data only, for existing Noel genuine signed PG17 clone.
-- Apply only AFTER trusted canonical signed C1 Organization fixture in disposable clone.
-- No live Personal, Task, occurrence, row IDs or source data ever imported.
SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=0
 AND EXISTS(SELECT 1 FROM atlas.organizations WHERE id='e5200000-0000-4000-8000-000000000801'::uuid)
 AND to_regprocedure('atlas.capture_anna_weeding_serial_queue_v1()') IS NOT NULL
 AND to_regprocedure('atlas.enqueue_new_field_row_weeding_task_v1()') IS NOT NULL
 THEN 1 ELSE 0 END) AS fictional_anna_two_roots_preflight;

INSERT INTO atlas.farms(id,organization_id,stable_key,name,status)
VALUES ('f9400000-0000-4000-8000-000000000006',
        'e5200000-0000-4000-8000-000000000801',
        'fictional-anna-old-rotation-2026',
        'FICTIONAL historical Anna and field-weeding queue',
        'active');

INSERT INTO atlas.task_release_queue_items(farm_id,queue_key,position,state,initial_batch,metadata)
SELECT 'f9400000-0000-4000-8000-000000000006'::uuid,
 CASE WHEN n<=34 THEN 'anna_weeding_rotation'
      WHEN n<=38 THEN 'field_rows_weeding_rotation'
      ELSE 'fictional-other-terminal-history-2026' END,
 n,
 CASE WHEN n BETWEEN 1 AND 7 OR n BETWEEN 35 AND 36 OR n BETWEEN 39 AND 44
      THEN 'completed' ELSE 'skipped' END,
 false, jsonb_build_object('fixtureOnly',true,'historicalEvidence','fictional-no-live-identities')
FROM generate_series(1,97) n;

SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=97
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')=15
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')=82
 AND NOT EXISTS(SELECT 1 FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='completed')=7
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_weeding_rotation' AND state='skipped')=27
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='completed')=2
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='field_rows_weeding_rotation' AND state='skipped')=2
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE task_id IS NOT NULL OR planned_occurrence_id IS NOT NULL)=0
 THEN 1 ELSE 0 END) AS fictional_terminal_anna_weeding_history;

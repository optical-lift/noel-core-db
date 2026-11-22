-- HELD fictional fixture, disposable Noel current-schema PG17 clone ONLY.
-- Apply only after Noel's trusted original C1 Auth/Organization synthetic fixture.
-- No production, Person, Task, occurrence, or historical queue data is copied.
SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=0
 AND EXISTS (SELECT 1 FROM atlas.organizations WHERE id='e5200000-0000-4000-8000-000000000801'::uuid)
 AND to_regprocedure('atlas.advance_pot_up_serial_queue_v1()') IS NOT NULL
 AND to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NOT NULL
 THEN 1 ELSE 0 END) AS synthetic_pot_up_source_preflight;

INSERT INTO atlas.farms(id,organization_id,stable_key,name,status)
VALUES(
 'f9400000-0000-4000-8000-000000000004',
 'e5200000-0000-4000-8000-000000000801',
 'fictional-old-pot-up-serial-2026',
 'FICTIONAL pot-up Task-release history',
 'active'
);

INSERT INTO atlas.task_release_queue_items(
 farm_id,queue_key,position,state,initial_batch,metadata
)
SELECT
 'f9400000-0000-4000-8000-000000000004'::uuid,
 CASE WHEN n<=9 THEN 'anna_pot_up_serial' ELSE 'fictional-other-terminal-history-2026' END,
 n,
 CASE WHEN n<=4 OR n BETWEEN 10 AND 87 THEN 'skipped' ELSE 'completed' END,
 false,
 jsonb_build_object('fixtureOnly',true,'originalHistory','fictional-no-live-identities')
FROM generate_series(1,97) n;

SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=97
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')=82
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')=15
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))=0
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='completed')=5
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE queue_key='anna_pot_up_serial' AND state='skipped')=4
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE task_id IS NOT NULL OR planned_occurrence_id IS NOT NULL)=0
 THEN 1 ELSE 0 END) AS fictional_terminal_pot_up_history_check;

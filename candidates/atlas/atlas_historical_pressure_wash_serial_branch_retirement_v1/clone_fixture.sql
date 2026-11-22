-- HELD: fictional, disposable current-production-schema PG17 clone ONLY.
-- Requires Noel's ORIGINAL trusted C1 Auth/Organization fixture first.
-- Reuses the existing historical 97-row queue shape, not real owner/worker
-- identities, task identities, notes, personal data or observed physical work.
-- No live/production queue rows are copied or changed.
SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=0
 AND EXISTS (SELECT 1 FROM atlas.organizations
   WHERE id='e5200000-0000-4000-8000-000000000801'::uuid)
 AND to_regprocedure('atlas.advance_gentle_pressure_wash_serial_queue_v1()') IS NOT NULL
 AND to_regprocedure('atlas.sync_task_release_queue_summary_v1(uuid,text)') IS NOT NULL
 THEN 1 ELSE 0 END) AS synthetic_pressure_wash_source_preflight;

INSERT INTO atlas.farms(id,organization_id,stable_key,name,status)
VALUES (
 'f9300000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000801',
 'synthetic-old-pressure-wash-serial-2026',
 'FICTIONAL pressure-wash release source',
 'active'
);

INSERT INTO atlas.task_release_queue_items(
 farm_id,queue_key,position,state,initial_batch,metadata
)
SELECT
 'f9300000-0000-4000-8000-000000000003'::uuid,
 CASE WHEN n<=5 THEN 'anna_gentle_pressure_wash_aug_2026'
      ELSE 'fictional-other-terminal-history-2026' END,
 n,
 CASE WHEN n<=82 THEN 'skipped' ELSE 'completed' END,
 false,
 jsonb_build_object('fixtureOnly',true,'originalHistory','fictional-no-live-ids')
FROM generate_series(1,97) AS n;

SELECT 1/(CASE WHEN
 (SELECT count(*) FROM atlas.task_release_queue_items)=97
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')=82
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')=15
 AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN ('active','queued'))=0
 AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE queue_key='anna_gentle_pressure_wash_aug_2026' AND state='skipped')=5
 AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE task_id IS NOT NULL OR planned_occurrence_id IS NOT NULL)=0
 THEN 1 ELSE 0 END) AS fictional_terminal_pressure_wash_history_check;

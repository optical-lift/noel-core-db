-- HELD DATA-ONLY SYNTHETIC protected-clone fixture, not production data.
-- Original Noel signed C1 source/denial fixture installs first. The live schema
-- snapshot source must supply the exact old functions; this fixture models only
-- 97 terminal historical queue rows (34 Anna-keyed), with no real identifiers.
SELECT 1 / (CASE WHEN
  (SELECT count(*) FROM atlas.task_release_queue_items)=0
  AND EXISTS (SELECT 1 FROM atlas.organizations
    WHERE id='e5200000-0000-4000-8000-000000000801'::uuid)
  AND NOT EXISTS (SELECT 1 FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgfoid=to_regprocedure('atlas.advance_anna_weeding_serial_queue_v1()'))
  THEN 1 ELSE 0 END) AS synthetic_anna_orphan_fixture_preflight;

INSERT INTO atlas.farms(id,organization_id,stable_key,name,status)
VALUES (
  'f9300000-0000-4000-8000-000000000002',
  'e5200000-0000-4000-8000-000000000801',
  'synthetic-anna-legacy-queue-retirement-2026',
  'SYNTHETIC SOURCE-ONLY legacy queue site',
  'active'
);

INSERT INTO atlas.task_release_queue_items(
  farm_id,queue_key,position,state,initial_batch,metadata
)
SELECT
  'f9300000-0000-4000-8000-000000000002'::uuid,
  CASE WHEN n<=34 THEN 'anna_weeding_rotation'
    ELSE 'synthetic-other-history-2026' END,
  n,
  CASE WHEN n<=82 THEN 'skipped' ELSE 'completed' END,
  false,
  jsonb_build_object('fixtureOnly',true,'historicalSource','synthetic-no-live-ids')
FROM generate_series(1,97) AS n;

SELECT 1 / (CASE WHEN
  (SELECT count(*) FROM atlas.task_release_queue_items)=97
  AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE queue_key='anna_weeding_rotation')=34
  AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE state='skipped')=82
  AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE state='completed')=15
  AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE state IN ('active','queued'))=0
  AND (SELECT count(*) FROM atlas.task_release_queue_items
    WHERE task_id IS NOT NULL OR planned_occurrence_id IS NOT NULL)=0
  THEN 1 ELSE 0 END) AS synthetic_anna_terminal_history_check;

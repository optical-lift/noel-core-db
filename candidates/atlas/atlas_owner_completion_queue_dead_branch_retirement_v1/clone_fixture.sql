-- HELD FICTIONAL, DISPOSABLE current-schema clone ONLY.
-- Original C1 signed fixture is installed by Noel's existing source-verified
-- protected harness BEFORE this scoped history fixture. No live row copied.
-- The old owner-completion release trigger was already retired in the
-- independent installed historical-queue progression trigger migration.
-- Exactly 97 historical queue keys (82 skipped, 15 completed); none active.
-- This models the *aggregate* real post-cleanup state, not source identities,
-- a physical Done, live Work, need, or user/person/permission record.

-- DATA-ONLY source-positive preflight; any mismatch fails with
-- division-by-zero inside this isolated test fixture, no procedural SQL.
SELECT 1 / (CASE WHEN
  (SELECT count(*) FROM atlas.task_release_queue_items)=0
  AND EXISTS (
    SELECT 1 FROM atlas.organizations
    WHERE id='e5200000-0000-4000-8000-000000000801'::uuid
  )
  AND NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.tasks'::regclass
      AND t.tgname='advance_owner_completion_gated_queue_v1'
      AND NOT t.tgisinternal
  )
  THEN 1 ELSE 0 END) AS fictional_original_c1_queue_preflight;

INSERT INTO atlas.farms(id,organization_id,stable_key,name,status)
VALUES (
 'f9300000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000801',
 'test-only-historical-owner-queue-farm-2026',
 'FICTIONAL test-only retired queue farm',
 'active'
);

INSERT INTO atlas.task_release_queue_items(
 farm_id,queue_key,position,state,initial_batch,metadata
)
SELECT
 'f9300000-0000-4000-8000-000000000001'::uuid,
 'fictional-owner-queue-retired-2026-v1',
 n,
 CASE WHEN n<=82 THEN 'skipped' ELSE 'completed' END,
 false,
 jsonb_build_object('fixtureOnly',true,'historicalSource','fictional-no-live-ids')
FROM generate_series(1,97) AS n;

-- DATA-ONLY positive/negative check of *fictional* historical state.
SELECT 1 / (CASE WHEN
  (SELECT count(*) FROM atlas.task_release_queue_items)=97
  AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='skipped')=82
  AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state='completed')=15
  AND (SELECT count(*) FROM atlas.task_release_queue_items WHERE state IN('active','queued'))=0
  AND (SELECT count(*) FROM atlas.task_release_queue_items
       WHERE task_id IS NOT NULL OR planned_occurrence_id IS NOT NULL)=0
  THEN 1 ELSE 0 END) AS fictional_terminal_queue_fixture_check;

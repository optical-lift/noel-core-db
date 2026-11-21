-- HELD SOURCE ONLY V2: owner-adjudicated withdrawal of obsolete 2026 unfinished queue.
-- V1 production release 20261121184327 failed closed at final no-loss guard;
-- this is a NEW source candidate and is NOT an amendment or replay of V1.
-- Additional source-positive live fact: two active prerequisite links from
-- these old Tasks, both require real DONE, both remain unsatisfied, to two
-- independent still-blocked/deferred-hidden Tasks. Their physical requirements
-- are neither satisfied nor retired by archiving the obsolete sources.
-- Not a production migration. Do not run directly on Supabase.
-- Canonical source / authorization: optical-lift/atlas#532 (Package B).
-- This does not declare any physical result, complete any Work, or disable a
-- shared Rulebook/release policy. It retires old schedule authority only.
--
-- Read-only production inventory (2026-11-21):
-- The two original released occurrence links are explicitly retired within
-- this migration; suppress the legacy terminal trigger's otherwise unavoidable
-- FARM-WIDE release sweep only for the three Task archive transitions.
-- Other Task guards remain active; the prior setting is restored immediately.
-- Two released original Task-backed occurrences are deliberately allowed
-- to retire through their existing terminal-Task trigger. All other historical
-- source rows remain unchanged, and the 64 old planned/eligible are cancelled
-- directly. The operation never attests to physical completion.
-- 97 historical queue rows, exactly seven historical queue keys;
-- 64 queued-linked occurrences planned(62)/eligible(2), none with a
-- released_task_id, current canonical Work or active adapters/children;
-- 75 queue pointers still active(7)/queued(68);
-- 3 old tasks open(2)/blocked(1), all previously owner adjudicated.
-- The separate Field Row 9 Navy bean crop is not claimed cleared or ready.
--
-- This source intentionally uses exact before-state digests and all-table
-- fingerprints for unaffected Task/occurrence/queue rows plus canonical
-- Work and Work Requirements. Any drift or triggered non-target mutation
-- aborts the whole transaction. Production requires separate exact approval.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

DO $historical_retirement$
DECLARE
    v_occ_ids uuid[];
    -- Two original released occurrences will be cancelled by the existing
    -- Task-terminal trigger when their old execution Tasks are archived.
    v_released_occ_ids uuid[] := ARRAY[
      '5d6123f4-ba5d-43c6-9185-816143bcc754'::uuid,
      '70909d03-21f8-4d22-975c-bff8a428f8be'::uuid
    ];
    v_guarded_occ_ids uuid[];
    v_queue_ids uuid[];
    v_task_ids uuid[] := ARRAY[
      'e05f3870-7c74-47d5-9998-483aa238f115'::uuid,
      'd1bb49af-667f-47e6-b03b-06d75c6e93e6'::uuid,
      '63ade0e9-28bc-4543-805f-d2c82d678315'::uuid
    ];
    v_before_queue_count integer;
    v_before_occ_count integer;
    v_before_task_count integer;
    v_queue_fp text;
    v_occ_fp text;
    v_task_fp text;
    v_work_fp text;
    v_requirements_fp text;
    v_unaffected_tasks_fp text;
    v_unaffected_occ_fp text;
    v_unaffected_queue_fp text;
    v_capacity_profiles_count integer;
    v_unaffected_capacity_fp text;
    v_changed integer;
    v_prior_reservoir_flag text;
    v_source_prerequisite_count integer;
BEGIN
    LOCK TABLE atlas.tasks, atlas.planned_work_occurrences,
      atlas.task_release_queue_items IN SHARE ROW EXCLUSIVE MODE;

    IF (SELECT count(*) FROM atlas.task_release_queue_items) <> 97
       OR EXISTS (
         SELECT 1 FROM atlas.task_release_queue_items q
         WHERE q.queue_key NOT IN (
           'anna_gentle_pressure_wash_aug_2026',
           'anna_pot_up_serial',
           'anna_soil_block_1_5_sequence',
           'anna_weeding_rotation',
           'field_rows_weeding_rotation',
           'owner_social_content_queue',
           'owner_venue_marketing_queue'
         )
       ) THEN
      RAISE EXCEPTION 'Legacy queue identity drift; no retirement performed';
    END IF;

    SELECT array_agg(DISTINCT o.id ORDER BY o.id) INTO v_occ_ids
    FROM atlas.task_release_queue_items q
    JOIN atlas.planned_work_occurrences o ON o.id=q.planned_occurrence_id
    WHERE o.state IN ('planned','eligible');

    SELECT array_agg(q.id ORDER BY q.id) INTO v_queue_ids
    FROM atlas.task_release_queue_items q
    WHERE q.state IN ('active','queued');

    IF coalesce(array_length(v_occ_ids,1),0) <> 64
       OR coalesce(array_length(v_queue_ids,1),0) <> 75 THEN
      RAISE EXCEPTION 'Unexpected 2026 unfinished occurrence/queue count; stop (occurrence_count=%, queue_count=%)', coalesce(array_length(v_occ_ids,1),0), coalesce(array_length(v_queue_ids,1),0);
    END IF;

    -- No new Work source is inferred. Explicitly include only the two
    -- genuine release-linked source IDs, never arbitrary trigger effects.
    SELECT array_agg(source_id ORDER BY source_id) INTO v_guarded_occ_ids
    FROM (
      SELECT unnest(v_occ_ids) AS source_id
      UNION
      SELECT unnest(v_released_occ_ids) AS source_id
    ) allowlisted;
    IF coalesce(array_length(v_guarded_occ_ids,1),0) <> 66 THEN
      RAISE EXCEPTION 'Expected 64 old scheduled plus two released source occurrence identities';
    END IF;

    SELECT md5(string_agg(o.id::text||':'||o.state, '|' ORDER BY o.id::text))
      INTO v_occ_fp
    FROM atlas.planned_work_occurrences o
    WHERE o.id=ANY(v_occ_ids);

    SELECT md5(string_agg(q.id::text||':'||q.state, '|' ORDER BY q.id::text))
      INTO v_queue_fp
    FROM atlas.task_release_queue_items q
    WHERE q.id=ANY(v_queue_ids);

    SELECT md5(string_agg(t.id::text||':'||t.status, '|' ORDER BY t.id::text))
      INTO v_task_fp
    FROM atlas.tasks t WHERE t.id=ANY(v_task_ids);

    IF v_occ_fp IS DISTINCT FROM '11b0b72a77547349850ad5cd5e114070'
       OR v_queue_fp IS DISTINCT FROM 'b7427b4ec1bc091c8a6d5f0ea5cef48c'
       OR v_task_fp IS DISTINCT FROM '84dec9ba9fe4f26c59a8ed8b5641aad7' THEN
      RAISE EXCEPTION 'Exact source rows or states have changed; stop';
    END IF;

    IF (SELECT count(*) FROM atlas.tasks t
        WHERE t.id=ANY(v_task_ids)
          AND t.status IN ('open','blocked')
          AND t.completed_at IS NULL
          AND EXISTS (
            SELECT 1 FROM atlas.task_release_queue_items q
            WHERE q.task_id=t.id
              AND q.queue_key=t.metadata->>'release_queue_key'
          )) <> 3 THEN
      RAISE EXCEPTION 'Three original source-identified historical Tasks changed';
    END IF;

    -- Confirm the original three Task/occurrence links, including
    -- two released originals and the one queued original Task with a
    -- still-planned source occurrence. This is source identity, not Results.
    IF (
      SELECT count(*) FROM (
        VALUES
        ('e05f3870-7c74-47d5-9998-483aa238f115'::uuid,'5d6123f4-ba5d-43c6-9185-816143bcc754'::uuid,'released'::text),
        ('d1bb49af-667f-47e6-b03b-06d75c6e93e6'::uuid,'70909d03-21f8-4d22-975c-bff8a428f8be'::uuid,'released'::text),
        ('63ade0e9-28bc-4543-805f-d2c82d678315'::uuid,'71ef03fa-36ff-4a54-bdad-dfe5336014c9'::uuid,'planned'::text)
      ) AS expected(task_id,occ_id,before_state)
      JOIN atlas.tasks t ON t.id=expected.task_id AND t.planned_occurrence_id=expected.occ_id
      JOIN atlas.planned_work_occurrences o ON o.id=expected.occ_id AND o.state=expected.before_state
      JOIN atlas.task_release_queue_items q ON q.task_id=t.id AND q.planned_occurrence_id=o.id
      WHERE (expected.before_state='released' AND o.released_task_id=t.id)
         OR (expected.before_state='planned' AND o.released_task_id IS NULL)
    ) <> 3 THEN
      RAISE EXCEPTION 'Exact historical Task/occurrence released links drifted; stop';
    END IF;

    IF EXISTS (
         SELECT 1 FROM atlas.planned_work_occurrences o
         WHERE o.id=ANY(v_occ_ids) AND o.released_task_id IS NOT NULL
       )
       OR EXISTS (
         SELECT 1 FROM atlas.planned_work_occurrences ch
         WHERE ch.parent_occurrence_id=ANY(v_guarded_occ_ids)
           AND ch.state NOT IN ('completed','cancelled')
       )
       OR EXISTS (
         SELECT 1 FROM atlas.tasks ch
         WHERE ch.status IN ('open','blocked')
           AND (ch.parent_task_id=ANY(v_task_ids)
                OR ch.metadata->>'parent_task_id'=ANY(
                     ARRAY(SELECT unnest(v_task_ids)::text)))
       )
       OR EXISTS (
         SELECT 1 FROM atlas.work_execution_adapters a
         WHERE a.state='active'
           AND (a.task_id=ANY(v_task_ids)
                OR a.planned_occurrence_id=ANY(v_guarded_occ_ids))
       )
       OR EXISTS (
         SELECT 1 FROM atlas.work_items w
         WHERE w.source_object_id=ANY(v_task_ids)
            OR w.source_object_id=ANY(v_guarded_occ_ids)
       ) THEN
      RAISE EXCEPTION 'Current Work, Task, or child evidence changed; stop';
    END IF;

    -- The normal Task status trigger maintains derived capacity projections.
    -- The three exact source Tasks already have capacity profiles in live Noel;
    -- require that exact existing set and refuse owner-locked profile mutation.
    -- Every unrelated profile identity and row is full-row fingerprinted.
    IF (SELECT count(*) FROM atlas.task_capacity_profiles p
        WHERE p.task_id=ANY(v_task_ids)) <> 3
       OR EXISTS (
         SELECT 1 FROM atlas.task_capacity_profiles p
         WHERE p.task_id=ANY(v_task_ids) AND p.owner_locked
       ) THEN
      RAISE EXCEPTION 'Target historical capacity profiles missing or owner-locked; stop';
    END IF;
    SELECT count(*) INTO v_capacity_profiles_count
      FROM atlas.task_capacity_profiles;
    SELECT md5(string_agg(to_jsonb(p)::text, E'\\n' ORDER BY p.task_id::text))
      INTO v_unaffected_capacity_fp
      FROM atlas.task_capacity_profiles p
      WHERE NOT (p.task_id=ANY(v_task_ids));

    SELECT count(*) INTO v_before_queue_count
      FROM atlas.task_release_queue_items;
    SELECT count(*) INTO v_before_occ_count
      FROM atlas.planned_work_occurrences;
    SELECT count(*) INTO v_before_task_count FROM atlas.tasks;

    SELECT md5(string_agg(to_jsonb(w)::text, E'\\n' ORDER BY w.id::text))
      INTO v_work_fp FROM atlas.work_items w;
    SELECT md5(string_agg(to_jsonb(r)::text, E'\\n' ORDER BY r.id::text))
      INTO v_requirements_fp FROM atlas.work_requirements r;
    SELECT md5(string_agg(to_jsonb(t)::text, E'\\n' ORDER BY t.id::text))
      INTO v_unaffected_tasks_fp
      FROM atlas.tasks t WHERE NOT (t.id=ANY(v_task_ids));
    SELECT md5(string_agg(to_jsonb(o)::text, E'\\n' ORDER BY o.id::text))
      INTO v_unaffected_occ_fp
      FROM atlas.planned_work_occurrences o WHERE NOT (o.id=ANY(v_guarded_occ_ids));
    SELECT md5(string_agg(to_jsonb(q)::text, E'\\n' ORDER BY q.id::text))
      INTO v_unaffected_queue_fp
      FROM atlas.task_release_queue_items q WHERE NOT (q.id=ANY(v_queue_ids));

    -- Withdraw schedule authority only. No completed_at, Result or crop
    -- observation is generated. The physical Field Row 9 crop remains real.
    UPDATE atlas.planned_work_occurrences o
       SET state='cancelled', updated_at=now()
     WHERE o.id=ANY(v_occ_ids) AND o.state IN ('planned','eligible');
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    IF v_changed <> 64 THEN
      RAISE EXCEPTION 'Expected 64 exact occurrence withdrawals, got %',v_changed;
    END IF;

    -- Archive exactly these three owner-adjudicated obsolete Tasks, never Done.
    -- The original atlas.release_after_task_terminal_v1 trigger would also
    -- run atlas.release_eligible_work_v1(farm,NULL,10) after EACH archive.
    -- That farm-wide scheduler could release unrelated current Work. Noel's
    -- existing atlas.reservoir_migration guard is read by that trigger only.
    -- Scope the suppression to this three-row archival statement and restore
    -- the previous value immediately. Other database/Task guards remain live.
    -- A live-only two-link prerequisite dependency is absent in V1's
    -- fictional fixture. Status UPDATE would automatically recalculate BOTH
    -- downstream Tasks, rewriting their blocker/metadata even though archive
    -- is NOT the "done" evidence required by either prerequisite.
    -- Verify exact source-positive custody before any scoped suppression.
    SELECT count(*)::integer INTO v_source_prerequisite_count
    FROM atlas.task_prerequisites p
    JOIN atlas.tasks downstream ON downstream.id=p.downstream_task_id
    WHERE p.active AND p.prerequisite_task_id=ANY(v_task_ids)
      AND p.required_status='done' AND p.hold_mode='deferred_hidden'
      AND p.satisfied_at IS NULL
      AND downstream.id<>ALL(v_task_ids)
      AND downstream.status='blocked'
      AND downstream.visibility_scope='management'
      AND downstream.assigned_membership_id IS NULL
      AND downstream.assigned_user_id IS NULL
      AND downstream.metadata->>'prerequisite_gate_state'='deferred_hidden';
    IF v_source_prerequisite_count <> 2
      OR (SELECT count(*) FROM atlas.task_prerequisites p
          WHERE p.active AND p.prerequisite_task_id=ANY(v_task_ids)) <> 2
      OR (SELECT count(DISTINCT p.downstream_task_id)
          FROM atlas.task_prerequisites p
          WHERE p.active AND p.prerequisite_task_id=ANY(v_task_ids)) <> 2 THEN
      RAISE EXCEPTION 'Exact two unsatisfied original prerequisite relationships drifted; stop';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger trg
      WHERE trg.tgrelid='atlas.tasks'::regclass
        AND trg.tgname='tasks_reconcile_prerequisite_dependents_v1'
        AND trg.tgenabled='O'
        AND NOT trg.tgisinternal
    ) THEN
      RAISE EXCEPTION 'Prerequisite reconciliation trigger custody changed; stop';
    END IF;

    -- Exactly one NON-AUTHORIZATION business-projection trigger is paused.
    -- The transaction already holds the Task table, and ALTER TABLE takes
    -- ACCESS EXCLUSIVE until COMMIT: no concurrent Task mutation can bypass
    -- the trigger in another session. Its DDL setting rolls back on ANY
    -- error. All task authorization, identity, reality and completion guards
    -- remain enabled and unchanged, including the original 730-table check.
    -- The two downstream prerequisite rows and Tasks must remain unchanged.
    EXECUTE 'ALTER TABLE atlas.tasks DISABLE TRIGGER tasks_reconcile_prerequisite_dependents_v1';

    v_prior_reservoir_flag := current_setting('atlas.reservoir_migration',true);
    PERFORM set_config('atlas.reservoir_migration','on',true);
    UPDATE atlas.tasks t
       SET status='archived', completed_at=NULL, updated_at=now()
     WHERE t.id=ANY(v_task_ids) AND t.status IN ('open','blocked');
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    PERFORM set_config('atlas.reservoir_migration',coalesce(v_prior_reservoir_flag,''),true);

    EXECUTE 'ALTER TABLE atlas.tasks ENABLE TRIGGER tasks_reconcile_prerequisite_dependents_v1';
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger trg
      WHERE trg.tgrelid='atlas.tasks'::regclass
        AND trg.tgname='tasks_reconcile_prerequisite_dependents_v1'
        AND trg.tgenabled='O'
        AND NOT trg.tgisinternal
    ) THEN
      RAISE EXCEPTION 'Prerequisite reconciliation trigger was not fully restored; rollback';
    END IF;
    IF v_changed <> 3 THEN
      RAISE EXCEPTION 'Expected three exact Task archives, got %',v_changed;
    END IF;

    -- Reproduce only the intended linked-occurrence retirement which the
    -- trigger otherwise performs. Exact two source IDs were verified above.
    -- Record historical withdrawal, never physical completion or Result.
    UPDATE atlas.planned_work_occurrences o
       SET state='cancelled',
           metadata=coalesce(o.metadata,'{}'::jsonb) || jsonb_build_object(
             'terminal_task_status','archived',
             'terminal_task_id',t.id,
             'terminal_at',now(),
             'historical_disposition_kind','withdrawn_obsolete_2026_queue',
             'historical_disposition_at',now()
           ),
           updated_at=now()
      FROM atlas.tasks t
     WHERE o.id=ANY(v_released_occ_ids)
       AND o.state='released'
       AND t.id=o.released_task_id
       AND t.planned_occurrence_id=o.id
       AND t.status='archived';
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    IF v_changed <> 2 THEN
      RAISE EXCEPTION 'Expected exactly two linked released source withdrawals, got %',v_changed;
    END IF;

    -- Stop remaining historical queue pointers being offered as unfinished.
    -- Existing completed/skipped queue states and completed Task records stay.
    UPDATE atlas.task_release_queue_items q
       SET state='skipped'
     WHERE q.id=ANY(v_queue_ids) AND q.state IN ('active','queued');
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    IF v_changed <> 75 THEN
      RAISE EXCEPTION 'Expected 75 exact historical queue withdrawals, got %',v_changed;
    END IF;

    IF (SELECT count(*) FROM atlas.task_capacity_profiles) <> v_capacity_profiles_count
       OR (SELECT count(*) FROM atlas.task_capacity_profiles p
           WHERE p.task_id=ANY(v_task_ids)) <> 3
       OR EXISTS (
           SELECT 1 FROM atlas.task_capacity_profiles p
           WHERE p.task_id=ANY(v_task_ids) AND p.owner_locked
       ) THEN
      RAISE EXCEPTION 'Capacity profile identity, row count or owner lock changed; rollback';
    END IF;

    IF (SELECT count(*) FROM atlas.task_release_queue_items) <> v_before_queue_count
       OR (SELECT count(*) FROM atlas.planned_work_occurrences) <> v_before_occ_count
       OR (SELECT count(*) FROM atlas.tasks) <> v_before_task_count
       OR (SELECT count(*) FROM atlas.planned_work_occurrences o
           WHERE o.id=ANY(v_occ_ids) AND o.state='cancelled') <> 64
       OR (SELECT count(*) FROM atlas.planned_work_occurrences o
           JOIN atlas.tasks t ON t.id=o.released_task_id
           WHERE o.id=ANY(v_released_occ_ids)
             AND o.state='cancelled' AND t.status='archived'
             AND o.metadata->>'terminal_task_status'='archived'
             AND o.metadata->>'terminal_task_id'=t.id::text) <> 2
       OR (SELECT count(*) FROM atlas.tasks t
           WHERE t.id=ANY(v_task_ids) AND t.status='archived'
             AND t.completed_at IS NULL) <> 3
       OR (SELECT count(*) FROM atlas.task_release_queue_items q
           WHERE q.id=ANY(v_queue_ids) AND q.state='skipped') <> 75
       OR EXISTS (
           SELECT 1 FROM atlas.task_release_queue_items q
           JOIN atlas.planned_work_occurrences o ON o.id=q.planned_occurrence_id
           WHERE o.state IN ('planned','eligible')
       )
       OR EXISTS (
           SELECT 1 FROM atlas.task_release_queue_items q
           JOIN atlas.tasks t ON t.id=q.task_id
           WHERE t.status IN ('open','blocked')
       ) THEN
      RAISE EXCEPTION 'Post-retirement source or no-new-task contract failed';
    END IF;

    IF (SELECT md5(string_agg(to_jsonb(w)::text, E'\\n' ORDER BY w.id::text))
        FROM atlas.work_items w) IS DISTINCT FROM v_work_fp
       OR (SELECT md5(string_agg(to_jsonb(r)::text, E'\\n' ORDER BY r.id::text))
           FROM atlas.work_requirements r) IS DISTINCT FROM v_requirements_fp
       OR (SELECT md5(string_agg(to_jsonb(t)::text, E'\\n' ORDER BY t.id::text))
           FROM atlas.tasks t WHERE NOT(t.id=ANY(v_task_ids)))
            IS DISTINCT FROM v_unaffected_tasks_fp
       OR (SELECT md5(string_agg(to_jsonb(o)::text, E'\\n' ORDER BY o.id::text))
           FROM atlas.planned_work_occurrences o WHERE NOT(o.id=ANY(v_guarded_occ_ids)))
            IS DISTINCT FROM v_unaffected_occ_fp
       OR (SELECT md5(string_agg(to_jsonb(q)::text, E'\\n' ORDER BY q.id::text))
           FROM atlas.task_release_queue_items q WHERE NOT(q.id=ANY(v_queue_ids)))
            IS DISTINCT FROM v_unaffected_queue_fp
       OR (SELECT md5(string_agg(to_jsonb(p)::text, E'\\n' ORDER BY p.task_id::text))
           FROM atlas.task_capacity_profiles p WHERE NOT(p.task_id=ANY(v_task_ids)))
            IS DISTINCT FROM v_unaffected_capacity_fp THEN
      RAISE EXCEPTION 'Untargeted history, capacity profile or canonical Work changed; rollback';
    END IF;

    RAISE NOTICE 'Source-guarded withdrawal: 64 old occurrences cancelled, 3 legacy Tasks archived, 2 released source occurrences cancelled, 75 queue pointers skipped, only 3 source-owned capacity profiles refreshed; other Work, profiles and history intact.';
END
$historical_retirement$;

COMMIT;

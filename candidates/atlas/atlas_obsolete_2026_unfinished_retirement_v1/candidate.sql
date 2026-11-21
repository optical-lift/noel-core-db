-- HELD SOURCE ONLY: owner-authorized withdrawal of obsolete 2026 unfinished queue.
-- Not a production migration. Do not run directly on Supabase.
-- Canonical source / authorization: optical-lift/atlas#532 (Package B).
-- This does not declare any physical result, complete any Work, or disable a
-- shared Rulebook/release policy. It retires old schedule authority only.
--
-- Read-only production inventory (2026-11-21):
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
    v_changed integer;
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
      RAISE EXCEPTION 'Unexpected 2026 unfinished occurrence/queue count; stop';
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

    IF EXISTS (
         SELECT 1 FROM atlas.planned_work_occurrences o
         WHERE o.id=ANY(v_occ_ids) AND o.released_task_id IS NOT NULL
       )
       OR EXISTS (
         SELECT 1 FROM atlas.planned_work_occurrences ch
         WHERE ch.parent_occurrence_id=ANY(v_occ_ids)
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
                OR a.planned_occurrence_id=ANY(v_occ_ids))
       )
       OR EXISTS (
         SELECT 1 FROM atlas.work_items w
         WHERE w.source_object_id=ANY(v_task_ids)
            OR w.source_object_id=ANY(v_occ_ids)
       ) THEN
      RAISE EXCEPTION 'Current Work, Task, or child evidence changed; stop';
    END IF;

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
      FROM atlas.planned_work_occurrences o WHERE NOT (o.id=ANY(v_occ_ids));
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

    -- Archive three historical owner-adjudicated items; never mark 'done'.
    UPDATE atlas.tasks t
       SET status='archived', completed_at=NULL, updated_at=now()
     WHERE t.id=ANY(v_task_ids) AND t.status IN ('open','blocked');
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    IF v_changed <> 3 THEN
      RAISE EXCEPTION 'Expected three exact Task archives, got %',v_changed;
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

    IF (SELECT count(*) FROM atlas.task_release_queue_items) <> v_before_queue_count
       OR (SELECT count(*) FROM atlas.planned_work_occurrences) <> v_before_occ_count
       OR (SELECT count(*) FROM atlas.tasks) <> v_before_task_count
       OR (SELECT count(*) FROM atlas.planned_work_occurrences o
           WHERE o.id=ANY(v_occ_ids) AND o.state='cancelled') <> 64
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
           FROM atlas.planned_work_occurrences o WHERE NOT(o.id=ANY(v_occ_ids)))
            IS DISTINCT FROM v_unaffected_occ_fp
       OR (SELECT md5(string_agg(to_jsonb(q)::text, E'\\n' ORDER BY q.id::text))
           FROM atlas.task_release_queue_items q WHERE NOT(q.id=ANY(v_queue_ids)))
            IS DISTINCT FROM v_unaffected_queue_fp THEN
      RAISE EXCEPTION 'Untargeted history or canonical Work changed; rollback; work=%, requirements=%, other_tasks=%, other_occ=%, other_queue=%',
        (SELECT md5(string_agg(to_jsonb(w)::text, E'\\\\n' ORDER BY w.id::text))
           IS DISTINCT FROM v_work_fp FROM atlas.work_items w),
        (SELECT md5(string_agg(to_jsonb(r)::text, E'\\\\n' ORDER BY r.id::text))
           IS DISTINCT FROM v_requirements_fp FROM atlas.work_requirements r),
        (SELECT md5(string_agg(to_jsonb(t)::text, E'\\\\n' ORDER BY t.id::text))
           IS DISTINCT FROM v_unaffected_tasks_fp
           FROM atlas.tasks t WHERE NOT (t.id=ANY(v_task_ids))),
        (SELECT md5(string_agg(to_jsonb(o)::text, E'\\\\n' ORDER BY o.id::text))
           IS DISTINCT FROM v_unaffected_occ_fp
           FROM atlas.planned_work_occurrences o WHERE NOT (o.id=ANY(v_occ_ids))),
        (SELECT md5(string_agg(to_jsonb(q)::text, E'\\\\n' ORDER BY q.id::text))
           IS DISTINCT FROM v_unaffected_queue_fp
           FROM atlas.task_release_queue_items q WHERE NOT (q.id=ANY(v_queue_ids)));
    END IF;

    RAISE NOTICE 'Source-guarded withdrawal: 64 old occurrences cancelled, 3 legacy Tasks archived, 75 queue pointers skipped; unrelated Work and historic rows intact.';
END
$historical_retirement$;

COMMIT;

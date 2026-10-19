DO $$ BEGIN IF to_regclass('practice.encounter_notes_v1') IS NULL OR to_regclass('practice.v_person_body_episode_history_v1') IS NULL THEN RAISE EXCEPTION 'Missing structures'; END IF; END $$;

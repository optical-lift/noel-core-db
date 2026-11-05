-- HELD P1 2026-11-05: exact current LIVE object_state DDL recovery.
-- Only use inside disposable PG17, never in production or retained clone.
-- Source: read-only Noel pg_catalog columns, checks/FKs, indexes, trigger,
-- RLS policy and table ACL. No rows, no guessed strategies or exceptions.
DO $pre$
BEGIN
 IF to_regclass('atlas.object_state') IS NOT NULL
 OR to_regprocedure('atlas.set_updated_at()') IS NULL
 OR to_regprocedure('atlas.can_read_farm_operations(uuid)') IS NULL
 THEN RAISE EXCEPTION 'STOP current care source already exists or source dependencies missing';
 END IF;
END;$pre$;
CREATE TABLE atlas.object_state (
 object_id uuid NOT NULL,
 farm_id uuid NOT NULL,
 life_status text NOT NULL DEFAULT 'open'::text,
 weed_pressure text NOT NULL DEFAULT 'unknown'::text,
 water_status text NOT NULL DEFAULT 'unknown'::text,
 last_touched_at date,
 last_weeded_at date,
 last_watered_at date,
 last_checked_at date,
 decision_required boolean NOT NULL DEFAULT false,
 harvest_confidence text NOT NULL DEFAULT 'unknown'::text,
 presentability text DEFAULT 'unknown'::text,
 active_task_count integer NOT NULL DEFAULT 0,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamp with time zone NOT NULL DEFAULT now(),
 updated_at timestamp with time zone NOT NULL DEFAULT now(),
 care_state text NOT NULL DEFAULT 'unknown'::text,
 care_strategy text NOT NULL DEFAULT 'unknown'::text,
 care_pressure text NOT NULL DEFAULT 'unknown'::text,
 care_trend text NOT NULL DEFAULT 'unknown'::text,
 care_freshness text NOT NULL DEFAULT 'unknown'::text,
 care_observed_at timestamp with time zone,
 care_review_on date,
 care_estimated_recovery_minutes integer,
 care_source_kind text NOT NULL DEFAULT 'unknown'::text,
 care_strategy_source text,
 care_strategy_set_at timestamp with time zone,
 care_strategy_set_by_membership_id uuid,
 care_reason jsonb NOT NULL DEFAULT '{}'::jsonb,
 care_updated_at timestamp with time zone NOT NULL DEFAULT now(),
 operational_truth text,
 operational_truth_source text,
 operational_truth_task_id uuid,
 operational_truth_changed_at timestamp with time zone,
 CONSTRAINT object_state_care_estimated_recovery_minutes_check CHECK (((care_estimated_recovery_minutes IS NULL) OR (care_estimated_recovery_minutes >= 0))),
 CONSTRAINT object_state_care_freshness_check CHECK ((care_freshness = ANY (ARRAY['observed'::text, 'estimated'::text, 'stale'::text, 'unknown'::text]))),
 CONSTRAINT object_state_care_pressure_check CHECK ((care_pressure = ANY (ARRAY['none'::text, 'light'::text, 'moderate'::text, 'heavy'::text, 'severe'::text, 'unknown'::text]))),
 CONSTRAINT object_state_care_source_kind_check CHECK ((care_source_kind = ANY (ARRAY['observation'::text, 'completion'::text, 'strategy'::text, 'estimate'::text, 'migration'::text, 'unknown'::text]))),
 CONSTRAINT object_state_care_state_check CHECK ((care_state = ANY (ARRAY['settled'::text, 'stirring'::text, 'needs_tending'::text, 'losing_shape'::text, 'recovery_needed'::text, 'resting'::text, 'suppressed'::text, 'decision_needed'::text, 'unknown'::text]))),
 CONSTRAINT object_state_care_strategy_check CHECK ((care_strategy = ANY (ARRAY['active_hand_care'::text, 'targeted_recovery'::text, 'mow_and_hold'::text, 'suppressed_by_tarp'::text, 'mulch_hold'::text, 'cover_crop_hold'::text, 'resting_until_review'::text, 'redesign_pending'::text, 'removal_pending'::text, 'unknown'::text]))),
 CONSTRAINT object_state_care_strategy_membership_fkey FOREIGN KEY (care_strategy_set_by_membership_id) REFERENCES atlas.farm_memberships(id) ON DELETE SET NULL,
 CONSTRAINT object_state_care_trend_check CHECK ((care_trend = ANY (ARRAY['improving'::text, 'stable'::text, 'rising'::text, 'unknown'::text]))),
 CONSTRAINT object_state_farm_id_fkey FOREIGN KEY (farm_id) REFERENCES atlas.farms(id) ON DELETE CASCADE,
 CONSTRAINT object_state_object_id_fkey FOREIGN KEY (object_id) REFERENCES atlas.growing_objects(id) ON DELETE CASCADE,
 CONSTRAINT object_state_operational_truth_task_id_fkey FOREIGN KEY (operational_truth_task_id) REFERENCES atlas.tasks(id) ON DELETE SET NULL,
 CONSTRAINT object_state_pkey PRIMARY KEY (object_id)
);
CREATE INDEX idx_object_state_farm ON atlas.object_state USING btree (farm_id);
CREATE INDEX object_state_care_strategy_membership_idx ON atlas.object_state USING btree (care_strategy_set_by_membership_id) WHERE (care_strategy_set_by_membership_id IS NOT NULL);
CREATE INDEX object_state_operational_truth_task_idx ON atlas.object_state USING btree (operational_truth_task_id) WHERE (operational_truth_task_id IS NOT NULL);
CREATE TRIGGER set_object_state_updated_at BEFORE UPDATE ON atlas.object_state FOR EACH ROW EXECUTE FUNCTION atlas.set_updated_at();
ALTER TABLE atlas.object_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.object_state FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE atlas.object_state TO authenticated;
GRANT ALL ON TABLE atlas.object_state TO service_role;
CREATE POLICY object_state_read_operations ON atlas.object_state
 FOR SELECT TO authenticated USING (atlas.can_read_farm_operations(farm_id));
DO $proof$
BEGIN
 IF (SELECT count(*) FROM atlas.object_state)<>0
 OR (SELECT count(*) FROM pg_attribute WHERE attrelid='atlas.object_state'::regclass AND attnum>0 AND NOT attisdropped)<>34
 OR (SELECT count(*) FROM pg_constraint WHERE conrelid='atlas.object_state'::regclass)<>12
 OR (SELECT count(*) FROM pg_policies WHERE schemaname='atlas' AND tablename='object_state')<>1
 OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.object_state'::regclass)
 OR has_table_privilege('anon','atlas.object_state','SELECT')
 OR NOT has_table_privilege('authenticated','atlas.object_state','SELECT')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.object_state'::regclass AND tgname='set_object_state_updated_at' AND tgenabled IN ('A','O'))
 THEN RAISE EXCEPTION 'STOP observed source constraints/policy changed';
 END IF;
 RAISE NOTICE 'PASS empty exact live care object_state shape, no inferred strategy';
END;$proof$;

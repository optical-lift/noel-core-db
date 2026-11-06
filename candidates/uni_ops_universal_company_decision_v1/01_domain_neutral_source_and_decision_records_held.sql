-- UNI-OPS-01 UNIVERSAL COMPANY SOURCE-DECISION KERNEL / HELD
-- Source-only candidate, NOT a migration. P3 14–17 are farm adapters,
-- NEVER the canonical universal definition of evidence or decision.
--
-- Company-neutral: NO farm, crop, seed, bucket, goal, rhythm, operator
-- dashboard, task, Clock, Household or recipient fields in this kernel.
-- One verified source case => signed governing-person decision ABOUT
-- whether further authority is needed. Decision NEVER issues Work.
--
-- One source adapter must independently verify the real source event,
-- the Organization, governing Ledger, Subject information boundary,
-- escalation threshold, revision and source freshness BEFORE registration.
-- This DDL deliberately supplies NO generic/ad hoc API that upgrades
-- arbitrary client text into an admitted source case. A source-admitted
-- row must ONLY be inserted by a separately audited bounded adapter.
-- No data API role receives INSERT, SELECT or RPC access from this file.

-- Do not build two independent governing decision writers in either order.
-- Existing P3 17 is a FARM ADAPTER draft, NOT a second universal root.
-- Preserve its source history until a truthful one-time adapter migration
-- and shared source verification have been independently approved.
DO $no_parallel_authority$
BEGIN
 IF pg_catalog.to_regclass(
     'atlas.uni_ops_p3_owner_attention_decision_events_v1'
 ) IS NOT NULL
 THEN RAISE EXCEPTION
   'Farm P3 17 independent governor decisions must be reconciled into one universal source before assembly'
   USING ERRCODE='55000';
 END IF;
END;
$no_parallel_authority$;

CREATE TABLE atlas.uni_ops_governed_source_cases_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid NOT NULL
   REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 governing_ledger_id uuid NOT NULL
   REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 -- Domain namespaces may be Contract, Customer, Production, Medical Lab,
 -- Event, HR, Project, etc. Never interpret this text as an authority.
 source_domain text NOT NULL
   CHECK (pg_catalog.char_length(source_domain) BETWEEN 2 AND 96),
 source_kind text NOT NULL
   CHECK (pg_catalog.char_length(source_kind) BETWEEN 2 AND 96),
 source_key text NOT NULL
   CHECK (pg_catalog.char_length(source_key) BETWEEN 1 AND 400),
 source_revision_key text NOT NULL
   CHECK (pg_catalog.char_length(source_revision_key) BETWEEN 1 AND 240),
 source_evidence_recorded_at timestamptz NOT NULL,
 source_adapter_contract text NOT NULL
   CHECK (pg_catalog.char_length(source_adapter_contract) BETWEEN 6 AND 160),
 source_attestation_fingerprint text NOT NULL
   CHECK (source_attestation_fingerprint ~ '^[0-9a-f]{32}$'),
 -- 'source_verified' is an ATTESTATION BY SOURCE ADAPTER, never by this
 -- table's own CHECK or by an operator. A fake inserted row is not proof.
 source_admission_state text NOT NULL DEFAULT 'held_pending_source_admission'
   CHECK (source_admission_state IN (
      'held_pending_source_admission','source_verified_by_adapter')),
 -- No assumption that every evidence event is a real Need/Work/Clock.
 attention_contract text NOT NULL DEFAULT 'principal_decision_candidate_v1'
   CHECK (attention_contract='principal_decision_candidate_v1'),
 source_registered_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 case_automatically_issues_work boolean NOT NULL DEFAULT false
   CHECK(case_automatically_issues_work=false),
 case_automatically_enters_principal_clock boolean NOT NULL DEFAULT false
   CHECK(case_automatically_enters_principal_clock=false),
 CONSTRAINT uni_ops_governed_case_one_revision_v1 UNIQUE(
   organization_id,governing_ledger_id,
   source_domain,source_kind,source_key,source_revision_key),
 CONSTRAINT uni_ops_governed_case_id_company_scope_unique_v1
   UNIQUE(id,organization_id,governing_ledger_id)
);
CREATE INDEX uni_ops_governed_case_source_history_v1
 ON atlas.uni_ops_governed_source_cases_v1(
   organization_id,governing_ledger_id,source_domain,
   source_kind,source_key,source_registered_at DESC,id DESC);
ALTER TABLE atlas.uni_ops_governed_source_cases_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_governed_source_cases_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_governed_source_cases_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- The decision history has one true governing Person and separate signed
-- user who performed this action. Not a delegated worker appointment.
CREATE TABLE atlas.uni_ops_governed_case_decision_events_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 case_id uuid NOT NULL REFERENCES atlas.uni_ops_governed_source_cases_v1(id)
   ON DELETE RESTRICT,
 organization_id uuid NOT NULL
   REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 governing_ledger_id uuid NOT NULL
   REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 source_action_id uuid NOT NULL UNIQUE,
 previous_decision_event_id uuid,
 governor_person_id uuid NOT NULL
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 governor_user_id uuid NOT NULL
   REFERENCES auth.users(id) ON DELETE RESTRICT,
 outcome text NOT NULL CHECK(outcome IN(
   'request_independent_work_admission',
   'request_principal_arbitration',
   'hold_for_more_source',
   'decline_new_action_at_present')),
 reason text NOT NULL
   CHECK(pg_catalog.char_length(reason) BETWEEN 12 AND 2000),
 source_attestation_fingerprint text NOT NULL
   CHECK(source_attestation_fingerprint ~ '^[0-9a-f]{32}$'),
 decided_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 -- A governor's desire is NOT a new accepted original, allocation,
 -- consent, a case's true Condition, a scheduled Clock or a Result.
 original_work_created boolean NOT NULL DEFAULT false
   CHECK(original_work_created=false),
 worker_consent_created boolean NOT NULL DEFAULT false
   CHECK(worker_consent_created=false),
 physical_actual_accepted boolean NOT NULL DEFAULT false
   CHECK(physical_actual_accepted=false),
 successor_work_automatically_created boolean NOT NULL DEFAULT false
   CHECK(successor_work_automatically_created=false),
 CONSTRAINT uni_ops_governed_decision_exact_scope_v1
 FOREIGN KEY(case_id,organization_id,governing_ledger_id)
 REFERENCES atlas.uni_ops_governed_source_cases_v1(
   id,organization_id,governing_ledger_id)
 ON DELETE RESTRICT,
 CONSTRAINT uni_ops_governed_decision_case_key_v1 UNIQUE(id,case_id),
 CONSTRAINT uni_ops_governed_decision_previous_same_case_v1
 FOREIGN KEY(previous_decision_event_id,case_id)
 REFERENCES atlas.uni_ops_governed_case_decision_events_v1(id,case_id)
 ON DELETE RESTRICT
);
CREATE INDEX uni_ops_governed_case_decisions_order_v1
 ON atlas.uni_ops_governed_case_decision_events_v1(
   case_id,decided_at DESC,id DESC);
ALTER TABLE atlas.uni_ops_governed_case_decision_events_v1
 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_governed_case_decision_events_v1
 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_governed_case_decision_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_governed_no_history_rewrite_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Original source case and governing decision history are immutable'
  USING ERRCODE='42501';
END;
$immutable$;
CREATE TRIGGER uni_ops_governed_source_case_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_governed_source_cases_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_governed_no_history_rewrite_v1();
CREATE TRIGGER uni_ops_governed_case_decision_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_governed_case_decision_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_governed_no_history_rewrite_v1();
REVOKE ALL ON FUNCTION atlas.uni_ops_governed_no_history_rewrite_v1()
 FROM PUBLIC,anon,authenticated,service_role;

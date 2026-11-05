-- Held P1 genuine exact-Subject disclosure source recovery, disposable only.
-- Source: live Noel's read-only pg_catalog/pg_get_functiondef 2026-11-05.
-- No production DDL; do not merge or migrate this test-only compatibility
-- source. The retained RiverSong DDL snapshot can omit this live source.
-- This reconstitutes an EMPTY append-only disclosure ledger with the current
-- live PK/FKs, unique action, checks, RLS and non-client ACL. Existing
-- historical disclosure is never copied, inferred, rewritten or granted.
-- The source SQL functions below are verbatim current live Noel definitions.
DO $preflight$
BEGIN
 IF to_regclass('atlas.subject_disclosure_decision_events_v1') IS NOT NULL THEN
   RAISE EXCEPTION 'STOP: Subject disclosure evidence table already present; reconcile, do not replace';
 END IF;
 IF to_regclass('atlas.organizations') IS NULL OR to_regclass('ledger.ledgers') IS NULL
   OR to_regclass('reality.entities') IS NULL THEN
   RAISE EXCEPTION 'STOP: bounded disclosure FK source missing';
 END IF;
END;$preflight$;

CREATE TABLE atlas.subject_disclosure_decision_events_v1 (
 id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 subject_domain text NOT NULL,
 subject_kind text NOT NULL,
 subject_id uuid NOT NULL,
 disclosure_class text NOT NULL CHECK (disclosure_class IN ('identity','condition','current_inventory')),
 decision_kind text NOT NULL CHECK (decision_kind IN ('grant','withhold')),
 source_action_id uuid NOT NULL,
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 12 AND 1600),
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT subject_disclosure_action_identity_v1 UNIQUE (ledger_id,source_action_id),
 CONSTRAINT subject_disclosure_supported_subject_v1 CHECK (
  (subject_domain='spatial' AND subject_kind='growing_object' AND disclosure_class IN ('identity','condition'))
  OR (subject_domain='event' AND subject_kind='occurrence' AND disclosure_class='identity')
  OR (subject_domain='spatial' AND subject_kind='farm' AND disclosure_class='current_inventory')
 )
);
CREATE INDEX subject_disclosure_current_lookup_v1 ON atlas.subject_disclosure_decision_events_v1
 (ledger_id,target_person_id,subject_domain,subject_kind,subject_id,disclosure_class,recorded_at DESC,id DESC);
ALTER TABLE atlas.subject_disclosure_decision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.subject_disclosure_decision_events_v1 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.block_subject_disclosure_mutation_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 RAISE EXCEPTION 'Original Subject disclosure decisions are append-only.'
 USING ERRCODE='42501';
END;
$function$;
REVOKE ALL ON FUNCTION atlas.block_subject_disclosure_mutation_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER subject_disclosure_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.subject_disclosure_decision_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_subject_disclosure_mutation_v1();

CREATE OR REPLACE FUNCTION atlas.has_current_subject_disclosure_v1(p_ledger_id uuid, p_person_id uuid, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_disclosure_class text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT coalesce((
  SELECT e.decision_kind='grant'
  FROM atlas.subject_disclosure_decision_events_v1 e
  WHERE e.ledger_id=p_ledger_id AND e.target_person_id=p_person_id
   AND e.subject_domain=p_subject_domain AND e.subject_kind=p_subject_kind
   AND e.subject_id=p_subject_id AND e.disclosure_class=p_disclosure_class
  ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
 ),false);
$function$;
REVOKE ALL ON FUNCTION atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_disclosure_class text, p_decision_kind text, p_source_action_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_existing atlas.subject_disclosure_decision_events_v1%rowtype;
 v_created atlas.subject_disclosure_decision_events_v1%rowtype;
BEGIN
 IF p_target_person_id IS NULL OR p_subject_id IS NULL OR p_source_action_id IS NULL
   OR NOT ((
     p_subject_domain='spatial' AND p_subject_kind='growing_object'
     AND p_disclosure_class IN ('identity','condition')
   ) OR (
     p_subject_domain='event' AND p_subject_kind='occurrence'
     AND p_disclosure_class='identity'
   ))
   OR p_decision_kind NOT IN ('grant','withhold')
   OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact bounded original Subject disclosure decision required.'
     USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Connected Person or Ledger unavailable.' USING ERRCODE='42501';
 END IF;
 IF p_subject_domain='spatial' THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.growing_objects o
     JOIN atlas.farms f ON f.id=o.farm_id
     WHERE o.id=p_subject_id AND f.organization_id=p_organization_id
   ) THEN
     RAISE EXCEPTION 'Original Subject unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
 ELSE
   -- Bind the exact Event to both the governed Ledger and its one
   -- organization. An ambiguous or inactive binding is not shareable.
   IF NOT EXISTS(
     SELECT 1
     FROM ledger.occurrence_calendar_bindings cb
     JOIN local_intel.occurrences o ON o.id=cb.occurrence_id
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=o.id AND ob.organization_id=p_organization_id
       AND ob.binding_state='active'
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id
       AND lop.organization_id=p_organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   ) OR (
     SELECT count(DISTINCT lop.organization_id)
     FROM ledger.occurrence_calendar_bindings cb
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id AND lop.status='active'
       AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=cb.occurrence_id
       AND ob.organization_id=lop.organization_id
       AND ob.binding_state='active'
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   )<>1 THEN
     RAISE EXCEPTION 'Original Event unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
 END IF;
 -- Serialize all competing grants/withholds on this exact Person + Subject
 -- + field class, not just retries with the same idempotency key.
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_disclosure:'||p_ledger_id::text||':'||
  p_target_person_id::text||':'||p_subject_domain||':'||
  p_subject_kind||':'||p_subject_id::text||':'||p_disclosure_class,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_action:'||p_ledger_id::text||':'||p_source_action_id::text,0));
 SELECT * INTO v_existing
 FROM atlas.subject_disclosure_decision_events_v1
 WHERE ledger_id=p_ledger_id AND source_action_id=p_source_action_id;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.organization_id IS DISTINCT FROM p_organization_id
    OR v_existing.target_person_id IS DISTINCT FROM p_target_person_id
    OR v_existing.subject_domain IS DISTINCT FROM p_subject_domain
    OR v_existing.subject_kind IS DISTINCT FROM p_subject_kind
    OR v_existing.subject_id IS DISTINCT FROM p_subject_id
    OR v_existing.disclosure_class IS DISTINCT FROM p_disclosure_class
    OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
    OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
    RAISE EXCEPTION 'Decision action ID already used for different disclosure.'
      USING ERRCODE='23505';
   END IF;
   v_created:=v_existing;
 ELSE
   INSERT INTO atlas.subject_disclosure_decision_events_v1(
     organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
     subject_id,disclosure_class,decision_kind,source_action_id,reason,decided_by_person_id,recorded_at
   ) VALUES(
     p_organization_id,p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class,p_decision_kind,p_source_action_id,btrim(p_reason),v_owner,clock_timestamp()
   ) RETURNING * INTO v_created;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','bounded_original_subject_disclosure_v1',
   'decisionId',v_created.id,'sourceActionId',p_source_action_id,
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'targetPersonId',p_target_person_id,'subjectDomain',p_subject_domain,
   'subjectKind',p_subject_kind,'subjectId',p_subject_id,
   'disclosureClass',p_disclosure_class,'decisionKind',p_decision_kind,
   'currentlyGranted',atlas.has_current_subject_disclosure_v1(
     p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class),
   'historicalDecisionPreserved',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.governor_set_subject_disclosure_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_disclosure_class text, p_decision_kind text, p_source_action_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT atlas.governor_set_subject_disclosure_self_api_v1(
 p_organization_id,p_ledger_id,p_target_person_id,
 p_subject_domain,p_subject_kind,p_subject_id,
 p_disclosure_class,p_decision_kind,p_source_action_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) TO authenticated,service_role;

DO $postconditions$
BEGIN
 IF (SELECT count(*) FROM atlas.subject_disclosure_decision_events_v1)<>0
 OR (SELECT count(*) FROM pg_constraint WHERE conrelid='atlas.subject_disclosure_decision_events_v1'::regclass)<>10
 OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.subject_disclosure_decision_events_v1'::regclass)
 OR (SELECT count(*) FROM pg_policies WHERE schemaname='atlas' AND tablename='subject_disclosure_decision_events_v1')<>0
 OR has_table_privilege('authenticated','atlas.subject_disclosure_decision_events_v1','SELECT')
 OR has_table_privilege('anon','atlas.subject_disclosure_decision_events_v1','SELECT')
 OR has_function_privilege('anon','public.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'STOP: recovered live Subject disclosure failed evidence and permission postconditions';
 END IF;
 RAISE NOTICE 'PASS live append-only exact Subject disclosure source, RLS, signed public governor API and no direct evidence access';
END;$postconditions$;

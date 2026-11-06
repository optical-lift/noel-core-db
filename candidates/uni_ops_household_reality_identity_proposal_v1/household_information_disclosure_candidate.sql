-- UNI-OPS-01 U5: source-specific Household identity / condition DISCLOSURE DECISIONS.
-- HELD candidate, NOT a public permission surface or a data-disclosure API.
-- Existing organization/Ledger subject_disclosure_decision_events_v1 does not
-- supply Household jurisdiction and must not be reused as a shortcut.
BEGIN;
CREATE TABLE atlas.uni_ops_household_disclosure_decision_events_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
  kernel_instance_id uuid NOT NULL REFERENCES
    atlas.household_kernel_instances(id) ON DELETE RESTRICT,
  target_person_entity_id uuid NOT NULL REFERENCES
    reality.entities(id) ON DELETE RESTRICT,
  disclosure_class text NOT NULL
    CHECK (disclosure_class IN ('subject_identity','subject_condition')),
  decision_kind text NOT NULL
    CHECK (decision_kind IN ('authorize','withdraw')),
  source_action_id uuid NOT NULL,
  decided_by_principal_id uuid NOT NULL REFERENCES
    atlas.principals(id) ON DELETE RESTRICT,
  decision_reason text NOT NULL CHECK (length(btrim(decision_reason)) BETWEEN 10 AND 1000),
  decided_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uni_ops_hh_disclosure_source_action_once UNIQUE
    (household_id,source_action_id)
);
CREATE INDEX uni_ops_hh_disclosure_current_lookup_v1
  ON atlas.uni_ops_household_disclosure_decision_events_v1
  (household_id,kernel_instance_id,target_person_entity_id,
    disclosure_class,event_sequence DESC);
ALTER TABLE atlas.uni_ops_household_disclosure_decision_events_v1
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.uni_ops_household_disclosure_decision_events_v1
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_household_disclosure_immutability_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $guard$
BEGIN
  RAISE EXCEPTION 'Household disclosure original events are immutable'
    USING ERRCODE='42501';
END;
$guard$;
CREATE TRIGGER uni_ops_household_disclosure_immutable_v1
BEFORE UPDATE OR DELETE ON atlas.uni_ops_household_disclosure_decision_events_v1
FOR EACH ROW EXECUTE FUNCTION
  atlas.uni_ops_household_disclosure_immutability_guard_v1();

CREATE FUNCTION atlas.uni_ops_decide_household_disclosure_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_target_person_entity_id uuid,
  p_disclosure_class text,
  p_decision_kind text,
  p_source_action_id uuid,
  p_decision_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $writer$
DECLARE
  v_principal_id uuid;
  v_governor_person_id uuid;
  v_event atlas.uni_ops_household_disclosure_decision_events_v1%ROWTYPE;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
     OR p_target_person_entity_id IS NULL OR p_source_action_id IS NULL
     OR p_disclosure_class IS NULL
     OR p_disclosure_class NOT IN ('subject_identity','subject_condition')
     OR p_decision_kind IS NULL
     OR p_decision_kind NOT IN ('authorize','withdraw')
     OR length(btrim(coalesce(p_decision_reason,''))) NOT BETWEEN 10 AND 1000
  THEN
    RAISE EXCEPTION 'Exact native Subject, Person, disclosure class and decision required'
      USING ERRCODE='42501';
  END IF;
  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL
     OR v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Current signed source Principal required'
      USING ERRCODE='42501';
  END IF;
  v_governor_person_id:=atlas.require_household_governor_self_v1(p_household_id);
  IF v_governor_person_id IS NULL THEN
    RAISE EXCEPTION 'Current Household governor required'
      USING ERRCODE='42501';
  END IF;
  -- Real native Household/kernel scope, not a matching label or company Ledger.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.household_kernel_instances k
    JOIN atlas.households h ON h.id=k.household_id
    JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
      AND d.version=k.kernel_version AND d.scope_kind='household'
      AND d.active=true
    WHERE h.id=p_household_id AND k.id=p_kernel_instance_id
      AND h.status='active' AND k.state='active'
      AND h.principal_id=v_principal_id
  ) THEN
    RAISE EXCEPTION 'Exact active Household native Subject required'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.id=p_target_person_entity_id
      AND e.entity_kind='person' AND e.identity_state='canonical'
  ) THEN
    RAISE EXCEPTION 'Exact canonical recipient Person required'
      USING ERRCODE='42501';
  END IF;

  -- One lock per native instance guarantees ordered source-authored
  -- authorize/withdraw decisions for all recipient/type combinations.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('UNI_OPS_HH_DISC:'||p_kernel_instance_id::text,0)
  );
  INSERT INTO atlas.uni_ops_household_disclosure_decision_events_v1 (
    household_id,kernel_instance_id,target_person_entity_id,disclosure_class,
    decision_kind,source_action_id,decided_by_principal_id,decision_reason
  ) VALUES (
    p_household_id,p_kernel_instance_id,p_target_person_entity_id,p_disclosure_class,
    p_decision_kind,p_source_action_id,v_principal_id,btrim(p_decision_reason)
  )
  ON CONFLICT (household_id,source_action_id) DO NOTHING
  RETURNING * INTO v_event;

  IF v_event.id IS NULL THEN
    SELECT * INTO v_event
    FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
    WHERE ev.household_id=p_household_id
      AND ev.source_action_id=p_source_action_id;
    IF v_event.id IS NULL
       OR v_event.kernel_instance_id IS DISTINCT FROM p_kernel_instance_id
       OR v_event.target_person_entity_id IS DISTINCT FROM p_target_person_entity_id
       OR v_event.disclosure_class IS DISTINCT FROM p_disclosure_class
       OR v_event.decision_kind IS DISTINCT FROM p_decision_kind
       OR v_event.decided_by_principal_id IS DISTINCT FROM v_principal_id
       OR v_event.decision_reason IS DISTINCT FROM btrim(p_decision_reason)
    THEN
      RAISE EXCEPTION 'Disclosure action replay conflicts with original source'
        USING ERRCODE='23505';
    END IF;
  END IF;

  -- An issued disclosure decision is not a transfer of evidence/notes,
  -- an assignment, an identity adjudication or permission to create Work.
  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_disclosure_source_decision_v1',
    'eventId',v_event.id,'disclosureClass',v_event.disclosure_class,
    'decisionKind',v_event.decision_kind,
    'sourceRecordedOnly',true,
    'dataDisclosedByThisAction',false,
    'nativeIdentityAdjudicated',false,
    'policyAdoptable',false,'workCreated',false,
    'successorWorkCreated',false
  );
END;
$writer$;

CREATE FUNCTION atlas.uni_ops_household_disclosure_current_self_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_disclosure_class text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $reader$
DECLARE
  v_principal_id uuid;
  v_person_entity_id uuid;
  v_decision_kind text;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
     OR p_disclosure_class IS NULL
     OR p_disclosure_class NOT IN ('subject_identity','subject_condition')
  THEN
    RAISE EXCEPTION 'Exact source and information class required' USING ERRCODE='42501';
  END IF;
  -- Caller may not supply a Person ID or use owner-supplied JWT metadata.
  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL OR
     v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Current signed recipient Principal required'
      USING ERRCODE='42501';
  END IF;
  v_person_entity_id:=atlas.current_person_id_v1();
  IF v_person_entity_id IS NULL THEN
    RAISE EXCEPTION 'Current canonical recipient Person required'
      USING ERRCODE='42501';
  END IF;

  SELECT ev.decision_kind INTO v_decision_kind
  FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
  JOIN atlas.households h ON h.id=ev.household_id
    AND h.status='active' AND h.principal_id=ev.decided_by_principal_id
  JOIN atlas.household_kernel_instances k ON k.id=ev.kernel_instance_id
    AND k.household_id=h.id AND k.state='active'
  JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
    AND d.version=k.kernel_version AND d.scope_kind='household'
    AND d.active=true
  WHERE ev.household_id=p_household_id
    AND ev.kernel_instance_id=p_kernel_instance_id
    AND ev.target_person_entity_id=v_person_entity_id
    AND ev.disclosure_class=p_disclosure_class
  ORDER BY ev.event_sequence DESC LIMIT 1;

  -- Fail closed on no decision, withdrawn decision, current governor
  -- change, retired kernel/world source or stale canonical Person.
  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_disclosure_current_self_v1',
    'informationClass',p_disclosure_class,
    'currentlyAuthorized',
      coalesce(v_decision_kind='authorize',false) AND EXISTS (
        SELECT 1 FROM reality.entities e
        WHERE e.id=v_person_entity_id AND e.entity_kind='person'
          AND e.identity_state='canonical'
      ),
    'dataReturned',false,
    'canIssueWork',false,
    'successorWorkCreated',false
  );
END;
$reader$;
REVOKE ALL ON FUNCTION atlas.uni_ops_decide_household_disclosure_internal_v1(
  uuid,uuid,uuid,text,text,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.uni_ops_household_disclosure_current_self_internal_v1(
  uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.uni_ops_household_disclosure_immutability_guard_v1()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

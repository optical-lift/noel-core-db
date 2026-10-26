-- SOURCE-ONLY CANDIDATE. DO NOT APPLY DIRECTLY TO LIVE DATABASE.
-- Atlas Household life-pattern authority: a pattern is not a recurring task.
BEGIN;

CREATE TABLE atlas.household_life_patterns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES atlas.households(id),
  stable_key text NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 180),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 1600),
  attention_shape text NOT NULL CHECK (length(btrim(attention_shape)) BETWEEN 1 AND 1000),
  -- An attributed household claim of the relevant relationship/responsibility,
  -- not a newly granted right or a verified external relationship source.
  household_basis_kind text NOT NULL CHECK
    (household_basis_kind IN ('household_relationship','household_responsibility')),
  household_basis_description text NOT NULL CHECK
    (length(btrim(household_basis_description)) BETWEEN 1 AND 1000),
  state text NOT NULL CHECK (state IN ('proposed','established','inactive')),
  participation_mode text NOT NULL CHECK
    (participation_mode IN ('undetermined','solo','shared','divided','rotating')),
  participant_member_ids uuid[] NOT NULL DEFAULT '{}',
  provenance text NOT NULL CHECK (provenance IN ('explicit_household_plan','user_proposal')),
  revision integer NOT NULL CHECK (revision >= 1),
  changed_by_user_id uuid NOT NULL,
  last_change_reason text,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  UNIQUE (household_id,stable_key)
);
CREATE INDEX household_life_patterns_household_state_idx
 ON atlas.household_life_patterns (household_id,state,updated_at);
ALTER TABLE atlas.household_life_patterns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_life_patterns FROM PUBLIC,anon,authenticated;
-- Access is only via validated principal / household-custodied functions.

CREATE TABLE atlas.household_life_pattern_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES atlas.households(id),
  pattern_id uuid NOT NULL REFERENCES atlas.household_life_patterns(id),
  action_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  revision integer NOT NULL CHECK (revision>=1),
  prior_state jsonb,
  established_state jsonb NOT NULL CHECK (jsonb_typeof(established_state)='object'),
  submitted_input jsonb NOT NULL CHECK (jsonb_typeof(submitted_input)='object'),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  UNIQUE(household_id,action_id),
  UNIQUE(pattern_id,revision)
);
ALTER TABLE atlas.household_life_pattern_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_life_pattern_events FROM PUBLIC,anon,authenticated;

-- Only the owning active Principal's Household may establish its pattern.
-- Participant references are descriptive and MUST NOT imply delegation,
-- consent, task assignment or access to another person's Personal Atlas.
CREATE OR REPLACE FUNCTION atlas.principal_upsert_household_life_pattern_self_api_v1(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $function$
DECLARE
  v_household uuid;
  v_actor uuid := auth.uid();
  v_action uuid;
  v_stable_key text;
  v_state text;
  v_provenance text;
  v_title text;
  v_description text;
  v_attention text;
  v_basis_kind text;
  v_basis_description text;
  v_mode text;
  v_reason text;
  v_members uuid[];
  v_revision integer;
  v_current atlas.household_life_patterns%rowtype;
  v_prior jsonb;
  v_changed atlas.household_life_patterns%rowtype;
  v_existing atlas.household_life_pattern_events%rowtype;
  v_event_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;
  v_household:=atlas.principal_current_household_id_v1();
  IF v_household IS NULL THEN
    RAISE EXCEPTION 'Active Principal household required.' USING errcode='42501';
  END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input)<>'object' THEN
    RAISE EXCEPTION 'Household pattern input must be an object.' USING errcode='22023';
  END IF;
  v_action:=nullif(p_input->>'sourceActionId','')::uuid;
  v_stable_key:=btrim(coalesce(p_input->>'stableKey',''));
  IF v_action IS NULL OR v_stable_key !~* '^pattern:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'Stable pattern key and UUID action receipt required.' USING errcode='22023';
  END IF;

  -- Household row lock serializes the scoped revision and replay checks.
  PERFORM 1 FROM atlas.households h WHERE h.id=v_household AND h.status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Household no longer active.' USING errcode='42501'; END IF;

  SELECT e.* INTO v_existing FROM atlas.household_life_pattern_events e
   WHERE e.household_id=v_household AND e.action_id=v_action;
  IF FOUND THEN
    IF v_existing.submitted_input IS DISTINCT FROM p_input THEN
      RAISE EXCEPTION 'sourceActionId replay changes the instruction.' USING errcode='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','principal_household_life_pattern_write_v1',
      'householdId',v_household,'patternId',v_existing.pattern_id,
      'revision',v_existing.revision,'eventId',v_existing.id,
      'idempotentReplay',true
    );
  END IF;

  v_title:=btrim(coalesce(p_input->>'title',''));
  v_description:=btrim(coalesce(p_input->>'description',''));
  v_attention:=btrim(coalesce(p_input->>'attentionShape',''));
  v_basis_kind:=btrim(coalesce(p_input->>'householdBasisKind',''));
  v_basis_description:=btrim(coalesce(p_input->>'householdBasisDescription',''));
  v_state:=btrim(coalesce(p_input->>'state',''));
  v_mode:=btrim(coalesce(p_input->>'participationMode','undetermined'));
  v_provenance:=btrim(coalesce(p_input->>'provenance',''));
  v_reason:=nullif(btrim(coalesce(p_input->>'changeReason','')),'');
  v_revision:=coalesce(nullif(p_input->>'expectedRevision','')::integer,-1);
  IF length(v_title) NOT BETWEEN 1 AND 180
     OR length(v_description) NOT BETWEEN 1 AND 1600
     OR length(v_attention) NOT BETWEEN 1 AND 1000
     OR v_basis_kind NOT IN ('household_relationship','household_responsibility')
     OR length(v_basis_description) NOT BETWEEN 1 AND 1000
     OR v_state NOT IN ('proposed','established','inactive')
     OR v_mode NOT IN ('undetermined','solo','shared','divided','rotating')
     OR v_provenance NOT IN ('explicit_household_plan','user_proposal')
     OR v_revision<0
     OR (v_state='established' AND v_provenance<>'explicit_household_plan')
     OR (v_state='inactive' AND v_reason IS NULL) THEN
    RAISE EXCEPTION 'Invalid or unauthorized household pattern transition.' USING errcode='22023';
  END IF;

  IF p_input->'participantMemberIds' IS NOT NULL
     AND jsonb_typeof(p_input->'participantMemberIds')<>'array' THEN
    RAISE EXCEPTION 'Participant IDs must be an array.' USING errcode='22023';
  END IF;
  SELECT coalesce(array_agg(DISTINCT x.value::uuid ORDER BY x.value::uuid),'{}'::uuid[])
    INTO v_members FROM jsonb_array_elements_text(
      coalesce(p_input->'participantMemberIds','[]'::jsonb)) x;
  IF array_length(v_members,1)>20 THEN
    RAISE EXCEPTION 'Too many household participants.' USING errcode='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_members) member_id
    WHERE NOT EXISTS (
      SELECT 1 FROM atlas.household_members m
       WHERE m.id=member_id AND m.household_id=v_household AND m.active
    )
  ) THEN
    RAISE EXCEPTION 'Participant must be a current member of this household.' USING errcode='42501';
  END IF;
  IF v_mode='solo' AND coalesce(array_length(v_members,1),0)>1 THEN
    RAISE EXCEPTION 'Solo pattern cannot name multiple participants.' USING errcode='22023';
  END IF;
  IF v_mode='undetermined' AND coalesce(array_length(v_members,1),0)>0 THEN
    RAISE EXCEPTION 'Unresolved participation cannot imply named responsibility.' USING errcode='22023';
  END IF;

  SELECT * INTO v_current FROM atlas.household_life_patterns
   WHERE household_id=v_household AND stable_key=v_stable_key FOR UPDATE;
  v_prior:=CASE WHEN v_current.id IS NULL THEN NULL ELSE to_jsonb(v_current) END;
  IF v_current.id IS NULL THEN
    IF v_revision<>0 OR v_state='inactive' THEN
      RAISE EXCEPTION 'New pattern requires revision zero and an active proposal.' USING errcode='22023';
    END IF;
    INSERT INTO atlas.household_life_patterns
      (household_id,stable_key,title,description,attention_shape,
       household_basis_kind,household_basis_description,state,
       participation_mode,participant_member_ids,provenance,revision,
       changed_by_user_id,last_change_reason)
    VALUES (v_household,v_stable_key,v_title,v_description,v_attention,
      v_basis_kind,v_basis_description,v_state,
      v_mode,v_members,v_provenance,1,v_actor,v_reason)
    RETURNING * INTO v_changed;
  ELSE
    IF v_current.revision<>v_revision THEN
      RAISE EXCEPTION 'Pattern has changed; reread before correcting it.' USING errcode='40001';
    END IF;
    UPDATE atlas.household_life_patterns
      SET title=v_title,description=v_description,attention_shape=v_attention,
          household_basis_kind=v_basis_kind,household_basis_description=v_basis_description,
          state=v_state,participation_mode=v_mode,participant_member_ids=v_members,
          provenance=v_provenance,revision=v_current.revision+1,
          changed_by_user_id=v_actor,last_change_reason=v_reason,
          updated_at=statement_timestamp()
      WHERE id=v_current.id AND household_id=v_household
      RETURNING * INTO v_changed;
  END IF;

  INSERT INTO atlas.household_life_pattern_events
    (household_id,pattern_id,action_id,actor_user_id,revision,
      prior_state,established_state,submitted_input)
  VALUES(v_household,v_changed.id,v_action,v_actor,v_changed.revision,
         v_prior,to_jsonb(v_changed),p_input)
  RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','principal_household_life_pattern_write_v1',
    'householdId',v_household,'patternId',v_changed.id,
    'revision',v_changed.revision,'eventId',v_event_id,'idempotentReplay',false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.principal_household_life_patterns_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $function$
DECLARE
  v_household uuid;
  v_items jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;
  v_household:=atlas.principal_current_household_id_v1();
  IF v_household IS NULL THEN
    RAISE EXCEPTION 'Active Principal household required.' USING errcode='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'stableKey',p.stable_key,'title',p.title,
    'description',p.description,'attentionShape',p.attention_shape,
    'householdBasisKind',p.household_basis_kind,
    'householdBasisDescription',p.household_basis_description,
    'state',p.state,'participationMode',p.participation_mode,
    'participantMemberIds',to_jsonb(p.participant_member_ids),
    'provenance',p.provenance,'revision',p.revision,
    'changeReason',p.last_change_reason
  ) ORDER BY p.updated_at DESC,p.id),'[]'::jsonb)
  INTO v_items FROM atlas.household_life_patterns p
  WHERE p.household_id=v_household;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','principal_household_life_patterns_self_v1',
    'householdId',v_household,'patterns',v_items,
    'truthBoundary',jsonb_build_object(
      'rhythmNotTask',true,'noAutomaticClockAdmission',true,
      'participantIdsNotAssignmentRights',true,'inactiveNotOverdue',true));
END;
$function$;

-- Browser membranes. No direct source table access.
CREATE OR REPLACE FUNCTION public.principal_household_life_patterns_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$ SELECT atlas.principal_household_life_patterns_self_api_v1(); $function$;
CREATE OR REPLACE FUNCTION public.principal_upsert_household_life_pattern_self_api_v1(p_input jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$ SELECT atlas.principal_upsert_household_life_pattern_self_api_v1(p_input); $function$;

REVOKE ALL ON FUNCTION atlas.principal_household_life_patterns_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.principal_upsert_household_life_pattern_self_api_v1(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.principal_household_life_patterns_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.principal_upsert_household_life_pattern_self_api_v1(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.principal_household_life_patterns_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.principal_upsert_household_life_pattern_self_api_v1(jsonb) TO authenticated;

COMMIT;

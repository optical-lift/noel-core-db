-- ATLAS candidate: same-original native Work text amendments and own Result
-- narrative readback. DRAFT ONLY; do not apply directly to production.
-- Owner governance is proved by the EXISTING native/institutional root.
-- A native Ledger seat alone is not sufficient. Result payload disclosure
-- is STRICTLY limited to exact signed reporter, not any other worker.
BEGIN;

CREATE TABLE atlas.native_work_text_revision_events_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  ledger_id uuid NOT NULL,
  work_item_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  actor_person_id uuid NOT NULL,
  before_title text NOT NULL,
  after_title text NOT NULL,
  before_instructions text,
  after_instructions text,
  old_updated_at timestamptz NOT NULL,
  new_updated_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT native_work_text_revision_exact_original_fk
    FOREIGN KEY(organization_id,work_item_id)
    REFERENCES atlas.work_items(organization_id,id) ON DELETE RESTRICT,
  CONSTRAINT native_work_text_revision_actual_change
    CHECK(before_title IS DISTINCT FROM after_title OR
      before_instructions IS DISTINCT FROM after_instructions)
);
CREATE INDEX native_work_text_revision_original_order_v1
  ON atlas.native_work_text_revision_events_v1(work_item_id,recorded_at,id);
ALTER TABLE atlas.native_work_text_revision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.native_work_text_revision_events_v1 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.guard_native_work_text_revision_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Native Work amendment history is immutable'
    USING ERRCODE='42501';
END
$function$;
CREATE TRIGGER native_work_text_revision_append_only_v1
  BEFORE UPDATE OR DELETE ON atlas.native_work_text_revision_events_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.guard_native_work_text_revision_immutable_v1();

-- Fail-closed, shared source precondition: BOTH roots, exact native
-- Ledger provenance, institutional owner membership and original Work.
-- Does not infer authorization from Event/Today page or title.
CREATE FUNCTION atlas.require_native_original_work_text_owner_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS atlas.work_items
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_membership uuid;
  v_work atlas.work_items%ROWTYPE;
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Exact Organization, Ledger and original Work required'
      USING ERRCODE='22023';
  END IF;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_membership:=atlas.current_effective_organization_membership_v1(
    p_organization_id);
  IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=v_membership AND m.organization_id=p_organization_id
      AND m.person_id=v_person AND m.user_id=auth.uid()
      AND m.role='owner' AND m.active
  ) THEN
    RAISE EXCEPTION 'Exact signed institutional owner required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.household_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original native Company Work unavailable'
      USING ERRCODE='42501';
  END IF;
  -- Only Work natively authored into Ledger/Event Work by Atlas, not
  -- derived production/medical/legacy sources with their own edit laws.
  IF v_work.source_object_type IS NULL OR
     v_work.source_object_type NOT IN
     ('ledger_occurrence_shared_work','ledger_connected_direct_task') THEN
    RAISE EXCEPTION 'This source-managed Work requires its own edit authority'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id
      AND r.work_item_id=p_work_item_id
      AND r.ledger_id=p_ledger_id
      AND r.attribution_state='active'
      AND (
        r.evidence_kind IN ('owner_attested','participant_attested')
        OR (r.evidence_kind='source_verified' AND EXISTS(
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            p_work_item_id,p_ledger_id) proof
          WHERE proof.source_schema=r.source_schema
            AND proof.source_table=r.source_table
            AND proof.source_id=r.source_id))
      )
  ) THEN
    RAISE EXCEPTION 'Exact native Work/Ledger relevance is not established'
      USING ERRCODE='42501';
  END IF;
  RETURN v_work;
END
$function$;

CREATE FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
BEGIN
  v_work:=atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_text_owner_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',v_work.id,'title',v_work.title,
    'instructions',v_work.instructions,'workState',v_work.work_state,
    'updatedAt',v_work.updated_at,
    'canEdit',v_work.work_state='open',
    'oneOriginalWorkId',true);
END
$function$;

CREATE FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_expected_updated_at timestamptz,p_new_title text,p_new_instructions text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_new atlas.work_items%ROWTYPE;
  v_title text:=btrim(coalesce(p_new_title,''));
  v_instructions text:=nullif(btrim(coalesce(p_new_instructions,'')),'');
  v_event_id uuid;
BEGIN
  -- Before locking, the original signed source must prove all privileges.
  PERFORM atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  IF p_expected_updated_at IS NULL OR length(v_title) NOT BETWEEN 1 AND 240
     OR v_instructions IS NOT NULL AND length(v_instructions)>10000 THEN
    RAISE EXCEPTION 'Exact expected revision and bounded Work text required'
      USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
    FOR UPDATE;
  IF v_work.id IS NULL OR v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Only open original Work may be edited' USING ERRCODE='23514';
  END IF;
  IF v_work.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'Original Work changed since the editor opened; reload before editing'
      USING ERRCODE='40001';
  END IF;
  IF v_work.title IS NOT DISTINCT FROM v_title AND
     v_work.instructions IS NOT DISTINCT FROM v_instructions THEN
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_text_revision_v1',
      'workItemId',v_work.id,'title',v_work.title,
      'instructions',v_work.instructions,'updatedAt',v_work.updated_at,
      'changed',false,'oneOriginalWorkId',true);
  END IF;
  UPDATE atlas.work_items w
    SET title=v_title,instructions=v_instructions,updated_at=clock_timestamp()
    WHERE w.id=v_work.id AND w.organization_id=v_work.organization_id
    RETURNING * INTO v_new;
  INSERT INTO atlas.native_work_text_revision_events_v1(
    organization_id,ledger_id,work_item_id,actor_user_id,actor_person_id,
    before_title,after_title,before_instructions,after_instructions,
    old_updated_at,new_updated_at
  ) VALUES(
    p_organization_id,p_ledger_id,p_work_item_id,auth.uid(),
    atlas.current_person_id_v1(),v_work.title,v_new.title,
    v_work.instructions,v_new.instructions,v_work.updated_at,v_new.updated_at
  ) RETURNING id INTO v_event_id;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_text_revision_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',v_work.id,'title',v_new.title,
    'instructions',v_new.instructions,'updatedAt',v_new.updated_at,
    'changed',true,'revisionEventId',v_event_id,
    'oneOriginalWorkId',true,'changedNoResultOrAllocation',true);
END
$function$;

-- Own authored Result narrative only, under STILL-CURRENT exact
-- native owner access. A governor's title does NOT grant all workers'
-- private payloads. No comments/notifications are inferred.
CREATE FUNCTION atlas.read_native_original_work_own_results_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 30
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_items jsonb:='[]'::jsonb;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Result history page limit 1 to 100 required'
      USING ERRCODE='22023';
  END IF;
  v_work:=atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'resultId',x.id,'workItemId',x.work_item_id,
    'resultKind',x.result_kind,'reportedAt',x.reported_at,
    'note',x.payload->>'note','isOwnSignedReport',true
  ) ORDER BY x.reported_at DESC,x.id DESC),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT r.id,r.work_item_id,r.result_kind,r.reported_at,r.payload
    FROM atlas.work_execution_results r
    WHERE r.work_item_id=v_work.id
      AND r.organization_id=p_organization_id
      AND r.reported_by_user_id=auth.uid()
    ORDER BY r.reported_at DESC,r.id DESC LIMIT p_limit
  ) x;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_own_results_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'items',v_items,
    'ownReporterOnly',true,'otherPeopleReportsDisclosed',false,
    'oneOriginalWorkId',true);
END
$function$;

-- Public REST membrane, signed role only; internal source tables never
-- receive grants to browser roles. Mirror established Atlas RPC contracts.
CREATE FUNCTION public.read_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.read_native_original_work_text_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
$function$;
CREATE FUNCTION public.revise_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_expected_updated_at timestamptz,p_new_title text,p_new_instructions text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.revise_native_original_work_text_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,
    p_expected_updated_at,p_new_title,p_new_instructions);
$function$;
CREATE FUNCTION public.read_native_original_work_own_results_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 30
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.read_native_original_work_own_results_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_limit);
$function$;

REVOKE ALL ON FUNCTION atlas.require_native_original_work_text_owner_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.guard_native_work_text_revision_immutable_v1()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  TO authenticated;

REVOKE ALL ON FUNCTION public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  TO authenticated;
COMMIT;

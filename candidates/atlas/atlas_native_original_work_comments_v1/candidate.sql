BEGIN;
-- SOURCE CANDIDATE ONLY. Not an authorized Production migration.
-- One original Work; ordinary coordination ink is not Work Result,
-- delivery, assignment, acceptance, or a second Work item.

CREATE TABLE IF NOT EXISTS atlas.native_original_work_comments_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  organization_id uuid NOT NULL,
  ledger_id uuid NOT NULL,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  author_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  source_action_id uuid NOT NULL,
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT native_original_work_comment_replay_v1
    UNIQUE (organization_id, work_item_id, author_person_id, source_action_id)
);
CREATE INDEX IF NOT EXISTS native_original_work_comments_scope_order_v1
  ON atlas.native_original_work_comments_v1 (
    organization_id, ledger_id, work_item_id, recorded_at, id
  );
ALTER TABLE atlas.native_original_work_comments_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.native_original_work_comments_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- This is not a membership/seat grant. It admits an exact original Work
-- only after independent current native Ledger relevance, auth identity
-- and the Person's own Work or true native Ledger root responsibility.
CREATE OR REPLACE FUNCTION atlas.native_original_work_comment_actor_v1(
  p_organization_id uuid, p_ledger_id uuid, p_work_item_id uuid,
  p_write boolean
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_access jsonb;
  v_work atlas.work_items%rowtype;
  v_root boolean := false;
  v_person_work boolean := false;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL
     OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Signed exact original Work required' USING ERRCODE='42501';
  END IF;
  v_access := atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Current signed Personal Atlas required' USING ERRCODE='42501';
  END IF;
  v_person := atlas.current_person_id_v1();
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Current canonical Person required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
  WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id;
  IF v_work.id IS NULL OR v_work.work_state NOT IN ('open','completed')
     OR (p_write AND v_work.work_state<>'open') THEN
    RAISE EXCEPTION 'Active source Work unavailable' USING ERRCODE='42501';
  END IF;
  -- Work may be displayed in several notebooks, but only one exact native
  -- Ledger source may admit THIS request; avoid a title/date-derived guess.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id
      AND r.ledger_id=p_ledger_id AND r.work_item_id=p_work_item_id
      AND r.attribution_state='active'
      AND (
        r.evidence_kind IN ('owner_attested','participant_attested')
        OR (r.evidence_kind='source_verified' AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            r.work_item_id,r.ledger_id
          ) e
          WHERE e.source_schema=r.source_schema
            AND e.source_table=r.source_table AND e.source_id=r.source_id
        ))
      )
  ) THEN
    RAISE EXCEPTION 'Source-bound Ledger Work required' USING ERRCODE='42501';
  END IF;

  BEGIN
    v_root := coalesce(atlas.company_work_native_ledger_owner_self_v1(
      p_organization_id,p_ledger_id
    ) = v_person,false);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_root := false;
  END;
  IF v_root IS NOT TRUE THEN
    IF NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_person
    ) OR NOT atlas.person_original_work_identity_disclosed_self_v1(
      p_organization_id,p_ledger_id,p_work_item_id,v_person
    ) THEN
      RAISE EXCEPTION 'Work identity not disclosed to current Person'
        USING ERRCODE='42501';
    END IF;
    -- A Work-linked Event's identity must independently be disclosed.
    -- A Work assignment alone does not disclose an unrelated Event.
    IF EXISTS (
      SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=p_organization_id
        AND c.work_item_id=p_work_item_id
        AND c.subject_domain='temporal' AND c.subject_kind='occurrence'
        AND NOT atlas.has_current_subject_disclosure_v1(
          p_ledger_id,v_person,'event','occurrence',c.subject_id,'identity'
        )
    ) THEN
      RAISE EXCEPTION 'Event identity not disclosed to current Person'
        USING ERRCODE='42501';
    END IF;
    -- Other subject-context families are not classified for comment-body
    -- disclosure in this v1. Deny instead of extrapolating from a Work title.
    IF EXISTS (
      SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=p_organization_id
        AND c.work_item_id=p_work_item_id
        AND NOT (
          (c.subject_domain='spatial' AND c.subject_kind='growing_object')
          OR (c.subject_domain='temporal' AND c.subject_kind='occurrence')
        )
    ) THEN
      RAISE EXCEPTION 'Additional subject disclosure still held'
        USING ERRCODE='42501';
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM atlas.work_allocations a
      WHERE a.organization_id=p_organization_id
        AND a.work_item_id=p_work_item_id
        AND a.allocation_role='responsible'
        AND a.assignee_canonical_person_id=v_person
        AND a.assignee_membership_id IS NULL
        AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
        AND a.establishment_basis_kind IN (
          'person_connection_receiver_uptake',
          'delegated_under_standing_scope',
          'ledger_connection_direct_assignment',
          'original_subject_direct_assignment_v1',
          'self_adoption'
        )
        AND (a.state='active'
          OR (NOT p_write AND a.state='completed'
              AND v_work.work_state='completed'))
    ) INTO v_person_work;
    -- Accepted collaboration is a separate receiver-established allocation.
    -- Membership + Ledger connection alone are never enough.
    IF NOT v_person_work THEN
      SELECT EXISTS (
        SELECT 1 FROM atlas.work_allocations a
        JOIN atlas.organization_memberships m
          ON m.id=a.assignee_membership_id
          AND m.organization_id=a.organization_id
          AND m.person_id=v_person
        WHERE a.organization_id=p_organization_id
          AND a.work_item_id=p_work_item_id
          AND a.allocation_role IN ('participant','approver')
          AND a.establishment_basis_kind='receiver_acceptance'
          AND a.state='active'
          AND atlas.organization_membership_present_effective_at_v1(
            m.id,m.organization_id,now()
          )
      ) INTO v_person_work;
    END IF;
    IF NOT v_person_work THEN
      RAISE EXCEPTION 'Exact Work responsibility or accepted participation required'
        USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN v_person;
END
$function$;
REVOKE ALL ON FUNCTION atlas.native_original_work_comment_actor_v1(
  uuid,uuid,uuid,boolean
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.append_native_original_work_comment_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_source_action_id uuid,p_body text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_body text := btrim(coalesce(p_body,''));
  v_comment atlas.native_original_work_comments_v1%rowtype;
BEGIN
  IF p_source_action_id IS NULL OR length(v_body) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION 'Bounded body and stable action ID required'
      USING ERRCODE='22023';
  END IF;
  -- A genuine same-action replay remains verifiable after an unrelated
  -- actor completes Work. Read access remains independently authorized;
  -- a new write still requires the Work to be open at its own locked point.
  v_actor := atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,false
  );
  SELECT * INTO v_comment FROM atlas.native_original_work_comments_v1 c
  WHERE c.organization_id=p_organization_id
    AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
    AND c.author_person_id=v_actor AND c.source_action_id=p_source_action_id;
  IF v_comment.id IS NOT NULL THEN
    IF v_comment.body<>v_body THEN
      RAISE EXCEPTION 'Idempotency action cannot change authored body'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_comment_write_v1',
      'organizationId',p_organization_id,'ledgerId',p_ledger_id,
      'workItemId',p_work_item_id,'commentId',v_comment.id,
      'recordedAt',v_comment.recorded_at,'body',v_comment.body,
      'idempotent',true,'originalWorkStateUnchanged',true,
      'isWorkResult',false,'notificationDelivered',false
    );
  END IF;
  -- The original must still be open. Never append new ink using historical
  -- permission from a completed or retired responsibility allocation.
  PERFORM 1 FROM atlas.work_items w WHERE w.id=p_work_item_id
    AND w.organization_id=p_organization_id AND w.work_state='open'
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original Work no longer open' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,true
  );
  INSERT INTO atlas.native_original_work_comments_v1(
    organization_id,ledger_id,work_item_id,author_person_id,source_action_id,body
  ) VALUES(
    p_organization_id,p_ledger_id,p_work_item_id,v_actor,p_source_action_id,v_body
  )
  ON CONFLICT ON CONSTRAINT native_original_work_comment_replay_v1 DO NOTHING
  RETURNING * INTO v_comment;
  IF v_comment.id IS NULL THEN
    SELECT * INTO v_comment FROM atlas.native_original_work_comments_v1 c
    WHERE c.organization_id=p_organization_id
      AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
      AND c.author_person_id=v_actor AND c.source_action_id=p_source_action_id;
    IF v_comment.id IS NULL OR v_comment.body<>v_body THEN
      RAISE EXCEPTION 'Concurrent idempotency identity collision'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_comment_write_v1',
      'organizationId',p_organization_id,'ledgerId',p_ledger_id,
      'workItemId',p_work_item_id,'commentId',v_comment.id,
      'recordedAt',v_comment.recorded_at,'body',v_comment.body,
      'idempotent',true,'originalWorkStateUnchanged',true,
      'isWorkResult',false,'notificationDelivered',false
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_comment_write_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'commentId',v_comment.id,
    'recordedAt',v_comment.recorded_at,'body',v_comment.body,
    'idempotent',false,'originalWorkStateUnchanged',true,
    'isWorkResult',false,'notificationDelivered',false
  );
END
$function$;
REVOKE ALL ON FUNCTION atlas.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.read_native_original_work_comments_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 40,
  p_after_recorded_at timestamptz DEFAULT NULL,
  p_after_comment_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_items jsonb := '[]'::jsonb;
  v_more boolean := false;
  v_next_at timestamptz;
  v_next_id uuid;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR
    (p_after_recorded_at IS NULL)<>(p_after_comment_id IS NULL) THEN
    RAISE EXCEPTION 'Bounded page and complete cursor required'
      USING ERRCODE='22023';
  END IF;
  v_actor := atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,false
  );
  WITH bounded AS (
    SELECT c.id,c.recorded_at,c.body,c.author_person_id
    FROM atlas.native_original_work_comments_v1 c
    WHERE c.organization_id=p_organization_id
      AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
      AND (p_after_recorded_at IS NULL OR
           (c.recorded_at,c.id)<(p_after_recorded_at,p_after_comment_id))
    ORDER BY c.recorded_at DESC,c.id DESC LIMIT p_limit+1
  ), numbered AS (
    SELECT b.*,row_number() OVER (ORDER BY b.recorded_at DESC,b.id DESC) AS rn
    FROM bounded b
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'commentId',s.id,'workItemId',p_work_item_id,'body',s.body,
      'recordedAt',s.recorded_at,'authoredBySelf',s.author_person_id=v_actor
    ) ORDER BY s.recorded_at DESC,s.id DESC) FILTER(WHERE s.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,
    (array_agg(s.recorded_at ORDER BY s.rn)
      FILTER(WHERE s.rn=p_limit))[1],
    (array_agg(s.id ORDER BY s.rn)
      FILTER(WHERE s.rn=p_limit))[1]
  INTO v_items,v_more,v_next_at,v_next_id FROM numbered s;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_comments_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'items',v_items,
    'hasMore',coalesce(v_more,false),
    'nextRecordedAt',CASE WHEN v_more THEN v_next_at ELSE NULL END,
    'nextCommentId',CASE WHEN v_more THEN v_next_id ELSE NULL END,
    'containsWorkResults',false,'isNotificationInbox',false,
    'authorsPreservedInCanonicalSource',true,
    'authorIdentityDisclosure','self_boolean_only'
  );
END
$function$;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) FROM PUBLIC, anon, authenticated, service_role;

-- Public RPCs are the ONLY browser entrypoints. Browser roles cannot read
-- private table or invoke the internal authorization function directly.
CREATE OR REPLACE FUNCTION public.append_native_original_work_comment_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_source_action_id uuid,p_body text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $wrapper$
  SELECT atlas.append_native_original_work_comment_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_source_action_id,p_body);
$wrapper$;
REVOKE ALL ON FUNCTION public.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_native_original_work_comments_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 40,
  p_after_recorded_at timestamptz DEFAULT NULL,
  p_after_comment_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $wrapper$
  SELECT atlas.read_native_original_work_comments_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_limit,
    p_after_recorded_at,p_after_comment_id);
$wrapper$;
REVOKE ALL ON FUNCTION public.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) TO authenticated;

-- Even a privileged adapter may not silently rewrite the originally
-- authored comment. Corrections require a separate explicitly governed event.
CREATE OR REPLACE FUNCTION atlas.reject_native_original_work_comment_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Original Work comments are immutable; append a correction'
    USING ERRCODE='42501';
END
$function$;
REVOKE ALL ON FUNCTION atlas.reject_native_original_work_comment_mutation_v1()
  FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS reject_native_original_work_comment_mutation_v1
  ON atlas.native_original_work_comments_v1;
CREATE TRIGGER reject_native_original_work_comment_mutation_v1
  BEFORE UPDATE OR DELETE ON atlas.native_original_work_comments_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.reject_native_original_work_comment_mutation_v1();

COMMIT;

-- ATLAS BUILD 3 / SOURCE-ONLY CANDIDATE — NOT RELEASED.
-- Canonical schema ownership: optical-lift/noel-core-db.
-- Run only in an authorized disposable schema clone after review.
-- No private people, Katie records, invitation, Auth or subscription rows.
BEGIN;

CREATE TABLE atlas.prepared_person_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  target_kind text NOT NULL CHECK (target_kind IN ('existing_person','provisional_person')),
  person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
  provisional_label text,
  scope_basis text NOT NULL CHECK (length(btrim(scope_basis)) BETWEEN 30 AND 1800),
  prepared_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  case_state text NOT NULL DEFAULT 'preparing'
    CHECK (case_state IN ('preparing','issued','withdrawn')),
  request_key text NOT NULL CHECK (length(btrim(request_key)) BETWEEN 8 AND 160),
  opened_at timestamptz NOT NULL DEFAULT now(),
  issued_at timestamptz,
  issued_by_user_id uuid REFERENCES auth.users(id),
  CHECK (
    (target_kind='existing_person' AND person_entity_id IS NOT NULL AND provisional_label IS NULL)
    OR
    (target_kind='provisional_person' AND person_entity_id IS NULL
       AND length(btrim(coalesce(provisional_label,''))) BETWEEN 2 AND 160)
  ),
  CHECK ((case_state='issued') = (issued_at IS NOT NULL))
);
CREATE UNIQUE INDEX prepared_person_case_request_v1
 ON atlas.prepared_person_cases(organization_id,prepared_by_user_id,request_key);
CREATE UNIQUE INDEX prepared_person_one_open_existing_v1
 ON atlas.prepared_person_cases(organization_id,person_entity_id)
 WHERE target_kind='existing_person' AND case_state='preparing';

CREATE TABLE atlas.prepared_person_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 case_id uuid NOT NULL REFERENCES atlas.prepared_person_cases(id) ON DELETE RESTRICT,
 evidence_record_id uuid NOT NULL UNIQUE REFERENCES atlas.evidence_records(id) ON DELETE RESTRICT,
 topic text NOT NULL CHECK (length(btrim(topic)) BETWEEN 2 AND 100),
 classification text NOT NULL CHECK (classification IN (
   'established_canonical','authorized_institutional',
   'operator_attested','authored_personal_proposal','missing_disputed'
 )),
 disclosure text NOT NULL CHECK (disclosure IN ('operator_only','recipient_review','withheld')),
 linked_record_kind text CHECK (linked_record_kind IN (
   'person','institutional_person_record',
   'organization_occurrence_binding','work_allocation','ledger_seat'
 )),
 linked_record_id uuid,
 revises_item_id uuid REFERENCES atlas.prepared_person_items(id) ON DELETE RESTRICT,
 conflicts_with_item_id uuid REFERENCES atlas.prepared_person_items(id) ON DELETE RESTRICT,
 authored_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (
   (classification IN ('established_canonical','authorized_institutional')
     AND linked_record_kind IS NOT NULL AND linked_record_id IS NOT NULL)
   OR
   (classification NOT IN ('established_canonical','authorized_institutional')
     AND linked_record_kind IS NULL AND linked_record_id IS NULL)
 ),
 CHECK (revises_item_id IS NULL OR revises_item_id<>id),
 CHECK (conflicts_with_item_id IS NULL OR conflicts_with_item_id<>id)
);
CREATE INDEX prepared_person_items_case_time_v1
 ON atlas.prepared_person_items(case_id,created_at,id);

CREATE TABLE atlas.prepared_person_decision_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 item_id uuid NOT NULL REFERENCES atlas.prepared_person_items(id) ON DELETE RESTRICT,
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decided_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 decision text NOT NULL CHECK (decision IN ('accept','reject','correct','defer')),
 correction_text text,
 request_key text NOT NULL CHECK (length(btrim(request_key)) BETWEEN 8 AND 160),
 decided_at timestamptz NOT NULL DEFAULT now(),
 CHECK ((decision='correct' AND length(btrim(coalesce(correction_text,''))) BETWEEN 3 AND 2000)
        OR (decision<>'correct' AND correction_text IS NULL)),
 UNIQUE(item_id,decided_by_user_id,request_key)
);
CREATE INDEX prepared_person_decisions_latest_v1
 ON atlas.prepared_person_decision_receipts(item_id,decided_at DESC,id DESC);

-- These are custody objects, never generic public fact storage.
-- No direct table API: only narrowly authorized commands and projections.
ALTER TABLE atlas.prepared_person_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.prepared_person_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.prepared_person_decision_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.prepared_person_cases,atlas.prepared_person_items,
  atlas.prepared_person_decision_receipts FROM PUBLIC,anon,authenticated;

-- Professional implementation access is always a scoped grant from an actual
-- institutional steward; professional login alone cannot inspect people.
CREATE TABLE atlas.prepared_person_operator_grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 case_id uuid NOT NULL REFERENCES atlas.prepared_person_cases(id) ON DELETE RESTRICT,
 practitioner_user_id uuid NOT NULL
   REFERENCES atlas.implementation_practitioners(human_user_id) ON DELETE RESTRICT,
 granted_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 grant_reason text NOT NULL CHECK (length(btrim(grant_reason)) BETWEEN 30 AND 1500),
 can_issue boolean NOT NULL DEFAULT false,
 can_inspect_org_events boolean NOT NULL DEFAULT false,
 granted_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz,
 revoked_by_user_id uuid REFERENCES auth.users(id),
 CHECK ((revoked_at IS NULL)=(revoked_by_user_id IS NULL))
);
CREATE UNIQUE INDEX prepared_person_one_active_practitioner_v1
 ON atlas.prepared_person_operator_grants(case_id,practitioner_user_id)
 WHERE revoked_at IS NULL;
ALTER TABLE atlas.prepared_person_operator_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.prepared_person_operator_grants FROM PUBLIC,anon,authenticated;

-- The signed actor's present-day grant and its original issuing steward's
-- current authority must both remain valid. Revoked authority is not inherited.
CREATE FUNCTION atlas.prepared_person_actor_allowed_v1(
 p_case_id uuid,p_operation text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT auth.uid() IS NOT NULL AND p_operation IN ('read','record','issue')
 AND EXISTS (
  SELECT 1 FROM atlas.prepared_person_cases c
  JOIN atlas.organizations o ON o.id=c.organization_id AND o.status='active'
  WHERE c.id=p_case_id AND (
   (c.prepared_by_user_id=auth.uid()
    AND EXISTS(SELECT 1 FROM atlas.organization_memberships om
      WHERE om.organization_id=c.organization_id AND om.user_id=auth.uid()
        AND om.active AND om.role IN ('owner','consultant'))
    AND (c.target_kind='provisional_person'
      OR atlas.existing_person_claim_actor_steward_v1(
        c.organization_id,c.person_entity_id,auth.uid())))
   OR EXISTS (
     SELECT 1 FROM atlas.prepared_person_operator_grants g
     JOIN atlas.implementation_practitioners pr
       ON pr.human_user_id=g.practitioner_user_id AND pr.status='active'
     WHERE g.case_id=c.id AND g.practitioner_user_id=auth.uid()
       AND g.revoked_at IS NULL
       AND (p_operation<>'issue' OR g.can_issue)
       AND NOT EXISTS(SELECT 1 FROM atlas.principals principal
         WHERE principal.user_id=auth.uid() AND principal.status='active')
       AND EXISTS(SELECT 1 FROM atlas.organization_memberships om
         WHERE om.organization_id=c.organization_id
           AND om.user_id=g.granted_by_user_id AND om.active
           AND om.role IN ('owner','consultant'))
       AND (c.target_kind='provisional_person'
         OR atlas.existing_person_claim_actor_steward_v1(
           c.organization_id,c.person_entity_id,g.granted_by_user_id))
   )
  )
 );
$fn$;

CREATE FUNCTION atlas.prepared_person_assign_practitioner_self_api_v1(
 p_case_id uuid,p_practitioner_user_id uuid,p_grant_reason text,
 p_can_issue boolean DEFAULT false,p_can_inspect_org_events boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype;
 v_existing atlas.prepared_person_operator_grants%rowtype; v_grant_id uuid;
BEGIN
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases
 WHERE id=p_case_id FOR UPDATE;
 PERFORM atlas.require_identity_steward_v1(v_case.organization_id);
 IF v_case.prepared_by_user_id IS DISTINCT FROM auth.uid()
    OR v_case.case_state<>'preparing' OR
    (v_case.target_kind='existing_person' AND NOT
      atlas.existing_person_claim_actor_steward_v1(
        v_case.organization_id,v_case.person_entity_id,auth.uid())) THEN
  RAISE EXCEPTION 'Current preparer-steward only may delegate this case'
     USING errcode='42501';
 END IF;
 IF length(btrim(coalesce(p_grant_reason,''))) NOT BETWEEN 30 AND 1500 OR
    NOT EXISTS (SELECT 1 FROM atlas.implementation_practitioners ip
       WHERE ip.human_user_id=p_practitioner_user_id AND ip.status='active')
    OR EXISTS (SELECT 1 FROM atlas.principals p
       WHERE p.user_id=p_practitioner_user_id AND p.status='active') THEN
  RAISE EXCEPTION 'Verified separate practitioner credential and delegation basis required'
     USING errcode='42501';
 END IF;
 SELECT * INTO v_existing FROM atlas.prepared_person_operator_grants
  WHERE case_id=p_case_id AND practitioner_user_id=p_practitioner_user_id
    AND revoked_at IS NULL FOR UPDATE;
 IF FOUND THEN
   IF v_existing.granted_by_user_id=auth.uid()
      AND v_existing.grant_reason=btrim(p_grant_reason)
      AND v_existing.can_issue=coalesce(p_can_issue,false)
      AND v_existing.can_inspect_org_events=coalesce(p_can_inspect_org_events,false) THEN
     RETURN jsonb_build_object('ok',true,'grantId',v_existing.id,
       'caseId',p_case_id,'practitionerUserId',p_practitioner_user_id,
       'canIssue',v_existing.can_issue,
       'canInspectOrgEvents',v_existing.can_inspect_org_events,'replay',true);
   END IF;
   RAISE EXCEPTION 'Grant exists with different authority; revoke before replacing'
     USING errcode='23505';
 END IF;
 INSERT INTO atlas.prepared_person_operator_grants
   (case_id,practitioner_user_id,granted_by_user_id,grant_reason,
     can_issue,can_inspect_org_events)
 VALUES(p_case_id,p_practitioner_user_id,auth.uid(),btrim(p_grant_reason),
        coalesce(p_can_issue,false),coalesce(p_can_inspect_org_events,false))
 RETURNING id INTO v_grant_id;
 RETURN jsonb_build_object('ok',true,'grantId',v_grant_id,'caseId',p_case_id,
    'practitionerUserId',p_practitioner_user_id,
    'canIssue',coalesce(p_can_issue,false),
    'canInspectOrgEvents',coalesce(p_can_inspect_org_events,false));
END $fn$;

-- Email locates a confirmed *professional Auth credential* only; this is
-- not a name/email-based Person identity resolution or Person construction.
CREATE FUNCTION atlas.prepared_person_assign_practitioner_email_self_api_v1(
 p_case_id uuid,p_practitioner_email text,p_grant_reason text,
 p_can_issue boolean DEFAULT false,p_can_inspect_org_events boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype; v_target uuid; v_count integer;
BEGIN
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases WHERE id=p_case_id;
 PERFORM atlas.require_identity_steward_v1(v_case.organization_id);
 IF v_case.prepared_by_user_id<>auth.uid() OR v_case.case_state<>'preparing'
   OR (v_case.target_kind='existing_person' AND NOT
       atlas.existing_person_claim_actor_steward_v1(
       v_case.organization_id,v_case.person_entity_id,auth.uid())) THEN
    RAISE EXCEPTION 'Exact case stewardship required' USING errcode='42501';
 END IF;
 IF length(btrim(coalesce(p_practitioner_email,''))) NOT BETWEEN 5 AND 320 THEN
   RAISE EXCEPTION 'Exact confirmed practitioner email required' USING errcode='22023';
 END IF;
 SELECT count(*)::integer, (array_agg(u.id))[1] INTO v_count,v_target
 FROM auth.users u
 JOIN atlas.implementation_practitioners p ON p.human_user_id=u.id
   AND p.status='active'
 WHERE lower(btrim(u.email))=lower(btrim(p_practitioner_email))
   AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL
   AND (u.banned_until IS NULL OR u.banned_until<=now());
 IF v_count<>1 THEN
   RAISE EXCEPTION 'One confirmed active practitioner credential required'
      USING errcode='42501';
 END IF;
 RETURN atlas.prepared_person_assign_practitioner_self_api_v1(
   p_case_id,v_target,p_grant_reason,p_can_issue,p_can_inspect_org_events);
END $fn$;

CREATE FUNCTION atlas.prepared_person_revoke_practitioner_self_api_v1(
 p_grant_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype; v_grant atlas.prepared_person_operator_grants%rowtype;
BEGIN
 SELECT * INTO STRICT v_grant FROM atlas.prepared_person_operator_grants
 WHERE id=p_grant_id FOR UPDATE;
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases WHERE id=v_grant.case_id;
 PERFORM atlas.require_identity_steward_v1(v_case.organization_id);
 IF v_case.prepared_by_user_id<>auth.uid() OR
    (v_case.target_kind='existing_person' AND NOT
     atlas.existing_person_claim_actor_steward_v1(
       v_case.organization_id,v_case.person_entity_id,auth.uid())) THEN
  RAISE EXCEPTION 'Current preparer-steward required to revoke'
    USING errcode='42501';
 END IF;
 IF v_grant.revoked_at IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'alreadyRevoked',true);
 END IF;
 UPDATE atlas.prepared_person_operator_grants
 SET revoked_at=now(),revoked_by_user_id=auth.uid() WHERE id=p_grant_id;
 RETURN jsonb_build_object('ok',true,'revoked',true,'grantId',p_grant_id);
END $fn$;

-- This internal permission predicate may be invoked by other definer functions,
-- not by generic client callers or third-party session carriers.
REVOKE ALL ON FUNCTION atlas.prepared_person_actor_allowed_v1(uuid,text)
 FROM PUBLIC,anon,authenticated;

-- Source: existing signed identity-steward authority.
-- A real Person must already be canonical and institutionally in scope.
-- Small, signed steward selector; no public directory and no inferred identity.
CREATE FUNCTION atlas.prepared_person_scope_options_self_api_v1(
 p_organization_id uuid DEFAULT NULL,p_query text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_organizations jsonb; v_people jsonb:='[]'::jsonb;
BEGIN
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Signed steward required' USING errcode='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'organizationId',o.id,'organizationLabel',o.name) ORDER BY o.name,o.id),'[]'::jsonb)
 INTO v_organizations
 FROM (SELECT DISTINCT om.organization_id
       FROM atlas.organization_memberships om
       WHERE om.user_id=auth.uid() AND om.active
         AND om.role IN ('owner','consultant')) scope
 JOIN atlas.organizations o ON o.id=scope.organization_id
  AND o.status='active';
 IF p_organization_id IS NOT NULL THEN
   PERFORM atlas.require_identity_steward_v1(p_organization_id);
   SELECT coalesce(jsonb_agg(row_data ORDER BY display_name,person_id),'[]'::jsonb)
    INTO v_people FROM (
     SELECT p.id AS person_id,p.display_name,
       jsonb_build_object('personId',p.id,'displayName',p.display_name,
                         'institutionalPersonRecordId',r.id) AS row_data
     FROM atlas.people p
     JOIN reality.entities e ON e.id=p.id AND e.entity_kind='person'
       AND e.identity_state='canonical'
     LEFT JOIN LATERAL (
       SELECT r.id FROM atlas.institutional_person_records r
       WHERE r.organization_id=p_organization_id AND r.person_id=p.id
         AND r.status='active' ORDER BY r.created_at LIMIT 1
     ) r ON true
     WHERE p.status='active'
       AND (r.id IS NOT NULL OR EXISTS (
         SELECT 1 FROM atlas.ledger_organization_participations lop
         JOIN ledger.seats s ON s.ledger_id=lop.ledger_id
           AND s.person_entity_id=p.id AND s.seat_state='active'
           AND s.ended_at IS NULL
         WHERE lop.organization_id=p_organization_id
           AND lop.status='active' AND lop.ended_at IS NULL
           AND lop.participation_kind IN ('governing','operating')))
       AND atlas.existing_person_claim_actor_steward_v1(
         p_organization_id,p.id,auth.uid())
       AND (btrim(coalesce(p_query,''))=''
           OR lower(p.display_name) LIKE '%'||lower(btrim(p_query))||'%')
     ORDER BY p.display_name,p.id
     LIMIT 25
   ) bounded;
 END IF;
 RETURN jsonb_build_object('ok',true,'organizations',v_organizations,
                            'people',v_people);
END $fn$;

CREATE FUNCTION atlas.prepared_person_begin_self_api_v1(
 p_organization_id uuid,p_target_kind text,p_person_entity_id uuid,
 p_provisional_label text,p_scope_basis text,p_request_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_existing atlas.prepared_person_cases%rowtype; v_id uuid;
BEGIN
 PERFORM atlas.require_identity_steward_v1(p_organization_id);
 IF p_target_kind NOT IN ('existing_person','provisional_person') THEN
   RAISE EXCEPTION 'Unsupported Person target' USING errcode='22023';
 END IF;
 IF p_target_kind='existing_person' THEN
   PERFORM atlas.existing_person_claim_steward_self_v1(p_organization_id,p_person_entity_id);
 ELSIF p_person_entity_id IS NOT NULL OR
   length(btrim(coalesce(p_provisional_label,''))) NOT BETWEEN 2 AND 160 THEN
   RAISE EXCEPTION 'Provisional label required without a fabricated Person ID'
     USING errcode='22023';
 END IF;
 IF length(btrim(coalesce(p_scope_basis,''))) NOT BETWEEN 30 AND 1800
    OR length(btrim(coalesce(p_request_key,''))) NOT BETWEEN 8 AND 160 THEN
   RAISE EXCEPTION 'Source authority and request receipt required' USING errcode='22023';
 END IF;
 SELECT * INTO v_existing FROM atlas.prepared_person_cases
  WHERE organization_id=p_organization_id AND prepared_by_user_id=auth.uid()
    AND request_key=p_request_key;
 IF FOUND THEN
   IF v_existing.target_kind<>p_target_kind
     OR v_existing.person_entity_id IS DISTINCT FROM p_person_entity_id
     OR v_existing.provisional_label IS DISTINCT FROM
         (CASE WHEN p_target_kind='provisional_person' THEN btrim(p_provisional_label) ELSE NULL END)
   THEN RAISE EXCEPTION 'Request key reused for a different target' USING errcode='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'caseId',v_existing.id,'state',v_existing.case_state,'replay',true);
 END IF;
 INSERT INTO atlas.prepared_person_cases
  (organization_id,target_kind,person_entity_id,provisional_label,
    scope_basis,prepared_by_user_id,request_key)
 VALUES(p_organization_id,p_target_kind,p_person_entity_id,
    CASE WHEN p_target_kind='provisional_person' THEN btrim(p_provisional_label) ELSE NULL END,
    btrim(p_scope_basis),auth.uid(),p_request_key)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('ok',true,'caseId',v_id,'state','preparing',
                           'canonicalPersonCreated',false);
END $fn$;

-- Author remains the actual signed operator. Permission to use a source
-- does not arise from its public accessibility or a browser URL.
CREATE FUNCTION atlas.prepared_person_record_self_api_v1(
 p_case_id uuid,p_request_key text,p_topic text,p_literal_text text,
 p_source_kind text,p_source_locator text,p_source_permission_basis text,
 p_observed_at timestamptz,p_confidence numeric,p_classification text,
 p_disclosure text,p_recipient_disclosure_basis text DEFAULT NULL,
 p_linked_record_kind text DEFAULT NULL,p_linked_record_id uuid DEFAULT NULL,
 p_revises_item_id uuid DEFAULT NULL,p_conflicts_with_item_id uuid DEFAULT NULL,
 p_effective_from timestamptz DEFAULT NULL,p_effective_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype;
 v_existing atlas.prepared_person_items%rowtype;
 v_old_id uuid; v_evidence_id uuid; v_item_id uuid; v_subject text;
BEGIN
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases
   WHERE id=p_case_id FOR UPDATE;
 IF v_case.case_state<>'preparing' OR NOT
     atlas.prepared_person_actor_allowed_v1(p_case_id,'record') THEN
   RAISE EXCEPTION 'Current scoped operator required to record evidence'
     USING errcode='42501';
 END IF;
 IF length(btrim(coalesce(p_request_key,''))) NOT BETWEEN 8 AND 160
  OR length(btrim(coalesce(p_topic,''))) NOT BETWEEN 2 AND 100
  OR length(btrim(coalesce(p_literal_text,''))) NOT BETWEEN 3 AND 2000
  OR length(btrim(coalesce(p_source_locator,''))) NOT BETWEEN 3 AND 1200
  OR length(btrim(coalesce(p_source_permission_basis,''))) NOT BETWEEN 20 AND 1500 THEN
   RAISE EXCEPTION 'Source, original wording, permission and operation key required' USING errcode='22023';
 END IF;
 IF p_source_kind NOT IN ('operator_firsthand','public_source','authorized_document',
                        'authorized_connected','canonical_record','operator_authored') OR
    p_classification NOT IN ('established_canonical','authorized_institutional',
     'operator_attested','authored_personal_proposal','missing_disputed') OR
    p_disclosure NOT IN ('operator_only','recipient_review','withheld') THEN
   RAISE EXCEPTION 'Unsupported custody classification' USING errcode='22023';
 END IF;
 IF p_disclosure='recipient_review' AND
   length(btrim(coalesce(p_recipient_disclosure_basis,''))) NOT BETWEEN 20 AND 1500 THEN
   RAISE EXCEPTION 'Recipient disclosure requires explicit source authority basis'
     USING errcode='42501';
 END IF;
 IF p_confidence IS NOT NULL AND (p_confidence<0 OR p_confidence>1) THEN
   RAISE EXCEPTION 'Confidence must be between 0 and 1' USING errcode='22023';
 END IF;
 IF p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL
    AND p_effective_until<p_effective_from THEN
   RAISE EXCEPTION 'Effective end must not precede effective start'
     USING errcode='22023';
 END IF;
 IF p_classification IN ('established_canonical','authorized_institutional') THEN
   IF p_linked_record_kind='person' AND
       p_classification='established_canonical' AND
       v_case.target_kind='existing_person' AND
       p_linked_record_id=v_case.person_entity_id AND
       EXISTS(SELECT 1 FROM reality.entities e WHERE e.id=p_linked_record_id
         AND e.entity_kind='person' AND e.identity_state='canonical') THEN
     NULL; -- exact existing identity, not a new Person.
   ELSIF p_linked_record_kind='institutional_person_record' AND
       p_classification='authorized_institutional' AND
       EXISTS(SELECT 1 FROM atlas.institutional_person_records r
        WHERE r.id=p_linked_record_id AND r.organization_id=v_case.organization_id
          AND r.person_id=v_case.person_entity_id AND r.status='active') THEN
     NULL; -- exact organization-owned relationship, not a new seat.
   ELSIF p_linked_record_kind='organization_occurrence_binding' AND
       p_classification='authorized_institutional' AND
       v_case.target_kind='existing_person' AND EXISTS (
         SELECT 1 FROM atlas.organization_occurrence_bindings ob
         JOIN local_intel.occurrences occ ON occ.id=ob.occurrence_id
         WHERE ob.id=p_linked_record_id AND ob.organization_id=v_case.organization_id
           AND ob.binding_state='active'
           AND (v_case.prepared_by_user_id=auth.uid()
              OR EXISTS(
                SELECT 1 FROM atlas.prepared_person_operator_grants grant_event
                WHERE grant_event.case_id=p_case_id
                  AND grant_event.practitioner_user_id=auth.uid()
                  AND grant_event.revoked_at IS NULL
                  AND grant_event.can_inspect_org_events
              ))) THEN
     NULL; -- steward-authorized Event source access only.
   ELSIF p_linked_record_kind='work_allocation' AND
       p_classification='authorized_institutional' AND EXISTS (
         SELECT 1 FROM atlas.work_allocations a
         JOIN atlas.work_items w ON w.id=a.work_item_id
           AND w.organization_id=v_case.organization_id
         WHERE a.id=p_linked_record_id AND a.organization_id=v_case.organization_id
           AND a.assignee_canonical_person_id=v_case.person_entity_id
           AND a.state='active') THEN
     NULL; -- this exact Person's real active allocation, no new Work.
   ELSIF p_linked_record_kind='ledger_seat' AND
       p_classification='authorized_institutional' AND EXISTS (
         SELECT 1 FROM ledger.seats seat
         JOIN atlas.ledger_organization_participations lop
           ON lop.ledger_id=seat.ledger_id
         JOIN ledger.ledgers led ON led.id=seat.ledger_id
         WHERE seat.id=p_linked_record_id
           AND seat.person_entity_id=v_case.person_entity_id
           AND seat.seat_state='active' AND seat.ended_at IS NULL
           AND led.ledger_state='active' AND led.retired_at IS NULL
           AND lop.organization_id=v_case.organization_id
           AND lop.status='active' AND lop.ended_at IS NULL
           AND lop.participation_kind IN ('governing','operating')) THEN
     NULL; -- original active native Ledger seat.
   ELSE
     RAISE EXCEPTION 'Referenced canonical domain record not proved in scope'
       USING errcode='42501';
   END IF;
 ELSIF p_linked_record_kind IS NOT NULL OR p_linked_record_id IS NOT NULL THEN
   RAISE EXCEPTION 'Operator testimony cannot claim canonical effect' USING errcode='22023';
 END IF;
 IF p_revises_item_id IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM atlas.prepared_person_items i
      WHERE i.id=p_revises_item_id AND i.case_id=p_case_id) THEN
    RAISE EXCEPTION 'Revision must remain in the same case' USING errcode='22023';
 END IF;
 IF p_conflicts_with_item_id IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM atlas.prepared_person_items i
      WHERE i.id=p_conflicts_with_item_id AND i.case_id=p_case_id) THEN
    RAISE EXCEPTION 'Conflict reference must remain in the same case' USING errcode='22023';
 END IF;
 -- Replaying a request must not manufacture a second record or overwrite evidence.
 SELECT i.* INTO v_existing FROM atlas.prepared_person_items i
 JOIN atlas.evidence_records e ON e.id=i.evidence_record_id
 WHERE i.case_id=p_case_id AND e.scope_kind='prepared_person_case'
   AND e.scope_id=p_case_id AND e.source_kind=p_source_kind AND e.source_key=p_request_key;
 IF FOUND THEN
   IF NOT EXISTS (
      SELECT 1 FROM atlas.evidence_records evidence
      WHERE evidence.id=v_existing.evidence_record_id
        AND evidence.value->>'literalText'=p_literal_text
        AND evidence.value->>'topic'=p_topic
        AND evidence.value->>'sourceLocator'=p_source_locator
        AND evidence.provenance->>'sourcePermissionBasis'=p_source_permission_basis
        AND evidence.provenance->>'recipientDisclosureBasis' IS NOT DISTINCT FROM
            p_recipient_disclosure_basis
        AND evidence.observed_at IS NOT DISTINCT FROM p_observed_at
        AND evidence.effective_from IS NOT DISTINCT FROM p_effective_from
        AND evidence.effective_until IS NOT DISTINCT FROM p_effective_until
        AND evidence.confidence IS NOT DISTINCT FROM p_confidence
        AND v_existing.classification=p_classification
        AND v_existing.disclosure=p_disclosure
        AND v_existing.linked_record_kind IS NOT DISTINCT FROM p_linked_record_kind
        AND v_existing.linked_record_id IS NOT DISTINCT FROM p_linked_record_id
        AND v_existing.revises_item_id IS NOT DISTINCT FROM p_revises_item_id
        AND v_existing.conflicts_with_item_id IS NOT DISTINCT FROM p_conflicts_with_item_id
   ) THEN
      RAISE EXCEPTION 'Operation key reused for different evidence' USING errcode='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'itemId',v_existing.id,'evidenceId',
     v_existing.evidence_record_id,'replay',true);
 END IF;
 v_subject:=CASE WHEN v_case.target_kind='existing_person'
   THEN v_case.person_entity_id::text ELSE 'unbound-case:'||p_case_id::text END;
 INSERT INTO atlas.evidence_records
   (scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    evidence_kind,source_kind,source_key,actor_user_id,value,confidence,
    observed_at,learned_at,effective_from,effective_until,provenance,metadata)
 VALUES ('prepared_person_case',p_case_id,'person',v_case.target_kind,v_subject,
  'prepared_person_original_observation',p_source_kind,p_request_key,auth.uid(),
  jsonb_build_object('literalText',p_literal_text,'topic',p_topic,'sourceLocator',p_source_locator),
  p_confidence,p_observed_at,now(),p_effective_from,p_effective_until,
  jsonb_build_object('recordedByUserId',auth.uid(),'sourcePermissionBasis',p_source_permission_basis,
    'recipientDisclosureBasis',p_recipient_disclosure_basis,
    'observationNotAcceptance',true),
  jsonb_build_object('caseId',p_case_id,'foundryStage','testimony',
    'noCanonicalPromotion',true))
 RETURNING id INTO v_evidence_id;
 INSERT INTO atlas.prepared_person_items
  (case_id,evidence_record_id,topic,classification,disclosure,linked_record_kind,
    linked_record_id,revises_item_id,conflicts_with_item_id,authored_by_user_id)
 VALUES(p_case_id,v_evidence_id,p_topic,p_classification,p_disclosure,
   p_linked_record_kind,p_linked_record_id,p_revises_item_id,
   p_conflicts_with_item_id,auth.uid()) RETURNING id INTO v_item_id;
 RETURN jsonb_build_object('ok',true,'itemId',v_item_id,'evidenceId',v_evidence_id,
    'state','evidence_only','canonicalEffect',false);
END $fn$;

CREATE FUNCTION atlas.prepared_person_operator_case_self_api_v1(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype; v_items jsonb;
BEGIN
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases WHERE id=p_case_id;
 IF NOT atlas.prepared_person_actor_allowed_v1(p_case_id,'read') THEN
   RAISE EXCEPTION 'Current scoped case operator authority required' USING errcode='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'id',i.id,'topic',i.topic,'classification',i.classification,
     'disclosure',i.disclosure,'linkedRecordKind',i.linked_record_kind,
     'linkedRecordId',i.linked_record_id,'revisesItemId',i.revises_item_id,
     'conflictsWithItemId',i.conflicts_with_item_id,
     'literalText',e.value->>'literalText',
     'sourceKind',e.source_kind,'sourceLocator',e.value->>'sourceLocator',
     'sourcePermissionBasis',e.provenance->>'sourcePermissionBasis',
     'observedAt',e.observed_at,'effectiveFrom',e.effective_from,
     'effectiveUntil',e.effective_until,'recordedAt',e.learned_at,
     'recordedByUserId',e.actor_user_id,'evidenceId',e.id,
     'confidence',e.confidence)
     ORDER BY i.created_at,i.id),'[]'::jsonb) INTO v_items
 FROM atlas.prepared_person_items i
 JOIN atlas.evidence_records e ON e.id=i.evidence_record_id
 WHERE i.case_id=p_case_id;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'targetKind',v_case.target_kind,'personEntityId',v_case.person_entity_id,
   'provisionalLabel',v_case.provisional_label,'caseState',v_case.case_state,
   'institutionalPersonRecordId',(SELECT r.id FROM atlas.institutional_person_records r
     WHERE r.organization_id=v_case.organization_id AND r.person_id=v_case.person_entity_id
       AND r.status='active' ORDER BY r.created_at LIMIT 1),
   'organizationId',v_case.organization_id,
   'canIssue',atlas.prepared_person_actor_allowed_v1(p_case_id,'issue'),
   'knownSources',jsonb_build_object(
     'ledgerConnections',coalesce((
       SELECT jsonb_agg(jsonb_build_object(
           'kind','ledger_seat','id',seat.id,
           'label',led.name,'ledgerId',led.id)
         ORDER BY led.name,seat.id)
       FROM ledger.seats seat
       JOIN atlas.ledger_organization_participations lop
         ON lop.ledger_id=seat.ledger_id
       JOIN ledger.ledgers led ON led.id=seat.ledger_id
       WHERE v_case.target_kind='existing_person'
         AND seat.person_entity_id=v_case.person_entity_id
         AND seat.seat_state='active' AND seat.ended_at IS NULL
         AND led.ledger_state='active' AND led.retired_at IS NULL
         AND lop.organization_id=v_case.organization_id
         AND lop.status='active' AND lop.ended_at IS NULL
         AND lop.participation_kind IN ('governing','operating')
       ),'[]'::jsonb),
     'institutionalEvents',coalesce((
       SELECT jsonb_agg(event_row ORDER BY start_at,id) FROM (
         SELECT ob.id,occ.start_at,
          jsonb_build_object('kind','organization_occurrence_binding',
            'id',ob.id,'label',occ.title,'occurrenceId',occ.id,
            'startsAt',occ.start_at,'eventStatus',occ.status) AS event_row
         FROM atlas.organization_occurrence_bindings ob
         JOIN local_intel.occurrences occ ON occ.id=ob.occurrence_id
         WHERE v_case.target_kind='existing_person'
           AND ob.organization_id=v_case.organization_id
           AND ob.binding_state='active'
           AND (v_case.prepared_by_user_id=auth.uid()
             OR EXISTS (
               SELECT 1 FROM atlas.prepared_person_operator_grants grant_event
               WHERE grant_event.case_id=v_case.id
                 AND grant_event.practitioner_user_id=auth.uid()
                 AND grant_event.revoked_at IS NULL
                 AND grant_event.can_inspect_org_events))
         ORDER BY occ.start_at DESC,ob.id LIMIT 40
       ) recent_events
       ),'[]'::jsonb),
     'assignedWork',coalesce((
       SELECT jsonb_agg(work_row ORDER BY allocated_at DESC,id) FROM (
         SELECT a.id,a.allocated_at,
          jsonb_build_object('kind','work_allocation','id',a.id,
            'label',w.title,'workItemId',w.id,
            'allocationState',a.state) AS work_row
         FROM atlas.work_allocations a
         JOIN atlas.work_items w ON w.id=a.work_item_id
           AND w.organization_id=v_case.organization_id
         WHERE v_case.target_kind='existing_person'
           AND a.organization_id=v_case.organization_id
           AND a.assignee_canonical_person_id=v_case.person_entity_id
           AND a.state='active'
         ORDER BY a.allocated_at DESC,a.id LIMIT 50
       ) source_work
       ),'[]'::jsonb)
   ),
   'operatorGrants',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'grantId',g.id,'practitionerUserId',g.practitioner_user_id,
      'practitionerEmail',(SELECT au.email FROM auth.users au WHERE au.id=g.practitioner_user_id),
      'canIssue',g.can_issue,
      'canInspectOrgEvents',g.can_inspect_org_events,
      'active',g.revoked_at IS NULL,
      'grantedByUserId',g.granted_by_user_id,'grantedAt',g.granted_at,
      'revokedAt',g.revoked_at) ORDER BY g.granted_at,g.id),'[]'::jsonb)
     FROM atlas.prepared_person_operator_grants g WHERE g.case_id=v_case.id
       AND v_case.prepared_by_user_id=auth.uid()),
   'scopeBasis',v_case.scope_basis,'items',v_items);
END $fn$;

CREATE FUNCTION atlas.prepared_person_operator_list_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT jsonb_build_object('ok',true,
   'cases',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'targetKind',c.target_kind,'personEntityId',c.person_entity_id,
      'provisionalLabel',c.provisional_label,'personLabel',p.display_name,
      'organizationId',c.organization_id,'state',c.case_state,
      'openedAt',c.opened_at,'issuedAt',c.issued_at)
      ORDER BY c.opened_at DESC,c.id)
     FROM atlas.prepared_person_cases c
     LEFT JOIN atlas.people p ON p.id=c.person_entity_id
     WHERE atlas.prepared_person_actor_allowed_v1(c.id,'read')),'[]'::jsonb));
$fn$;

CREATE FUNCTION atlas.prepared_person_issue_self_api_v1(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_case atlas.prepared_person_cases%rowtype;
BEGIN
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases WHERE id=p_case_id FOR UPDATE;
 IF NOT atlas.prepared_person_actor_allowed_v1(p_case_id,'issue') THEN
   RAISE EXCEPTION 'Current scoped issue authority required' USING errcode='42501';
 END IF;
 -- Provisional subjects cannot be bound by name/email similarity.
 -- Build 2 must establish and verify the canonical identity first.
 IF v_case.target_kind<>'existing_person' THEN
   RAISE EXCEPTION 'Provisional case awaits governed Person identity resolution'
    USING errcode='42501';
 END IF;
 -- Exact intended Person was already validated by the signed grant/steward check.
 IF v_case.case_state='issued' THEN
   RETURN jsonb_build_object('ok',true,'state','issued','caseId',p_case_id,'replay',true);
 END IF;
 IF v_case.case_state<>'preparing' OR NOT EXISTS
   (SELECT 1 FROM atlas.prepared_person_items i
      WHERE i.case_id=p_case_id AND i.disclosure='recipient_review'
        AND NOT EXISTS (SELECT 1 FROM atlas.prepared_person_items next_i
                           WHERE next_i.revises_item_id=i.id)) THEN
   RAISE EXCEPTION 'Recipient-visible prepared evidence required' USING errcode='22023';
 END IF;
 UPDATE atlas.prepared_person_cases
  SET case_state='issued',issued_at=now(),issued_by_user_id=auth.uid()
  WHERE id=p_case_id;
 RETURN jsonb_build_object('ok',true,'caseId',p_case_id,'state','issued',
                           'invitationIssued',false,'canonicalEffect',false);
END $fn$;

-- A recipient must carry a signed exact canonical Person credential.
-- An invitation URL, email match, or organizational relationship is insufficient.
CREATE FUNCTION atlas.prepared_person_recipient_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_uid uuid:=auth.uid(); v_person uuid; v_packets jsonb;
BEGIN
 SELECT CASE WHEN count(*)=1 THEN (array_agg(b.person_entity_id))[1] ELSE NULL END
 INTO v_person FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
  AND e.entity_kind='person' AND e.identity_state='canonical'
 JOIN auth.users u ON u.id=b.auth_user_id AND u.email_confirmed_at IS NOT NULL
   AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now())
 WHERE b.auth_user_id=v_uid AND b.binding_state='active' AND b.retired_at IS NULL;
 IF v_person IS NULL OR v_person IS DISTINCT FROM atlas.current_person_id_v1() THEN
  RETURN jsonb_build_object('ok',false,'code','verified_person_required','cases','[]'::jsonb);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'caseId',c.id,'issuedAt',c.issued_at,'items',
     (SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',i.id,'topic',i.topic,'classification',i.classification,
       'conflictsWithItemId',i.conflicts_with_item_id,
       'literalText',e.value->>'literalText',
       'sourceKind',e.source_kind,'sourceDetailAccess','not_admitted',
       'observedAt',e.observed_at,'effectiveFrom',e.effective_from,
       'effectiveUntil',e.effective_until,'recordedAt',e.learned_at,
       'recordedByUserId',e.actor_user_id,'evidenceId',e.id,
       'linkedRecordKind',i.linked_record_kind,'linkedRecordId',i.linked_record_id,
       'latestDecision', (SELECT r.decision FROM atlas.prepared_person_decision_receipts r
          WHERE r.item_id=i.id AND r.person_entity_id=v_person
            ORDER BY r.decided_at DESC,r.id DESC LIMIT 1),
       'latestCorrectionText', (SELECT r.correction_text FROM atlas.prepared_person_decision_receipts r
          WHERE r.item_id=i.id AND r.person_entity_id=v_person
            ORDER BY r.decided_at DESC,r.id DESC LIMIT 1))
       ORDER BY i.created_at,i.id),'[]'::jsonb)
       FROM atlas.prepared_person_items i
       JOIN atlas.evidence_records e ON e.id=i.evidence_record_id
       WHERE i.case_id=c.id AND i.disclosure='recipient_review'
         AND NOT EXISTS (SELECT 1 FROM atlas.prepared_person_items successor
                           WHERE successor.revises_item_id=i.id)))
    ORDER BY c.issued_at,c.id),'[]'::jsonb)
 INTO v_packets
 FROM atlas.prepared_person_cases c
 WHERE c.target_kind='existing_person' AND c.person_entity_id=v_person
   AND c.case_state='issued';
 RETURN jsonb_build_object('ok',true,'personId',v_person,'cases',v_packets,
                           'acceptanceDoesNotCreateWork',true);
END $fn$;

CREATE FUNCTION atlas.prepared_person_decide_self_api_v1(
 p_item_id uuid,p_decision text,p_request_key text,p_correction_text text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_uid uuid:=auth.uid(); v_person uuid; v_item atlas.prepared_person_items%rowtype;
 v_case atlas.prepared_person_cases%rowtype;
 v_existing atlas.prepared_person_decision_receipts%rowtype; v_id uuid;
BEGIN
 SELECT * INTO STRICT v_item FROM atlas.prepared_person_items WHERE id=p_item_id;
 SELECT * INTO STRICT v_case FROM atlas.prepared_person_cases WHERE id=v_item.case_id;
 SELECT CASE WHEN count(*)=1 THEN (array_agg(b.person_entity_id))[1] ELSE NULL END
 INTO v_person FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
  AND e.entity_kind='person' AND e.identity_state='canonical'
 JOIN auth.users u ON u.id=b.auth_user_id AND u.email_confirmed_at IS NOT NULL
   AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now())
 WHERE b.auth_user_id=v_uid AND b.binding_state='active' AND b.retired_at IS NULL;
 IF v_person IS NULL OR v_person IS DISTINCT FROM atlas.current_person_id_v1()
   OR v_case.person_entity_id IS DISTINCT FROM v_person OR
   v_case.case_state<>'issued' OR v_item.disclosure<>'recipient_review'
   OR EXISTS(SELECT 1 FROM atlas.prepared_person_items successor
     WHERE successor.revises_item_id=v_item.id) THEN
   RAISE EXCEPTION 'Verified recipient and visible current item required'
     USING errcode='42501';
 END IF;
 IF p_decision NOT IN ('accept','reject','correct','defer')
   OR length(btrim(coalesce(p_request_key,''))) NOT BETWEEN 8 AND 160
   OR (p_decision='correct' AND
     length(btrim(coalesce(p_correction_text,''))) NOT BETWEEN 3 AND 2000)
   OR (p_decision<>'correct' AND p_correction_text IS NOT NULL) THEN
  RAISE EXCEPTION 'Invalid recipient decision' USING errcode='22023';
 END IF;
 SELECT * INTO v_existing FROM atlas.prepared_person_decision_receipts
 WHERE item_id=p_item_id AND decided_by_user_id=v_uid AND request_key=p_request_key;
 IF FOUND THEN
  IF v_existing.decision<>p_decision OR
    v_existing.correction_text IS DISTINCT FROM p_correction_text THEN
    RAISE EXCEPTION 'Decision receipt reused with different answer' USING errcode='23505';
  END IF;
  RETURN jsonb_build_object('ok',true,'receiptId',v_existing.id,'replay',true);
 END IF;
 INSERT INTO atlas.prepared_person_decision_receipts
  (item_id,person_entity_id,decided_by_user_id,decision,correction_text,request_key)
 VALUES(p_item_id,v_person,v_uid,p_decision,p_correction_text,p_request_key)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('ok',true,'receiptId',v_id,'decision',p_decision,
   'canonicalEffect',false,'domainPromotion','not_performed');
END $fn$;

REVOKE ALL ON FUNCTION
 atlas.prepared_person_assign_practitioner_self_api_v1(uuid,uuid,text,boolean,boolean),
 atlas.prepared_person_assign_practitioner_email_self_api_v1(uuid,text,text,boolean,boolean),
 atlas.prepared_person_revoke_practitioner_self_api_v1(uuid),
 atlas.prepared_person_scope_options_self_api_v1(uuid,text),
 atlas.prepared_person_begin_self_api_v1(uuid,text,uuid,text,text,text),
 atlas.prepared_person_record_self_api_v1(uuid,text,text,text,text,text,text,timestamptz,numeric,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz),
 atlas.prepared_person_operator_case_self_api_v1(uuid),
 atlas.prepared_person_operator_list_self_api_v1(),
 atlas.prepared_person_issue_self_api_v1(uuid),
 atlas.prepared_person_recipient_self_api_v1(),
 atlas.prepared_person_decide_self_api_v1(uuid,text,text,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
 atlas.prepared_person_assign_practitioner_self_api_v1(uuid,uuid,text,boolean,boolean),
 atlas.prepared_person_assign_practitioner_email_self_api_v1(uuid,text,text,boolean,boolean),
 atlas.prepared_person_revoke_practitioner_self_api_v1(uuid),
 atlas.prepared_person_scope_options_self_api_v1(uuid,text),
 atlas.prepared_person_begin_self_api_v1(uuid,text,uuid,text,text,text),
 atlas.prepared_person_record_self_api_v1(uuid,text,text,text,text,text,text,timestamptz,numeric,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz),
 atlas.prepared_person_operator_case_self_api_v1(uuid),
 atlas.prepared_person_operator_list_self_api_v1(),
 atlas.prepared_person_issue_self_api_v1(uuid),
 atlas.prepared_person_recipient_self_api_v1(),
 atlas.prepared_person_decide_self_api_v1(uuid,text,text,text)
 TO authenticated;


-- Public PostgREST transport: only authenticated sessions; source checks stay
-- inside the atlas.* authoritative commands, not in a bearer URL or UI.
CREATE FUNCTION public.prepared_person_scope_options_self_api_v1(p_organization_id uuid DEFAULT NULL,p_query text DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_scope_options_self_api_v1(p_organization_id,p_query); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_scope_options_self_api_v1(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_scope_options_self_api_v1(uuid,text) TO authenticated;

CREATE FUNCTION public.prepared_person_begin_self_api_v1(p_organization_id uuid,p_target_kind text,p_person_entity_id uuid,p_provisional_label text,p_scope_basis text,p_request_key text) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_begin_self_api_v1(p_organization_id,p_target_kind,p_person_entity_id,p_provisional_label,p_scope_basis,p_request_key); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_begin_self_api_v1(uuid,text,uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_begin_self_api_v1(uuid,text,uuid,text,text,text) TO authenticated;

CREATE FUNCTION public.prepared_person_record_self_api_v1(p_case_id uuid,p_request_key text,p_topic text,p_literal_text text,p_source_kind text,p_source_locator text,p_source_permission_basis text,p_observed_at timestamptz,p_confidence numeric,p_classification text,p_disclosure text,p_recipient_disclosure_basis text DEFAULT NULL,p_linked_record_kind text DEFAULT NULL,p_linked_record_id uuid DEFAULT NULL,p_revises_item_id uuid DEFAULT NULL,p_conflicts_with_item_id uuid DEFAULT NULL,p_effective_from timestamptz DEFAULT NULL,p_effective_until timestamptz DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_record_self_api_v1(p_case_id,p_request_key,p_topic,p_literal_text,p_source_kind,p_source_locator,p_source_permission_basis,p_observed_at,p_confidence,p_classification,p_disclosure,p_recipient_disclosure_basis,p_linked_record_kind,p_linked_record_id,p_revises_item_id,p_conflicts_with_item_id,p_effective_from,p_effective_until); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_record_self_api_v1(uuid,text,text,text,text,text,text,timestamptz,numeric,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_record_self_api_v1(uuid,text,text,text,text,text,text,timestamptz,numeric,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz) TO authenticated;

CREATE FUNCTION public.prepared_person_operator_case_self_api_v1(p_case_id uuid) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_operator_case_self_api_v1(p_case_id); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_operator_case_self_api_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_operator_case_self_api_v1(uuid) TO authenticated;

CREATE FUNCTION public.prepared_person_operator_list_self_api_v1() RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_operator_list_self_api_v1(); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_operator_list_self_api_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_operator_list_self_api_v1() TO authenticated;

CREATE FUNCTION public.prepared_person_issue_self_api_v1(p_case_id uuid) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_issue_self_api_v1(p_case_id); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_issue_self_api_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_issue_self_api_v1(uuid) TO authenticated;

CREATE FUNCTION public.prepared_person_recipient_self_api_v1() RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_recipient_self_api_v1(); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_recipient_self_api_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_recipient_self_api_v1() TO authenticated;

CREATE FUNCTION public.prepared_person_decide_self_api_v1(p_item_id uuid,p_decision text,p_request_key text,p_correction_text text DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
 AS $transport$ SELECT atlas.prepared_person_decide_self_api_v1(p_item_id,p_decision,p_request_key,p_correction_text); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_decide_self_api_v1(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_decide_self_api_v1(uuid,text,text,text) TO authenticated;

CREATE FUNCTION public.prepared_person_assign_practitioner_self_api_v1(
 p_case_id uuid,p_practitioner_user_id uuid,p_grant_reason text,
 p_can_issue boolean DEFAULT false,p_can_inspect_org_events boolean DEFAULT false
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
AS $transport$ SELECT atlas.prepared_person_assign_practitioner_self_api_v1(
 p_case_id,p_practitioner_user_id,p_grant_reason,p_can_issue,p_can_inspect_org_events); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_assign_practitioner_self_api_v1(uuid,uuid,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_assign_practitioner_self_api_v1(uuid,uuid,text,boolean,boolean) TO authenticated;

CREATE FUNCTION public.prepared_person_assign_practitioner_email_self_api_v1(
 p_case_id uuid,p_practitioner_email text,p_grant_reason text,
 p_can_issue boolean DEFAULT false,p_can_inspect_org_events boolean DEFAULT false
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
AS $transport$ SELECT atlas.prepared_person_assign_practitioner_email_self_api_v1(
 p_case_id,p_practitioner_email,p_grant_reason,p_can_issue,p_can_inspect_org_events); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_assign_practitioner_email_self_api_v1(uuid,text,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_assign_practitioner_email_self_api_v1(uuid,text,text,boolean,boolean) TO authenticated;

CREATE FUNCTION public.prepared_person_revoke_practitioner_self_api_v1(
 p_grant_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='pg_catalog'
AS $transport$ SELECT atlas.prepared_person_revoke_practitioner_self_api_v1(
 p_grant_id); $transport$;
REVOKE ALL ON FUNCTION public.prepared_person_revoke_practitioner_self_api_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepared_person_revoke_practitioner_self_api_v1(uuid) TO authenticated;

COMMIT;

-- Build 5: first responsibility is offered by a native Ledger owner and
-- established only by the worker's own acceptance, never by impersonation.
BEGIN;
CREATE TABLE atlas.company_work_initial_responsibility_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
  offered_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  offered_by_membership_id uuid NOT NULL REFERENCES atlas.organization_memberships(id) ON DELETE RESTRICT,
  target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  target_membership_id uuid NOT NULL REFERENCES atlas.organization_memberships(id) ON DELETE RESTRICT,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 1200),
  offer_state text NOT NULL DEFAULT 'offered'
    CHECK (offer_state IN ('offered','accepted','declined','stale','withdrawn')),
  accepted_allocation_id uuid REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT,
  offered_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolution_reason text,
  CHECK (offered_by_person_id<>target_person_id),
  CHECK ((offer_state='offered' AND resolved_at IS NULL AND accepted_allocation_id IS NULL)
     OR (offer_state='accepted' AND resolved_at IS NOT NULL AND accepted_allocation_id IS NOT NULL)
     OR (offer_state IN ('declined','stale','withdrawn') AND resolved_at IS NOT NULL AND accepted_allocation_id IS NULL))
);
CREATE UNIQUE INDEX company_work_initial_responsibility_one_pending_v1
  ON atlas.company_work_initial_responsibility_offers(work_item_id)
  WHERE offer_state='offered';
REVOKE ALL ON TABLE atlas.company_work_initial_responsibility_offers FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.offer_unallocated_company_work_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_target_person_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_actor_person uuid;
 v_actor_membership uuid;
 v_target_membership uuid;
 v_target_count int;
 v_existing atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_created atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 IF p_work_item_id IS NULL OR p_ledger_id IS NULL OR p_target_person_id IS NULL
   OR v_reason IS NULL OR length(v_reason)>1200 THEN
   RAISE EXCEPTION 'Exact Work, Ledger, target Person and reason required'
     USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' THEN
   RAISE EXCEPTION 'Open Company Work required' USING ERRCODE='22023';
 END IF;
 v_actor_person:=atlas.company_work_native_ledger_owner_self_v1(v_work.organization_id,p_ledger_id);
 SELECT atlas.current_effective_organization_membership_v1(v_work.organization_id) INTO v_actor_membership;
 IF v_actor_membership IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=v_actor_membership AND m.person_id=v_actor_person
      AND m.organization_id=v_work.organization_id) THEN
   RAISE EXCEPTION 'Owner institutional membership not established' USING ERRCODE='42501';
 END IF;
 IF p_target_person_id=v_actor_person THEN
   RAISE EXCEPTION 'Use self-adoption for your own work, not an employee offer'
    USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance l
    WHERE l.work_item_id=v_work.id AND l.organization_id=v_work.organization_id
      AND l.ledger_id=p_ledger_id AND l.attribution_state='active'
      AND (l.evidence_kind='owner_attested' OR
       (l.evidence_kind='source_verified' AND EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(l.work_item_id,l.ledger_id) proof
        WHERE proof.source_schema=l.source_schema AND proof.source_table=l.source_table
          AND proof.source_id=l.source_id
       )))
 ) THEN
   RAISE EXCEPTION 'Verify exact native Ledger relevance before offering work'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(
    SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=v_work.id
      AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible' AND a.state='active'
 ) THEN RAISE EXCEPTION 'Already assigned; use responsibility transfer'
   USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM reality.entities e WHERE e.id=p_target_person_id
     AND e.entity_kind='person' AND e.identity_state='canonical'
 ) THEN RAISE EXCEPTION 'Target canonical Person required' USING ERRCODE='23514'; END IF;
 SELECT count(*)::int,(array_agg(m.id ORDER BY m.created_at,m.id))[1]
   INTO v_target_count,v_target_membership
 FROM atlas.organization_memberships m
 JOIN atlas.organization_employee_seats s
   ON s.organization_membership_id=m.id AND s.organization_id=m.organization_id
 WHERE m.organization_id=v_work.organization_id AND m.person_id=p_target_person_id
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
   AND s.status='active' AND s.seat_class='employee' AND s.ended_at IS NULL;
 IF v_target_count<>1 THEN
   RAISE EXCEPTION 'Exactly one active worker membership and employee seat required'
     USING ERRCODE='23514';
 END IF;
 SELECT * INTO v_existing
 FROM atlas.company_work_initial_responsibility_offers
 WHERE work_item_id=v_work.id AND offer_state='offered' FOR UPDATE;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.target_person_id<>p_target_person_id OR v_existing.ledger_id<>p_ledger_id THEN
     RAISE EXCEPTION 'Another offer is already pending for this Work'
       USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offer_v1',
    'state','offered','alreadyOffered',true,'offerId',v_existing.id,
    'workItemId',v_work.id,'ledgerId',p_ledger_id,'targetPersonId',p_target_person_id,
    'responsibilityChanged',false);
 END IF;
 INSERT INTO atlas.company_work_initial_responsibility_offers(
   organization_id,work_item_id,ledger_id,offered_by_person_id,
   offered_by_membership_id,target_person_id,target_membership_id,reason
 ) VALUES (v_work.organization_id,v_work.id,p_ledger_id,v_actor_person,
   v_actor_membership,p_target_person_id,v_target_membership,v_reason)
 RETURNING * INTO v_created;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offer_v1',
   'state','offered','alreadyOffered',false,'offerId',v_created.id,
   'workItemId',v_work.id,'ledgerId',p_ledger_id,'targetPersonId',p_target_person_id,
   'responsibilityChanged',false,'workerViewed',false,'scheduled',false);
END
$fn$;

CREATE FUNCTION atlas.respond_unallocated_company_work_self_api_v1(
 p_offer_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_self uuid:=atlas.current_person_id_v1();
 v_offer atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_membership uuid;
 v_decision text:=lower(btrim(coalesce(p_decision,'')));
 v_receipt jsonb;
 v_alloc uuid;
 v_ready boolean;
BEGIN
 IF auth.uid() IS NULL OR v_self IS NULL THEN
   RAISE EXCEPTION 'Signed-in canonical Person required' USING ERRCODE='42501';
 END IF;
 IF v_decision NOT IN ('accepted','declined') OR p_offer_id IS NULL THEN
   RAISE EXCEPTION 'Accept or decline one exact offer' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_offer FROM atlas.company_work_initial_responsibility_offers
   WHERE id=p_offer_id FOR UPDATE;
 IF v_offer.id IS NULL OR v_offer.target_person_id<>v_self THEN
   RAISE EXCEPTION 'Offer unavailable to current Person' USING ERRCODE='42501';
 END IF;
 IF v_offer.offer_state<>'offered' THEN
   IF v_offer.offer_state=v_decision THEN
     RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
       'state',v_offer.offer_state,'offerId',v_offer.id,'workItemId',v_offer.work_item_id,
       'allocationId',v_offer.accepted_allocation_id,'alreadyResolved',true);
   END IF;
   RAISE EXCEPTION 'Offer already resolved' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||v_offer.work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items
   WHERE id=v_offer.work_item_id AND organization_id=v_offer.organization_id FOR UPDATE;
 v_membership:=atlas.current_effective_organization_membership_v1(v_offer.organization_id);
 IF v_membership IS NULL OR v_membership<>v_offer.target_membership_id THEN
   RAISE EXCEPTION 'Original worker membership must remain effective' USING ERRCODE='42501';
 END IF;
 IF v_decision='declined' THEN
   UPDATE atlas.company_work_initial_responsibility_offers
      SET offer_state='declined',resolved_at=now(),resolution_reason='recipient_declined'
       WHERE id=v_offer.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
     'state','declined','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
     'responsibilityChanged',false);
 END IF;
 SELECT (v_work.id IS NOT NULL AND v_work.work_state='open'
    AND NOT EXISTS(SELECT 1 FROM atlas.work_allocations a
      WHERE a.work_item_id=v_offer.work_item_id
       AND a.allocation_role='responsible' AND a.state='active')
    AND EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance l
       WHERE l.organization_id=v_offer.organization_id AND l.work_item_id=v_offer.work_item_id
         AND l.ledger_id=v_offer.ledger_id AND l.attribution_state='active'
         AND (l.evidence_kind='owner_attested' OR
          (l.evidence_kind='source_verified' AND EXISTS(
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(l.work_item_id,l.ledger_id) proof
            WHERE proof.source_schema=l.source_schema
              AND proof.source_table=l.source_table AND proof.source_id=l.source_id))))
    AND EXISTS(SELECT 1 FROM atlas.organization_employee_seats s
      WHERE s.organization_membership_id=v_membership
       AND s.organization_id=v_offer.organization_id
       AND s.status='active' AND s.seat_class='employee' AND s.ended_at IS NULL))
 INTO v_ready;
 IF NOT coalesce(v_ready,false) THEN
   UPDATE atlas.company_work_initial_responsibility_offers
     SET offer_state='stale',resolved_at=now(),resolution_reason='eligibility_or_work_changed_before_uptake'
       WHERE id=v_offer.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
      'state','stale','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
      'responsibilityChanged',false);
 END IF;
 v_receipt:=atlas.set_company_work_responsibility_with_basis_internal_v2(
   v_offer.work_item_id,v_membership,v_membership,'self_adoption',
   jsonb_build_object('sourceKind','company_work_initial_responsibility_offer',
     'sourceId',v_offer.id,'nativeLedgerId',v_offer.ledger_id,
     'offeredByPersonId',v_offer.offered_by_person_id,
     'receiverPersonId',v_self),
   'receiver_accepted_initial_company_work_offer',
   jsonb_build_object('source','respond_unallocated_company_work_self_api_v1',
     'offerId',v_offer.id,'receiverUptake',true)
 );
 IF v_receipt->>'state' NOT IN ('established','unchanged')
    OR (v_receipt->>'workItemId')::uuid<>v_offer.work_item_id
    OR (v_receipt->>'assigneeMembershipId')::uuid<>v_membership THEN
    RAISE EXCEPTION 'Receiver established Work allocation not proven' USING ERRCODE='23514';
 END IF;
 v_alloc:=(v_receipt->>'allocationId')::uuid;
 UPDATE atlas.company_work_initial_responsibility_offers
   SET offer_state='accepted',resolved_at=now(),accepted_allocation_id=v_alloc,
       resolution_reason='receiver_accepted'
 WHERE id=v_offer.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
   'state','accepted','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
   'allocationId',v_alloc,'responsiblePersonId',v_self,'responsibilityChanged',true,
   'scheduled',false,'workerDayDeliveryProven',false);
END
$fn$;

CREATE FUNCTION atlas.company_work_initial_offers_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_incoming jsonb;
 v_outgoing jsonb;
BEGIN
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';
 END IF;
 IF v_person IS NULL THEN
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offers_self_v1',
      'state','person_binding_required','incoming','[]'::jsonb,'outgoing','[]'::jsonb);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'offerId',o.id,'workItemId',o.work_item_id,'workTitle',w.title,
   'organizationId',o.organization_id,'ledgerId',o.ledger_id,
   'offeredByPersonId',o.offered_by_person_id,'offeredAt',o.offered_at,'reason',o.reason
 ) ORDER BY o.offered_at,o.id),'[]'::jsonb) INTO v_incoming
 FROM atlas.company_work_initial_responsibility_offers o
 JOIN atlas.work_items w ON w.id=o.work_item_id
 WHERE o.target_person_id=v_person AND o.offer_state='offered'
  AND EXISTS(SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=o.target_membership_id AND m.person_id=v_person
      AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now()))
  AND EXISTS(SELECT 1 FROM atlas.organization_employee_seats seat
    WHERE seat.organization_membership_id=o.target_membership_id
      AND seat.organization_id=o.organization_id AND seat.status='active'
      AND seat.seat_class='employee' AND seat.ended_at IS NULL);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'offerId',o.id,'workItemId',o.work_item_id,'workTitle',w.title,
   'organizationId',o.organization_id,'ledgerId',o.ledger_id,
   'targetPersonId',o.target_person_id,'offeredAt',o.offered_at,'reason',o.reason
 ) ORDER BY o.offered_at,o.id),'[]'::jsonb) INTO v_outgoing
 FROM atlas.company_work_initial_responsibility_offers o
 JOIN atlas.work_items w ON w.id=o.work_item_id
 WHERE o.offered_by_person_id=v_person AND o.offer_state='offered'
   AND atlas.is_organization_owner(o.organization_id);
 RETURN jsonb_build_object('ok',true,
   'contractVersion','company_work_initial_offers_self_v1',
   'state','ready','incoming',v_incoming,'outgoing',v_outgoing,
   'offerIsNotAssignment',true,'workerViewedOrDeliveredNotProven',true);
END
$fn$;

CREATE FUNCTION atlas.withdraw_unallocated_company_work_offer_self_api_v1(
  p_offer_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_work_item_id uuid;
 v_offer atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_owner_person uuid;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL OR p_offer_id IS NULL OR v_reason IS NULL
   OR length(v_reason)>1200 THEN
   RAISE EXCEPTION 'Signed-in owner, offer and withdrawal reason required'
     USING ERRCODE='42501';
 END IF;
 SELECT work_item_id INTO v_work_item_id
 FROM atlas.company_work_initial_responsibility_offers WHERE id=p_offer_id;
 IF v_work_item_id IS NULL THEN
   RAISE EXCEPTION 'Offer not found' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||v_work_item_id::text,0));
 SELECT * INTO v_offer FROM atlas.company_work_initial_responsibility_offers
 WHERE id=p_offer_id FOR UPDATE;
 v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
   v_offer.organization_id,v_offer.ledger_id);
 IF v_offer.offer_state='withdrawn' THEN
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_withdraw_v1',
    'state','withdrawn','alreadyWithdrawn',true,'offerId',v_offer.id,
    'workItemId',v_offer.work_item_id,'responsibilityChanged',false);
 END IF;
 IF v_offer.offer_state<>'offered' THEN
   RAISE EXCEPTION 'Resolved Work offer cannot be withdrawn' USING ERRCODE='23514';
 END IF;
 UPDATE atlas.company_work_initial_responsibility_offers
   SET offer_state='withdrawn',resolved_at=now(),resolution_reason=v_reason WHERE id=v_offer.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_withdraw_v1',
    'state','withdrawn','alreadyWithdrawn',false,'offerId',v_offer.id,
    'workItemId',v_offer.work_item_id,'responsibilityChanged',false);
END
$fn$;

REVOKE ALL ON FUNCTION atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.respond_unallocated_company_work_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.company_work_initial_offers_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.respond_unallocated_company_work_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.company_work_initial_offers_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text) TO authenticated;

CREATE FUNCTION public.offer_unallocated_company_work_self_api_v1(p_work_item_id uuid,p_ledger_id uuid,p_target_person_id uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.offer_unallocated_company_work_self_api_v1(p_work_item_id,p_ledger_id,p_target_person_id,p_reason); $fn$;
CREATE FUNCTION public.respond_unallocated_company_work_self_api_v1(p_offer_id uuid,p_decision text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.respond_unallocated_company_work_self_api_v1(p_offer_id,p_decision); $fn$;
CREATE FUNCTION public.company_work_initial_offers_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.company_work_initial_offers_self_api_v1(); $fn$;
CREATE FUNCTION public.withdraw_unallocated_company_work_offer_self_api_v1(p_offer_id uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.withdraw_unallocated_company_work_offer_self_api_v1(p_offer_id,p_reason); $fn$;
REVOKE ALL ON FUNCTION public.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.respond_unallocated_company_work_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.company_work_initial_offers_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_unallocated_company_work_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_work_initial_offers_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_unallocated_company_work_offer_self_api_v1(uuid,text) TO authenticated;
COMMIT;

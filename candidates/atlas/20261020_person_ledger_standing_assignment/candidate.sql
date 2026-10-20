BEGIN;
-- Build 5: admit one canonical Person/Native-Ledger connection into the
-- existing accepted standing-assignment agreement. Employee delivery seats
-- do not establish responsibility, consent, assignment, or access.
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ADD COLUMN worker_ledger_seat_id uuid REFERENCES ledger.seats(id);
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ALTER COLUMN worker_membership_id DROP NOT NULL,
 ALTER COLUMN position_id DROP NOT NULL,
 ALTER COLUMN position_appointment_id DROP NOT NULL,
 ALTER COLUMN organization_unit_id DROP NOT NULL;
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ADD CONSTRAINT standing_scope_canonical_or_transitional_carrier_v1
 CHECK (worker_ledger_seat_id IS NOT NULL OR worker_membership_id IS NOT NULL);
CREATE UNIQUE INDEX company_work_standing_ledger_connection_current_v1
 ON atlas.company_work_standing_assignment_scopes (worker_ledger_seat_id)
 WHERE worker_ledger_seat_id IS NOT NULL
   AND scope_state IN ('proposed','active');
ALTER TABLE atlas.work_allocations
 DROP CONSTRAINT work_allocations_exact_assignee_carrier_v1;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_exact_assignee_carrier_v1
 CHECK (assignee_membership_id IS NOT NULL OR
    (assignee_canonical_person_id IS NOT NULL AND
      establishment_basis_kind IN ('person_connection_receiver_uptake','delegated_under_standing_scope')));

CREATE OR REPLACE FUNCTION atlas.propose_company_work_standing_scope_by_connection_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_person_id uuid,
 p_terms text,p_valid_until timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_owner uuid;
 v_manager_membership uuid;
 v_worker_seat uuid;
 v_count integer;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
 v_new atlas.company_work_standing_assignment_scopes%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
 OR p_worker_person_id IS NULL OR v_terms IS NULL
 OR length(v_terms) NOT BETWEEN 30 AND 3000
 OR (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'Signed-in owner, exact Ledger Person, terms and future expiry required'
   USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 v_manager_membership:=atlas.current_effective_organization_membership_v1(p_organization_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_memberships m
   WHERE m.id=v_manager_membership AND m.organization_id=p_organization_id
   AND m.person_id=v_owner AND m.active AND m.role='owner') THEN
   RAISE EXCEPTION 'Institutional owner authority not proven' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM reality.entities e
   WHERE e.id=p_worker_person_id AND e.entity_kind='person' AND e.identity_state='canonical') THEN
   RAISE EXCEPTION 'Canonical Person required' USING ERRCODE='23514';
 END IF;
 SELECT count(*)::integer,min(s.id::text)::uuid INTO v_count,v_worker_seat
 FROM ledger.seats s
 WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=p_worker_person_id
  AND s.seat_state='active' AND s.ended_at IS NULL;
 IF v_count<>1 THEN
   RAISE EXCEPTION 'Exactly one active canonical Person-Ledger connection required' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.standing_scope:'||v_worker_seat::text,0));
 INSERT INTO atlas.company_work_standing_assignment_scopes(
  organization_id,ledger_id,worker_membership_id,worker_person_id,
  worker_ledger_seat_id,position_id,position_appointment_id,organization_unit_id,
  proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until)
 VALUES(p_organization_id,p_ledger_id,NULL,p_worker_person_id,
  v_worker_seat,NULL,NULL,NULL,v_owner,v_manager_membership,v_terms,p_valid_until)
 RETURNING * INTO v_new;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','company_work_standing_scope_v1',
  'state','proposed','scopeId',v_new.id,'organizationId',p_organization_id,
  'nativeLedgerId',p_ledger_id,'workerPersonId',p_worker_person_id,
  'workerLedgerSeatId',v_worker_seat,
  'positionId',NULL,'requiresWorkerConsent',true,'assignmentCreated',false);
END
$function$;
REVOKE ALL ON FUNCTION atlas.propose_company_work_standing_scope_by_connection_self_api_v1(uuid,uuid,uuid,text,timestamptz)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.propose_company_work_standing_scope_by_connection_self_api_v1(uuid,uuid,uuid,text,timestamptz)
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.company_work_standing_scopes_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_incoming jsonb;
 v_outgoing jsonb;
BEGIN
 IF auth.uid() IS NULL OR v_person IS NULL THEN
   RAISE EXCEPTION 'Canonical signed-in Person required' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,'ledgerId',s.ledger_id,
   'workerPersonId',s.worker_person_id,'workerLedgerSeatId',s.worker_ledger_seat_id,
   'positionId',s.position_id,'positionTitle',p.display_title,
   'organizationUnitId',s.organization_unit_id,'proposalTerms',s.proposal_terms,
   'state',s.scope_state,'validUntil',s.valid_until
 ) ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_incoming
 FROM atlas.company_work_standing_assignment_scopes s
 LEFT JOIN atlas.organization_positions p ON p.id=s.position_id
 WHERE s.worker_person_id=v_person AND s.scope_state IN ('proposed','active')
 AND (
   (s.worker_ledger_seat_id IS NOT NULL AND EXISTS(
     SELECT 1 FROM ledger.seats seat WHERE seat.id=s.worker_ledger_seat_id
       AND seat.ledger_id=s.ledger_id AND seat.person_entity_id=v_person
       AND seat.seat_state='active' AND seat.ended_at IS NULL))
   OR (s.worker_ledger_seat_id IS NULL AND EXISTS(
     SELECT 1 FROM atlas.organization_memberships m
     WHERE m.id=s.worker_membership_id AND m.person_id=v_person
       AND m.organization_id=s.organization_id
       AND atlas.organization_membership_present_effective_at_v1(
         m.id,m.organization_id,now())))
 );
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,'ledgerId',s.ledger_id,
   'workerPersonId',s.worker_person_id,'workerLedgerSeatId',s.worker_ledger_seat_id,
   'positionId',s.position_id,'proposalTerms',s.proposal_terms,
   'state',s.scope_state,'acceptedAt',s.accepted_at,'validUntil',s.valid_until
 ) ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_outgoing
 FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.proposed_by_person_id=v_person AND s.scope_state IN ('proposed','active');
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
  'incoming',v_incoming,'outgoing',v_outgoing,
  'workerAcceptedScopeIsNotWorkerDayReceipt',true);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.respond_company_work_standing_scope_self_api_v1(
 p_scope_id uuid,p_decision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_decision text:=lower(btrim(coalesce(p_decision,'')));
BEGIN
 IF auth.uid() IS NULL OR v_person IS NULL OR p_scope_id IS NULL
 OR v_decision NOT IN ('accept','decline') THEN
  RAISE EXCEPTION 'Authenticated worker Person and explicit decision required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
  WHERE id=p_scope_id FOR UPDATE;
 IF v_scope.id IS NULL OR v_scope.worker_person_id IS DISTINCT FROM v_person
 OR v_scope.scope_state<>'proposed' THEN
  RAISE EXCEPTION 'Scope unavailable or already resolved' USING ERRCODE='42501';
 END IF;
 IF v_decision='decline' THEN
  UPDATE atlas.company_work_standing_assignment_scopes
  SET scope_state='declined',declined_at=now() WHERE id=v_scope.id;
  RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
    'state','declined','scopeId',v_scope.id,'standingAuthorityEstablished',false);
 END IF;
 IF v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now() THEN
  RAISE EXCEPTION 'Scope expired before acceptance' USING ERRCODE='23514';
 END IF;
 IF v_scope.worker_ledger_seat_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM ledger.seats seat
    WHERE seat.id=v_scope.worker_ledger_seat_id
      AND seat.ledger_id=v_scope.ledger_id AND seat.person_entity_id=v_person
      AND seat.seat_state='active' AND seat.ended_at IS NULL) THEN
     RAISE EXCEPTION 'Exact Person Ledger connection no longer active' USING ERRCODE='23514';
   END IF;
 ELSE
   IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_memberships m
    JOIN atlas.organization_position_appointments a ON a.id=v_scope.position_appointment_id
      AND a.organization_membership_id=m.id AND a.position_id=v_scope.position_id
    JOIN atlas.organization_positions p ON p.id=v_scope.position_id
    WHERE m.id=v_scope.worker_membership_id AND m.person_id=v_person
     AND m.organization_id=v_scope.organization_id
     AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
     AND a.status='active' AND a.ends_at IS NULL
     AND p.status='active' AND p.organization_unit_id=v_scope.organization_unit_id) THEN
    RAISE EXCEPTION 'Original Position scope no longer supports consent' USING ERRCODE='23514';
   END IF;
 END IF;
 UPDATE atlas.company_work_standing_assignment_scopes SET scope_state='active',
   accepted_at=now(),accepted_by_person_id=v_person WHERE id=v_scope.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
  'state','active','scopeId',v_scope.id,'standingAuthorityEstablished',true,
  'personConsentRecorded',true,'workAssignmentCreated',false);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.manager_assign_company_work_under_standing_scope_self_api_v1(
 p_work_item_id uuid,p_scope_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_owner uuid;
 v_actor_membership uuid;
 v_new atlas.work_allocations%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 v_contract text:='ordinary_company_work_worker_attestation_v1';
BEGIN
 IF auth.uid() IS NULL OR p_work_item_id IS NULL OR p_scope_id IS NULL
 OR v_reason IS NULL OR length(v_reason)>1200 THEN
  RAISE EXCEPTION 'Work, exact accepted scope, signed-in owner and reason required'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
 WHERE id=p_scope_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' OR v_scope.id IS NULL
 OR v_scope.scope_state<>'active' OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR v_scope.worker_ledger_seat_id IS NULL
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR v_work.organization_id<>v_scope.organization_id
 OR (v_scope.organization_unit_id IS NOT NULL
  AND v_work.organization_unit_id IS DISTINCT FROM v_scope.organization_unit_id) THEN
  RAISE EXCEPTION 'Open in-scope Work and accepted Person-Ledger standing agreement required'
   USING ERRCODE='23514';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
  v_work.organization_id,v_scope.ledger_id);
 v_actor_membership:=atlas.current_effective_organization_membership_v1(
  v_work.organization_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_memberships m
  WHERE m.id=v_actor_membership AND m.organization_id=v_work.organization_id
  AND m.person_id=v_owner AND m.role='owner' AND m.active) THEN
   RAISE EXCEPTION 'Owner manager not established' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.seats seat
  WHERE seat.id=v_scope.worker_ledger_seat_id AND seat.ledger_id=v_scope.ledger_id
  AND seat.person_entity_id=v_scope.worker_person_id
  AND seat.seat_state='active' AND seat.ended_at IS NULL) THEN
  RAISE EXCEPTION 'Accepted Person-Ledger connection is no longer active'
   USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
  WHERE o.work_item_id=v_work.id AND o.offer_state='offered') THEN
  RAISE EXCEPTION 'Withdraw or resolve the pending individual Work offer first'
   USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
  WHERE rel.work_item_id=v_work.id AND rel.organization_id=v_work.organization_id
   AND rel.ledger_id=v_scope.ledger_id AND rel.attribution_state='active'
   AND (rel.evidence_kind='owner_attested' OR
    (rel.evidence_kind='source_verified' AND EXISTS(
     SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
       v_work.id,v_scope.ledger_id) proof
     WHERE proof.source_schema=rel.source_schema
      AND proof.source_table=rel.source_table
      AND proof.source_id=rel.source_id)))) THEN
  RAISE EXCEPTION 'Exact native Ledger Work source not proven'
   USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_allocations a
  WHERE a.work_item_id=v_work.id AND a.state='active'
   AND a.allocation_role='responsible') THEN
  RAISE EXCEPTION 'Work already has a responsible Person' USING ERRCODE='23514';
 END IF;
 -- Ordinary source-carried Work uses the established Person-native reporting
 -- contract. Never overwrite a source-specific result contract.
 IF v_work.result_contract_key IS NULL AND
  v_work.source_object_type IN ('personal_dated_task','legacy_task') THEN
  IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key=v_contract AND p.active
     AND p.source_domain='organization'
     AND p.acceptance_mode='worker_attestation') THEN
   RAISE EXCEPTION 'Ordinary Work result policy unavailable' USING ERRCODE='23514';
  END IF;
  INSERT INTO atlas.company_work_result_contract_bindings_v1(
   organization_id,ledger_id,work_item_id,actor_person_id,
   actor_membership_id,contract_key,reason)
  VALUES(v_work.organization_id,v_scope.ledger_id,v_work.id,
   v_owner,v_actor_membership,v_contract,
   'Owner assigns existing Work under recipient-accepted standing Ledger scope');
  UPDATE atlas.work_items SET result_contract_key=v_contract,updated_at=now()
   WHERE id=v_work.id AND result_contract_key IS NULL;
 END IF;
 INSERT INTO atlas.work_allocations(
  organization_id,work_item_id,assignee_membership_id,assignee_canonical_person_id,
  assigned_by_membership_id,allocation_role,state,allocated_at,
  establishment_basis_kind,establishment_basis,metadata)
 VALUES(v_work.organization_id,v_work.id,NULL,v_scope.worker_person_id,
  v_actor_membership,'responsible','active',now(),
  'delegated_under_standing_scope',
  jsonb_build_object(
   'contractVersion','exact_work_responsibility_establishment_v2',
   'basisKind','delegated_under_standing_scope',
   'organizationId',v_work.organization_id,'workItemId',v_work.id,
   'targetPersonId',v_scope.worker_person_id,'nativeLedgerId',v_scope.ledger_id,
   'actorMembershipId',v_actor_membership,
   'workerLedgerSeatId',v_scope.worker_ledger_seat_id,
   'scopeId',v_scope.id,'scopeAcceptedAt',v_scope.accepted_at,'establishedAt',now()),
  jsonb_build_object(
   'source','manager_delegated_under_accepted_person_ledger_scope_v1',
   'managerPersonId',v_owner,'scopeId',v_scope.id,'reason',v_reason,
   'canonicalPersonCarrier',true,
   'workerDayReceiptProven',false,'workerReadProven',false))
 RETURNING * INTO v_new;
 RETURN jsonb_build_object('ok',true,
  'contractVersion','company_work_delegated_assignment_v1',
  'state','assigned','workItemId',v_work.id,'allocationId',v_new.id,
  'ledgerId',v_scope.ledger_id,'scopeId',v_scope.id,
  'responsiblePersonId',v_scope.worker_person_id,
  'responsibleMembershipId',NULL,'workerAcceptancePerTaskRequired',false,
  'workerDayPlacementProven',false,'workerReadProven',false,
  'resultContractKey',(SELECT result_contract_key FROM atlas.work_items
   WHERE id=v_work.id));
END
$function$;

CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_today_self_api_v1(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or v_self is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Page size must be between 1 and 100' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',row.work_id,'allocationId',row.allocation_id,
    'organizationId',row.organization_id,'ledgerId',row.ledger_id,
    'title',row.title,'instructions',row.instructions,
    'sourceType',row.source_type,'sourceId',row.source_id,
    'sourceDate',row.source_date,'sourceDateIsNotScheduledDay',true,
    'resultContractKey',row.result_contract,
    'canReportOrdinaryCompletion',row.result_contract=
      'ordinary_company_work_worker_attestation_v1',
    'uptakeKind',row.uptake_kind,'employeeSeatRequired',false)
    order by row.allocated_at,row.work_id),'[]'::jsonb) into v_items
  from (
    select w.id work_id,a.id allocation_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      w.title,w.instructions,w.source_object_type source_type,
      w.source_object_id source_id,
      case when w.metadata->>'originalServiceDate' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        then w.metadata->>'originalServiceDate' else null end source_date,
      w.result_contract_key result_contract,
      coalesce(a.establishment_basis->>'uptakeKind',
        case when a.establishment_basis_kind='delegated_under_standing_scope'
         then 'accepted_standing_scope_direct_assignment' end) uptake_kind,a.allocated_at
    from atlas.work_allocations a
    join atlas.work_items w on w.id=a.work_item_id
      and w.organization_id=a.organization_id
    where a.allocation_role='responsible' and a.state='active'
      and a.assignee_canonical_person_id=v_self
      and a.establishment_basis_kind IN ('person_connection_receiver_uptake','delegated_under_standing_scope')
      and w.work_state='open'
    order by a.allocated_at,a.id
    limit p_limit
  ) row;
  return jsonb_build_object('ok',true,
    'contractVersion','connected_person_company_work_today_v1',
    'personId',v_self,'items',v_items,
    'sourceDateIsNotAWorkSchedule',true,'employeeSeatRequired',false);
end
$function$
;
CREATE OR REPLACE FUNCTION atlas.report_connected_person_company_work_internal_v1(p_work_item_id uuid, p_result_kind text, p_idempotency_key text, p_payload jsonb, p_mode text, p_owner_ledger_id uuid, p_witness_evidence text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_actor uuid:=atlas.current_person_id_v1();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_mode text:=lower(btrim(coalesce(p_mode,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_evidence text:=nullif(btrim(coalesce(p_witness_evidence,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_reporter_ipr uuid;
begin
  if v_uid is null or v_actor is null then
    raise exception 'Signed-in canonical reporting Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_mode not in ('own_work','owner_witness')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, result, mode, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work not found' using errcode='P0002'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible'
      and a.establishment_basis_kind IN ('person_connection_receiver_uptake','delegated_under_standing_scope')
      and a.state in ('active','completed')
    order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Exact Person-native responsible allocation not found' using errcode='23514';
  end if;
  if v_mode='own_work' then
    if v_allocation.assignee_canonical_person_id<>v_actor then
      raise exception 'Only actual responsible Person can make own-work report' using errcode='42501';
    end if;
  else
    if v_evidence is null or length(v_evidence) not between 16 and 2000
      or (v_allocation.establishment_basis->>'nativeLedgerId') is distinct from
        p_owner_ledger_id::text
      or atlas.company_work_native_ledger_owner_self_v1(
        v_work.organization_id,p_owner_ledger_id)<>v_actor then
      raise exception 'Owner report requires exact Ledger and detailed external evidence'
        using errcode='42501';
    end if;
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.metadata->>'reportMode' is distinct from v_mode
      or v_existing.metadata->>'authenticatedReporterPersonId'
           is distinct from v_actor::text
      or (v_mode='owner_witness' and
          v_existing.payload->>'ownerWitnessEvidence' is distinct from v_evidence)
      or (v_mode='own_work' and
          (v_existing.payload-'claimedPerformerPersonId'-'ownerWitnessEvidence')
            is distinct from p_payload) then
      raise exception 'Result idempotency collision' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,
      'resultId',v_existing.id,'workItemId',v_work.id,
      'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Terminal Work cannot receive another result' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists(select 1 from atlas.work_result_contract_policies p
      where p.contract_key=v_work.result_contract_key and p.active
        and p.acceptance_mode='worker_attestation'
        and p.source_domain='organization') then
    raise exception 'Source-specific Work requires its authorized result channel'
      using errcode='23514';
  end if;
  select ipr.id into v_reporter_ipr
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_work.organization_id
      and ipr.person_id=v_actor and ipr.status='active'
    order by ipr.created_at limit 1;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,null,v_reporter_ipr,
    v_kind,v_work.result_contract_key,v_key,
    p_payload||jsonb_strip_nulls(jsonb_build_object(
      'claimedPerformerPersonId',v_allocation.assignee_canonical_person_id,
      'ownerWitnessEvidence',case when v_mode='owner_witness'
        then v_evidence else null end)),
    jsonb_build_object('source','report_connected_person_company_work_internal_v1',
      'reportMode',v_mode,'authenticatedReporterPersonId',v_actor,
      'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
      'performanceIsWitnessedClaim',v_mode='owner_witness',
      'employeeSeatRequired',false)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values (
      v_work.organization_id,v_work.id,v_result.id,'accepted',
      case when v_mode='own_work' then 'self_responsible_person_attestation'
        else 'owner_witnessed_person_result' end,
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'responsibleAllocationId',v_allocation.id,
        'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
        'authenticatedReporterPersonId',v_actor,
        'ownerWitnessEvidence',case when v_mode='owner_witness'
          then v_evidence else null end)),
      jsonb_build_object('source','report_connected_person_company_work_internal_v1',
        'reportMode',v_mode,'notAnEmployeeWorkerDayReport',true)
    ) returning * into v_acceptance;
    update atlas.work_items
      set work_state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_work.id and work_state='open';
    update atlas.work_allocations
      set state='completed',completed_at=coalesce(completed_at,now()),
        updated_at=now()
      where id=v_allocation.id and state='active';
  end if;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','connected_person_company_work_result_v1',
    'workItemId',v_work.id,'resultId',v_result.id,
    'resultKind',v_kind,'workState',
      case when v_kind='completed' then 'completed' else 'open' end,
    'acceptanceDecision',v_acceptance.decision,
    'reportMode',v_mode,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,
    'reporterPersonId',v_actor,'sourceHistoryPreserved',true);
end
$function$
;
CREATE OR REPLACE FUNCTION atlas.company_work_self_responsibilities_api_v1()
 RETURNS TABLE(organization_id uuid, organization_name text, organization_unit_id uuid, organization_unit_key text, organization_unit_name text, work_item_id uuid, allocation_id uuid, title text, instructions text, work_state text, operation_class text, allocation_role text, allocated_at timestamp with time zone, requirements jsonb, next_target_at timestamp with time zone, execution_state text, execution_reason text, legacy_task_id uuid, legacy_task_status text, legacy_task_due_date date, attention_lease_id uuid, attention_lease_state text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;

  RETURN QUERY
  WITH base AS MATERIALIZED(
    SELECT
      wi.organization_id,
      o.name organization_name,
      wi.organization_unit_id,
      ou.stable_key organization_unit_key,
      ou.name organization_unit_name,
      wi.id work_item_id,
      wa.id allocation_id,
      wi.title,
      wi.instructions,
      wi.work_state,
      wi.operation_class,
      wa.allocation_role,
      wa.allocated_at,
      a.task_id legacy_task_id,
      t.status legacy_task_status,
      t.due_date legacy_task_due_date,
      t.blocker_text,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_execution_readiness_v1(t.id) END readiness,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_operation_fit_warrant_v1(t.id) END operation_fit
    FROM atlas.work_allocations wa
    JOIN atlas.work_items wi
      ON wi.organization_id=wa.organization_id
     AND wi.id=wa.work_item_id
     AND wi.work_state='open'
    JOIN atlas.organizations o ON o.id=wi.organization_id
    LEFT JOIN atlas.organization_units ou
      ON ou.organization_id=wi.organization_id
     AND ou.id=wi.organization_unit_id
    LEFT JOIN LATERAL(
      SELECT wea.task_id
      FROM atlas.work_execution_adapters wea
      WHERE wea.organization_id=wi.organization_id
        AND wea.work_item_id=wi.id
        AND wea.state='active'
        AND wea.task_id IS NOT NULL
      ORDER BY wea.created_at DESC
      LIMIT 1
    ) a ON true
    LEFT JOIN atlas.tasks t ON t.id=a.task_id
    WHERE wa.state='active' AND wa.allocation_role='responsible'
      AND (
        wa.assignee_canonical_person_id=atlas.current_person_id_v1()
        OR EXISTS(
          SELECT 1 FROM atlas.organization_memberships m
          WHERE m.id=wa.assignee_membership_id
            AND m.organization_id=wa.organization_id
            AND m.user_id=auth.uid() AND m.active
        )
      )
  )
  SELECT
    b.organization_id,b.organization_name,b.organization_unit_id,b.organization_unit_key,
    b.organization_unit_name,b.work_item_id,b.allocation_id,b.title,b.instructions,b.work_state,
    b.operation_class,b.allocation_role,b.allocated_at,
    coalesce(req.requirements,'[]'::jsonb),
    req.next_target_at,
    CASE
      WHEN b.legacy_task_id IS NULL THEN 'unassessed'
      WHEN b.legacy_task_status='blocked' THEN 'waiting'
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'waiting'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'needs_resolution'
      ELSE 'ready'
    END,
    CASE
      WHEN b.legacy_task_id IS NULL THEN NULL
      WHEN b.legacy_task_status='blocked' THEN coalesce(nullif(btrim(b.blocker_text),''),'task_blocked')
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'execution_requirements_not_ready'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'operation_identity_unresolved'
      ELSE NULL
    END,
    b.legacy_task_id,b.legacy_task_status,b.legacy_task_due_date,
    focus.lease_id,focus.lease_state
  FROM base b
  LEFT JOIN LATERAL(
    SELECT
      jsonb_agg(jsonb_build_object(
        'requirementId',r.id,
        'summary',r.summary,
        'state',r.state,
        'earliestRelevantAt',r.earliest_relevant_at,
        'latestSatisfactoryAt',r.latest_satisfactory_at,
        'consequenceOfDelay',r.consequence_of_delay
      ) ORDER BY r.latest_satisfactory_at NULLS LAST,r.created_at,r.id) requirements,
      min(r.latest_satisfactory_at) next_target_at
    FROM atlas.work_requirement_links l
    JOIN atlas.work_requirements r
      ON r.organization_id=l.organization_id
     AND r.id=l.requirement_id
    WHERE l.organization_id=b.organization_id
      AND l.work_item_id=b.work_item_id
      AND l.active
      AND r.state='active'
  ) req ON true
  LEFT JOIN LATERAL(
    SELECT el.id lease_id,
           (atlas.execution_lease_current_state_v1(el.id)->>'state')::text lease_state
    FROM atlas.execution_leases el
    WHERE el.organization_id=b.organization_id
      AND NOT el.shadow_only
      AND el.execution_kind='task'
      AND el.execution_id=b.legacy_task_id
      AND (atlas.execution_lease_current_state_v1(el.id)->>'state') IN ('leased','started','interrupted')
    ORDER BY el.created_at DESC
    LIMIT 1
  ) focus ON true
  ORDER BY
    CASE
      WHEN focus.lease_id IS NOT NULL THEN 0
      WHEN b.legacy_task_status='blocked' THEN 3
      WHEN b.legacy_task_id IS NOT NULL
       AND coalesce((b.readiness->>'executionReady')::boolean,false)
       AND coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 1
      ELSE 2
    END,
    req.next_target_at NULLS LAST,
    b.allocated_at,
    b.work_item_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.
  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id=new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- Canonical standing delegation: acceptance belongs to a Person and
  -- an exact active Ledger connection, never to an employee seat or Position.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'workerLedgerSeatId','')=''
       or coalesce(v_basis->>'scopeId','')=''
       or coalesce(v_basis->>'scopeAcceptedAt','')='' then
      raise exception 'Canonical standing assignment requires exact Person-Ledger agreement provenance'
        using errcode='23514';
    end if;
    if v_requires_basis and not exists (
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join ledger.seats seat
        on seat.id=scope.worker_ledger_seat_id
       and seat.ledger_id=scope.ledger_id
       and seat.person_entity_id=scope.worker_person_id
       and seat.seat_state='active' and seat.ended_at is null
      join atlas.work_items work
        on work.id=new.work_item_id
       and work.organization_id=scope.organization_id
       and work.work_state='open'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
       and relevance.organization_id=scope.organization_id
       and relevance.ledger_id=scope.ledger_id
       and relevance.attribution_state='active'
      join atlas.organization_memberships manager
        on manager.id=new.assigned_by_membership_id
       and manager.organization_id=scope.organization_id
       and manager.active and manager.role='owner'
      where scope.id::text=v_basis->>'scopeId'
        and scope.organization_id=new.organization_id
        and scope.worker_person_id=new.assignee_canonical_person_id
        and scope.worker_ledger_seat_id::text=v_basis->>'workerLedgerSeatId'
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.scope_state='active'
        and scope.accepted_at is not null
        and scope.accepted_at::text=v_basis->>'scopeAcceptedAt'
        and scope.accepted_by_person_id=scope.worker_person_id
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and (scope.organization_unit_id is null
             or scope.organization_unit_id=work.organization_unit_id)
        and (relevance.evidence_kind='owner_attested' or
            (relevance.evidence_kind='source_verified' and exists(
              select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
              where proof.source_schema=relevance.source_schema
                and proof.source_table=relevance.source_table
                and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Exact accepted Person-Ledger scope cannot authorize this Work'
        using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.validate_active_work_allocation_membership_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
begin
  if new.state='active' then
    if new.allocation_role='responsible'
      and new.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope') then
      if new.assignee_membership_id is not null
        or new.assignee_canonical_person_id is null
        or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Person-native responsibility requires an exact active Ledger connection'
          using errcode='23514';
      end if;
    elsif not exists (
      select 1 from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id and om.active
    ) then
      raise exception 'Legacy active Work allocation requires active Organization Membership'
        using errcode='23514';
    end if;
    if new.assigned_by_membership_id is not null
      and (tg_op='INSERT'
        or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
        or old.state is distinct from new.state
        or old.organization_id is distinct from new.organization_id)
      and not exists (
        select 1 from atlas.organization_memberships om
        where om.id=new.assigned_by_membership_id
          and om.organization_id=new.organization_id and om.active
      ) then
      raise exception 'Active Work allocation cannot name an inactive assigning membership'
        using errcode='23514';
    end if;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION atlas.sync_production_company_work_responsibility_carrier_v1(p_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_occ atlas.planned_work_occurrences%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_farm_member_count integer:=0;
  v_conflict_id uuid;
  v_result jsonb;
begin
  if p_work_item_id is null then
    raise exception 'Company Work item is required.' using errcode='22023';
  end if;

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;

  if v_work.source_object_type<>'production_bed_assignment' then
    return jsonb_build_object('state','unsupported_source','workItemId',v_work.id);
  end if;

  if v_work.work_state<>'open' then
    return jsonb_build_object('state','work_not_open','workItemId',v_work.id,'workState',v_work.work_state);
  end if;

  select * into v_adapter
  from atlas.work_execution_adapters
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and state='active'
    and planned_occurrence_id is not null
  order by created_at
  limit 1;

  if v_adapter.id is null then
    return jsonb_build_object('state','no_execution_carrier','workItemId',v_work.id);
  end if;

  select * into v_occ
  from atlas.planned_work_occurrences
  where id=v_adapter.planned_occurrence_id;

  if v_occ.id is null then
    return jsonb_build_object('state','missing_execution_occurrence','workItemId',v_work.id,'adapterId',v_adapter.id);
  end if;

  select * into v_allocation
  from atlas.work_allocations
  where organization_id=v_work.organization_id
    and work_item_id=v_work.id
    and state='active'
    and allocation_role='responsible'
  limit 1;

  if v_allocation.id is null then
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)-'assigned_membership_id'-'assigned_user_id')
          || jsonb_build_object('visibility_scope','system_internal')
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','unresolved',
               'responsibility_authority','work_allocations',
               'legacy_assignment_suppressed',true
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=null,
          assigned_user_id=null,
          visibility_scope='system_internal',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','unresolved',
            'responsibility_authority','work_allocations',
            'legacy_assignment_suppressed',true
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','responsibility_unresolved',
          'responsibilityAuthority','work_allocations',
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    update atlas.work_planning_conflicts
    set state='resolved',resolution_kind='responsibility_released',
        resolution_note='Canonical Responsibility is currently unassigned; no worker carrier should be inferred.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id
      and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';

    perform atlas.materialize_production_bed_preparation_company_work_v1(v_work.source_object_id,null);

    return jsonb_build_object(
      'state','responsibility_unresolved',
      'workItemId',v_work.id,
      'adapterId',v_adapter.id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  end if;


  -- Person-native responsibility is real, but never smuggles a synthetic
  -- employee/farm membership into the historical execution carrier.
  if v_allocation.assignee_membership_id is null
    and v_allocation.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope') then
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)
        - 'assigned_membership_id' - 'assigned_user_id')
       ||jsonb_build_object('visibility_scope','system_internal')
       ||jsonb_build_object('metadata',
          coalesce(task_payload->'metadata','{}'::jsonb)
          ||jsonb_build_object('responsibility_state','person_native_assigned',
             'responsibility_authority','work_allocations',
             'company_work_allocation_id',v_allocation.id,
             'legacy_assignment_suppressed',true)),
      updated_at=now()
    where id=v_occ.id;
    if v_adapter.task_id is not null then
      update atlas.tasks set assigned_membership_id=null,assigned_user_id=null,
        visibility_scope='system_internal',
        metadata=coalesce(metadata,'{}'::jsonb)
          ||jsonb_build_object('responsibility_state','person_native_assigned',
             'responsibility_authority','work_allocations',
             'company_work_allocation_id',v_allocation.id,
             'legacy_assignment_suppressed',true),
        updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;
    update atlas.work_execution_adapters
      set metadata=coalesce(metadata,'{}'::jsonb)
        ||jsonb_build_object('executionCarrierDeliveryState','person_native_today',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'carrierAssignmentIsResponsibilityEvidence',false),
        updated_at=now()
    where id=v_adapter.id;
    update atlas.work_planning_conflicts
      set state='resolved',resolution_kind='person_native_delivery',
        resolution_note='Canonical Person owns this Work; no fake employee carrier was created.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';
    perform atlas.materialize_production_bed_preparation_company_work_v1(
      v_work.source_object_id,null);
    return jsonb_build_object('state','person_native_today',
      'workItemId',v_work.id,'allocationId',v_allocation.id,
      'personId',v_allocation.assignee_canonical_person_id,
      'legacyEmployeeCarrierCreated',false);
  end if;

  select * into v_org_member
  from atlas.organization_memberships
  where id=v_allocation.assignee_membership_id
    and organization_id=v_work.organization_id
    and active;

  if v_org_member.id is null then
    raise exception 'Active responsible allocation points to an inactive or foreign Organization Membership.' using errcode='23514';
  end if;

  select count(*)::integer into v_farm_member_count
  from atlas.farm_memberships fm
  where fm.farm_id=v_occ.farm_id
    and fm.user_id=v_org_member.user_id
    and fm.active;

  if v_farm_member_count=1 then
    select * into v_farm_member
    from atlas.farm_memberships fm
    where fm.farm_id=v_occ.farm_id
      and fm.user_id=v_org_member.user_id
      and fm.active
    order by fm.created_at
    limit 1;

    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)
          || jsonb_build_object(
               'assigned_membership_id',v_farm_member.id::text,
               'assigned_user_id',v_org_member.user_id::text,
               'visibility_scope','assigned_worker'
             ))
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','assigned',
               'responsibility_authority','work_allocations',
               'company_work_allocation_id',v_allocation.id,
               'assignee_organization_membership_id',v_org_member.id,
               'execution_farm_membership_id',v_farm_member.id,
               'carrier_assignment_is_responsibility_evidence',false
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=v_farm_member.id,
          assigned_user_id=v_org_member.user_id,
          visibility_scope='assigned_worker',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','assigned',
            'responsibility_authority','work_allocations',
            'company_work_allocation_id',v_allocation.id,
            'assignee_organization_membership_id',v_org_member.id,
            'execution_farm_membership_id',v_farm_member.id,
            'carrier_assignment_is_responsibility_evidence',false
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','ready',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'executionFarmMembershipId',v_farm_member.id,
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    update atlas.work_planning_conflicts
    set state='resolved',resolution_kind='execution_membership_resolved',
        resolution_note='Canonical Responsibility now resolves to exactly one active Farm Membership for this compatibility carrier.',
        resolved_at=now(),updated_at=now()
    where organization_id=v_work.organization_id
      and work_item_id=v_work.id
      and state='open'
      and metadata->>'source'='company_work_execution_carrier_membership';

    v_result:=jsonb_build_object(
      'state','carrier_ready',
      'workItemId',v_work.id,
      'allocationId',v_allocation.id,
      'organizationMembershipId',v_org_member.id,
      'farmMembershipId',v_farm_member.id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  else
    update atlas.planned_work_occurrences
    set task_payload=(coalesce(task_payload,'{}'::jsonb)-'assigned_membership_id'-'assigned_user_id')
          || jsonb_build_object('visibility_scope','system_internal')
          || jsonb_build_object('metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
               'responsibility_state','assigned_delivery_unresolved',
               'responsibility_authority','work_allocations',
               'company_work_allocation_id',v_allocation.id,
               'assignee_organization_membership_id',v_org_member.id,
               'active_matching_farm_memberships',v_farm_member_count
             )),
        updated_at=now()
    where id=v_occ.id;

    if v_adapter.task_id is not null then
      update atlas.tasks
      set assigned_membership_id=null,
          assigned_user_id=null,
          visibility_scope='system_internal',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'responsibility_state','assigned_delivery_unresolved',
            'responsibility_authority','work_allocations',
            'company_work_allocation_id',v_allocation.id,
            'assignee_organization_membership_id',v_org_member.id,
            'active_matching_farm_memberships',v_farm_member_count
          ),
          updated_at=now()
      where id=v_adapter.task_id and status in ('open','blocked');
    end if;

    update atlas.work_execution_adapters
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'executionCarrierDeliveryState','membership_unresolved',
          'responsibilityAuthority','work_allocations',
          'companyWorkAllocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'activeMatchingFarmMemberships',v_farm_member_count,
          'carrierAssignmentIsResponsibilityEvidence',false
        ),
        updated_at=now()
    where id=v_adapter.id;

    select pc.id into v_conflict_id
    from atlas.work_planning_conflicts pc
    where pc.organization_id=v_work.organization_id
      and pc.work_item_id=v_work.id
      and pc.state='open'
      and pc.metadata->>'source'='company_work_execution_carrier_membership'
    order by pc.detected_at desc
    limit 1;

    if v_conflict_id is null then
      insert into atlas.work_planning_conflicts(
        organization_id,work_item_id,allocation_id,conflict_kind,detected_at,required_by,
        capacity_snapshot,reason,state,metadata
      ) values(
        v_work.organization_id,v_work.id,v_allocation.id,'no_eligible_assignee',now(),
        (select preferred_end_at from atlas.work_time_contracts where work_item_id=v_work.id and contract_state='active' order by created_at desc limit 1),
        jsonb_build_object('activeMatchingFarmMemberships',v_farm_member_count),
        'Canonical Responsibility is established, but the legacy farm execution carrier cannot resolve the responsible Organization Membership to exactly one active Farm Membership. Responsibility remains true; carrier delivery is unresolved.',
        'open',jsonb_build_object(
          'source','company_work_execution_carrier_membership',
          'allocationId',v_allocation.id,
          'assigneeOrganizationMembershipId',v_org_member.id,
          'farmId',v_occ.farm_id
        )
      ) returning id into v_conflict_id;
    else
      update atlas.work_planning_conflicts
      set allocation_id=v_allocation.id,
          capacity_snapshot=jsonb_build_object('activeMatchingFarmMemberships',v_farm_member_count),
          reason='Canonical Responsibility is established, but the legacy farm execution carrier cannot resolve the responsible Organization Membership to exactly one active Farm Membership. Responsibility remains true; carrier delivery is unresolved.',
          metadata=metadata||jsonb_build_object('allocationId',v_allocation.id,'assigneeOrganizationMembershipId',v_org_member.id,'farmId',v_occ.farm_id),
          updated_at=now()
      where id=v_conflict_id;
    end if;

    v_result:=jsonb_build_object(
      'state','responsibility_assigned_carrier_unresolved',
      'workItemId',v_work.id,
      'allocationId',v_allocation.id,
      'organizationMembershipId',v_org_member.id,
      'activeMatchingFarmMemberships',v_farm_member_count,
      'planningConflictId',v_conflict_id,
      'occurrenceId',v_occ.id,
      'taskId',v_adapter.task_id
    );
  end if;

  perform atlas.materialize_production_bed_preparation_company_work_v1(v_work.source_object_id,null);
  return v_result;
end;
$function$;

COMMIT;

BEGIN;
-- Source-only exact-preimage patch. No replacement Work or legacy table.
DO $patch$
DECLARE d text; a text; b text;
BEGIN
 d:=pg_get_functiondef('atlas.today_work_assignment_activity_self_api_v1(date,text,integer)'::regprocedure);
 IF md5(d)<>'9528171cd3a1a886243f8275652139ad' THEN RAISE EXCEPTION 'Assignment activity source drift'; END IF;
 a:=$a$    and a.establishment_basis->>'senderPersonId'=v_person::text$a$;
 b:=a||chr(10)||'    and a.assignee_canonical_person_id<>v_person';
 IF length(d)-length(replace(d,a,''))<>length(a) THEN RAISE EXCEPTION 'Assignment activity anchor drift';END IF;
 EXECUTE replace(d,a,b);

 d:=pg_get_functiondef('atlas.report_connected_person_company_work_internal_v1(uuid,text,text,jsonb,text,uuid,text)'::regprocedure);
 IF md5(d)<>'c7cfef69c35e6571221e7f6573125cb3' THEN RAISE EXCEPTION 'Result source drift'; END IF;
 a:=$a$  v_reporter_ipr uuid;
begin$a$;
 b:=$b$  v_reporter_ipr uuid;
  v_performed date; v_timezone text;
begin$b$;
 IF length(d)-length(replace(d,a,''))<>length(a) THEN RAISE EXCEPTION 'Result declaration drift';END IF;
 d:=replace(d,a,b);
 a:=$a$  perform pg_advisory_xact_lock(hashtextextended($a$;
 b:=$b$  -- Only a completed own-work Result can explicitly attest its performed day.
  if p_payload ? 'performedOnCivilDate' or p_payload ? 'performedOnTimezone' then
    v_timezone:=p_payload->>'performedOnTimezone';
    if v_mode<>'own_work' or v_kind<>'completed'
       or coalesce(p_payload->>'performedOnCivilDate','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       or v_timezone is null
       or not exists(select 1 from pg_catalog.pg_timezone_names tz where tz.name=v_timezone)
    then raise exception 'Explicit own completion day and timezone required' using errcode='22023';end if;
    begin
      v_performed:=(p_payload->>'performedOnCivilDate')::date;
    exception when datetime_field_overflow or invalid_datetime_format then
      raise exception 'Invalid performed-on day' using errcode='22023';
    end;
    if v_performed>(now() at time zone v_timezone)::date
    then raise exception 'Actual completion cannot be a future day' using errcode='22023';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended($b$;
 IF length(d)-length(replace(d,a,''))<>length(a) THEN RAISE EXCEPTION 'Result validation anchor drift';END IF;
 d:=replace(d,a,b);
 a:=$a$'employeeSeatRequired',false)
  ) returning * into v_result;$a$;
 b:=$b$'employeeSeatRequired',false)
    ||case when v_performed is not null then jsonb_build_object(
       'performedOnCivilDate',v_performed,'performedOnTimezone',v_timezone,
       'performedOnBasis','signed_responsible_person_attestation') else '{}'::jsonb end
  ) returning * into v_result;$b$;
 IF length(d)-length(replace(d,a,''))<>length(a) THEN RAISE EXCEPTION 'Result evidence anchor drift';END IF;
 EXECUTE replace(d,a,b);
END $patch$;

-- Record, rather than propose, when signed authority permits. Old v1
-- submitters and already pending originals are not silently adjudicated.
CREATE FUNCTION atlas.record_ledger_work_self_api_v2(p_ledger_id uuid,p_title text,p_attention_date_proposal date,p_source_action_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE receipt jsonb; decision jsonb; governor uuid;
BEGIN
 receipt:=atlas.submit_ledger_work_self_api_v1(p_ledger_id,p_title,p_attention_date_proposal,p_source_action_id);
 IF receipt->>'createdNow'='true' AND receipt->>'reviewState'='submitted' THEN
   BEGIN
     SELECT c.principal_id INTO governor FROM atlas.capability_root_authority_context_self_v1(p_ledger_id) c
       WHERE c.person_id=atlas.current_person_id_v1() AND c.principal_id=atlas.current_principal_id_v1();
   EXCEPTION WHEN insufficient_privilege THEN governor:=NULL;
   END;
   IF governor IS NOT NULL THEN
     decision:=atlas.decide_ledger_work_intake_root_self_api_v1((receipt->>'intakeId')::uuid,
        'accepted_for_ledger',0,'Work established by its current Ledger governor.');
     IF decision->>'reviewState' IS DISTINCT FROM 'accepted_for_ledger'
       OR decision->>'workItemId' IS DISTINCT FROM receipt->>'workItemId'
       OR decision->>'ledgerId' IS DISTINCT FROM p_ledger_id::text
     THEN RAISE EXCEPTION 'Exact governing decision not confirmed' USING errcode='23514';END IF;
     receipt:=receipt||jsonb_build_object('reviewState','accepted_for_ledger','notificationKind',null);
   END IF;
 END IF;
 RETURN receipt||jsonb_build_object('contractVersion','ledger_work_record_v2');
END;
$fn$;
CREATE FUNCTION public.record_ledger_work_self_api_v2(p_ledger_id uuid,p_title text,p_attention_date_proposal date,p_source_action_id text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
 SELECT atlas.record_ledger_work_self_api_v2($1,$2,$3,$4);
$fn$;
REVOKE ALL ON FUNCTION atlas.record_ledger_work_self_api_v2(uuid,text,date,text),public.record_ledger_work_self_api_v2(uuid,text,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.record_ledger_work_self_api_v2(uuid,text,date,text),public.record_ledger_work_self_api_v2(uuid,text,date,text) TO authenticated;

-- Accepted own Results form the day journal independent of work-on plans.
-- Prior Results without a signed performed date are recorded-on evidence only.
CREATE FUNCTION atlas.connected_person_company_work_day_self_api_v2(p_date date,p_timezone text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE viewer uuid; base jsonb; items jsonb;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
    OR p_date IS NULL OR p_timezone IS NULL
    OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names tz WHERE tz.name=p_timezone)
 THEN RAISE EXCEPTION 'Signed Person, day and timezone required' USING errcode='42501';END IF;
 viewer:=atlas.current_person_id_v1();
 IF viewer IS NULL THEN RAISE EXCEPTION 'Canonical Person required' USING errcode='42501';END IF;
 base:=atlas.connected_person_company_work_day_self_api_v1(p_date);
 WITH own_results AS MATERIALIZED (
  SELECT w.id work_id,w.organization_id,w.title,w.instructions,a.id allocation_id,
    (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
    w.completed_at,r.id result_id,r.reported_at,
    CASE WHEN r.metadata->>'performedOnBasis'='signed_responsible_person_attestation'
      THEN (r.metadata->>'performedOnCivilDate')::date END performed_on
  FROM atlas.work_allocations a
  JOIN atlas.work_items w ON w.id=a.work_item_id AND w.organization_id=a.organization_id
  JOIN LATERAL (
    SELECT r.id,r.reported_at,r.metadata FROM atlas.work_execution_results r
    WHERE r.work_item_id=w.id AND r.organization_id=w.organization_id
      AND r.responsible_allocation_id=a.id AND r.result_kind='completed'
      AND r.metadata->>'reportMode'='own_work'
      AND r.metadata->>'authenticatedReporterPersonId'=viewer::text
      AND r.metadata->>'canonicalResponsiblePersonId'=viewer::text
      AND r.result_contract_key='ordinary_company_work_worker_attestation_v1'
      AND EXISTS(SELECT 1 FROM atlas.work_result_acceptances ra
        WHERE ra.execution_result_id=r.id AND ra.work_item_id=w.id AND ra.organization_id=w.organization_id
          AND ra.decision='accepted')
    ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
  ) r ON true
  WHERE a.assignee_canonical_person_id=viewer AND a.assignee_membership_id IS NULL
    AND a.allocation_role='responsible' AND a.state='completed' AND w.work_state='completed'
    AND a.establishment_basis_kind IN ('person_connection_receiver_uptake','delegated_under_standing_scope',
      'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
    AND atlas.person_has_native_ledger_connection_v1(w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,viewer)
    AND atlas.person_original_work_identity_disclosed_self_v1(w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,w.id,viewer)
 ), projected AS (
  SELECT item||jsonb_build_object('journalDate',p_date,'journalBasis','existing_plan_day') packet
  FROM jsonb_array_elements(base->'items') item
  WHERE NOT EXISTS(SELECT 1 FROM own_results r WHERE r.work_id::text=item->>'workItemId')
  UNION ALL
  SELECT jsonb_build_object('workItemId',r.work_id,'allocationId',r.allocation_id,
    'organizationId',r.organization_id,'ledgerId',r.ledger_id,'title',r.title,'instructions',r.instructions,
    'planId',plan.id,'executionDate',plan.planned_service_date,'exposureDate',plan.exposure_service_date,
    'journalDate',p_date,'journalBasis',CASE WHEN r.performed_on IS NULL THEN 'recorded_on_day' ELSE 'performed_on_day' END,
    'performedOn',r.performed_on,'workState','completed','allocationState','completed',
    'completedAt',r.completed_at,'latestResultId',r.result_id,'latestResultKind','completed',
    'latestResultAt',r.reported_at,'latestAcceptanceDecision','accepted','canReportOrdinaryCompletion',false)
  FROM own_results r
  LEFT JOIN LATERAL (
    SELECT p.id,p.planned_service_date,p.exposure_service_date FROM atlas.work_execution_plans p
    WHERE p.work_item_id=r.work_id AND p.organization_id=r.organization_id
      AND p.responsible_allocation_id=r.allocation_id AND p.plan_state='completed'
    ORDER BY p.created_at DESC,p.id DESC LIMIT 1
  ) plan ON true
  WHERE coalesce(r.performed_on,(r.reported_at at time zone p_timezone)::date)=p_date
 )
 SELECT coalesce(jsonb_agg(packet ORDER BY packet->>'workItemId'),'[]'::jsonb) INTO items FROM projected;
 RETURN jsonb_build_object('ok',true,'contractVersion','connected_person_company_work_day_v2',
   'date',p_date,'timezone',p_timezone,'personId',viewer,'items',items,'oneCanonicalWorkIdentity',true);
END;
$fn$;
CREATE FUNCTION public.connected_person_company_work_day_self_api_v2(p_date date,p_timezone text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $fn$
 SELECT atlas.connected_person_company_work_day_self_api_v2($1,$2);
$fn$;
REVOKE ALL ON FUNCTION atlas.connected_person_company_work_day_self_api_v2(date,text),public.connected_person_company_work_day_self_api_v2(date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.connected_person_company_work_day_self_api_v2(date,text),public.connected_person_company_work_day_self_api_v2(date,text) TO authenticated;
COMMIT;

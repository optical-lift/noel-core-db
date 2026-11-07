-- UNI-OPS-01 / HELD source-only transport proposal.
-- DEFAULT CLOSED: NO authenticated/anon/service_role/public EXECUTE grant.
-- This is NOT a release migration, not an instruction to deploy or grant.
-- One known case UUID -> exactly one existing current-root-checked private
-- receipt; no listing, source narrative, Subject details, Person roster,
-- mutation, Company decision, Work, assignment, or Clock.
-- Depends on the exact held Company 01/02/03 reader package. A separate
-- explicit access/privacy decision and signed PostgREST negative test are
-- required before introducing an authenticated EXECUTE grant.
BEGIN;

DO $private_reader_pin$
DECLARE
  v_reader oid := to_regprocedure(
    'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)'
  );
BEGIN
  IF v_reader IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE p.oid=v_reader AND n.nspname='atlas'
         AND p.prosecdef AND p.provolatile='s'
     )
     OR has_function_privilege(
       'authenticated',
       'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)',
       'EXECUTE'
     )
     OR to_regprocedure(
       'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)'
     ) IS NOT NULL
  THEN
    RAISE EXCEPTION
      'HELD Company case receipt transport source/permission drift'
      USING ERRCODE='42501';
  END IF;
END;
$private_reader_pin$;

CREATE FUNCTION public.uni_ops_company_governed_case_receipt_self_api_v1(
  p_case_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $one_known_case_receipt$
DECLARE
  v_receipt jsonb;
  v_allowed_keys text[] := ARRAY[
    'ok',
    'contractVersion',
    'caseId',
    'sourceCaseRegisteredAt',
    'sourceEvidenceRecordedAt',
    'domainAdapterMarkedVerified',
    'latestRegisteredAdmittedRevision',
    'latestGovernorDecisionId',
    'latestGovernorDecisionAt',
    'latestGovernorDecisionOutcome',
    'currentDomainSourceStillNeedsFreshProof',
    'realSourceSubjectDisclosureWasNotGrantedByThisReader',
    'permissionToCreateOriginalWork',
    'permissionToAssignWorker',
    'permissionToPlacePrincipalClockCandidate',
    'permissionToAcceptActualOrDone',
    'permissionToAutoCreateNextWork'
  ]::text[];
BEGIN
  -- The real signed principal/Person is required even for a read.
  -- The private reader then checks CURRENT governing Ledger root, current
  -- Organization/Ledger participation, and exact case ID. It returns the
  -- same 42501 for missing cases and unauthorized persons.
  IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL
     OR p_case_id IS NULL
  THEN
    RAISE EXCEPTION 'Known current signed governor case required'
      USING ERRCODE='42501';
  END IF;
  v_receipt := atlas.uni_ops_company_governed_case_receipt_self_held_v1(
    p_case_id
  );

  -- Positive source reply is still not an access grant. Fail closed on
  -- any future expansion, altered version, changed source-freshness
  -- warning, or TRUE permission to issue Work or access Subject material.
  IF v_receipt IS NULL
     OR pg_catalog.jsonb_typeof(v_receipt) IS DISTINCT FROM 'object'
     OR NOT (v_receipt ?& v_allowed_keys)
     OR (v_receipt - v_allowed_keys) <> '{}'::jsonb
     OR v_receipt->>'ok' IS DISTINCT FROM 'true'
     OR v_receipt->>'contractVersion'
        IS DISTINCT FROM 'uni_ops_company_governed_case_receipt_v1'
     OR v_receipt->>'caseId' IS DISTINCT FROM p_case_id::text
     OR v_receipt->'domainAdapterMarkedVerified' IS DISTINCT FROM 'true'::jsonb
     OR v_receipt->'currentDomainSourceStillNeedsFreshProof'
        IS DISTINCT FROM 'true'::jsonb
     OR v_receipt->'realSourceSubjectDisclosureWasNotGrantedByThisReader'
        IS DISTINCT FROM 'true'::jsonb
     OR v_receipt->'permissionToCreateOriginalWork'
        IS DISTINCT FROM 'false'::jsonb
     OR v_receipt->'permissionToAssignWorker'
        IS DISTINCT FROM 'false'::jsonb
     OR v_receipt->'permissionToPlacePrincipalClockCandidate'
        IS DISTINCT FROM 'false'::jsonb
     OR v_receipt->'permissionToAcceptActualOrDone'
        IS DISTINCT FROM 'false'::jsonb
     OR v_receipt->'permissionToAutoCreateNextWork'
        IS DISTINCT FROM 'false'::jsonb
  THEN
    RAISE EXCEPTION 'Company case receipt projection is not safe to expose'
      USING ERRCODE='42501';
  END IF;

  -- Exact safe projection, not raw table/source/body access. No source
  -- identifiers except the known caseId, no recipient or roster, no
  -- Subject text, no decision reason, no hidden institutional detail.
  RETURN pg_catalog.jsonb_build_object(
    'ok',v_receipt->'ok',
    'contractVersion',v_receipt->'contractVersion',
    'caseId',v_receipt->'caseId',
    'sourceCaseRegisteredAt',v_receipt->'sourceCaseRegisteredAt',
    'sourceEvidenceRecordedAt',v_receipt->'sourceEvidenceRecordedAt',
    'domainAdapterMarkedVerified',v_receipt->'domainAdapterMarkedVerified',
    'latestRegisteredAdmittedRevision',v_receipt->'latestRegisteredAdmittedRevision',
    'latestGovernorDecisionId',v_receipt->'latestGovernorDecisionId',
    'latestGovernorDecisionAt',v_receipt->'latestGovernorDecisionAt',
    'latestGovernorDecisionOutcome',v_receipt->'latestGovernorDecisionOutcome',
    'currentDomainSourceStillNeedsFreshProof',
       v_receipt->'currentDomainSourceStillNeedsFreshProof',
    'realSourceSubjectDisclosureWasNotGrantedByThisReader',
       v_receipt->'realSourceSubjectDisclosureWasNotGrantedByThisReader',
    'permissionToCreateOriginalWork',v_receipt->'permissionToCreateOriginalWork',
    'permissionToAssignWorker',v_receipt->'permissionToAssignWorker',
    'permissionToPlacePrincipalClockCandidate',
       v_receipt->'permissionToPlacePrincipalClockCandidate',
    'permissionToAcceptActualOrDone',
       v_receipt->'permissionToAcceptActualOrDone',
    'permissionToAutoCreateNextWork',
       v_receipt->'permissionToAutoCreateNextWork'
  );
END;
$one_known_case_receipt$;

-- Function creation carries PostgreSQL's default PUBLIC EXECUTE unless it
-- is explicitly revoked. These revokes occur in the SAME transaction
-- before this function can be visible to another transaction. A future
-- separately authorized access grant must be separately reviewed/tested.
REVOKE ALL ON FUNCTION
  public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION
  public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)
IS 'HELD / DEFAULT CLOSED: one known signed Company governor case receipt; no public execution until separate source/privacy/transport acceptance';

DO $remain_closed$
BEGIN
  IF has_function_privilege(
    'authenticated',
    'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'service_role',
    'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'HELD transport unexpectedly granted'
      USING ERRCODE='42501';
  END IF;
END;
$remain_closed$;
COMMIT;

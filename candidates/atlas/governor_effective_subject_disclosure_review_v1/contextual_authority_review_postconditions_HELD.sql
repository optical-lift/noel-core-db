-- Apply after canonical governor review + held contextual override on disposable clone.

-- Option C P0B: context jurisdiction facts are diagnostic, never target access.
DO $contextual_root_review$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef(
    'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure
  ) INTO v_def;
  IF position('contextualAuthorityReview' in v_def)=0
    OR position('v_target_principal_count=1' in v_def)=0
    OR position('v_exact_participation_count=1' in v_def)=0
    OR position('v_primary_candidate_count=1' in v_def)=0
    OR position('a.ended_at IS NULL' in v_def)=0
    OR position('legacyDualRootIsNotUniversalAuthorityLaw' in v_def)=0
    OR position('doesNotAuthorizeAnyOperation' in v_def)=0
    OR position('contextualOperationObservations' in v_def)=0
    OR position('contextualFieldObservations' in v_def)=0
    OR position('grantChainCoverage' in v_def)=0
    OR position('legacy_last_decision_only' in v_def)=0
    OR position('sourceWriterRecheckRequired' in v_def)=0
    OR position('doesNotDiscloseFieldToTarget' in v_def)=0
    OR position('effectivePermission' in v_def)=0
    OR position('verification_incomplete' in v_def)=0
    OR position('notAnEffectivePermissionCertificate' in v_def)=0
    OR position('notASignedTargetSessionProof' in v_def)=0
    OR position('isSignedTargetAccessProof' in v_def)=0
  THEN
    RAISE EXCEPTION 'Contextual governor review is missing bounded, non-grant source guards';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
    'EXECUTE')
    OR has_function_privilege('anon',
    'public.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
    'EXECUTE')
    OR has_function_privilege('authenticated',
    'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
    'EXECUTE')
  THEN
    RAISE EXCEPTION 'Governor-only review RPC boundary altered';
  END IF;
END $contextual_root_review$;

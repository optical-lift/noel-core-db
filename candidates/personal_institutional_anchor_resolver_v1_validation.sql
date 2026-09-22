begin;

do $validation$
declare
  v_user uuid := 'f6b10000-0000-4000-8000-000000000001'::uuid;
  v_capture uuid := 'f6b10000-0000-4000-8000-000000000004'::uuid;
  v_proposed jsonb;
  v_proposal_id uuid;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_result jsonb;
  v_before_org integer;
  v_before_composition integer;
  v_before_items integer;
  v_before_cases integer;
begin
  if to_regprocedure('atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)') is null then
    raise exception 'Institutional Anchor Resolver function missing.';
  end if;

  select count(*) into v_before_org from atlas.organizations;
  select count(*) into v_before_composition from atlas.atlas_service_commercial_compositions;
  select count(*) into v_before_items from atlas.atlas_service_commercial_composition_items;
  select count(*) into v_before_cases from atlas.implementation_cases;

  v_proposed := atlas.propose_personal_reality_effects_internal_v1(
    v_user,
    v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-anchor:unknown-example',
      'effectKind','institutional_anchor',
      'proposal',jsonb_build_object('candidateLabel','No Existing Fixture Institution'),
      'confidence',1,
      'explanation','Validation institutional anchor.',
      'metadata',jsonb_build_object('validationFixture',true)
    )),
    'rule',
    'validation:personal_institutional_resolver_v1'
  );

  v_proposal_id := nullif(v_proposed#>>'{effects,0,id}','')::uuid;
  if v_proposal_id is null then
    raise exception 'Validation Institutional Anchor proposal missing.';
  end if;

  v_receipt := atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,
    v_proposal_id,
    'confirm',
    'validation:institutional-resolver-confirm',
    '{"source":"validation_fixture"}'::jsonb
  );
  v_receipt_id := nullif(v_receipt->>'receiptId','')::uuid;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform atlas.confirm_personal_reality_effect_self_api_v1(v_proposal_id,v_receipt_id);

  v_result := atlas.resolve_personal_institutional_anchor_self_api_v1(v_proposal_id,12);

  if v_result->>'state'<>'unresolved'
     or jsonb_array_length(v_result->'existingLedgers')<>0
     or jsonb_array_length(v_result->'accessibleOrganizations')<>0
     or jsonb_array_length(v_result->'implementationCases')<>0 then
    raise exception 'No-match Institutional Anchor did not remain unresolved: %',v_result;
  end if;

  if coalesce((v_result#>>'{truthBoundary,labelMatchDoesNotEstablishIdentity}')::boolean,false) is not true
     or coalesce((v_result#>>'{truthBoundary,noMatchDoesNotAuthorizeOrganizationCreation}')::boolean,false) is not true
     or coalesce((v_result#>>'{truthBoundary,doesNotCreateCommercialProposal}')::boolean,false) is not true then
    raise exception 'Resolver truth boundary is incomplete: %',v_result;
  end if;

  if (select count(*) from atlas.organizations)<>v_before_org
     or (select count(*) from atlas.atlas_service_commercial_compositions)<>v_before_composition
     or (select count(*) from atlas.atlas_service_commercial_composition_items)<>v_before_items
     or (select count(*) from atlas.implementation_cases)<>v_before_cases then
    raise exception 'Read-only resolver mutated downstream reality.';
  end if;

  perform set_config('request.jwt.claim.sub','f6b10000-0000-4000-8000-000000000099',true);
  begin
    perform atlas.resolve_personal_institutional_anchor_self_api_v1(v_proposal_id,12);
    raise exception 'Resolver allowed another user to inspect the proposal.';
  exception
    when insufficient_privilege then null;
  end;

  if not has_function_privilege(
       'authenticated',
       'atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)',
       'EXECUTE'
     ) then
    raise exception 'Resolver privilege boundary is incorrect.';
  end if;
end;
$validation$;

rollback;

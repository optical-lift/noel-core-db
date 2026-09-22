begin;

do $validation$
declare
  v_user uuid := 'f6a10000-0000-4000-8000-000000000001'::uuid;
  v_capture uuid := 'f6a10000-0000-4000-8000-000000000004'::uuid;
  v_result jsonb;
  v_validation jsonb;
  v_proposal_id uuid;
  v_receipt_id uuid;
  v_confirmed jsonb;
  v_before_org integer;
  v_before_composition integer;
  v_before_items integer;
  v_before_cases integer;
  v_before_entitlements integer;
  v_before_personal_purchases integer;
  v_before_implementation_purchases integer;
begin
  if to_regclass('atlas.personal_reality_effect_proposals') is null
     or to_regprocedure('atlas.propose_personal_reality_effects_internal_v1(uuid,uuid,jsonb,text,text)') is null
     or to_regprocedure('atlas.issue_personal_reality_human_decision_receipt_serv_v1(uuid,uuid,text,text,jsonb)') is null
     or to_regprocedure('atlas.confirm_personal_reality_effect_self_api_v1(uuid,uuid)') is null then
    raise exception 'Live Personal Reality Capture Membrane v1 is required.';
  end if;

  v_validation := atlas.personal_reality_effect_validation_v1(
    'institutional_anchor',
    jsonb_build_object(
      'candidateLabel','Camps International',
      'institutionalSignals',jsonb_build_array('payroll','employees','recurring operations'),
      'relationshipHint','organization I help operate'
    )
  );

  if coalesce((v_validation->>'readyForConfirmation')::boolean,false) is not true then
    raise exception 'Valid institutional anchor did not become confirmable: %',v_validation;
  end if;

  v_validation := atlas.personal_reality_effect_validation_v1(
    'institutional_anchor',
    '{"institutionalSignals":["payroll"]}'::jsonb
  );

  if coalesce((v_validation->>'readyForConfirmation')::boolean,false) is not false
     or not (v_validation->'issues' ? 'institutional_candidate_label_required') then
    raise exception 'Institutional anchor accepted without candidate label: %',v_validation;
  end if;

  v_validation := atlas.personal_reality_effect_validation_v1(
    'institutional_anchor',
    '{"candidateLabel":"Camps International","institutionalSignals":"payroll"}'::jsonb
  );

  if coalesce((v_validation->>'readyForConfirmation')::boolean,false) is not false
     or not (v_validation->'issues' ? 'institutional_signals_must_be_array') then
    raise exception 'Institutional anchor accepted malformed signals: %',v_validation;
  end if;

  select count(*) into v_before_org from atlas.organizations;
  select count(*) into v_before_composition from atlas.atlas_service_commercial_compositions;
  select count(*) into v_before_items from atlas.atlas_service_commercial_composition_items;
  select count(*) into v_before_cases from atlas.implementation_cases;
  select count(*) into v_before_entitlements from atlas.ledger_entitlements;
  select count(*) into v_before_personal_purchases from atlas.personal_atlas_purchases;
  select count(*) into v_before_implementation_purchases from atlas.implementation_purchases;

  v_result := atlas.propose_personal_reality_effects_internal_v1(
    v_user,
    v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-anchor:camps-international',
      'effectKind','institutional_anchor',
      'proposal',jsonb_build_object(
        'candidateLabel','Camps International',
        'institutionalSignals',jsonb_build_array('payroll'),
        'relationshipHint','organization I help operate'
      ),
      'confidence',1,
      'explanation','The person explicitly identified the captured testimony as institutional.',
      'metadata',jsonb_build_object(
        'productContract','personal_institutional_anchor_v1',
        'explicitSemanticChoice',true
      )
    )),
    'rule',
    'validation:personal_institutional_anchor_v1'
  );

  v_proposal_id := nullif(v_result#>>'{effects,0,id}','')::uuid;

  if v_proposal_id is null then
    raise exception 'Institutional anchor proposal did not return an id: %',v_result;
  end if;

  if not exists (
    select 1
    from atlas.personal_reality_effect_proposals p
    where p.id=v_proposal_id
      and p.capture_id=v_capture
      and p.effect_kind='institutional_anchor'
      and p.readiness_state='ready_for_confirmation'
      and p.decision_state='pending'
      and p.route_state='not_ready'
      and p.proposal->>'candidateLabel'='Camps International'
  ) then
    raise exception 'Institutional anchor proposal state/custody is incorrect.';
  end if;

  v_result := atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,
    v_proposal_id,
    'confirm',
    'validation:confirm-institutional-anchor-v1',
    '{"source":"validation_fixture"}'::jsonb
  );

  v_receipt_id := nullif(v_result->>'receiptId','')::uuid;
  if v_receipt_id is null then
    raise exception 'Institutional anchor confirmation receipt was not issued: %',v_result;
  end if;

  perform set_config('request.jwt.claim.sub',v_user::text,true);

  v_confirmed := atlas.confirm_personal_reality_effect_self_api_v1(
    v_proposal_id,
    v_receipt_id
  );

  if v_confirmed#>>'{proposal,decision_state}' <> 'confirmed'
     or v_confirmed#>>'{proposal,route_state}' <> 'ready' then
    raise exception 'Institutional anchor did not stop at confirmed/ready: %',v_confirmed;
  end if;

  if (select count(*) from atlas.organizations) <> v_before_org
     or (select count(*) from atlas.atlas_service_commercial_compositions) <> v_before_composition
     or (select count(*) from atlas.atlas_service_commercial_composition_items) <> v_before_items
     or (select count(*) from atlas.implementation_cases) <> v_before_cases
     or (select count(*) from atlas.ledger_entitlements) <> v_before_entitlements
     or (select count(*) from atlas.personal_atlas_purchases) <> v_before_personal_purchases
     or (select count(*) from atlas.implementation_purchases) <> v_before_implementation_purchases then
    raise exception 'Institutional anchor proposal/confirmation mutated downstream institutional or commercial truth.';
  end if;

  begin
    perform atlas.apply_personal_reality_effect_self_api_v1(v_proposal_id);
  exception
    when others then
      raise exception 'Generic apply did not fail closed cleanly for institutional anchor: %',sqlerrm;
  end;

  if not exists (
    select 1
    from atlas.personal_reality_effect_proposals p
    where p.id=v_proposal_id
      and p.decision_state='confirmed'
      and p.route_state='destination_unavailable'
      and p.destination_kind is null
      and p.destination_id is null
  ) then
    raise exception 'Generic apply did not preserve institutional anchor as unresolved downstream authority.';
  end if;

  if (select count(*) from atlas.organizations) <> v_before_org
     or (select count(*) from atlas.atlas_service_commercial_compositions) <> v_before_composition
     or (select count(*) from atlas.atlas_service_commercial_composition_items) <> v_before_items
     or (select count(*) from atlas.implementation_cases) <> v_before_cases
     or (select count(*) from atlas.ledger_entitlements) <> v_before_entitlements then
    raise exception 'Fail-closed application created downstream institutional/commercial truth.';
  end if;
end;
$validation$;

rollback;

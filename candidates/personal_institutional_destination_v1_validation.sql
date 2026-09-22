begin;

do $validation$
declare
  v_user uuid := 'f6c10000-0000-4000-8000-000000000001'::uuid;
  v_capture uuid := 'f6c10000-0000-4000-8000-000000000004'::uuid;
  v_anchor_result jsonb;
  v_anchor_id uuid;
  v_anchor_receipt jsonb;
  v_anchor_receipt_id uuid;
  v_destination_result jsonb;
  v_destination_id uuid;
  v_destination_receipt jsonb;
  v_destination_receipt_id uuid;
  v_applied jsonb;
  v_before_org integer;
  v_before_compositions integer;
  v_before_cases integer;
begin
  select count(*) into v_before_org from atlas.organizations;
  select count(*) into v_before_compositions from atlas.atlas_service_commercial_compositions;
  select count(*) into v_before_cases from atlas.implementation_cases;

  v_anchor_result:=atlas.propose_personal_reality_effects_internal_v1(
    v_user,
    v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-anchor:validation',
      'effectKind','institutional_anchor',
      'proposal',jsonb_build_object('candidateLabel','No Existing Fixture Institution'),
      'confidence',1,
      'explanation','Validation anchor.',
      'metadata',jsonb_build_object('validationFixture',true)
    )),
    'rule',
    'validation:personal_institutional_destination_v1'
  );
  v_anchor_id:=nullif(v_anchor_result#>>'{effects,0,id}','')::uuid;

  v_anchor_receipt:=atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,v_anchor_id,'confirm','validation:destination-anchor-confirm',
    '{"source":"validation_fixture"}'::jsonb
  );
  v_anchor_receipt_id:=nullif(v_anchor_receipt->>'receiptId','')::uuid;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform atlas.confirm_personal_reality_effect_self_api_v1(v_anchor_id,v_anchor_receipt_id);

  v_destination_result:=atlas.propose_personal_reality_effects_internal_v1(
    v_user,
    v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-destination:validation',
      'effectKind','institutional_destination',
      'proposal',jsonb_build_object(
        'sourceInstitutionalAnchorProposalId',v_anchor_id,
        'destinationKind','unresolved',
        'destinationLabel','None of these'
      ),
      'confidence',1,
      'explanation','The person explicitly chose to leave the destination unresolved.',
      'metadata',jsonb_build_object('validationFixture',true)
    )),
    'rule',
    'validation:personal_institutional_destination_v1'
  );
  v_destination_id:=nullif(v_destination_result#>>'{effects,0,id}','')::uuid;

  if v_destination_id is null then
    raise exception 'Institutional Destination proposal missing.';
  end if;

  v_destination_receipt:=atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,v_destination_id,'confirm','validation:destination-confirm',
    '{"source":"validation_fixture"}'::jsonb
  );
  v_destination_receipt_id:=nullif(v_destination_receipt->>'receiptId','')::uuid;

  perform atlas.confirm_personal_reality_effect_self_api_v1(
    v_destination_id,v_destination_receipt_id
  );

  v_applied:=atlas.apply_personal_institutional_destination_self_api_v1(v_destination_id);

  if v_applied->>'routeState'<>'applied'
     or v_applied->>'destinationKind'<>'institutional_unresolved'
     or nullif(v_applied->>'destinationId','') is not null then
    raise exception 'Unresolved Institutional Destination was not applied correctly: %',v_applied;
  end if;

  if (select count(*) from atlas.organizations)<>v_before_org
     or (select count(*) from atlas.atlas_service_commercial_compositions)<>v_before_compositions
     or (select count(*) from atlas.implementation_cases)<>v_before_cases then
    raise exception 'Institutional Destination application mutated downstream institutional/commercial truth.';
  end if;

  if not exists(
    select 1
    from atlas.personal_reality_effect_proposals p
    where p.id=v_destination_id
      and p.effect_kind='institutional_destination'
      and p.decision_state='confirmed'
      and p.route_state='applied'
      and p.destination_kind='institutional_unresolved'
  ) then
    raise exception 'Applied Institutional Destination state missing.';
  end if;
end;
$validation$;

rollback;

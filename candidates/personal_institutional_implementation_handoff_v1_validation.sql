begin;

do $validation$
declare
  v_user uuid := 'f6d10000-0000-4000-8000-000000000001'::uuid;
  v_capture uuid := 'f6d10000-0000-4000-8000-000000000004'::uuid;
  v_case uuid := 'f6d10000-0000-4000-8000-000000000011'::uuid;
  v_anchor jsonb; v_anchor_id uuid; v_receipt jsonb; v_receipt_id uuid;
  v_destination jsonb; v_destination_id uuid; v_handoff jsonb; v_entry_id uuid;
  v_before_candidates integer; v_before_org integer; v_before_compositions integer;
begin
  select count(*) into v_before_candidates from atlas.implementation_reality_candidates where implementation_case_id=v_case;
  select count(*) into v_before_org from atlas.organizations;
  select count(*) into v_before_compositions from atlas.atlas_service_commercial_compositions;

  v_anchor:=atlas.propose_personal_reality_effects_internal_v1(
    v_user,v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-anchor:fixture-implementation','effectKind','institutional_anchor',
      'proposal',jsonb_build_object('candidateLabel','Fixture Implementation'),'confidence',1,
      'explanation','Validation anchor.','metadata',jsonb_build_object('validationFixture',true)
    )),
    'rule','validation:personal_institutional_handoff_v1'
  );
  v_anchor_id:=nullif(v_anchor#>>'{effects,0,id}','')::uuid;

  v_receipt:=atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,v_anchor_id,'confirm','validation:handoff-anchor-confirm','{"source":"validation_fixture"}'::jsonb
  );
  v_receipt_id:=nullif(v_receipt->>'receiptId','')::uuid;
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform atlas.confirm_personal_reality_effect_self_api_v1(v_anchor_id,v_receipt_id);

  if not exists(
    select 1
    from jsonb_array_elements(atlas.resolve_personal_institutional_anchor_self_api_v1(v_anchor_id,25)->'implementationCases') item
    where nullif(item->>'implementationCaseId','')::uuid=v_case
  ) then raise exception 'Fixture Implementation Case was not visible through resolver.'; end if;

  v_destination:=atlas.propose_personal_reality_effects_internal_v1(
    v_user,v_capture,
    jsonb_build_array(jsonb_build_object(
      'effectKey','institutional-destination:fixture-implementation','effectKind','institutional_destination',
      'proposal',jsonb_build_object(
        'sourceInstitutionalAnchorProposalId',v_anchor_id,'destinationKind','implementation_case',
        'destinationId',v_case,'destinationLabel','Fixture Implementation'
      ),
      'confidence',1,'explanation','Validation implementation destination.',
      'metadata',jsonb_build_object('validationFixture',true)
    )),
    'rule','validation:personal_institutional_handoff_v1'
  );
  v_destination_id:=nullif(v_destination#>>'{effects,0,id}','')::uuid;

  v_receipt:=atlas.issue_personal_reality_human_decision_receipt_serv_v1(
    v_user,v_destination_id,'confirm','validation:handoff-destination-confirm','{"source":"validation_fixture"}'::jsonb
  );
  v_receipt_id:=nullif(v_receipt->>'receiptId','')::uuid;
  perform atlas.confirm_personal_reality_effect_self_api_v1(v_destination_id,v_receipt_id);
  perform atlas.apply_personal_institutional_destination_self_api_v1(v_destination_id);

  v_handoff:=atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(v_destination_id);
  v_entry_id:=nullif(v_handoff->>'conversationEntryId','')::uuid;
  if v_entry_id is null then raise exception 'Implementation conversation handoff did not return an entry id: %',v_handoff; end if;

  if not exists(
    select 1 from atlas.implementation_conversation_entries e
    where e.id=v_entry_id and e.implementation_case_id=v_case and e.author_user_id=v_user and e.entry_kind='text'
      and e.body='Payroll is Friday.'
      and e.metadata->>'personalRealityCaptureId'=v_capture::text
      and e.metadata->>'institutionalAnchorProposalId'=v_anchor_id::text
      and e.metadata->>'personalInstitutionalDestinationProposalId'=v_destination_id::text
      and coalesce((e.metadata->>'literalTestimonyPreserved')::boolean,false)
      and coalesce((e.metadata->>'implementationRealityCandidateCreated')::boolean,true)=false
  ) then raise exception 'Implementation handoff entry lost testimony or provenance.'; end if;

  v_handoff:=atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(v_destination_id);
  if coalesce((v_handoff->>'created')::boolean,true) is not false
     or nullif(v_handoff->>'conversationEntryId','')::uuid<>v_entry_id then
    raise exception 'Implementation handoff retry was not idempotent: %',v_handoff;
  end if;

  if (select count(*) from atlas.implementation_reality_candidates where implementation_case_id=v_case)<>v_before_candidates then
    raise exception 'Participant testimony handoff created a practitioner Reality Candidate.';
  end if;
  if (select count(*) from atlas.organizations)<>v_before_org
     or (select count(*) from atlas.atlas_service_commercial_compositions)<>v_before_compositions then
    raise exception 'Participant testimony handoff mutated Organization or commercial truth.';
  end if;
end;
$validation$;

rollback;

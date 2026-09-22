begin;

alter table atlas.personal_reality_effect_proposals
  drop constraint if exists personal_reality_effect_proposals_effect_kind_check;

alter table atlas.personal_reality_effect_proposals
  add constraint personal_reality_effect_proposals_effect_kind_check
  check (
    effect_kind in (
      'claim',
      'capacity_block',
      'capacity_adjustment',
      'one_off_action',
      'fact_only',
      'institutional_anchor'
    )
  );

create or replace function atlas.personal_reality_effect_validation_v1(p_kind text,p_body jsonb)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare
  issues jsonb:='[]'::jsonb; tp jsonb; tz text; rk text; a timestamptz; b timestamptz; n numeric;
  has_time boolean:=false; k text:=coalesce(p_kind,''); v text;
begin
  if p_body is null or jsonb_typeof(p_body)<>'object' then
    return jsonb_build_object('readyForConfirmation',false,'issues',jsonb_build_array('proposal_object_required'));
  end if;
  if k='claim' then
    if nullif(btrim(p_body#>>'{subject,domain}'),'') is null then issues:=issues||'"subject_domain_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{subject,kind}'),'') is null then issues:=issues||'"subject_kind_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{subject,id}'),'') is null then issues:=issues||'"subject_identity_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{claim,claimType}'),'') is null then issues:=issues||'"claim_type_required"'::jsonb; end if;
    if nullif(btrim(p_body#>>'{claim,lifecycleState}'),'') is null then issues:=issues||'"claim_lifecycle_required"'::jsonb;
    elsif p_body#>>'{claim,lifecycleState}' not in ('reported','observed','accepted','rejected','unknown') then issues:=issues||'"claim_lifecycle_not_first_party"'::jsonb; end if;
    if not coalesce((p_body->'claim')?'value',false) then issues:=issues||'"claim_value_required"'::jsonb; end if;
    if nullif(p_body#>>'{claim,validFrom}','') is not null then
      has_time:=true; v:=p_body#>>'{claim,validFrom}';
      if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"claim_valid_from_requires_explicit_offset"'::jsonb;
      else begin a:=v::timestamptz; exception when others then issues:=issues||'"claim_valid_from_invalid"'::jsonb; end; end if;
    end if;
    if nullif(p_body#>>'{claim,validUntil}','') is not null then
      has_time:=true; v:=p_body#>>'{claim,validUntil}';
      if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"claim_valid_until_requires_explicit_offset"'::jsonb;
      else begin b:=v::timestamptz; exception when others then issues:=issues||'"claim_valid_until_invalid"'::jsonb; end; end if;
    end if;
    if a is not null and b is not null and b<a then issues:=issues||'"claim_valid_until_precedes_valid_from"'::jsonb; end if;
    if has_time then tp:=p_body->'timingProvenance'; end if;
  elsif k='one_off_action' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"action_title_required"'::jsonb; end if;
    if p_body?'expectedMinutes' then
      if jsonb_typeof(p_body->'expectedMinutes')<>'number' then issues:=issues||'"expected_minutes_invalid"'::jsonb;
      else n:=(p_body->>'expectedMinutes')::numeric; if n<=0 or trunc(n)<>n then issues:=issues||'"expected_minutes_must_be_positive_integer"'::jsonb; end if; end if;
    end if;
    has_time:=nullif(p_body->>'becomesRelevantAt','') is not null or nullif(p_body->>'mustFinishBy','') is not null
      or nullif(p_body->>'preferredWindowStart','') is not null or nullif(p_body->>'preferredWindowEnd','') is not null;
    if (nullif(p_body->>'preferredWindowStart','') is null) <> (nullif(p_body->>'preferredWindowEnd','') is null) then issues:=issues||'"preferred_window_requires_both_boundaries"'::jsonb; end if;
    foreach v in array array[p_body->>'becomesRelevantAt',p_body->>'mustFinishBy',p_body->>'preferredWindowStart',p_body->>'preferredWindowEnd'] loop
      if nullif(btrim(v),'') is not null then
        if not atlas.personal_reality_timestamp_is_explicit_v1(v) then issues:=issues||'"action_time_requires_explicit_offset"'::jsonb;
        else begin perform v::timestamptz; exception when others then issues:=issues||'"action_time_invalid"'::jsonb; end; end if;
      end if;
    end loop;
    begin a:=nullif(p_body->>'becomesRelevantAt','')::timestamptz; exception when others then a:=null; end;
    begin b:=nullif(p_body->>'mustFinishBy','')::timestamptz; exception when others then b:=null; end;
    if a is not null and b is not null and b<a then issues:=issues||'"action_finish_precedes_relevance"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'preferredWindowStart') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'preferredWindowEnd') then
      begin a:=(p_body->>'preferredWindowStart')::timestamptz; b:=(p_body->>'preferredWindowEnd')::timestamptz;
        if b<=a then issues:=issues||'"preferred_window_must_be_positive"'::jsonb; end if; exception when others then null; end;
    end if;
    if has_time then tp:=p_body->'timingProvenance'; end if;
  elsif k='capacity_block' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"capacity_title_required"'::jsonb; end if;
    if nullif(btrim(p_body->>'blockKind'),'') is null then issues:=issues||'"capacity_block_kind_required"'::jsonb;
    elsif p_body->>'blockKind' not in ('human_fixed','household','family','travel','appointment','recovery','other') then issues:=issues||'"capacity_block_kind_not_unavailability"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') then issues:=issues||'"capacity_start_requires_explicit_offset"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then issues:=issues||'"capacity_end_requires_explicit_offset"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then
      begin a:=(p_body->>'startsAt')::timestamptz; b:=(p_body->>'endsAt')::timestamptz; if b<=a then issues:=issues||'"capacity_interval_must_be_positive"'::jsonb; end if;
      exception when others then issues:=issues||'"capacity_interval_invalid"'::jsonb; end;
    end if;
    tp:=p_body->'timingProvenance';
  elsif k='capacity_adjustment' then
    if nullif(btrim(p_body->>'title'),'') is null then issues:=issues||'"capacity_adjustment_title_required"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') then issues:=issues||'"capacity_adjustment_start_requires_explicit_offset"'::jsonb; end if;
    if not atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then issues:=issues||'"capacity_adjustment_end_requires_explicit_offset"'::jsonb; end if;
    if not (p_body?'availabilityFraction') then issues:=issues||'"availability_fraction_required"'::jsonb; end if;
    if p_body?'availabilityFraction' then
      if jsonb_typeof(p_body->'availabilityFraction')<>'number' then issues:=issues||'"availability_fraction_invalid"'::jsonb;
      else n:=(p_body->>'availabilityFraction')::numeric; if n<=0 or n>=1 then issues:=issues||'"availability_fraction_must_be_between_zero_and_one"'::jsonb; end if; end if;
    end if;
    if p_body?'maximumPlannedMinutes' then issues:=issues||'"maximum_planned_minutes_not_allowed_for_capacity_adjustment"'::jsonb; end if;
    if p_body?'discretionaryCapacityMinutes' then issues:=issues||'"discretionary_capacity_minutes_not_allowed_for_capacity_adjustment"'::jsonb; end if;
    if atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'startsAt') and atlas.personal_reality_timestamp_is_explicit_v1(p_body->>'endsAt') then
      begin a:=(p_body->>'startsAt')::timestamptz; b:=(p_body->>'endsAt')::timestamptz; if b<=a then issues:=issues||'"capacity_adjustment_interval_must_be_positive"'::jsonb; end if;
      exception when others then issues:=issues||'"capacity_adjustment_interval_invalid"'::jsonb; end;
    end if;
    tp:=p_body->'timingProvenance';
  elsif k='institutional_anchor' then
    if nullif(btrim(p_body->>'candidateLabel'),'') is null then
      issues:=issues||'"institutional_candidate_label_required"'::jsonb;
    elsif char_length(btrim(p_body->>'candidateLabel'))>240 then
      issues:=issues||'"institutional_candidate_label_too_long"'::jsonb;
    end if;
    if p_body?'institutionalSignals' then
      if jsonb_typeof(p_body->'institutionalSignals')<>'array' then
        issues:=issues||'"institutional_signals_must_be_array"'::jsonb;
      elsif exists (
        select 1 from jsonb_array_elements(p_body->'institutionalSignals') x
        where jsonb_typeof(x)<>'string' or nullif(btrim(x#>>'{}'),'') is null
      ) then
        issues:=issues||'"institutional_signals_must_be_nonblank_strings"'::jsonb;
      end if;
    end if;
    if p_body?'relationshipHint'
       and jsonb_typeof(p_body->'relationshipHint')<>'string' then
      issues:=issues||'"institutional_relationship_hint_must_be_string"'::jsonb;
    end if;
  elsif k<>'fact_only' then issues:=issues||'"unsupported_effect_kind"'::jsonb; end if;

  if tp is not null then
    if jsonb_typeof(tp)<>'object' then issues:=issues||'"timing_provenance_required"'::jsonb;
    else
      if nullif(btrim(tp->>'sourceText'),'') is null then issues:=issues||'"timing_source_text_required"'::jsonb; end if;
      tz:=nullif(btrim(tp->>'timezone'),'');
      if tz is null then issues:=issues||'"timing_timezone_required"'::jsonb;
      elsif not exists(select 1 from pg_catalog.pg_timezone_names where name=tz) then issues:=issues||'"timing_timezone_unknown"'::jsonb; end if;
      rk:=nullif(btrim(tp->>'resolutionKind'),'');
      if rk is null then issues:=issues||'"timing_resolution_kind_required"'::jsonb;
      elsif rk not in ('explicit_absolute','explicit_local','human_clarified','source_context') then issues:=issues||'"timing_resolution_kind_invalid"'::jsonb; end if;
    end if;
  elsif has_time or k in ('capacity_block','capacity_adjustment') then issues:=issues||'"timing_provenance_required"'::jsonb; end if;
  return jsonb_build_object('readyForConfirmation',jsonb_array_length(issues)=0,'issues',issues,
    'truthBoundary',jsonb_build_object('validationDoesNotConfirmTruth',true,'missingIdentityRequiresClarification',true,'relativeTimeIsNotSilentlyNormalized',true,'reducedCapacityIsDistinctFromCapacityBlock',true));
end;$function$;
revoke all on function atlas.personal_reality_effect_validation_v1(text,jsonb) from public,anon,authenticated;

create or replace function atlas.propose_personal_reality_effects_internal_v1(p_owner_user_id uuid,p_capture_id uuid,p_effects jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare
  cap atlas.personal_reality_captures%rowtype; old atlas.personal_reality_effect_proposals%rowtype; superseded atlas.personal_reality_effect_proposals%rowtype; rowv atlas.personal_reality_effect_proposals%rowtype;
  x jsonb; ek text; kind text; body jsonb; conf numeric; expl text; md jsonb; validation jsonb; readiness text; sid uuid; items jsonb:='[]'::jsonb;
begin
  if p_owner_user_id is null or p_capture_id is null or p_effects is null or jsonb_typeof(p_effects)<>'array' then raise exception 'owner, captureId, and effects array are required.' using errcode='22023'; end if;
  if p_interpreter_kind not in ('self_authenticated','ai','rule','import') or nullif(btrim(p_interpreter_ref),'') is null then raise exception 'Valid interpreter provenance is required.' using errcode='22023'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=p_capture_id and c.owner_user_id=p_owner_user_id for update;
  if cap.id is null then raise exception 'Personal reality capture not found.' using errcode='P0002'; end if;
  for x in select value from jsonb_array_elements(p_effects) loop
    if jsonb_typeof(x)<>'object' then raise exception 'Each effect proposal must be an object.' using errcode='22023'; end if;
    ek:=nullif(btrim(x->>'effectKey'),''); kind:=nullif(btrim(x->>'effectKind'),''); body:=x->'proposal'; expl:=nullif(btrim(x->>'explanation'),'');
    conf:=case when x?'confidence' then (x->>'confidence')::numeric else null end; md:=coalesce(case when jsonb_typeof(x->'metadata')='object' then x->'metadata' end,'{}'::jsonb); sid:=nullif(x->>'supersedesProposalId','')::uuid;
    if ek is null or kind is null or jsonb_typeof(body)<>'object' then raise exception 'effectKey, effectKind, and proposal are required.' using errcode='22023'; end if;
    if kind not in ('claim','capacity_block','capacity_adjustment','one_off_action','fact_only','institutional_anchor') then raise exception 'Unsupported effectKind.' using errcode='22023'; end if;
    if conf is not null and (conf<0 or conf>1) then raise exception 'Effect confidence must be between 0 and 1.' using errcode='22023'; end if;
    if sid is not null then
      select * into superseded from atlas.personal_reality_effect_proposals p where p.id=sid and p.owner_user_id=p_owner_user_id and p.principal_id=cap.principal_id;
      if superseded.id is null then raise exception 'supersedesProposalId must identify this Principal own proposal.' using errcode='42501'; end if;
      if superseded.decision_state='revoked' or superseded.route_state='superseded' then raise exception 'Supersede the current proposal, not an obsolete proposal.' using errcode='23505'; end if;
    end if;
    validation:=atlas.personal_reality_effect_validation_v1(kind,body); readiness:=case when coalesce((validation->>'readyForConfirmation')::boolean,false) then 'ready_for_confirmation' else 'needs_clarification' end;
    select * into old from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.effect_key=ek;
    if old.id is not null then
      if old.effect_kind is distinct from kind or old.proposal is distinct from body or old.interpreter_kind is distinct from p_interpreter_kind
        or old.interpreter_ref is distinct from p_interpreter_ref or old.confidence is distinct from conf or old.explanation is distinct from expl
        or old.readiness_state is distinct from readiness or old.validation is distinct from validation or old.supersedes_proposal_id is distinct from sid or old.metadata is distinct from md then
        raise exception 'effectKey retry does not match existing effect proposal.' using errcode='23505'; end if;
      items:=items||jsonb_build_array(to_jsonb(old)); continue;
    end if;
    insert into atlas.personal_reality_effect_proposals(capture_id,principal_id,owner_user_id,effect_key,effect_kind,proposal,interpreter_kind,interpreter_ref,confidence,explanation,readiness_state,validation,supersedes_proposal_id,metadata)
    values(cap.id,cap.principal_id,p_owner_user_id,ek,kind,body,p_interpreter_kind,p_interpreter_ref,conf,expl,readiness,validation,sid,md)
    on conflict(capture_id,effect_key) do nothing returning * into rowv;
    if rowv.id is null then
      select * into old from atlas.personal_reality_effect_proposals p where p.capture_id=cap.id and p.effect_key=ek;
      if old.id is null or old.effect_kind is distinct from kind or old.proposal is distinct from body or old.interpreter_kind is distinct from p_interpreter_kind or old.interpreter_ref is distinct from p_interpreter_ref
        or old.confidence is distinct from conf or old.explanation is distinct from expl or old.readiness_state is distinct from readiness or old.validation is distinct from validation or old.supersedes_proposal_id is distinct from sid or old.metadata is distinct from md then
        raise exception 'effectKey retry does not match concurrently created effect proposal.' using errcode='23505'; end if;
      items:=items||jsonb_build_array(to_jsonb(old)); continue;
    end if;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,event_kind,state_axis,from_state,to_state,detail)
    values(rowv.id,cap.id,cap.principal_id,case when p_interpreter_kind='self_authenticated' then p_owner_user_id else null end,'proposed','proposal',null,'proposed',jsonb_build_object('interpreterKind',p_interpreter_kind,'interpreterRef',p_interpreter_ref,'effectKind',kind,'readinessState',readiness));
    items:=items||jsonb_build_array(to_jsonb(rowv));
  end loop;
  perform atlas.refresh_personal_reality_capture_state_v1(cap.id);
  return jsonb_build_object('ok',true,'contractVersion','personal_reality_effect_proposal_v1','captureId',cap.id,'evidenceId',cap.evidence_id,'effects',items,
    'truthBoundary',jsonb_build_object('proposalIsNotTruth',true,'interpreterKindComesFromTrustedRouteNotPayload',true,'selfAuthenticatedDoesNotMeanHumanConfirmed',true,'needsClarificationCannotBeConfirmed',true));
end;$function$;
revoke all on function atlas.propose_personal_reality_effects_internal_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;

create or replace function atlas.apply_personal_reality_effect_self_api_v1(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  u uuid:=auth.uid(); q atlas.personal_reality_effect_proposals%rowtype; oldq atlas.personal_reality_effect_proposals%rowtype; cap atlas.personal_reality_captures%rowtype; body jsonb; result jsonb;
  dk text; did text; rb text; fn regprocedure; tfn regprocedure; fs text; fnm text; ts text; tnm text; source_key text; old_claim atlas.claim_records%rowtype;
  same_subject boolean:=false; old_reversed boolean:=false; old_dec text; old_route text; cs text;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into q from atlas.personal_reality_effect_proposals p where p.id=p_proposal_id and p.owner_user_id=u for update;
  if q.id is null then raise exception 'Effect proposal not found.' using errcode='P0002'; end if;
  select * into cap from atlas.personal_reality_captures c where c.id=q.capture_id and c.owner_user_id=u;
  if q.route_state='applied' then return jsonb_build_object('ok',true,'changed',false,'routeState','applied','destinationKind',q.destination_kind,'destinationId',q.destination_id,'destinationState',atlas.personal_reality_destination_state_v1(q.destination_kind,q.destination_id)); end if;
  if q.decision_state<>'confirmed' or q.decision_receipt_id is null then raise exception 'Human confirmation receipt required before application.' using errcode='42501'; end if;
  if q.readiness_state<>'ready_for_confirmation' or q.route_state not in ('ready','destination_unavailable') then raise exception 'Proposal is not ready for application.' using errcode='22023'; end if;
  rb:=q.route_state; body:=q.proposal; source_key:='personal_reality_proposal:'||q.id::text;
  if q.supersedes_proposal_id is not null then
    select * into oldq from atlas.personal_reality_effect_proposals p where p.id=q.supersedes_proposal_id and p.owner_user_id=u and p.principal_id=q.principal_id for update;
    if oldq.id is null or oldq.decision_state='revoked' or oldq.route_state='superseded' then raise exception 'Superseded proposal is unavailable or obsolete.' using errcode='23505'; end if;
    old_dec:=oldq.decision_state; old_route:=oldq.route_state;
  end if;
  if q.effect_kind='one_off_action' then fn:=to_regprocedure('atlas.capture_personal_one_off_action_self_api_v1(jsonb)');
  elsif q.effect_kind='capacity_block' then fn:=to_regprocedure('atlas.record_principal_capacity_block_self_api_v1(jsonb)');
  elsif q.effect_kind='capacity_adjustment' then fn:=to_regprocedure('atlas.record_principal_capacity_adjustment_self_api_v1(jsonb)'); end if;
  if q.effect_kind in ('one_off_action','capacity_block','capacity_adjustment','institutional_anchor') and fn is null then
    update atlas.personal_reality_effect_proposals set route_state='destination_unavailable',updated_at=now() where id=q.id returning * into q;
    if rb<>'destination_unavailable' then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
      values(q.id,cap.id,cap.principal_id,u,q.decision_receipt_id,'destination_unavailable','route',rb,'destination_unavailable',jsonb_build_object('effectKind',q.effect_kind)); end if;
    cs:=atlas.refresh_personal_reality_capture_state_v1(cap.id);
    return jsonb_build_object('ok',true,'changed',(rb<>'destination_unavailable'),'routeState','destination_unavailable','effectKind',q.effect_kind,'captureState',cs);
  end if;
  if q.effect_kind='fact_only' then dk:='evidence_record'; did:=cap.evidence_id::text; result:=jsonb_build_object('ok',true,'evidenceId',cap.evidence_id);
  elsif q.effect_kind='claim' then
    if oldq.id is not null and oldq.route_state='applied' and oldq.effect_kind='claim' then
      select * into old_claim from atlas.claim_records c where c.id=oldq.destination_id::uuid and c.scope_kind='person' and c.scope_id=u;
      if old_claim.id is null then raise exception 'Prior Claim destination missing.' using errcode='P0002'; end if;
      same_subject:=old_claim.subject_domain=body#>>'{subject,domain}' and old_claim.subject_kind=body#>>'{subject,kind}' and old_claim.subject_id=body#>>'{subject,id}';
    end if;
    result:=atlas.record_person_claim_from_capture_evidence_v1(jsonb_build_object('sourceEvidenceId',cap.evidence_id,'proposalId',q.id,'decisionReceiptId',q.decision_receipt_id,'subject',body->'subject','claim',body->'claim','supersedesClaimId',case when same_subject then old_claim.id else null end));
    dk:='claim_record'; did:=result->>'claimId'; if same_subject then old_reversed:=true; end if;
  else
    body:=(body-'sourceKey'-'sourceEvidenceId'-'sourceClaimId'-'testimony'-'floorClass'-'protectionLevel'-'interruptibility'-'reasonForFloor'-'consequence'-'blocksCapacity'-'maximumPlannedMinutes'-'discretionaryCapacityMinutes')
      ||jsonb_build_object('sourceKey',source_key,'sourceEvidenceId',cap.evidence_id,
        'metadata',coalesce(case when jsonb_typeof(body->'metadata')='object' then body->'metadata' end,'{}'::jsonb)||jsonb_build_object('personalRealityProposalId',q.id,'decisionReceiptId',q.decision_receipt_id,'timingProvenance',body->'timingProvenance'));
    if q.effect_kind='one_off_action' then body:=body||jsonb_build_object('testimony',cap.testimony); end if;
    select n.nspname,p.proname into fs,fnm from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.oid=fn::oid;
    execute format('select %I.%I($1)',fs,fnm) into result using body;
    if q.effect_kind='one_off_action' then dk:='principal_one_off_action'; did:=result#>>'{action,id}';
    elsif q.effect_kind='capacity_block' then dk:='principal_capacity_block'; did:=result#>>'{capacityBlock,id}';
    else dk:='principal_capacity_adjustment'; did:=result#>>'{capacityAdjustment,id}'; end if;
    if did is null then raise exception 'Destination did not return an id.' using errcode='55000'; end if;
  end if;
  if oldq.id is not null and oldq.route_state='applied' and not old_reversed then
    if oldq.effect_kind='claim' then
      select * into old_claim from atlas.claim_records c where c.id=oldq.destination_id::uuid and c.scope_kind='person' and c.scope_id=u;
      if old_claim.id is null then raise exception 'Prior Claim destination missing.' using errcode='P0002'; end if;
      update atlas.claim_records set lifecycle_state='superseded',superseded_at=now() where id=old_claim.id and lifecycle_state<>'superseded';
      if not found then raise exception 'Prior Claim already superseded.' using errcode='23505'; end if;
      insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata) values(old_claim.id,cap.evidence_id,'corrects',jsonb_build_object('correctionProposalId',q.id)) on conflict(claim_id,evidence_id,relation_kind) do nothing; old_reversed:=true;
    elsif oldq.effect_kind='one_off_action' then tfn:=to_regprocedure('atlas.transition_personal_one_off_action_self_api_v1(uuid,text)');
    elsif oldq.effect_kind='capacity_block' then tfn:=to_regprocedure('atlas.transition_principal_capacity_block_self_api_v1(uuid,text,text)');
    elsif oldq.effect_kind='capacity_adjustment' then tfn:=to_regprocedure('atlas.transition_principal_capacity_adjustment_self_api_v1(uuid,text,text)'); end if;
    if oldq.effect_kind in ('one_off_action','capacity_block','capacity_adjustment') then
      if tfn is null then raise exception 'Correction transition writer unavailable.' using errcode='55000'; end if;
      select n.nspname,p.proname into ts,tnm from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.oid=tfn::oid;
      if oldq.effect_kind='one_off_action' then execute format('select %I.%I($1,$2)',ts,tnm) into result using oldq.destination_id::uuid,'cancel';
      else execute format('select %I.%I($1,$2,$3)',ts,tnm) into result using oldq.destination_id::uuid,'cancel','Superseded by corrected personal reality interpretation.'; end if; old_reversed:=true;
    end if;
  end if;
  update atlas.personal_reality_effect_proposals set route_state='applied',applied_at=coalesce(applied_at,now()),destination_kind=dk,destination_id=did,updated_at=now() where id=q.id returning * into q;
  insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
  values(q.id,cap.id,cap.principal_id,u,q.decision_receipt_id,'applied','route',rb,'applied',jsonb_build_object('destinationKind',dk,'destinationId',did,'sourceEvidenceId',cap.evidence_id));
  if oldq.id is not null then
    update atlas.personal_reality_effect_proposals set decision_state='revoked',route_state=case when route_state='applied' then 'superseded' else 'not_ready' end,revoked_at=now(),updated_at=now() where id=oldq.id returning * into oldq;
    insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
    values(oldq.id,oldq.capture_id,oldq.principal_id,u,q.decision_receipt_id,'superseded','decision',old_dec,'revoked',jsonb_build_object('supersededByProposalId',q.id,'oldDestinationReversed',old_reversed));
    if old_route is distinct from oldq.route_state then insert into atlas.personal_reality_effect_events(proposal_id,capture_id,principal_id,actor_user_id,authority_receipt_id,event_kind,state_axis,from_state,to_state,detail)
      values(oldq.id,oldq.capture_id,oldq.principal_id,u,q.decision_receipt_id,'superseded','route',old_route,oldq.route_state,jsonb_build_object('supersededByProposalId',q.id)); end if;
    perform atlas.refresh_personal_reality_capture_state_v1(oldq.capture_id);
  end if;
  cs:=atlas.refresh_personal_reality_capture_state_v1(cap.id);
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','personal_reality_effect_application_v1','proposalId',q.id,'decisionState',q.decision_state,'routeState',q.route_state,
    'effectKind',q.effect_kind,'destinationKind',dk,'destinationId',did,'destinationState',atlas.personal_reality_destination_state_v1(dk,did),'evidenceId',cap.evidence_id,'captureState',cs,
    'truthBoundary',jsonb_build_object('applicationAuthorityComesFromHumanDecisionReceiptNotCaller',true,'destinationCallsAreLateBoundAndFailClosed',true,'sourceKeyUsesProposalUuid',true,'correctionIsTransactional',true));
end;$function$;

commit;

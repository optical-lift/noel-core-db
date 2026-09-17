begin;

-- Package 7 Communications convergence Stage 3.
--
-- Receipt is Communication evidence, not a response obligation. Common
-- Communication Conversation remains visible independently of Response Case.
-- Only an accepted, unambiguous `actionable` assessment may admit/touch an
-- Institutional Response Case. Unknown remains unknown.

-- Preserve append-only revision lineage. Current production already carries
-- this column; IF NOT EXISTS keeps the migration replay-safe for older clones.
alter table atlas.communication_actionability_assessments
  add column if not exists supersedes_assessment_id uuid;

do $ddl$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='atlas.communication_actionability_assessments'::regclass
      and conname='communication_actionability_asses_supersedes_assessment_id_fkey'
  ) then
    alter table atlas.communication_actionability_assessments
      add constraint communication_actionability_asses_supersedes_assessment_id_fkey
      foreign key (supersedes_assessment_id)
      references atlas.communication_actionability_assessments(id)
      on delete restrict;
  end if;
end;
$ddl$;

-- Older source declared one accepted row per Event while also declaring the
-- table append-only. Revisions are now explicit successor rows instead.
drop index if exists atlas.communication_actionability_one_current_accepted_uq;
create index if not exists communication_actionability_supersedes_idx
  on atlas.communication_actionability_assessments(supersedes_assessment_id)
  where supersedes_assessment_id is not null;

comment on column atlas.communication_actionability_assessments.supersedes_assessment_id is
'Append-only accepted-actionability revision edge. A later accepted assessment supersedes the prior accepted leaf without mutating historical evidence.';

create or replace function atlas.guard_communication_actionability_supersession_v2()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_prior atlas.communication_actionability_assessments%rowtype;
begin
  if new.supersedes_assessment_id is null then
    return new;
  end if;

  select * into v_prior
  from atlas.communication_actionability_assessments
  where id=new.supersedes_assessment_id;

  if v_prior.id is null then
    raise exception 'Superseded actionability assessment does not exist.' using errcode='23503';
  end if;
  if v_prior.communication_event_id is distinct from new.communication_event_id then
    raise exception 'Actionability revision must remain on the same Communication Event.' using errcode='23514';
  end if;
  if v_prior.assessment_authority<>'accepted' or new.assessment_authority<>'accepted' then
    raise exception 'Only an accepted actionability assessment may supersede an accepted assessment.' using errcode='23514';
  end if;
  if exists (
    select 1
    from atlas.communication_actionability_assessments successor
    where successor.supersedes_assessment_id=v_prior.id
      and successor.assessment_authority='accepted'
  ) then
    raise exception 'Accepted actionability assessment already has a successor.' using errcode='23505';
  end if;

  return new;
end;
$function$;

drop trigger if exists communication_actionability_supersession_v2
  on atlas.communication_actionability_assessments;
create trigger communication_actionability_supersession_v2
before insert on atlas.communication_actionability_assessments
for each row execute function atlas.guard_communication_actionability_supersession_v2();

-- Resolve the current accepted leaf. Zero accepted leaves is lawful unknown;
-- multiple accepted leaves are ambiguous and therefore also fail closed to
-- unknown rather than choosing by timestamp.
create or replace function atlas.communication_event_actionability_packet_v2(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_count int;
  v_current atlas.communication_actionability_assessments%rowtype;
begin
  select count(*)
  into v_count
  from atlas.communication_actionability_assessments a
  where a.communication_event_id=p_communication_event_id
    and a.assessment_authority='accepted'
    and not exists (
      select 1
      from atlas.communication_actionability_assessments successor
      where successor.supersedes_assessment_id=a.id
        and successor.assessment_authority='accepted'
    );

  if v_count=0 then
    return jsonb_build_object(
      'contractVersion','communication_actionability_packet_v2',
      'communicationEventId',p_communication_event_id,
      'classification','unknown',
      'authority','none',
      'assessmentId',null,
      'ambiguous',false
    );
  end if;

  if v_count<>1 then
    return jsonb_build_object(
      'contractVersion','communication_actionability_packet_v2',
      'communicationEventId',p_communication_event_id,
      'classification','unknown',
      'authority','ambiguous',
      'assessmentId',null,
      'ambiguous',true,
      'acceptedLeafCount',v_count
    );
  end if;

  select a.* into v_current
  from atlas.communication_actionability_assessments a
  where a.communication_event_id=p_communication_event_id
    and a.assessment_authority='accepted'
    and not exists (
      select 1
      from atlas.communication_actionability_assessments successor
      where successor.supersedes_assessment_id=a.id
        and successor.assessment_authority='accepted'
    )
  limit 1;

  return jsonb_build_object(
    'contractVersion','communication_actionability_packet_v2',
    'communicationEventId',p_communication_event_id,
    'classification',v_current.classification,
    'authority','accepted',
    'assessmentId',v_current.id,
    'supersedesAssessmentId',v_current.supersedes_assessment_id,
    'assessedByUserId',v_current.assessed_by_user_id,
    'basis',v_current.basis,
    'acceptedAt',v_current.created_at,
    'ambiguous',false
  );
end;
$function$;

-- Keep the established scalar helper name, but make its semantics explicitly
-- revision-aware and ambiguity-safe.
create or replace function atlas.communication_event_actionability_v1(
  p_communication_event_id uuid
)
returns text
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select atlas.communication_event_actionability_packet_v2($1)->>'classification';
$function$;

-- Pure structural policy. This is intentionally narrow: it may establish only
-- exact provider-neutral interaction forms (plus the already-documented legacy
-- comment/reaction thread prefixes). It never infers actionability from sender,
-- subject, body, email address, or channel kind.
create or replace function atlas.communication_structural_actionability_from_evidence_v1(
  p_direction text,
  p_interaction_kind text,
  p_thread_ref text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path=pg_catalog
as $function$
declare
  v_direction text:=lower(btrim(coalesce(p_direction,'')));
  v_kind text:=lower(btrim(coalesce(p_interaction_kind,'')));
  v_thread text:=lower(btrim(coalesce(p_thread_ref,'')));
begin
  if v_direction<>'incoming' then
    return jsonb_build_object(
      'contractVersion','communication_structural_actionability_v1',
      'classification','unknown',
      'acceptanceWarranted',false,
      'reason','not_incoming'
    );
  end if;

  if v_kind in ('public_comment','reaction')
     or v_thread like 'comment:%'
     or v_thread like 'reaction:%' then
    return jsonb_build_object(
      'contractVersion','communication_structural_actionability_v1',
      'classification','informational',
      'acceptanceWarranted',true,
      'reason',case when v_kind<>'' then v_kind else 'legacy_public_interaction_thread' end
    );
  end if;

  if v_kind in ('system_notice','broadcast') then
    return jsonb_build_object(
      'contractVersion','communication_structural_actionability_v1',
      'classification','automated',
      'acceptanceWarranted',true,
      'reason',v_kind
    );
  end if;

  return jsonb_build_object(
    'contractVersion','communication_structural_actionability_v1',
    'classification','unknown',
    'acceptanceWarranted',false,
    'reason',case when v_kind<>'' then 'unadjudicated_interaction_kind' else 'insufficient_structural_evidence' end
  );
end;
$function$;

create or replace function atlas.communication_structural_actionability_policy_v1(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_kind text;
  v_thread_ref text;
  v_policy jsonb;
begin
  select * into v_event
  from atlas.communication_events
  where id=p_communication_event_id;

  if v_event.id is null then
    return jsonb_build_object(
      'contractVersion','communication_structural_actionability_v1',
      'communicationEventId',p_communication_event_id,
      'classification','unknown',
      'acceptanceWarranted',false,
      'reason','event_not_found'
    );
  end if;

  v_kind:=coalesce(
    nullif(v_event.canonical_event#>>'{source,interactionKind}',''),
    nullif(v_event.canonical_event#>>'{sourcePayload,interactionKind}',''),
    ''
  );
  v_thread_ref:=coalesce(
    nullif(v_event.canonical_event#>>'{source,threadRef}',''),
    nullif(v_event.canonical_event#>>'{sourcePayload,threadRef}',''),
    ''
  );

  v_policy:=atlas.communication_structural_actionability_from_evidence_v1(
    v_event.direction,v_kind,v_thread_ref
  );

  return v_policy || jsonb_build_object(
    'communicationEventId',v_event.id,
    'observedInteractionKind',nullif(v_kind,''),
    'observedThreadRef',nullif(v_thread_ref,'')
  );
end;
$function$;

-- Append one accepted adjudication. Accepted history is never updated/deleted;
-- revisions point to the prior accepted leaf. A caller-provided stable
-- adjudicationKey makes replay idempotent.
create or replace function atlas.accept_communication_actionability_service_v1(
  p_communication_event_id uuid,
  p_classification text,
  p_basis jsonb,
  p_assessed_by_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_classification text:=lower(btrim(coalesce(p_classification,'')));
  v_basis jsonb:=coalesce(p_basis,'{}'::jsonb);
  v_key text;
  v_existing atlas.communication_actionability_assessments%rowtype;
  v_current atlas.communication_actionability_assessments%rowtype;
  v_current_count int;
  v_inserted atlas.communication_actionability_assessments%rowtype;
begin
  if v_classification not in ('unknown','actionable','informational','automated','junk') then
    raise exception 'Unsupported communication actionability classification.' using errcode='22023';
  end if;
  if jsonb_typeof(v_basis)<>'object' then
    raise exception 'Actionability basis must be an object.' using errcode='22023';
  end if;

  v_key:=btrim(coalesce(v_basis->>'adjudicationKey',''));
  if v_key='' then
    raise exception 'Accepted actionability requires a stable adjudicationKey.' using errcode='22023';
  end if;

  select * into v_event
  from atlas.communication_events
  where id=p_communication_event_id
  for update;
  if v_event.id is null then
    raise exception 'Communication Event not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.communication_actionability_assessments a
  where a.communication_event_id=v_event.id
    and a.assessment_authority='accepted'
    and a.basis->>'adjudicationKey'=v_key
  order by a.created_at,a.id
  limit 1;

  if v_existing.id is not null then
    if v_existing.classification is distinct from v_classification then
      raise exception 'Actionability adjudication key conflicts with an existing accepted classification.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'contractVersion','communication_actionability_adjudication_v1',
      'state','accepted',
      'idempotent',true,
      'communicationEventId',v_event.id,
      'assessmentId',v_existing.id,
      'classification',v_existing.classification,
      'supersedesAssessmentId',v_existing.supersedes_assessment_id
    );
  end if;

  select count(*)
  into v_current_count
  from atlas.communication_actionability_assessments a
  where a.communication_event_id=v_event.id
    and a.assessment_authority='accepted'
    and not exists (
      select 1
      from atlas.communication_actionability_assessments successor
      where successor.supersedes_assessment_id=a.id
        and successor.assessment_authority='accepted'
    );

  if v_current_count>1 then
    raise exception 'Communication Event has ambiguous accepted actionability history.' using errcode='23514';
  end if;

  if v_current_count=1 then
    select a.* into v_current
    from atlas.communication_actionability_assessments a
    where a.communication_event_id=v_event.id
      and a.assessment_authority='accepted'
      and not exists (
        select 1
        from atlas.communication_actionability_assessments successor
        where successor.supersedes_assessment_id=a.id
          and successor.assessment_authority='accepted'
      )
    limit 1;
  end if;

  insert into atlas.communication_actionability_assessments(
    communication_event_id,classification,assessment_authority,
    assessed_by_user_id,basis,supersedes_assessment_id
  ) values(
    v_event.id,v_classification,'accepted',p_assessed_by_user_id,
    v_basis,v_current.id
  )
  returning * into v_inserted;

  return jsonb_build_object(
    'contractVersion','communication_actionability_adjudication_v1',
    'state','accepted',
    'idempotent',false,
    'communicationEventId',v_event.id,
    'assessmentId',v_inserted.id,
    'classification',v_inserted.classification,
    'supersedesAssessmentId',v_inserted.supersedes_assessment_id
  );
end;
$function$;

-- Auto-accept only the narrow structural classes above. Unknown creates no row.
create or replace function atlas.ensure_structural_communication_actionability_service_v1(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_policy jsonb;
  v_result jsonb;
  v_basis jsonb;
begin
  v_policy:=atlas.communication_structural_actionability_policy_v1(p_communication_event_id);

  if coalesce((v_policy->>'acceptanceWarranted')::boolean,false)=false then
    return jsonb_build_object(
      'contractVersion','communication_actionability_structural_acceptance_v1',
      'state','unadjudicated',
      'communicationEventId',p_communication_event_id,
      'classification','unknown',
      'policy',v_policy
    );
  end if;

  v_basis:=jsonb_build_object(
    'adjudicationKey','structural-actionability-v1:'||p_communication_event_id::text,
    'authorityKind','deterministic_structural_policy',
    'policy',v_policy
  );

  v_result:=atlas.accept_communication_actionability_service_v1(
    p_communication_event_id,
    v_policy->>'classification',
    v_basis,
    null
  );

  return v_result || jsonb_build_object(
    'contractVersion','communication_actionability_structural_acceptance_v1',
    'policy',v_policy
  );
end;
$function$;

create or replace function atlas.communication_actionability_allows_response_v1(
  p_classification text
)
returns boolean
language sql
immutable
security definer
set search_path=pg_catalog
as $function$
  select lower(btrim(coalesce($1,'')))='actionable';
$function$;

-- Response Case is now a consequence of accepted actionability. Historical
-- response events remain authoritative history: replaying an already-recorded
-- event returns that history before applying the new gate.
create or replace function atlas.ensure_institutional_response_case_for_event_service_v1(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_msg atlas.institutional_conversation_messages%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_prior atlas.institutional_conversation_response_events%rowtype;
  v_actionability jsonb;
  v_classification text;
  v_common_conversation_id uuid;
  v_num int;
  v_from text;
begin
  select * into v_event
  from atlas.communication_events
  where id=p_communication_event_id;
  select * into v_msg
  from atlas.institutional_conversation_messages
  where communication_event_id=p_communication_event_id;

  if v_event.id is null or v_msg.id is null then
    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','not_admitted',
      'communicationEventId',p_communication_event_id
    );
  end if;
  if v_event.direction<>'incoming' then
    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','no_inbound_obligation_inferred',
      'communicationEventId',v_event.id,
      'institutionalConversationId',v_msg.institutional_conversation_id
    );
  end if;
  if not exists(
    select 1
    from atlas.communication_event_participants p
    where p.communication_event_id=v_event.id
      and not p.is_self
  ) then
    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','no_external_participant',
      'communicationEventId',v_event.id
    );
  end if;

  select communication_conversation_id
  into v_common_conversation_id
  from atlas.institutional_conversation_roots
  where institutional_conversation_id=v_msg.institutional_conversation_id;

  if v_common_conversation_id is null then
    raise exception 'Institutional Conversation lacks common Communication Conversation root.' using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.communication_conversation_events cce
    where cce.communication_conversation_id=v_common_conversation_id
      and cce.communication_event_id=v_event.id
  ) then
    raise exception 'Response admission Event is not a member of the common Communication Conversation.' using errcode='23514';
  end if;

  -- Historical consequence remains history even if no accepted actionability
  -- assessment existed at the time it was created.
  select * into v_prior
  from atlas.institutional_conversation_response_events
  where related_communication_event_id=v_event.id
    and event_kind in ('opened','inbound_received')
  order by created_at,id
  limit 1;

  if v_prior.id is not null then
    select * into v_case
    from atlas.institutional_conversation_response_cases
    where id=v_prior.response_case_id;

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','already_recorded',
      'historicalConsequencePreserved',true,
      'communicationEventId',v_event.id,
      'communicationConversationId',v_common_conversation_id,
      'responseCaseId',v_prior.response_case_id,
      'institutionalConversationId',v_msg.institutional_conversation_id,
      'caseState',v_case.case_state
    );
  end if;

  v_actionability:=atlas.communication_event_actionability_packet_v2(v_event.id);
  v_classification:=coalesce(v_actionability->>'classification','unknown');

  if not atlas.communication_actionability_allows_response_v1(v_classification) then
    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state',case v_classification
        when 'informational' then 'informational_no_response_case'
        when 'automated' then 'automated_no_response_case'
        when 'junk' then 'junk_no_response_case'
        else 'awaiting_actionability'
      end,
      'communicationEventId',v_event.id,
      'communicationConversationId',v_common_conversation_id,
      'institutionalConversationId',v_msg.institutional_conversation_id,
      'actionability',v_actionability,
      'responsibilityInferred',false,
      'communicationEvidenceRetained',true
    );
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_msg.institutional_conversation_id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1
  for update;

  if v_case.id is null then
    select coalesce(max(case_number),0)+1 into v_num
    from atlas.institutional_conversation_response_cases
    where institutional_conversation_id=v_msg.institutional_conversation_id;

    insert into atlas.institutional_conversation_response_cases(
      institutional_conversation_id,organization_id,organization_unit_id,
      case_number,case_state,opened_by_communication_event_id,opened_at,metadata
    ) values(
      v_msg.institutional_conversation_id,v_event.organization_id,v_event.organization_unit_id,
      v_num,'unclaimed',v_event.id,coalesce(v_event.occurred_at,v_event.captured_at),
      jsonb_build_object(
        'openingRule','accepted_communication_actionability',
        'communicationConversationId',v_common_conversation_id,
        'actionability',v_actionability
      )
    ) returning * into v_case;

    insert into atlas.institutional_conversation_response_events(
      response_case_id,institutional_conversation_id,event_kind,from_state,to_state,
      related_communication_event_id,metadata,occurred_at
    ) values(
      v_case.id,v_case.institutional_conversation_id,'opened',null,'unclaimed',
      v_event.id,
      jsonb_build_object(
        'communicationDoesNotEqualResponsibility',true,
        'communicationConversationId',v_common_conversation_id,
        'actionability',v_actionability
      ),
      coalesce(v_event.occurred_at,v_event.captured_at)
    );

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','opened_unclaimed',
      'communicationEventId',v_event.id,
      'communicationConversationId',v_common_conversation_id,
      'responseCaseId',v_case.id,
      'institutionalConversationId',v_case.institutional_conversation_id,
      'actionability',v_actionability,
      'responsibilityInferred',false
    );
  end if;

  v_from:=v_case.case_state;
  if v_case.case_state='waiting_external' then
    update atlas.institutional_conversation_response_cases
    set case_state='needs_response',updated_at=now()
    where id=v_case.id
    returning * into v_case;

    insert into atlas.institutional_conversation_response_events(
      response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,
      related_communication_event_id,metadata,occurred_at
    ) values(
      v_case.id,v_case.institutional_conversation_id,'inbound_received',v_from,'needs_response',
      (select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),
      v_event.id,
      jsonb_build_object('communicationConversationId',v_common_conversation_id,'actionability',v_actionability),
      coalesce(v_event.occurred_at,v_event.captured_at)
    );

    return jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','returned_to_needs_response',
      'communicationEventId',v_event.id,
      'communicationConversationId',v_common_conversation_id,
      'responseCaseId',v_case.id,
      'actionability',v_actionability
    );
  end if;

  insert into atlas.institutional_conversation_response_events(
    response_case_id,institutional_conversation_id,event_kind,from_state,to_state,work_item_id,
    related_communication_event_id,metadata,occurred_at
  ) values(
    v_case.id,v_case.institutional_conversation_id,'inbound_received',v_case.case_state,v_case.case_state,
    (select work_item_id from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id),
    v_event.id,
    jsonb_build_object('communicationConversationId',v_common_conversation_id,'actionability',v_actionability),
    coalesce(v_event.occurred_at,v_event.captured_at)
  );

  return jsonb_build_object(
    'contractVersion','institutional_response_case_admission_v2',
    'state','inbound_recorded',
    'communicationEventId',v_event.id,
    'communicationConversationId',v_common_conversation_id,
    'responseCaseId',v_case.id,
    'caseState',v_case.case_state,
    'actionability',v_actionability
  );
end;
$function$;

-- Explicit adjudication command. It records one accepted decision and only then
-- asks the governed response consequence membrane to act on it. Non-actionable
-- revisions never retroactively close/delete historical cases.
create or replace function atlas.adjudicate_communication_actionability_service_v1(
  p_communication_event_id uuid,
  p_classification text,
  p_basis jsonb,
  p_assessed_by_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_assessment jsonb;
  v_consequence jsonb;
begin
  v_assessment:=atlas.accept_communication_actionability_service_v1(
    p_communication_event_id,p_classification,p_basis,p_assessed_by_user_id
  );

  if lower(btrim(coalesce(p_classification,'')))='actionable' then
    v_consequence:=atlas.ensure_institutional_response_case_for_event_service_v1(
      p_communication_event_id
    );
  else
    v_consequence:=jsonb_build_object(
      'contractVersion','institutional_response_case_admission_v2',
      'state','not_requested_for_non_actionable_classification',
      'classification',lower(btrim(coalesce(p_classification,'')))
    );
  end if;

  return jsonb_build_object(
    'contractVersion','communication_actionability_adjudication_with_consequence_v1',
    'assessment',v_assessment,
    'responseConsequence',v_consequence
  );
end;
$function$;

-- The institutional ingest path now establishes narrow structural actionability
-- before asking whether a response consequence exists. Unknown stays visible in
-- common Correspondence with no Response Case.
create or replace function atlas.ingest_organization_communication_events_service_v3(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_receipt jsonb;
  v_batch_id uuid;
  v_event_id uuid;
  v_actionability jsonb;
  v_result jsonb;
  v_cases int:=0;
  v_structural_acceptances int:=0;
  v_awaiting_actionability int:=0;
  v_non_actionable int:=0;
begin
  v_receipt:=atlas.ingest_organization_communication_events_service_v2(
    p_connected_source_id,p_events,p_manifest
  );
  v_batch_id:=(v_receipt->>'batchId')::uuid;

  for v_event_id in
    select id
    from atlas.communication_events
    where ingest_batch_id=v_batch_id
    order by created_at,id
  loop
    v_actionability:=atlas.ensure_structural_communication_actionability_service_v1(v_event_id);
    if v_actionability->>'state'='accepted' then
      v_structural_acceptances:=v_structural_acceptances+1;
    end if;

    v_result:=atlas.ensure_institutional_response_case_for_event_service_v1(v_event_id);
    if v_result->>'state' in ('opened_unclaimed','returned_to_needs_response','inbound_recorded') then
      v_cases:=v_cases+1;
    elsif v_result->>'state'='awaiting_actionability' then
      v_awaiting_actionability:=v_awaiting_actionability+1;
    elsif v_result->>'state' in ('informational_no_response_case','automated_no_response_case','junk_no_response_case') then
      v_non_actionable:=v_non_actionable+1;
    end if;
  end loop;

  return v_receipt || jsonb_build_object(
    'responseCasesTouched',v_cases,
    'structuralActionabilityAccepted',v_structural_acceptances,
    'awaitingActionability',v_awaiting_actionability,
    'nonActionableWithoutResponseCase',v_non_actionable,
    'actionabilityContractVersion','communication_actionability_adjudication_v1',
    'contractVersion','organization_communication_ingest_receipt_v3'
  );
end;
$function$;

-- Canonical read v2 exposes actionability as its own evidence dimension rather
-- than deriving it from Response Case presence/state.
create or replace function atlas.organization_correspondence_list_self_api_v2(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.organization_correspondence_list_self_api_v1(
    p_organization_id,p_communication_endpoint_id,p_limit
  );

  select coalesce(jsonb_agg(
    case
      when nullif(item#>>'{latestEvent,communicationEventId}','') is null then item
      else jsonb_set(
        item,
        '{latestEvent,actionability}',
        atlas.communication_event_actionability_packet_v2(
          (item#>>'{latestEvent,communicationEventId}')::uuid
        ),
        true
      )
    end
    order by (item->>'lastActivityAt')::timestamptz desc,item->>'communicationConversationId'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item;

  return (v_base-'items') || jsonb_build_object(
    'contractVersion','organization_correspondence_list_v2',
    'items',v_items
  );
end;
$function$;

create or replace function atlas.organization_correspondence_conversation_self_api_v2(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_events jsonb;
begin
  v_base:=atlas.organization_correspondence_conversation_self_api_v1(
    p_communication_conversation_id
  );

  select coalesce(jsonb_agg(
    event || jsonb_build_object(
      'actionability',atlas.communication_event_actionability_packet_v2(
        (event->>'communicationEventId')::uuid
      )
    )
    order by coalesce((event->>'occurredAt')::timestamptz,(event->>'capturedAt')::timestamptz),event->>'communicationEventId'
  ),'[]'::jsonb)
  into v_events
  from jsonb_array_elements(coalesce(v_base->'events','[]'::jsonb)) event;

  return (v_base-'events') || jsonb_build_object(
    'contractVersion','organization_correspondence_conversation_v2',
    'events',v_events
  );
end;
$function$;

-- Internal helpers and consequence writers remain service-only.
revoke all on function atlas.guard_communication_actionability_supersession_v2() from public,anon,authenticated;
revoke all on function atlas.communication_event_actionability_packet_v2(uuid) from public,anon,authenticated;
revoke all on function atlas.communication_event_actionability_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.communication_structural_actionability_from_evidence_v1(text,text,text) from public,anon,authenticated;
revoke all on function atlas.communication_structural_actionability_policy_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.accept_communication_actionability_service_v1(uuid,text,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.ensure_structural_communication_actionability_service_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.communication_actionability_allows_response_v1(text) from public,anon,authenticated;
revoke all on function atlas.ensure_institutional_response_case_for_event_service_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb) from public,anon,authenticated;

grant execute on function atlas.communication_event_actionability_packet_v2(uuid) to service_role;
grant execute on function atlas.communication_event_actionability_v1(uuid) to service_role;
grant execute on function atlas.communication_structural_actionability_from_evidence_v1(text,text,text) to service_role;
grant execute on function atlas.communication_structural_actionability_policy_v1(uuid) to service_role;
grant execute on function atlas.accept_communication_actionability_service_v1(uuid,text,jsonb,uuid) to service_role;
grant execute on function atlas.ensure_structural_communication_actionability_service_v1(uuid) to service_role;
grant execute on function atlas.communication_actionability_allows_response_v1(text) to service_role;
grant execute on function atlas.ensure_institutional_response_case_for_event_service_v1(uuid) to service_role;
grant execute on function atlas.adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid) to service_role;
grant execute on function atlas.ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb) to service_role;

-- Canonical self-read v2 stays browser-readable through the governed membrane;
-- the actionability table/helpers themselves remain closed.
revoke all on function atlas.organization_correspondence_list_self_api_v2(uuid,uuid,integer) from public,anon;
revoke all on function atlas.organization_correspondence_conversation_self_api_v2(uuid) from public,anon;
grant execute on function atlas.organization_correspondence_list_self_api_v2(uuid,uuid,integer) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_conversation_self_api_v2(uuid) to authenticated,service_role;

comment on function atlas.communication_event_actionability_packet_v2(uuid) is
'Resolves one append-only accepted actionability leaf for a Communication Event. Zero or ambiguous accepted leaves resolve to unknown; no Response Case state is consulted.';
comment on function atlas.accept_communication_actionability_service_v1(uuid,text,jsonb,uuid) is
'Appends one accepted actionability adjudication with explicit supersession and replay key. Does not itself assert responsibility.';
comment on function atlas.ensure_structural_communication_actionability_service_v1(uuid) is
'Auto-accepts only exact public/reaction/system/broadcast structural evidence. Sender/subject/body/channel heuristics are forbidden; insufficient evidence remains unknown.';
comment on function atlas.ensure_institutional_response_case_for_event_service_v1(uuid) is
'Stage 3 response consequence membrane. Historical response consequences are preserved; new/touched Response Cases require accepted actionable Communication Event evidence rooted in common Conversation.';
comment on function atlas.organization_correspondence_list_self_api_v2(uuid,uuid,integer) is
'Common Conversation Correspondence list with actionability exposed independently from optional Institutional Response Case consequence.';
comment on function atlas.organization_correspondence_conversation_self_api_v2(uuid) is
'Common Conversation detail with per-Event actionability packets independent from Response Case/Work consequence state.';

commit;

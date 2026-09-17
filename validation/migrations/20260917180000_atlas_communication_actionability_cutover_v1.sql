-- Validation for Package 7 Communications convergence Stage 3.
-- Run after Stage 1 + Stage 2 + Stage 3 in disposable / production-schema-clone validation.

begin;

-- Required Stage 3 contracts exist.
do $validation$
declare
  v_missing text[]:=array[]::text[];
  v_name text;
begin
  foreach v_name in array array[
    'communication_event_actionability_packet_v2(uuid)',
    'communication_event_actionability_v1(uuid)',
    'communication_structural_actionability_from_evidence_v1(text,text,text)',
    'communication_structural_actionability_policy_v1(uuid)',
    'accept_communication_actionability_service_v1(uuid,text,jsonb,uuid)',
    'ensure_structural_communication_actionability_service_v1(uuid)',
    'communication_actionability_allows_response_v1(text)',
    'ensure_institutional_response_case_for_event_service_v1(uuid)',
    'adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid)',
    'ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb)',
    'organization_correspondence_list_self_api_v2(uuid,uuid,integer)',
    'organization_correspondence_conversation_self_api_v2(uuid)'
  ] loop
    if to_regprocedure('atlas.'||v_name) is null then
      v_missing:=array_append(v_missing,v_name);
    end if;
  end loop;

  if cardinality(v_missing)>0 then
    raise exception 'Stage 3 required functions are missing: %',array_to_string(v_missing,', ');
  end if;
end;
$validation$;

-- The append-only revision seam must exist without the contradictory one-current
-- accepted unique index.
do $validation$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='communication_actionability_assessments'
      and column_name='supersedes_assessment_id'
  ) then
    raise exception 'Actionability supersession lineage column is missing.';
  end if;

  if to_regclass('atlas.communication_actionability_one_current_accepted_uq') is not null then
    raise exception 'Legacy one-accepted-row index conflicts with append-only actionability revision.';
  end if;

  if to_regclass('atlas.communication_actionability_supersedes_idx') is null then
    raise exception 'Actionability supersession lookup index is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid='atlas.communication_actionability_assessments'::regclass
      and t.tgname='communication_actionability_append_only_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Actionability append-only guard was lost.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid='atlas.communication_actionability_assessments'::regclass
      and t.tgname='communication_actionability_supersession_v2'
      and not t.tgisinternal
  ) then
    raise exception 'Actionability supersession guard is missing.';
  end if;
end;
$validation$;

-- Exact structural evidence may establish only bounded non-actionable classes.
-- Channel, sender, subject, and body are intentionally absent from this pure policy.
do $validation$
declare
  v_result jsonb;
begin
  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','public_comment','');
  if v_result->>'classification'<>'informational'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not true then
    raise exception 'public_comment is not deterministically informational.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','reaction','');
  if v_result->>'classification'<>'informational'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not true then
    raise exception 'reaction is not deterministically informational.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','system_notice','');
  if v_result->>'classification'<>'automated'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not true then
    raise exception 'system_notice is not deterministically automated.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','broadcast','');
  if v_result->>'classification'<>'automated'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not true then
    raise exception 'broadcast is not deterministically automated.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','','comment:legacy-1');
  if v_result->>'classification'<>'informational'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not true then
    raise exception 'Legacy comment thread evidence is not bounded informational.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','email','rfc-root:test');
  if v_result->>'classification'<>'unknown'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not false then
    raise exception 'Unknown/direct email evidence was incorrectly promoted to accepted actionability.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('incoming','','rfc-root:test');
  if v_result->>'classification'<>'unknown'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not false then
    raise exception 'Insufficient structural evidence no longer remains unknown.';
  end if;

  v_result:=atlas.communication_structural_actionability_from_evidence_v1('outgoing','public_comment','comment:test');
  if v_result->>'classification'<>'unknown'
     or coalesce((v_result->>'acceptanceWarranted')::boolean,false) is not false then
    raise exception 'Outgoing evidence was incorrectly treated as inbound actionability.';
  end if;
end;
$validation$;

-- Only actionable can cross the Response Case admission membrane.
do $validation$
begin
  if atlas.communication_actionability_allows_response_v1('actionable') is not true then
    raise exception 'Accepted actionable classification does not admit response consequence.';
  end if;

  if atlas.communication_actionability_allows_response_v1('unknown')
     or atlas.communication_actionability_allows_response_v1('informational')
     or atlas.communication_actionability_allows_response_v1('automated')
     or atlas.communication_actionability_allows_response_v1('junk')
     or atlas.communication_actionability_allows_response_v1(null) then
    raise exception 'A non-actionable/unknown classification can admit a response consequence.';
  end if;
end;
$validation$;

-- Effective actionability is independent from Response Case state and fails
-- closed on zero/ambiguous accepted leaves.
do $validation$
declare
  v_definition text;
begin
  select lower(pg_get_functiondef('atlas.communication_event_actionability_packet_v2(uuid)'::regprocedure))
  into v_definition;

  if position('communication_actionability_assessments' in v_definition)=0
     or position('supersedes_assessment_id' in v_definition)=0 then
    raise exception 'Effective actionability is not resolved from append-only assessment lineage.';
  end if;

  if position('institutional_conversation_response_cases' in v_definition)>0
     or position('institutional_conversation_response_events' in v_definition)>0 then
    raise exception 'Response consequence state is incorrectly defining actionability.';
  end if;

  if position('acceptedleafcount' in v_definition)=0
     or strpos(v_definition,$needle$'classification','unknown'$needle$)=0 then
    raise exception 'Actionability ambiguity does not visibly fail closed to unknown.';
  end if;
end;
$validation$;

-- Accepted adjudications must be append-only, replay-keyed, and linked to the
-- prior accepted leaf rather than mutating it.
do $validation$
declare
  v_definition text;
begin
  select lower(pg_get_functiondef('atlas.accept_communication_actionability_service_v1(uuid,text,jsonb,uuid)'::regprocedure))
  into v_definition;

  if position('adjudicationkey' in v_definition)=0
     or position('supersedes_assessment_id' in v_definition)=0
     or position('for update' in v_definition)=0 then
    raise exception 'Accepted actionability writer lacks replay/serialization/supersession custody.';
  end if;

  if v_definition ~ E'\\m(update|delete)\\M[[:space:]]+atlas\\.communication_actionability_assessments' then
    raise exception 'Accepted actionability writer mutates append-only assessment history.';
  end if;
end;
$validation$;

-- The response consequence must resolve the common Conversation/event membership,
-- preserve already-recorded history, then apply accepted actionability before any
-- new case open/touch logic.
do $validation$
declare
  v_definition text;
  v_history_pos int;
  v_gate_pos int;
begin
  select lower(pg_get_functiondef('atlas.ensure_institutional_response_case_for_event_service_v1(uuid)'::regprocedure))
  into v_definition;

  if position('institutional_conversation_roots' in v_definition)=0
     or position('communication_conversation_events' in v_definition)=0 then
    raise exception 'Response admission no longer proves common Conversation membership.';
  end if;
  if position('communication_event_actionability_packet_v2' in v_definition)=0
     or position('communication_actionability_allows_response_v1' in v_definition)=0 then
    raise exception 'Response admission bypasses accepted actionability.';
  end if;
  if position('awaiting_actionability' in v_definition)=0
     or position('informational_no_response_case' in v_definition)=0
     or position('automated_no_response_case' in v_definition)=0
     or position('junk_no_response_case' in v_definition)=0 then
    raise exception 'Response admission does not preserve visible non-case states.';
  end if;

  v_history_pos:=position('historicalconsequencepreserved' in v_definition);
  v_gate_pos:=position('communication_event_actionability_packet_v2' in v_definition);
  if v_history_pos=0 or v_gate_pos=0 or v_history_pos>v_gate_pos then
    raise exception 'Historical response consequence is not preserved before the new actionability gate.';
  end if;
end;
$validation$;

-- Ingest establishes only bounded structural assessments before response-case
-- admission. It must not classify from sender/subject/body heuristics.
do $validation$
declare
  v_ingest text;
  v_policy text;
  v_structural_pos int;
  v_response_pos int;
begin
  select lower(pg_get_functiondef('atlas.ingest_organization_communication_events_service_v3(uuid,jsonb,jsonb)'::regprocedure))
  into v_ingest;
  select lower(pg_get_functiondef('atlas.communication_structural_actionability_from_evidence_v1(text,text,text)'::regprocedure))
  into v_policy;

  v_structural_pos:=position('ensure_structural_communication_actionability_service_v1' in v_ingest);
  v_response_pos:=position('ensure_institutional_response_case_for_event_service_v1' in v_ingest);
  if v_structural_pos=0 or v_response_pos=0 or v_structural_pos>v_response_pos then
    raise exception 'Organization ingest does not establish structural actionability before response consequence.';
  end if;

  if position('speaker_address' in v_policy)>0
     or position('subject' in v_policy)>0
     or position('body' in v_policy)>0
     or position('endpoint_kind' in v_policy)>0 then
    raise exception 'Structural actionability policy contains forbidden content/channel heuristics.';
  end if;
end;
$validation$;

-- Common Correspondence v2 exposes actionability independently from optional
-- Response Case compatibility data.
do $validation$
declare
  v_list text;
  v_detail text;
begin
  select lower(pg_get_functiondef('atlas.organization_correspondence_list_self_api_v2(uuid,uuid,integer)'::regprocedure))
  into v_list;
  select lower(pg_get_functiondef('atlas.organization_correspondence_conversation_self_api_v2(uuid)'::regprocedure))
  into v_detail;

  if position('organization_correspondence_list_self_api_v1' in v_list)=0
     or position('communication_event_actionability_packet_v2' in v_list)=0 then
    raise exception 'Correspondence list v2 is not common-read + independent actionability.';
  end if;
  if position('organization_correspondence_conversation_self_api_v1' in v_detail)=0
     or position('communication_event_actionability_packet_v2' in v_detail)=0 then
    raise exception 'Correspondence detail v2 is not common-read + per-event actionability.';
  end if;
end;
$validation$;

-- Stage 1 root/event continuity must still hold before this consequence cutover.
do $validation$
begin
  if exists(
    select 1
    from atlas.institutional_conversations ic
    left join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ic.id
    where root.institutional_conversation_id is null
  ) then
    raise exception 'Stage 3 cannot operate while an Institutional Conversation lacks a common root.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversation_messages message
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=message.institutional_conversation_id
    left join atlas.communication_conversation_events event_link
      on event_link.communication_event_id=message.communication_event_id
     and event_link.communication_conversation_id=root.communication_conversation_id
    where event_link.communication_event_id is null
  ) then
    raise exception 'Stage 3 response consequence could reference an Event outside its common Conversation.';
  end if;
end;
$validation$;

-- Browser can read the governed actionability-decorated common projection, but
-- cannot write/read raw actionability authority or invoke service consequence APIs.
do $validation$
begin
  if has_table_privilege('authenticated','atlas.communication_actionability_assessments','SELECT')
     or has_table_privilege('authenticated','atlas.communication_actionability_assessments','INSERT')
     or has_table_privilege('authenticated','atlas.communication_actionability_assessments','UPDATE')
     or has_table_privilege('authenticated','atlas.communication_actionability_assessments','DELETE') then
    raise exception 'Authenticated browser can bypass actionability custody table.';
  end if;

  if has_function_privilege('authenticated','atlas.accept_communication_actionability_service_v1(uuid,text,jsonb,uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.ensure_structural_communication_actionability_service_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.ensure_institutional_response_case_for_event_service_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid)','EXECUTE') then
    raise exception 'Authenticated browser can invoke Stage 3 internal authority directly.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_correspondence_list_self_api_v2(uuid,uuid,integer)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_conversation_self_api_v2(uuid)','EXECUTE') then
    raise exception 'Authenticated browser lacks governed common Correspondence v2 read.';
  end if;
end;
$validation$;

rollback;

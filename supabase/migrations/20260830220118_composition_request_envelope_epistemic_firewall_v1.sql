create table if not exists atlas.composition_request_envelopes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  mode text not null default 'shadow' check (mode='shadow'),
  source_domain text not null,
  source_ref text,
  literal_request text not null,
  request_mode text not null,
  envelope_payload jsonb not null,
  validation_state text not null check (validation_state in ('passed','rejected')),
  violations jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  interpreter_kind text not null,
  interpreter_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table atlas.composition_request_envelopes enable row level security;
revoke all on atlas.composition_request_envelopes from public,anon,authenticated;

create or replace function atlas.validate_composition_request_envelope_v1(p_envelope jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v_literal text;
  v_mode text;
  v_fact jsonb;
  v_inf jsonb;
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_key text;
  v_status text;
  v_evidence text;
  v_basis text;
  v_prohibited text[]:=array[
    'exhausted','bored','distressed','overwhelmed','incapable','incapacity','poor_parenting','bad_parenting',
    'child_misbehavior','children_misbehaving','needs_education','needs_outdoors','needs_entertainment','needs_rejoicing',
    'canon_function','canon_priority','moral_failure'
  ];
begin
  if p_envelope is null or not (p_envelope ?& array['literal_request','request_mode','fact_items','inferred_items']) then
    raise exception 'request envelope requires literal_request, request_mode, fact_items, inferred_items';
  end if;
  v_literal:=p_envelope->>'literal_request'; v_mode:=p_envelope->>'request_mode';
  if jsonb_typeof(p_envelope->'fact_items')<>'array' or jsonb_typeof(p_envelope->'inferred_items')<>'array' then
    raise exception 'fact_items and inferred_items must be arrays';
  end if;

  for v_fact in select value from jsonb_array_elements(p_envelope->'fact_items') loop
    v_key:=v_fact->>'key'; v_status:=v_fact->>'epistemic_status'; v_evidence:=v_fact->'source_evidence'->>'text';
    if v_key is null or v_status not in ('explicit','externally_observed') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_fact_item','fact',v_fact)); continue;
    end if;
    if v_status='explicit' then
      if v_fact->'source_evidence'->>'kind'<>'literal_span' or coalesce(v_evidence,'')='' or strpos(lower(v_literal),lower(v_evidence))=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','explicit_fact_without_literal_evidence','fact_key',v_key,'evidence_text',v_evidence));
      end if;
    else
      if coalesce(v_fact->'source_evidence'->>'ref','')='' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','external_fact_without_source_ref','fact_key',v_key));
      end if;
    end if;
  end loop;

  for v_inf in select value from jsonb_array_elements(p_envelope->'inferred_items') loop
    v_key:=v_inf->>'key'; v_basis:=v_inf->>'basis';
    if v_key is null or v_inf->>'epistemic_status'<>'derived' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_inferred_item','item',v_inf)); continue;
    end if;
    if v_key=any(v_prohibited) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','prohibited_hidden_inference','inference_key',v_key,'message','request interpretation may not invent psychological, parenting, medium, or canon conclusions'));
    end if;
    if v_key='delegated_composition' then
      if v_mode<>'open_composition' or v_inf->>'value'<>'true' or v_basis<>'open_ended_planning_request' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_delegated_composition_inference','item',v_inf));
      end if;
    elsif coalesce(v_basis,'')='' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','derived_item_without_basis','inference_key',v_key));
    end if;
  end loop;

  if v_mode='open_composition' and not exists(
    select 1 from jsonb_array_elements(p_envelope->'inferred_items') i
    where i->>'key'='delegated_composition' and i->>'value'='true' and i->>'basis'='open_ended_planning_request'
  ) then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('key','open_composition_without_delegation_marker','message','request may be parsed, but bounded-discretion composition cannot activate until delegated_composition is explicitly derived from request form'));
  end if;

  return jsonb_build_object(
    'validation_state',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'violations',v_violations,'warnings',v_warnings,
    'normalized',jsonb_build_object(
      'literal_request',v_literal,'request_mode',v_mode,
      'fact_items',p_envelope->'fact_items','inferred_items',p_envelope->'inferred_items',
      'parser_contract','explicit facts require literal/source custody; derived request-form authority is separate from hidden condition'
    )
  );
end;
$$;

create or replace function atlas.submit_composition_request_envelope_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_ref text,
  p_interpreter_kind text,
  p_interpreter_version text,
  p_envelope jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare v_result jsonb; v_id uuid;
begin
  v_result:=atlas.validate_composition_request_envelope_v1(p_envelope);
  insert into atlas.composition_request_envelopes(
    organization_id,source_domain,source_ref,literal_request,request_mode,envelope_payload,
    validation_state,violations,warnings,interpreter_kind,interpreter_version
  ) values(
    p_organization_id,p_source_domain,p_source_ref,p_envelope->>'literal_request',p_envelope->>'request_mode',p_envelope,
    v_result->>'validation_state',coalesce(v_result->'violations','[]'::jsonb),coalesce(v_result->'warnings','[]'::jsonb),p_interpreter_kind,p_interpreter_version
  ) returning id into v_id;
  return jsonb_build_object('request_envelope_id',v_id,'validation',v_result);
end;
$$;

revoke all on function atlas.validate_composition_request_envelope_v1(jsonb) from public,anon,authenticated;
revoke all on function atlas.submit_composition_request_envelope_v1(uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.validate_composition_request_envelope_v1(jsonb) to postgres;
grant execute on function atlas.submit_composition_request_envelope_v1(uuid,text,text,text,text,jsonb) to postgres;
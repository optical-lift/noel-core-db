create table if not exists atlas.composition_neutral_policies (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null default 'global',
  organization_id uuid references atlas.organizations(id) on delete cascade,
  policy_key text not null,
  version integer not null,
  status text not null check (status in ('shadow','retired')),
  source_domain text not null default 'shared',
  policy_contract jsonb not null,
  no_canon_authority boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(scope_key,policy_key,version)
);
alter table atlas.composition_neutral_policies enable row level security;
revoke all on atlas.composition_neutral_policies from public,anon,authenticated;

insert into atlas.composition_neutral_policies(scope_key,organization_id,policy_key,version,status,source_domain,policy_contract,no_canon_authority)
values ('global',null,'shared_tie_set_coherence_v1',1,'shadow','shared',jsonb_build_object(
  'purpose','choose a practical presentation/execution ordering only after Noel has preserved a tie or absence of canon precedence',
  'must_respect',jsonb_build_array('active claims','hard timing','dependencies','readiness','capacity','blockers','source-authored order hints when genuinely comparable'),
  'may_choose',jsonb_build_array('one ordering among remaining materially equal orderings'),
  'must_label',jsonb_build_array('not_unique_canon_order=true','ordering_authority=neutral_composition_policy'),
  'prohibited',jsonb_build_array('inventing canon priority','dropping protected claims','overriding hard timing or dependency','presenting convenience as moral superiority')
),true)
on conflict (scope_key,policy_key,version) do update set policy_contract=excluded.policy_contract,status=excluded.status,no_canon_authority=true,updated_at=now();

create or replace function atlas.get_worker_day_composition_signals_v4(
  p_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v jsonb;
  v_ambiguities jsonb;
begin
  v:=atlas.get_worker_day_composition_signals_v3(p_membership_id,p_service_date);
  select coalesce(jsonb_agg(
    case when x->>'key'='missing_independent_sequence_authority' then
      x || jsonb_build_object(
        'blocking',false,
        'resolution_class','neutral_tie_set',
        'neutral_policy_key','shared_tie_set_coherence_v1',
        'effect','Noel preserves lack of precedence; a neutral composer may choose one practical order without canon authority.'
      )
    else x end
  ),'[]'::jsonb) into v_ambiguities
  from jsonb_array_elements(coalesce(v->'ambiguities','[]'::jsonb)) x;
  return jsonb_set(v,'{ambiguities}',v_ambiguities,true) || jsonb_build_object(
    'signal_adapter_version','atlas_worker_day_composition_signals_v4',
    'neutral_order_policy_eligible',true
  );
end;
$$;

create or replace function atlas.validate_shadow_composition_proposal_v2(
  p_derivation_id uuid,
  p_proposal jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v_base jsonb;
  v_der record;
  v_ambiguity jsonb;
  v_policy_key text;
  v_policy_count integer;
  v_extra_violations jsonb := '[]'::jsonb;
begin
  select * into v_der from atlas.composition_derivation_runs where id=p_derivation_id;
  if not found then raise exception 'derivation not found'; end if;

  for v_ambiguity in select value from jsonb_array_elements(coalesce(v_der.domain_signals->'ambiguities','[]'::jsonb)) loop
    if coalesce((v_ambiguity->>'blocking')::boolean,true)=false and v_ambiguity->>'resolution_class'='neutral_tie_set' then
      v_policy_key:=coalesce(p_proposal->>'neutral_policy_key',v_ambiguity->>'neutral_policy_key');
      if p_proposal->>'ordering_authority'<>'neutral_composition_policy'
         or coalesce((p_proposal->>'not_unique_canon_order')::boolean,false) is not true then
        v_extra_violations:=v_extra_violations||jsonb_build_array(jsonb_build_object(
          'key','neutral_tie_order_not_labeled','ambiguity_key',v_ambiguity->>'key',
          'message','a practical order through a Noel tie-set must be labeled neutral and non-unique canonically'
        ));
      end if;
      select count(*) into v_policy_count from atlas.composition_neutral_policies
      where policy_key=v_policy_key and version=1 and status='shadow' and no_canon_authority=true
        and (scope_key='global' or organization_id=v_der.organization_id);
      if v_policy_count=0 then
        v_extra_violations:=v_extra_violations||jsonb_build_array(jsonb_build_object('key','neutral_policy_not_found','policy_key',v_policy_key));
      end if;
    end if;
  end loop;

  v_base:=atlas.validate_shadow_composition_proposal_v1(p_derivation_id,p_proposal);
  if jsonb_array_length(v_extra_violations)>0 then
    return jsonb_set(jsonb_set(v_base,'{violations}',coalesce(v_base->'violations','[]'::jsonb)||v_extra_violations,true),'{validation_state}','"rejected"'::jsonb,true);
  end if;
  return v_base;
end;
$$;

create or replace function atlas.submit_shadow_composition_proposal_v2(
  p_derivation_id uuid,
  p_proposal_key text,
  p_generator_kind text,
  p_generator_version text,
  p_proposal jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare v_result jsonb; v_id uuid;
begin
  v_result:=atlas.validate_shadow_composition_proposal_v2(p_derivation_id,p_proposal);
  insert into atlas.composition_proposals(derivation_id,proposal_key,generator_kind,generator_version,proposal_payload,validation_state,violations,warnings,metadata)
  values(p_derivation_id,p_proposal_key,p_generator_kind,p_generator_version,p_proposal,v_result->>'validation_state',coalesce(v_result->'violations','[]'::jsonb),coalesce(v_result->'warnings','[]'::jsonb),jsonb_build_object('validator','atlas.validate_shadow_composition_proposal_v2','validator_version',2))
  on conflict(derivation_id,proposal_key) do update set generator_kind=excluded.generator_kind,generator_version=excluded.generator_version,proposal_payload=excluded.proposal_payload,validation_state=excluded.validation_state,violations=excluded.violations,warnings=excluded.warnings,metadata=excluded.metadata,updated_at=now()
  returning id into v_id;
  return jsonb_build_object('proposal_id',v_id,'validation',v_result);
end;
$$;

revoke all on function atlas.get_worker_day_composition_signals_v4(uuid,date) from public,anon,authenticated;
revoke all on function atlas.validate_shadow_composition_proposal_v2(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.submit_shadow_composition_proposal_v2(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.get_worker_day_composition_signals_v4(uuid,date) to postgres;
grant execute on function atlas.validate_shadow_composition_proposal_v2(uuid,jsonb) to postgres;
grant execute on function atlas.submit_shadow_composition_proposal_v2(uuid,text,text,text,jsonb) to postgres;
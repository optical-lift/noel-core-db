-- Keep the first Reality responsibility slice self-carried by the verified setup
-- sponsor all the way through the UI contract. Entity options remain case-scoped.

create or replace function atlas.implementation_reality_scope_options_self_api_v1(
  p_implementation_case_id uuid,
  p_kind text,
  p_query text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality','ledger'
as $function$
declare
  v_query text:=lower(btrim(coalesce(p_query,'')));
  v_limit integer:=least(greatest(coalesce(p_limit,20),1),50);
  v_items jsonb:='[]'::jsonb;
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(p_implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;
  if p_kind not in ('entity','person') then
    raise exception 'Reality scope option kind must be entity or person.' using errcode='22023';
  end if;

  if p_kind='entity' then
    with allowed as (
      select e.id,e.entity_kind,e.display_name,e.stable_key,'case_ledger_subject'::text as match_basis
      from atlas.ledger_entitlement_bindings b
      join ledger.ledgers l on l.id=b.ledger_id and l.ledger_state='active'
      join reality.entities e on e.id=l.subject_entity_id and e.identity_state='canonical'
      where b.implementation_case_id=p_implementation_case_id
        and b.state in ('bound','activated')
        and b.ended_at is null
      union
      select e.id,e.entity_kind,e.display_name,e.stable_key,'case_promoted_reality_entity'::text as match_basis
      from atlas.implementation_reality_candidates c
      join reality.entities e
        on c.canonical_consequence_kind='reality_entity'
       and c.canonical_consequence_ref=e.id::text
       and e.identity_state='canonical'
      where c.implementation_case_id=p_implementation_case_id
        and c.candidate_state='promoted'
    ), ranked as (
      select distinct on (id)
        id,entity_kind,display_name,stable_key,match_basis,
        case
          when v_query<>'' and lower(display_name)=v_query then 0
          when v_query<>'' and strpos(lower(display_name),v_query)=1 then 1
          when v_query<>'' and strpos(lower(stable_key),v_query)=1 then 2
          else 3
        end as match_rank
      from allowed
      where v_query='' or strpos(lower(display_name),v_query)>0 or strpos(lower(stable_key),v_query)>0
      order by id,case match_basis when 'case_ledger_subject' then 0 else 1 end
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','reality_entity','canonicalId',id,'label',display_name,
      'entityKind',entity_kind,'stableKey',stable_key,'matchBasis',match_basis
    ) order by match_rank,display_name,id),'[]'::jsonb)
    into v_items
    from (select * from ranked order by match_rank,display_name,id limit v_limit) items;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','person','canonicalId',id,'label',display_name,
      'entityKind','person','stableKey',stable_key,'matchBasis','verified_case_setup_sponsor'
    ) order by match_rank,display_name,id),'[]'::jsonb)
    into v_items
    from (
      select distinct e.id,e.display_name,e.stable_key,
        case
          when v_query<>'' and lower(e.display_name)=v_query then 0
          when v_query<>'' and strpos(lower(e.display_name),v_query)=1 then 1
          when v_query<>'' and strpos(lower(e.stable_key),v_query)=1 then 2
          else 3
        end as match_rank
      from atlas.implementation_case_participants participant
      join reality.auth_person_bindings binding
        on binding.auth_user_id=participant.human_user_id
       and binding.binding_state='active'
       and binding.retired_at is null
      join reality.entities e
        on e.id=binding.person_entity_id
       and e.entity_kind='person'
       and e.identity_state='canonical'
      where participant.implementation_case_id=p_implementation_case_id
        and participant.relationship_kind='setup_sponsor'
        and participant.active
        and participant.ended_at is null
        and participant.verified_at is not null
        and (v_query='' or strpos(lower(e.display_name),v_query)>0 or strpos(lower(e.stable_key),v_query)>0)
      order by match_rank,e.display_name,e.id
      limit v_limit
    ) people;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_scope_options_v1',
    'implementationCaseId',p_implementation_case_id,
    'kind',p_kind,
    'query',coalesce(p_query,''),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'caseScopedOnly',true,
      'globalRealityDirectoryExposed',false,
      'personOptionsLimitedToVerifiedSetupSponsor',p_kind='person'
    )
  );
end;
$function$;

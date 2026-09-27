-- Nonprofit contribution identity hardening v1.
-- Core fundraising facts are immutable after establishment. State, metadata, and establishment
-- basis may advance; changing who/what/when/value requires an explicit future correction path.

create or replace function atlas.guard_fundraising_financial_fact_immutability_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_old_core jsonb;
  v_new_core jsonb;
begin
  if tg_table_name='fundraising_contributions' then
    v_old_core:=to_jsonb(old)-array['record_state','establishment_basis','metadata','updated_at'];
    v_new_core:=to_jsonb(new)-array['record_state','establishment_basis','metadata','updated_at'];
  elsif tg_table_name='fundraising_pledges' then
    v_old_core:=to_jsonb(old)-array['pledge_state','establishment_basis','metadata','updated_at'];
    v_new_core:=to_jsonb(new)-array['pledge_state','establishment_basis','metadata','updated_at'];
  elsif tg_table_name='fundraising_grant_awards' then
    v_old_core:=to_jsonb(old)-array['award_state','establishment_basis','metadata','updated_at'];
    v_new_core:=to_jsonb(new)-array['award_state','establishment_basis','metadata','updated_at'];
  else
    raise exception 'Unsupported fundraising financial fact table.' using errcode='55000';
  end if;

  if v_new_core is distinct from v_old_core then
    raise exception 'Established fundraising financial facts are immutable; use an explicit correction/void path.' using errcode='55000';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_fundraising_financial_fact_immutability_v1()
  from public,anon,authenticated;

drop trigger if exists fundraising_contributions_immutability_guard_v1 on atlas.fundraising_contributions;
create trigger fundraising_contributions_immutability_guard_v1
before update on atlas.fundraising_contributions
for each row execute function atlas.guard_fundraising_financial_fact_immutability_v1();

drop trigger if exists fundraising_pledges_immutability_guard_v1 on atlas.fundraising_pledges;
create trigger fundraising_pledges_immutability_guard_v1
before update on atlas.fundraising_pledges
for each row execute function atlas.guard_fundraising_financial_fact_immutability_v1();

drop trigger if exists fundraising_grant_awards_immutability_guard_v1 on atlas.fundraising_grant_awards;
create trigger fundraising_grant_awards_immutability_guard_v1
before update on atlas.fundraising_grant_awards
for each row execute function atlas.guard_fundraising_financial_fact_immutability_v1();

create or replace function atlas.fundraising_constituent_profile_self_api_v1(
  p_fundraising_entity_id uuid,
  p_constituent_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_entity reality.entities%rowtype;
  v_history jsonb;
begin
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;

  select * into v_entity
  from reality.entities e
  where e.id=p_constituent_entity_id and e.identity_state='canonical';
  if v_entity.id is null then raise exception 'Canonical constituent Reality entity required.' using errcode='23503'; end if;

  if not exists(
    select 1 from atlas.fundraising_constituent_relationships r
    where r.fundraising_entity_id=p_fundraising_entity_id
      and r.constituent_entity_id=p_constituent_entity_id
      and r.relationship_state='active'
      and r.ended_at is null
  ) then
    raise exception 'Active fundraising constituent relationship required.' using errcode='23503';
  end if;

  v_history:=atlas.fundraising_constituent_financial_history_self_api_v1(
    p_fundraising_entity_id,p_constituent_entity_id
  );

  return jsonb_build_object(
    'contractVersion','fundraising_constituent_profile_v1',
    'fundraisingEntityId',p_fundraising_entity_id,
    'constituentEntityId',v_entity.id,
    'identity',jsonb_build_object(
      'displayName',v_entity.display_name,
      'entityKind',v_entity.entity_kind,
      'contactRoutes',coalesce((
        select jsonb_agg(jsonb_build_object(
          'contactRouteId',cr.id,'routeKind',cr.route_kind,'routeValue',cr.route_value,
          'routeState',cr.route_state,'lastVerifiedAt',cr.last_verified_at
        ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                   cr.last_verified_at desc nulls last,cr.id)
        from reality.contact_routes cr
        where cr.entity_id=v_entity.id and cr.route_state in ('verified','observed')
      ),'[]'::jsonb)
    ),
    'relationships',coalesce((
      select jsonb_agg(jsonb_build_object(
        'relationshipId',r.id,'relationshipKind',r.relationship_kind,
        'relationshipState',r.relationship_state,'beganAt',r.began_at
      ) order by r.relationship_kind,r.id)
      from atlas.fundraising_constituent_relationships r
      where r.fundraising_entity_id=p_fundraising_entity_id
        and r.constituent_entity_id=p_constituent_entity_id
        and r.relationship_state='active'
        and r.ended_at is null
    ),'[]'::jsonb),
    'financialHistory',v_history,
    'truthBoundary',jsonb_build_object(
      'oneCanonicalRealityEntity',true,
      'contactRoutesOwnedByReality',true,
      'donorStandingDerivedFromFinancialHistory',true,
      'accountingRecognitionEstablishedHere',false
    )
  );
end;
$$;

revoke all on function atlas.fundraising_constituent_profile_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.fundraising_constituent_profile_self_api_v1(uuid,uuid)
  to authenticated;

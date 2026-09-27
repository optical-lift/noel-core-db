-- Atlas canonical fundraising contacts v1
--
-- One real Person/Organization may be discovered through many sources, communicate through many
-- routes, and participate in many fundraising/accounting events. Fundraising never owns identity.
-- Canonical identity lives in reality.entities; names and routes are projections/evidence.
--
-- Boundaries:
--   local_intel entity != canonical Reality entity
--   source contact wording != constituent identity
--   donor/supporter relationship != another Person record
--   fundraising relationship stores no copied name/email/phone
--   communication eligibility does not itself authorize a send

create or replace function atlas.smart_contact_reality_entity_internal_v2(
  p_source_entity_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=''
as $$
  with candidates as (
    select distinct lb.new_id
    from compatibility.legacy_bindings lb
    join reality.entities e
      on e.id=lb.new_id
     and e.identity_state='canonical'
    where lb.legacy_schema='local_intel'
      and lb.legacy_table='entities'
      and lb.legacy_key=p_source_entity_id::text
      and lb.disposition='maps_to'
      and lb.new_schema='reality'
      and lb.new_table='entities'
  ), counted as (
    select count(*)::integer as n,
           min(new_id::text)::uuid as only_id
    from candidates
  )
  select case when n=1 then only_id else null end
  from counted;
$$;

revoke all on function atlas.smart_contact_reality_entity_internal_v2(uuid)
  from public,anon,authenticated;
grant execute on function atlas.smart_contact_reality_entity_internal_v2(uuid)
  to service_role;

comment on function atlas.smart_contact_reality_entity_internal_v2(uuid) is
  'Resolves one Local Intelligence research entity to exactly one canonical Reality entity through compatibility bindings. Ambiguous or unresolved identities return null rather than guessing.';

-- Compatibility storage can now preserve the research entity while carrying canonical Reality
-- identity beside it. Existing V1 writers continue to populate entity_id exactly as before.
alter table atlas.smart_contact_saved_search_run_items
  add column if not exists reality_entity_id uuid references reality.entities(id) on delete restrict;

create unique index if not exists smart_contact_saved_search_run_items_reality_uq
  on atlas.smart_contact_saved_search_run_items(run_id,reality_entity_id)
  where reality_entity_id is not null;

create index if not exists smart_contact_saved_search_run_items_reality_idx
  on atlas.smart_contact_saved_search_run_items(reality_entity_id,run_id)
  where reality_entity_id is not null;

alter table atlas.contact_selection_packet_items
  add column if not exists reality_entity_id uuid references reality.entities(id) on delete restrict;

create index if not exists contact_selection_packet_items_reality_idx
  on atlas.contact_selection_packet_items(reality_entity_id,packet_id)
  where reality_entity_id is not null;

comment on column atlas.smart_contact_saved_search_run_items.reality_entity_id is
  'Canonical Reality identity when this Smart Contact has been lawfully resolved. entity_id remains the Local Intelligence research identity for provenance.';
comment on column atlas.contact_selection_packet_items.reality_entity_id is
  'Canonical Reality identity for contact selection. Legacy entity_id remains source/research provenance until communication workflows fully cut over.';

create table if not exists atlas.fundraising_constituent_relationships (
  id uuid primary key default gen_random_uuid(),
  fundraising_entity_id uuid not null references reality.entities(id) on delete restrict,
  constituent_entity_id uuid not null references reality.entities(id) on delete restrict,
  relationship_kind text not null,
  relationship_state text not null default 'active',
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete set null,
  establishment_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  began_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fundraising_constituent_entities_distinct check (fundraising_entity_id<>constituent_entity_id),
  constraint fundraising_constituent_relationship_kind_check check (
    relationship_kind in ('prospect','supporter','grant_funder','partner','volunteer','other')
  ),
  constraint fundraising_constituent_relationship_state_check check (
    relationship_state in ('active','paused','retired')
  ),
  constraint fundraising_constituent_relationship_end_check check (
    (relationship_state in ('active','paused') and ended_at is null)
    or (relationship_state='retired' and ended_at is not null)
  ),
  constraint fundraising_constituent_establishment_basis_object check (jsonb_typeof(establishment_basis)='object'),
  constraint fundraising_constituent_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(fundraising_entity_id,constituent_entity_id,relationship_kind)
);

create index if not exists fundraising_constituent_relationships_constituent_idx
  on atlas.fundraising_constituent_relationships(constituent_entity_id,relationship_state,fundraising_entity_id);
create index if not exists fundraising_constituent_relationships_fundraising_idx
  on atlas.fundraising_constituent_relationships(fundraising_entity_id,relationship_state,constituent_entity_id);

comment on table atlas.fundraising_constituent_relationships is
  'Fundraising/development relationship between a canonical Reality organization/business and a canonical Reality constituent. This table intentionally stores no copied names, emails, phones, or postal addresses. Donor status will be derived from canonical contribution history rather than becoming a second identity.';

alter table atlas.fundraising_constituent_relationships enable row level security;
revoke all on table atlas.fundraising_constituent_relationships from public,anon,authenticated;

create or replace function atlas.guard_fundraising_constituent_reality_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_fundraising_kind text;
  v_constituent_kind text;
begin
  select e.entity_kind into v_fundraising_kind
  from reality.entities e
  where e.id=new.fundraising_entity_id
    and e.identity_state='canonical';
  if v_fundraising_kind not in ('business','organization') then
    raise exception 'Fundraising entity must be a canonical Reality business or organization.' using errcode='23514';
  end if;

  select e.entity_kind into v_constituent_kind
  from reality.entities e
  where e.id=new.constituent_entity_id
    and e.identity_state='canonical';
  if v_constituent_kind not in ('person','business','organization') then
    raise exception 'Constituent must be a canonical Reality person, business, or organization.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_fundraising_constituent_reality_v1()
  from public,anon,authenticated;
drop trigger if exists fundraising_constituent_reality_guard_v1
  on atlas.fundraising_constituent_relationships;
create trigger fundraising_constituent_reality_guard_v1
before insert or update of fundraising_entity_id,constituent_entity_id,relationship_state,relationship_kind
on atlas.fundraising_constituent_relationships
for each row execute function atlas.guard_fundraising_constituent_reality_v1();

create or replace function atlas.fundraising_entity_authorized_self_v1(
  p_fundraising_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  with context as (
    select auth.uid() as user_id,atlas.current_person_id_v1() as person_id
  )
  select exists(
    select 1
    from context c
    join reality.entities e
      on e.id=p_fundraising_entity_id
     and e.identity_state='canonical'
     and e.entity_kind in ('business','organization')
    where c.user_id is not null
      and c.person_id is not null
      and (
        exists(
          select 1
          from reality.responsibility_relations r
          where r.carrier_person_entity_id=c.person_id
            and r.relation_state='active'
            and r.jurisdiction_kind='entity'
            and r.jurisdiction_entity_id=p_fundraising_entity_id
            and r.began_at<=now()
            and r.ended_at is null
            and r.permitted_operations @> array['fundraising.manage']::text[]
        )
        or exists(
          select 1
          from ledger.ledgers l
          join ledger.seats s
            on s.ledger_id=l.id
           and s.person_entity_id=c.person_id
           and s.seat_state='active'
           and s.ended_at is null
          where l.subject_entity_id=p_fundraising_entity_id
            and l.ledger_state='active'
            and l.retired_at is null
        )
      )
  );
$$;

revoke all on function atlas.fundraising_entity_authorized_self_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.fundraising_entity_authorized_self_v1(uuid)
  to authenticated,service_role;

create or replace function atlas.establish_fundraising_constituent_self_api_v1(
  p_fundraising_entity_id uuid,
  p_constituent_entity_id uuid,
  p_relationship_kind text,
  p_establishment_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_kind text:=lower(btrim(coalesce(p_relationship_kind,'')));
  v_principal_id uuid;
  v_row atlas.fundraising_constituent_relationships%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;
  if v_kind not in ('prospect','supporter','grant_funder','partner','volunteer','other') then
    raise exception 'Unsupported fundraising constituent relationship kind.' using errcode='22023';
  end if;
  if p_establishment_basis is null or jsonb_typeof(p_establishment_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Establishment basis and metadata must be JSON objects.' using errcode='22023';
  end if;
  if not exists(
    select 1 from reality.entities e
    where e.id=p_constituent_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Canonical Reality constituent required; unresolved contact evidence cannot become a constituent.' using errcode='23503';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();

  insert into atlas.fundraising_constituent_relationships(
    fundraising_entity_id,constituent_entity_id,relationship_kind,relationship_state,
    established_by_principal_id,established_by_user_id,establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_constituent_entity_id,v_kind,'active',
    v_principal_id,auth.uid(),
    p_establishment_basis||jsonb_build_object(
      'authority','establish_fundraising_constituent_self_api_v1',
      'canonicalRealityEntityRequired',true,
      'sourceContactTextDoesNotCreateIdentity',true
    ),p_metadata
  ) on conflict(fundraising_entity_id,constituent_entity_id,relationship_kind)
  do update set
    relationship_state='active',
    ended_at=null,
    establishment_basis=atlas.fundraising_constituent_relationships.establishment_basis||excluded.establishment_basis,
    metadata=atlas.fundraising_constituent_relationships.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','fundraising_constituent_v1',
    'constituentRelationshipId',v_row.id,
    'fundraisingEntityId',v_row.fundraising_entity_id,
    'constituentEntityId',v_row.constituent_entity_id,
    'relationshipKind',v_row.relationship_kind,
    'relationshipState',v_row.relationship_state,
    'truthBoundary',jsonb_build_object(
      'canonicalIdentityOwnedByReality',true,
      'namesAndContactRoutesCopiedIntoFundraising',false,
      'donorStatusDerivedFromContributionHistory',true,
      'communicationAuthorized',false
    )
  );
end;
$$;

revoke all on function atlas.establish_fundraising_constituent_self_api_v1(uuid,uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.establish_fundraising_constituent_self_api_v1(uuid,uuid,text,jsonb,jsonb)
  to authenticated;

create or replace function atlas.fundraising_constituents_self_api_v1(
  p_fundraising_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','fundraising_constituents_v1',
    'fundraisingEntityId',p_fundraising_entity_id,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'constituentEntityId',e.id,
        'displayName',e.display_name,
        'entityKind',e.entity_kind,
        'relationshipKinds',rel.relationship_kinds,
        'contactRoutes',coalesce(routes.routes,'[]'::jsonb)
      ) order by e.display_name,e.id)
      from reality.entities e
      join lateral (
        select array_agg(r.relationship_kind order by r.relationship_kind) as relationship_kinds
        from atlas.fundraising_constituent_relationships r
        where r.fundraising_entity_id=p_fundraising_entity_id
          and r.constituent_entity_id=e.id
          and r.relationship_state='active'
          and r.ended_at is null
      ) rel on cardinality(rel.relationship_kinds)>0
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'contactRouteId',cr.id,
          'routeKind',cr.route_kind,
          'routeValue',cr.route_value,
          'routeState',cr.route_state,
          'lastVerifiedAt',cr.last_verified_at
        ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                   cr.last_verified_at desc nulls last,cr.id) as routes
        from reality.contact_routes cr
        where cr.entity_id=e.id
          and cr.route_state in ('verified','observed')
      ) routes on true
      where e.identity_state='canonical'
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'canonicalRealityEntitiesOnly',true,
      'contactRoutesReadFromReality',true,
      'donorStatusDerivedFromContributionHistory',true,
      'communicationAuthorized',false
    )
  );
end;
$$;

revoke all on function atlas.fundraising_constituents_self_api_v1(uuid) from public,anon;
grant execute on function atlas.fundraising_constituents_self_api_v1(uuid) to authenticated;

create or replace function atlas.fundraising_newsletter_audience_self_api_v1(
  p_fundraising_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','fundraising_newsletter_audience_v1',
    'fundraisingEntityId',p_fundraising_entity_id,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'constituentEntityId',e.id,
        'displayName',e.display_name,
        'entityKind',e.entity_kind,
        'relationshipKinds',rel.relationship_kinds,
        'emailRouteId',email.id,
        'email',email.route_value,
        'emailState',email.route_state
      ) order by e.display_name,e.id)
      from reality.entities e
      join lateral (
        select array_agg(r.relationship_kind order by r.relationship_kind) as relationship_kinds
        from atlas.fundraising_constituent_relationships r
        where r.fundraising_entity_id=p_fundraising_entity_id
          and r.constituent_entity_id=e.id
          and r.relationship_state='active'
          and r.ended_at is null
      ) rel on cardinality(rel.relationship_kinds)>0
      join lateral (
        select cr.*
        from reality.contact_routes cr
        where cr.entity_id=e.id
          and lower(cr.route_kind)='email'
          and cr.route_state in ('verified','observed')
        order by case cr.route_state when 'verified' then 0 else 1 end,
                 cr.last_verified_at desc nulls last,cr.id
        limit 1
      ) email on true
      where e.identity_state='canonical'
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sameCanonicalEntitiesAsFundraisingAndAccounting',true,
      'emailReadFromRealityContactRoute',true,
      'suppressedAndRetiredRoutesExcluded',true,
      'audienceProjectionDoesNotAuthorizeSend',true
    )
  );
end;
$$;

revoke all on function atlas.fundraising_newsletter_audience_self_api_v1(uuid) from public,anon;
grant execute on function atlas.fundraising_newsletter_audience_self_api_v1(uuid) to authenticated;

-- V2 Smart Contacts keeps Local Intelligence as research evidence but makes Reality identity
-- explicit. Already-established fundraising constituents are included even if no Local Intel
-- research entity exists for them.
create or replace function atlas.smart_contacts_search_service_v2(
  p_organization_id uuid,
  p_query jsonb,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_base jsonb;
  v_item jsonb;
  v_source_id uuid;
  v_reality_id uuid;
  v_org_reality_id uuid;
  v_entity reality.entities%rowtype;
  v_routes jsonb;
  v_canonical_items jsonb:='[]'::jsonb;
  v_unresolved_items jsonb:='[]'::jsonb;
  v_seen uuid[]:='{}'::uuid[];
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
  v_text text:=nullif(lower(btrim(coalesce(p_query->>'text',''))),'');
  v_canonical_only boolean:=coalesce((p_query->>'canonicalOnly')::boolean,false);
  v_count integer:=0;
begin
  if p_query is null or jsonb_typeof(p_query)<>'object' then
    raise exception 'Smart Contacts query must be a JSON object.' using errcode='22023';
  end if;

  v_base:=atlas.smart_contacts_search_service_v1(p_organization_id,p_query,v_limit);
  v_org_reality_id:=atlas.reality_entity_for_legacy_organization_internal_v1(p_organization_id);

  for v_item in select value from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb))
  loop
    begin v_source_id:=(v_item->>'entityId')::uuid;
    exception when others then v_source_id:=null; end;
    v_reality_id:=case when v_source_id is null then null else atlas.smart_contact_reality_entity_internal_v2(v_source_id) end;

    if v_reality_id is not null and not (v_reality_id=any(v_seen)) then
      select * into v_entity from reality.entities e
      where e.id=v_reality_id and e.identity_state='canonical';
      select coalesce(jsonb_agg(jsonb_build_object(
        'contactRouteId',cr.id,'routeKind',cr.route_kind,'routeValue',cr.route_value,
        'routeState',cr.route_state,'lastVerifiedAt',cr.last_verified_at
      ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                 cr.last_verified_at desc nulls last,cr.id),'[]'::jsonb)
      into v_routes
      from reality.contact_routes cr
      where cr.entity_id=v_reality_id and cr.route_state in ('verified','observed');

      v_canonical_items:=v_canonical_items||jsonb_build_array(
        (v_item-'entityId')||jsonb_build_object(
          'entityId',v_reality_id,
          'realityEntityId',v_reality_id,
          'sourceEntityId',v_source_id,
          'canonicalState','resolved',
          'canonicalIdentity',jsonb_build_object(
            'displayName',v_entity.display_name,'entityKind',v_entity.entity_kind,
            'contactRoutes',v_routes
          )
        )
      );
      v_seen:=array_append(v_seen,v_reality_id);
    elsif not v_canonical_only then
      v_unresolved_items:=v_unresolved_items||jsonb_build_array(
        (v_item-'entityId')||jsonb_build_object(
          'entityId',null,
          'realityEntityId',null,
          'sourceEntityId',v_source_id,
          'canonicalState','unresolved',
          'researchGaps',coalesce(v_item->'researchGaps','[]'::jsonb)||jsonb_build_array('reality_identity_unresolved')
        )
      );
    end if;
  end loop;

  if v_org_reality_id is not null then
    for v_entity in
      select distinct e.*
      from atlas.fundraising_constituent_relationships r
      join reality.entities e on e.id=r.constituent_entity_id and e.identity_state='canonical'
      where r.fundraising_entity_id=v_org_reality_id
        and r.relationship_state='active'
        and r.ended_at is null
        and (v_text is null or lower(e.display_name) like '%'||v_text||'%')
      order by e.display_name,e.id
    loop
      if not (v_entity.id=any(v_seen)) then
        select coalesce(jsonb_agg(jsonb_build_object(
          'contactRouteId',cr.id,'routeKind',cr.route_kind,'routeValue',cr.route_value,
          'routeState',cr.route_state,'lastVerifiedAt',cr.last_verified_at
        ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                   cr.last_verified_at desc nulls last,cr.id),'[]'::jsonb)
        into v_routes
        from reality.contact_routes cr
        where cr.entity_id=v_entity.id and cr.route_state in ('verified','observed');

        v_canonical_items:=v_canonical_items||jsonb_build_array(jsonb_build_object(
          'entityId',v_entity.id,
          'realityEntityId',v_entity.id,
          'sourceEntityId',null,
          'name',v_entity.display_name,
          'entityType',v_entity.entity_kind,
          'canonicalState','resolved',
          'canonicalIdentity',jsonb_build_object(
            'displayName',v_entity.display_name,'entityKind',v_entity.entity_kind,
            'contactRoutes',v_routes
          ),
          'match',jsonb_build_object(
            'relevanceScore',80,
            'signalKeys',jsonb_build_array('established_fundraising_constituent')
          ),
          'researchGaps','[]'::jsonb,
          'organizationOverlay',jsonb_build_object('fundraisingConstituent',true)
        ));
        v_seen:=array_append(v_seen,v_entity.id);
      end if;
    end loop;
  end if;

  v_count:=least(v_limit,jsonb_array_length(v_canonical_items)+jsonb_array_length(v_unresolved_items));

  return jsonb_build_object(
    'contractVersion','atlas_smart_contacts_reality_v2',
    'productName','Atlas Smart Contacts',
    'organizationId',p_organization_id,
    'query',p_query,
    'resultCount',v_count,
    'canonicalCount',least(v_limit,jsonb_array_length(v_canonical_items)),
    'unresolvedCount',case when v_canonical_only then 0 else greatest(0,v_count-least(v_limit,jsonb_array_length(v_canonical_items))) end,
    'items',(
      select coalesce(jsonb_agg(value),'[]'::jsonb)
      from (
        select value,ord from jsonb_array_elements(v_canonical_items||v_unresolved_items) with ordinality x(value,ord)
        where ord<=v_limit
        order by ord
      ) limited
    ),
    'truthBoundary',jsonb_build_object(
      'canonicalReality','reality.entities',
      'localIntelRetainedAsResearchEvidence',true,
      'unresolvedResearchContactMayBecomeConstituent',false,
      'fundraisingConstituentsDiscoverableWithoutLocalIntelRecord',true,
      'searchCreatesRelationship',false,
      'searchAuthorizesCommunication',false
    )
  );
end;
$$;

revoke all on function atlas.smart_contacts_search_service_v2(uuid,jsonb,integer)
  from public,anon,authenticated;
grant execute on function atlas.smart_contacts_search_service_v2(uuid,jsonb,integer)
  to service_role;

create or replace function atlas.smart_contacts_search_self_api_v2(
  p_organization_id uuid,
  p_query jsonb,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.smart_contacts_search_service_v2(p_organization_id,p_query,p_limit);
end;
$$;

revoke all on function atlas.smart_contacts_search_self_api_v2(uuid,jsonb,integer) from public,anon;
grant execute on function atlas.smart_contacts_search_self_api_v2(uuid,jsonb,integer) to authenticated;

-- Atlas Census TIGER state-scoped refresh v1.
-- Makes national rollout incremental and records state coverage completeness.

create or replace function atlas.refresh_census_tiger_state_geography_v1(
  p_state_fips text,
  p_source_vintage text default '2026',
  p_page_size integer default 100,
  p_admission_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_state text:=btrim(coalesce(p_state_fips,''));
  v_vintage text:=btrim(coalesce(p_source_vintage,''));
  v_load jsonb;
  v_feature record;
  v_relation record;
  v_receipt jsonb;
  v_features integer:=0;
  v_inserted integer:=0;
  v_converged integer:=0;
  v_bound integer:=0;
  v_relations integer:=0;
begin
  if v_state !~ '^[0-9]{2}$' then raise exception 'state FIPS must be exactly two digits.' using errcode='22023'; end if;
  if v_vintage='' then raise exception 'source vintage is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'admission basis must be an object.' using errcode='22023'; end if;

  v_load:=geography.load_census_tigerweb_state_v1(v_state,v_vintage,p_page_size);

  for v_feature in
    select f.id
    from geography.source_features f
    where f.dataset_key='census.tiger'
      and f.source_vintage=v_vintage
      and f.is_current and f.feature_state='active'
      and f.canonical_place_kind is not null
      and (
        (f.feature_kind='census_state' and f.identity_namespace='census.tiger.state.geoid' and f.identity_key=v_state)
        or f.administrative_codes->>'stateFips'=v_state
      )
    order by f.source_feature_key
  loop
    v_receipt:=atlas.admit_authoritative_geography_feature_to_reality_service_v1(
      v_feature.id,
      p_admission_basis || jsonb_build_object('stateFips',v_state,'sourceVintage',v_vintage,'refreshContract','ATLAS_CENSUS_TIGER_STATE_REFRESH_V1')
    );
    v_features:=v_features+1;
    if coalesce((v_receipt->>'inserted')::boolean,false) then
      v_inserted:=v_inserted+1;
    elsif coalesce((v_receipt->>'convergedExisting')::boolean,false) then
      v_converged:=v_converged+1;
    else
      v_bound:=v_bound+1;
    end if;
  end loop;

  for v_relation in
    select r.id
    from geography.source_relations r
    join geography.source_features sf
      on sf.dataset_key=r.dataset_key
     and sf.source_vintage=r.source_vintage
     and sf.identity_namespace=r.subject_identity_namespace
     and sf.identity_key=r.subject_identity_key
     and sf.is_current and sf.feature_state='active'
    where r.dataset_key='census.tiger'
      and r.source_vintage=v_vintage
      and r.is_current and r.relation_state='active'
      and r.relationship_kind='contained_in'
      and sf.administrative_codes->>'stateFips'=v_state
    order by r.source_relation_key
  loop
    perform atlas.admit_authoritative_geography_relation_to_reality_service_v1(
      v_relation.id,
      p_admission_basis || jsonb_build_object('stateFips',v_state,'sourceVintage',v_vintage,'refreshContract','ATLAS_CENSUS_TIGER_STATE_REFRESH_V1')
    );
    v_relations:=v_relations+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','census_tiger_state_geography_refresh_v1',
    'datasetKey','census.tiger','sourceVintage',v_vintage,'stateFips',v_state,
    'sourceLoad',v_load,
    'canonicalFeatureCount',v_features,
    'insertedCanonicalPlaces',v_inserted,
    'convergedExistingPlaces',v_converged,
    'boundExistingPlaces',v_bound,
    'establishedContainmentRelations',v_relations,
    'communicationAuthorized',false
  );
end
$function$;

create or replace view geography.v_census_tiger_state_status_v1 as
with states as (
  select
    f.source_vintage,
    f.identity_key as state_fips,
    f.display_name as state_name,
    f.properties->>'STUSAB' as state_abbreviation,
    f.id as state_source_feature_id
  from geography.source_features f
  where f.dataset_key='census.tiger'
    and f.feature_kind='census_state'
    and f.identity_namespace='census.tiger.state.geoid'
    and f.is_current and f.feature_state='active'
), feature_counts as (
  select
    f.source_vintage,
    coalesce(f.administrative_codes->>'stateFips',case when f.feature_kind='census_state' then f.identity_key end) as state_fips,
    count(*)::integer as source_feature_count,
    count(*) filter (where b.source_feature_id is not null and b.binding_state='active')::integer as bound_feature_count
  from geography.source_features f
  left join geography.place_feature_bindings b on b.source_feature_id=f.id and b.binding_state='active'
  where f.dataset_key='census.tiger' and f.is_current and f.feature_state='active'
  group by f.source_vintage,coalesce(f.administrative_codes->>'stateFips',case when f.feature_kind='census_state' then f.identity_key end)
), relation_counts as (
  select
    r.source_vintage,
    sf.administrative_codes->>'stateFips' as state_fips,
    count(*)::integer as source_relation_count,
    count(*) filter (where exists(
      select 1
      from reality.relationship_propositions rp
      where rp.idempotency_key='geographic_substrate:'||r.id::text
        and rp.proposition_state='accepted'
    ))::integer as admitted_relation_count
  from geography.source_relations r
  join geography.source_features sf
    on sf.dataset_key=r.dataset_key
   and sf.source_vintage=r.source_vintage
   and sf.identity_namespace=r.subject_identity_namespace
   and sf.identity_key=r.subject_identity_key
   and sf.is_current and sf.feature_state='active'
  where r.dataset_key='census.tiger'
    and r.is_current and r.relation_state='active'
  group by r.source_vintage,sf.administrative_codes->>'stateFips'
)
select
  s.source_vintage,
  s.state_fips,
  s.state_name,
  s.state_abbreviation,
  coalesce(fc.source_feature_count,0) as source_feature_count,
  coalesce(fc.bound_feature_count,0) as bound_feature_count,
  coalesce(rc.source_relation_count,0) as source_relation_count,
  coalesce(rc.admitted_relation_count,0) as admitted_relation_count,
  (coalesce(fc.source_feature_count,0)>0 and coalesce(fc.bound_feature_count,0)=coalesce(fc.source_feature_count,0)) as identity_complete,
  (coalesce(rc.source_relation_count,0)=coalesce(rc.admitted_relation_count,0)) as containment_complete
from states s
left join feature_counts fc on fc.source_vintage=s.source_vintage and fc.state_fips=s.state_fips
left join relation_counts rc on rc.source_vintage=s.source_vintage and rc.state_fips=s.state_fips;

comment on function atlas.refresh_census_tiger_state_geography_v1(text,text,integer,jsonb) is 'State-scoped idempotent geographic substrate refresh: load Census source observations, admit/bind canonical Places, then admit authoritative contained_in topology for that state only.';
comment on view geography.v_census_tiger_state_status_v1 is 'Per-state Census substrate coverage and governed admission completeness for incremental national rollout.';

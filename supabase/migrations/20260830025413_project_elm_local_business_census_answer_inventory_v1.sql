do $block$
declare
  v_oid regprocedure := 'local_intel.record_business_census_discovery_v1(uuid,jsonb)'::regprocedure;
  v_def text;
  v_old text := $$jsonb_build_object('business_census',true,'identity_basis','publicly indexed named business discovery','first_census_source_id',v_source_id,'query_family',v_work.query_family_key)$$;
  v_new text := $$jsonb_build_object('business_census',true,'identity_basis','publicly indexed named business discovery','first_census_source_id',v_source_id,'query_family',v_work.query_family_key,'publication_state','identity_publishable','category',coalesce(v_category,'business'))$$;
begin
  v_def := pg_get_functiondef(v_oid);
  if position(v_old in v_def)=0 then
    raise exception 'Expected census entity metadata constructor not found in record_business_census_discovery_v1';
  end if;
  execute replace(v_def,v_old,v_new);
end
$block$;

with category_by_entity as (
  select distinct on (r.canonical_entity_id)
         r.canonical_entity_id,
         coalesce(nullif(btrim(r.category_text),''),'business') as category
  from local_intel.business_census_discovery_records r
  where r.canonical_entity_id is not null
  order by r.canonical_entity_id,r.observed_at desc
)
update local_intel.entities e
set metadata=e.metadata || jsonb_build_object(
      'publication_state','identity_publishable',
      'category',coalesce(c.category,e.metadata->>'category','business')
    ),
    updated_at=now()
from category_by_entity c
where e.id=c.canonical_entity_id
  and coalesce((e.metadata->>'business_census')::boolean,false)=true
  and e.entity_type='business'
  and e.status<>'inactive';

revoke all on function local_intel.record_business_census_discovery_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function local_intel.record_business_census_discovery_v1(uuid,jsonb) to service_role;

comment on function local_intel.record_business_census_discovery_v1(uuid,jsonb) is 'Ingests one publicly discovered named business into governed Local Intel identity custody. New public-indexed census businesses are identity_publishable to Elm Local search with a durable category, while current availability remains separately evidence-gated.';
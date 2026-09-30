-- Atlas Geographic Substrate privilege hardening v1.
-- Geographic corpus mutation and canonical admission remain internal/service-only.

revoke all on schema geography from public,anon,authenticated;
grant usage on schema geography to service_role;

revoke all on function geography.upsert_source_feature_v1(jsonb) from public,anon,authenticated;
revoke all on function geography.upsert_source_relation_v1(jsonb) from public,anon,authenticated;
revoke all on function geography.load_census_tigerweb_state_v1(text,text,integer) from public,anon,authenticated;
revoke all on function geography.resolve_named_place_v1(text,text,text,text) from public,anon,authenticated;
revoke all on function geography.places_covering_point_v1(double precision,double precision,text[]) from public,anon,authenticated;

grant execute on function geography.upsert_source_feature_v1(jsonb) to service_role;
grant execute on function geography.upsert_source_relation_v1(jsonb) to service_role;
grant execute on function geography.load_census_tigerweb_state_v1(text,text,integer) to service_role;
grant execute on function geography.resolve_named_place_v1(text,text,text,text) to service_role;
grant execute on function geography.places_covering_point_v1(double precision,double precision,text[]) to service_role;

revoke all on function atlas.admit_authoritative_geography_feature_to_reality_service_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.admit_authoritative_geography_dataset_to_reality_service_v1(text,text,jsonb) from public,anon,authenticated;
revoke all on function atlas.admit_authoritative_geography_relation_to_reality_service_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.admit_authoritative_geography_relations_dataset_v1(text,text,jsonb) from public,anon,authenticated;
revoke all on function atlas.refresh_census_tiger_state_geography_v1(text,text,integer,jsonb) from public,anon,authenticated;

grant execute on function atlas.admit_authoritative_geography_feature_to_reality_service_v1(uuid,jsonb) to service_role;
grant execute on function atlas.admit_authoritative_geography_dataset_to_reality_service_v1(text,text,jsonb) to service_role;
grant execute on function atlas.admit_authoritative_geography_relation_to_reality_service_v1(uuid,jsonb) to service_role;
grant execute on function atlas.admit_authoritative_geography_relations_dataset_v1(text,text,jsonb) to service_role;
grant execute on function atlas.refresh_census_tiger_state_geography_v1(text,text,integer,jsonb) to service_role;

grant select on geography.v_census_tiger_state_status_v1 to service_role;
grant select on geography.v_canonical_place_geometry_v1 to service_role;

comment on schema geography is 'Internal Atlas source-aware geographic substrate. Direct client access is denied; governed Atlas/service membranes expose permitted geographic behavior.';

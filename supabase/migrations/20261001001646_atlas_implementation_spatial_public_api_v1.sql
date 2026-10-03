-- Public Data API wrappers for the Implementation spatial sentence workbench.
-- These wrappers expose only authenticated, case-scoped self APIs; authority remains
-- enforced inside the atlas schema functions.

create or replace function public.implementation_spatial_subject_options_self_api_v1(
  p_implementation_case_id uuid,
  p_subject_kind text,
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.implementation_spatial_subject_options_self_api_v1(
    p_implementation_case_id,p_subject_kind,p_query,p_limit
  );
$function$;

create or replace function public.implementation_place_options_self_api_v1(
  p_implementation_case_id uuid,
  p_query text,
  p_limit integer default 25
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.implementation_place_options_self_api_v1(
    p_implementation_case_id,p_query,p_limit
  );
$function$;

create or replace function public.create_implementation_spatial_candidate_self_api_v1(
  p_implementation_case_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_context_kind text,
  p_place_entity_id uuid default null,
  p_presence_mode text default 'physical',
  p_distance_limit_meters double precision default null,
  p_literal_statement text default null,
  p_implementation_thread_id uuid default null,
  p_basis_kind text default 'reconstruction_of_existing_reality'
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.create_implementation_spatial_candidate_self_api_v1(
    p_implementation_case_id,p_subject_kind,p_subject_id,p_context_kind,
    p_place_entity_id,p_presence_mode,p_distance_limit_meters,p_literal_statement,
    p_implementation_thread_id,p_basis_kind
  );
$function$;

create or replace function public.preview_implementation_reality_candidate_promotion_self_api_v2(p_candidate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_result jsonb;
  v_proc regprocedure;
  v_available boolean:=false;
begin
  v_result:=atlas.preview_implementation_reality_candidate_promotion_self_api_v2(p_candidate_id);
  v_proc:=to_regprocedure('public.promote_implementation_reality_candidate_self_api_v2(uuid)');
  v_available:=v_proc is not null and has_function_privilege('authenticated',v_proc,'EXECUTE');
  return v_result || jsonb_build_object(
    'promotionCommandAvailable',v_available,
    'canExecutePromotion',v_available and coalesce((v_result->>'canPromote')::boolean,false)
  );
end
$function$;

create or replace function public.promote_implementation_reality_candidate_self_api_v2(p_candidate_id uuid)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.promote_implementation_reality_candidate_self_api_v2(p_candidate_id);
$function$;

revoke all on function public.implementation_spatial_subject_options_self_api_v1(uuid,text,text,integer) from public,anon;
revoke all on function public.implementation_place_options_self_api_v1(uuid,text,integer) from public,anon;
revoke all on function public.create_implementation_spatial_candidate_self_api_v1(uuid,text,uuid,text,uuid,text,double precision,text,uuid,text) from public,anon;
revoke all on function public.preview_implementation_reality_candidate_promotion_self_api_v2(uuid) from public,anon;
revoke all on function public.promote_implementation_reality_candidate_self_api_v2(uuid) from public,anon;

grant execute on function public.implementation_spatial_subject_options_self_api_v1(uuid,text,text,integer) to authenticated,service_role;
grant execute on function public.implementation_place_options_self_api_v1(uuid,text,integer) to authenticated,service_role;
grant execute on function public.create_implementation_spatial_candidate_self_api_v1(uuid,text,uuid,text,uuid,text,double precision,text,uuid,text) to authenticated,service_role;
grant execute on function public.preview_implementation_reality_candidate_promotion_self_api_v2(uuid) to authenticated,service_role;
grant execute on function public.promote_implementation_reality_candidate_self_api_v2(uuid) to authenticated,service_role;

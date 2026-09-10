begin;

create or replace function public.implementation_workbench_self_api_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_workbench_self_api_v1();
$function$;

create or replace function public.bootstrap_initial_implementation_practitioner_self_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.bootstrap_initial_implementation_practitioner_self_v1();
$function$;

create or replace function public.claim_implementation_case_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.claim_implementation_case_self_api_v1(p_implementation_case_id);
$function$;

create or replace function public.implementation_case_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_case_self_api_v1(p_implementation_case_id);
$function$;

comment on function public.implementation_workbench_self_api_v1() is
  'Browser-facing PostgREST membrane for the canonical Atlas practitioner Workbench self API. Canonical logic remains in atlas schema.';
comment on function public.bootstrap_initial_implementation_practitioner_self_v1() is
  'Browser-facing PostgREST membrane for the one-time initial practitioner bootstrap. Canonical logic remains in atlas schema.';
comment on function public.claim_implementation_case_self_api_v1(uuid) is
  'Browser-facing PostgREST membrane for claiming an implementation case. Canonical logic remains in atlas schema.';
comment on function public.implementation_case_self_api_v1(uuid) is
  'Browser-facing PostgREST membrane for reading one implementation case. Canonical logic remains in atlas schema.';

revoke all on function public.implementation_workbench_self_api_v1() from public, anon;
revoke all on function public.bootstrap_initial_implementation_practitioner_self_v1() from public, anon;
revoke all on function public.claim_implementation_case_self_api_v1(uuid) from public, anon;
revoke all on function public.implementation_case_self_api_v1(uuid) from public, anon;

grant execute on function public.implementation_workbench_self_api_v1() to authenticated;
grant execute on function public.bootstrap_initial_implementation_practitioner_self_v1() to authenticated;
grant execute on function public.claim_implementation_case_self_api_v1(uuid) to authenticated;
grant execute on function public.implementation_case_self_api_v1(uuid) to authenticated;

commit;
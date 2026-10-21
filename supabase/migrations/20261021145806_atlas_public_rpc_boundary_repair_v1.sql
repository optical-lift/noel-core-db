-- Atlas guarded browser RPC bridge repair: do not duplicate canonical data or modify domain authority.
-- The notebook uses PostgREST default public schema; source RPCs remain owned in atlas.
-- Each bridge is SECURITY INVOKER; authenticated callers still meet every original atlas self-RPC gate.
begin;

-- Exact public API projection for connected_ledger_inbox_self_api_v1
create or replace function public.connected_ledger_inbox_self_api_v1(p_limit integer DEFAULT 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.connected_ledger_inbox_self_api_v1($1);
$atlas_bridge$;
revoke all on function public.connected_ledger_inbox_self_api_v1(p_limit integer) from public, anon;
grant execute on function public.connected_ledger_inbox_self_api_v1(p_limit integer) to authenticated;

-- Exact public API projection for connected_ledger_person_choices_self_api_v1
create or replace function public.connected_ledger_person_choices_self_api_v1(p_ledger_id uuid, p_limit integer DEFAULT 100, p_after_person_id uuid DEFAULT NULL::uuid)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.connected_ledger_person_choices_self_api_v1($1,$2,$3);
$atlas_bridge$;
revoke all on function public.connected_ledger_person_choices_self_api_v1(p_ledger_id uuid, p_limit integer, p_after_person_id uuid) from public, anon;
grant execute on function public.connected_ledger_person_choices_self_api_v1(p_ledger_id uuid, p_limit integer, p_after_person_id uuid) to authenticated;

-- Exact public API projection for connected_ledger_respond_self_api_v1
create or replace function public.connected_ledger_respond_self_api_v1(p_dispatch_id uuid, p_decision text)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.connected_ledger_respond_self_api_v1($1,$2);
$atlas_bridge$;
revoke all on function public.connected_ledger_respond_self_api_v1(p_dispatch_id uuid, p_decision text) from public, anon;
grant execute on function public.connected_ledger_respond_self_api_v1(p_dispatch_id uuid, p_decision text) to authenticated;

-- Exact public API projection for connected_ledger_send_self_api_v1
create or replace function public.connected_ledger_send_self_api_v1(p_ledger_id uuid, p_recipient_person_id uuid, p_body text, p_kind text, p_source_action_id text)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.connected_ledger_send_self_api_v1($1,$2,$3,$4,$5);
$atlas_bridge$;
revoke all on function public.connected_ledger_send_self_api_v1(p_ledger_id uuid, p_recipient_person_id uuid, p_body text, p_kind text, p_source_action_id text) from public, anon;
grant execute on function public.connected_ledger_send_self_api_v1(p_ledger_id uuid, p_recipient_person_id uuid, p_body text, p_kind text, p_source_action_id text) to authenticated;

-- Exact public API projection for connected_person_company_work_day_self_api_v1
create or replace function public.connected_person_company_work_day_self_api_v1(p_date date)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.connected_person_company_work_day_self_api_v1($1);
$atlas_bridge$;
revoke all on function public.connected_person_company_work_day_self_api_v1(p_date date) from public, anon;
grant execute on function public.connected_person_company_work_day_self_api_v1(p_date date) to authenticated;

-- Exact public API projection for delete_unlinked_personal_task_self_api_v1
create or replace function public.delete_unlinked_personal_task_self_api_v1(p_task_id uuid)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.delete_unlinked_personal_task_self_api_v1($1);
$atlas_bridge$;
revoke all on function public.delete_unlinked_personal_task_self_api_v1(p_task_id uuid) from public, anon;
grant execute on function public.delete_unlinked_personal_task_self_api_v1(p_task_id uuid) to authenticated;

-- Exact public API projection for native_today_work_void_preflight_self_api_v1
create or replace function public.native_today_work_void_preflight_self_api_v1(p_work_item_id uuid, p_ledger_id uuid)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.native_today_work_void_preflight_self_api_v1($1,$2);
$atlas_bridge$;
revoke all on function public.native_today_work_void_preflight_self_api_v1(p_work_item_id uuid, p_ledger_id uuid) from public, anon;
grant execute on function public.native_today_work_void_preflight_self_api_v1(p_work_item_id uuid, p_ledger_id uuid) to authenticated;

-- Exact public API projection for owner_create_native_ledger_today_work_self_api_v1
create or replace function public.owner_create_native_ledger_today_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope_id uuid, p_sentence text, p_execution_date date, p_due_date date, p_source_action_id text, p_atlas_verification boolean DEFAULT false)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.owner_create_native_ledger_today_work_self_api_v1($1,$2,$3,$4,$5,$6,$7,$8);
$atlas_bridge$;
revoke all on function public.owner_create_native_ledger_today_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope_id uuid, p_sentence text, p_execution_date date, p_due_date date, p_source_action_id text, p_atlas_verification boolean) from public, anon;
grant execute on function public.owner_create_native_ledger_today_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope_id uuid, p_sentence text, p_execution_date date, p_due_date date, p_source_action_id text, p_atlas_verification boolean) to authenticated;

-- Exact public API projection for owner_native_ledger_blocker_detail_self_api_v1
create or replace function public.owner_native_ledger_blocker_detail_self_api_v1(p_work_item_id uuid, p_ledger_id uuid)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.owner_native_ledger_blocker_detail_self_api_v1($1,$2);
$atlas_bridge$;
revoke all on function public.owner_native_ledger_blocker_detail_self_api_v1(p_work_item_id uuid, p_ledger_id uuid) from public, anon;
grant execute on function public.owner_native_ledger_blocker_detail_self_api_v1(p_work_item_id uuid, p_ledger_id uuid) to authenticated;

-- Exact public API projection for owner_set_connected_person_work_day_self_api_v1
create or replace function public.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.owner_set_connected_person_work_day_self_api_v1($1,$2,$3,$4);
$atlas_bridge$;
revoke all on function public.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text) from public, anon;
grant execute on function public.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text) to authenticated;

-- Exact public API projection for owner_void_native_today_work_self_api_v1
create or replace function public.owner_void_native_today_work_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_reason text)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.owner_void_native_today_work_self_api_v1($1,$2,$3);
$atlas_bridge$;
revoke all on function public.owner_void_native_today_work_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_reason text) from public, anon;
grant execute on function public.owner_void_native_today_work_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_reason text) to authenticated;

-- Exact public API projection for personal_archived_tasks_day_self_api_v1
create or replace function public.personal_archived_tasks_day_self_api_v1(p_date date)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.personal_archived_tasks_day_self_api_v1($1);
$atlas_bridge$;
revoke all on function public.personal_archived_tasks_day_self_api_v1(p_date date) from public, anon;
grant execute on function public.personal_archived_tasks_day_self_api_v1(p_date date) to authenticated;

-- Exact public API projection for set_personal_task_archive_self_api_v1
create or replace function public.set_personal_task_archive_self_api_v1(p_task_id uuid, p_archived boolean)
returns jsonb language sql security invoker set search_path='pg_catalog' as $atlas_bridge$
  select atlas.set_personal_task_archive_self_api_v1($1,$2);
$atlas_bridge$;
revoke all on function public.set_personal_task_archive_self_api_v1(p_task_id uuid, p_archived boolean) from public, anon;
grant execute on function public.set_personal_task_archive_self_api_v1(p_task_id uuid, p_archived boolean) to authenticated;

-- The Supabase PostgREST gateway must discover the newly exposed public RPC signatures.
notify pgrst, 'reload schema';
commit;

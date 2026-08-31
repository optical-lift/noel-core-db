BEGIN;

create or replace function atlas.owner_operator_record_weekly_harvest_row_v3(
  p_effective_membership_id uuid,
  p_task_id uuid,
  p_crop_cycle_id uuid,
  p_result_kind text,
  p_harvest_grade text,
  p_bucket_halves integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_context jsonb;
begin
  v_context := atlas.owner_operator_context_v1(p_effective_membership_id);
  return atlas.record_weekly_harvest_row_core_v3(
    p_task_id,
    p_crop_cycle_id,
    (v_context#>>'{effective,membershipId}')::uuid,
    v_context#>>'{effective,role}',
    p_result_kind,
    p_harvest_grade,
    p_bucket_halves,
    p_idempotency_key,
    true
  );
end;
$function$;

revoke all on function atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,uuid,text,text,integer,text) from public;
grant execute on function atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,uuid,text,text,integer,text) to authenticated;
grant execute on function atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,uuid,text,text,integer,text) to service_role;

COMMIT;

begin;

-- Flower Preparation public command membrane v2.
-- Browser callers receive one fixed public delegate. Canonical directive semantics,
-- Operating Knowledge resolution, review completion, and work release remain owned by
-- atlas.record_flower_preparation_directive_v2 -> unchanged v1.

do $preflight$
begin
  if to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v2 command authority is missing.';
  end if;
end
$preflight$;

create or replace function public.record_flower_preparation_directive_self_api_v2(
  p_owner_review_task_id uuid,
  p_lines jsonb,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_preparation_directive_v2(
    p_owner_review_task_id,
    p_lines,
    p_note,
    p_idempotency_key
  );
$function$;

comment on function public.record_flower_preparation_directive_self_api_v2(uuid,jsonb,text,text) is
  'Authenticated browser membrane for Flower Preparation v2. Delegates unchanged to Atlas-owned directive authority; does not establish Harvest, Ready, Worker Day, Company Work, or Operating Knowledge truth itself.';

revoke all on function public.record_flower_preparation_directive_self_api_v2(uuid,jsonb,text,text)
  from public, anon;
grant execute on function public.record_flower_preparation_directive_self_api_v2(uuid,jsonb,text,text)
  to authenticated, service_role;

do $verification$
declare
  v_oid oid;
  v_def text;
begin
  select p.oid, pg_get_functiondef(p.oid)
  into v_oid, v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'record_flower_preparation_directive_self_api_v2'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text, text';

  if v_oid is null then
    raise exception 'Public Flower Preparation v2 command membrane was not found.';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'Authenticated Flower Preparation v2 browser execution was not enabled.';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'Anonymous Flower Preparation v2 browser execution must remain disabled.';
  end if;
  if position('atlas.record_flower_preparation_directive_v2' in v_def) = 0 then
    raise exception 'Public Flower Preparation v2 membrane no longer delegates to Atlas-owned authority.';
  end if;
end
$verification$;

commit;

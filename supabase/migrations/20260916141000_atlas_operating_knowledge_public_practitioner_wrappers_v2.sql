begin;

-- Browser/PostgREST membrane for the already-governed Atlas practitioner
-- Operating Knowledge API. These public functions add no authority: each call
-- delegates to an existing atlas.* self-authorized function, where practitioner
-- custody and mutation rules remain authoritative.

do $preflight$
declare
  v_missing text[] := '{}'::text[];
begin
  if to_regprocedure('atlas.operating_knowledge_workbench_self_api_v1()') is null then
    v_missing := array_append(v_missing, 'atlas.operating_knowledge_workbench_self_api_v1()');
  end if;
  if to_regprocedure('atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)') is null then
    v_missing := array_append(v_missing, 'atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)');
  end if;
  if to_regprocedure('atlas.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric)') is null then
    v_missing := array_append(v_missing, 'atlas.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric)');
  end if;
  if to_regprocedure('atlas.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)') is null then
    v_missing := array_append(v_missing, 'atlas.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)');
  end if;
  if to_regprocedure('atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz)') is null then
    v_missing := array_append(v_missing, 'atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz)');
  end if;
  if to_regprocedure('atlas.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)') is null then
    v_missing := array_append(v_missing, 'atlas.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)');
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Operating Knowledge public membrane prerequisites are missing: %', array_to_string(v_missing, ', ');
  end if;
end;
$preflight$;

create or replace function public.operating_knowledge_workbench_self_api_v1()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.operating_knowledge_workbench_self_api_v1();
$function$;

create or replace function public.propose_operating_knowledge_practitioner_self_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_family_key text,
  p_stable_key text,
  p_knowledge_kind text,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null,
  p_evidence_kind text default null,
  p_evidence_note text default null
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.propose_operating_knowledge_practitioner_self_api_v1(
    p_organization_id,
    p_organization_unit_id,
    p_family_key,
    p_stable_key,
    p_knowledge_kind,
    p_title,
    p_statement,
    p_scope_match,
    p_effect,
    p_precedence,
    p_confidence,
    p_evidence_kind,
    p_evidence_note
  );
$function$;

create or replace function public.revise_operating_knowledge_candidate_practitioner_self_v1(
  p_knowledge_id uuid,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.revise_operating_knowledge_candidate_practitioner_self_v1(
    p_knowledge_id,
    p_title,
    p_statement,
    p_scope_match,
    p_effect,
    p_precedence,
    p_confidence
  );
$function$;

create or replace function public.add_operating_knowledge_evidence_practitioner_self_v1(
  p_knowledge_id uuid,
  p_evidence_kind text,
  p_interpretation_kind text,
  p_source_locator jsonb default '{}'::jsonb,
  p_evidence_snapshot jsonb default '{}'::jsonb,
  p_note text default null,
  p_observed_at timestamptz default now()
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.add_operating_knowledge_evidence_practitioner_self_v1(
    p_knowledge_id,
    p_evidence_kind,
    p_interpretation_kind,
    p_source_locator,
    p_evidence_snapshot,
    p_note,
    p_observed_at
  );
$function$;

create or replace function public.adjudicate_operating_knowledge_practitioner_self_v1(
  p_knowledge_id uuid,
  p_decision_kind text,
  p_basis text,
  p_authority_label text,
  p_effective_from timestamptz default null
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.adjudicate_operating_knowledge_practitioner_self_v1(
    p_knowledge_id,
    p_decision_kind,
    p_basis,
    p_authority_label,
    p_effective_from
  );
$function$;

create or replace function public.replace_operating_knowledge_practitioner_self_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_knowledge_id uuid,
  p_title text,
  p_statement text,
  p_scope_match jsonb,
  p_effect jsonb,
  p_precedence integer default 0,
  p_confidence numeric default null,
  p_evidence_kind text default null,
  p_evidence_note text default null
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.replace_operating_knowledge_practitioner_self_api_v1(
    p_organization_id,
    p_organization_unit_id,
    p_knowledge_id,
    p_title,
    p_statement,
    p_scope_match,
    p_effect,
    p_precedence,
    p_confidence,
    p_evidence_kind,
    p_evidence_note
  );
$function$;

revoke all on function public.operating_knowledge_workbench_self_api_v1() from public, anon;
revoke all on function public.propose_operating_knowledge_practitioner_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) from public, anon;
revoke all on function public.revise_operating_knowledge_candidate_practitioner_self_v1(uuid, text, text, jsonb, jsonb, integer, numeric) from public, anon;
revoke all on function public.add_operating_knowledge_evidence_practitioner_self_v1(uuid, text, text, jsonb, jsonb, text, timestamptz) from public, anon;
revoke all on function public.adjudicate_operating_knowledge_practitioner_self_v1(uuid, text, text, text, timestamptz) from public, anon;
revoke all on function public.replace_operating_knowledge_practitioner_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) from public, anon;

grant execute on function public.operating_knowledge_workbench_self_api_v1() to authenticated, service_role;
grant execute on function public.propose_operating_knowledge_practitioner_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) to authenticated, service_role;
grant execute on function public.revise_operating_knowledge_candidate_practitioner_self_v1(uuid, text, text, jsonb, jsonb, integer, numeric) to authenticated, service_role;
grant execute on function public.add_operating_knowledge_evidence_practitioner_self_v1(uuid, text, text, jsonb, jsonb, text, timestamptz) to authenticated, service_role;
grant execute on function public.adjudicate_operating_knowledge_practitioner_self_v1(uuid, text, text, text, timestamptz) to authenticated, service_role;
grant execute on function public.replace_operating_knowledge_practitioner_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) to authenticated, service_role;

comment on function public.operating_knowledge_workbench_self_api_v1() is
  'Browser membrane for the authority-checked Atlas practitioner Operating Knowledge workbench. Adds no authority.';
comment on function public.propose_operating_knowledge_practitioner_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) is
  'Browser membrane for proposing Company Operating Knowledge through existing practitioner authority.';
comment on function public.revise_operating_knowledge_candidate_practitioner_self_v1(uuid, text, text, jsonb, jsonb, integer, numeric) is
  'Browser membrane for revising a candidate Company Operating Knowledge record through existing practitioner authority.';
comment on function public.add_operating_knowledge_evidence_practitioner_self_v1(uuid, text, text, jsonb, jsonb, text, timestamptz) is
  'Browser membrane for attaching evidence to Company Operating Knowledge through existing practitioner authority.';
comment on function public.adjudicate_operating_knowledge_practitioner_self_v1(uuid, text, text, text, timestamptz) is
  'Browser membrane for governed practitioner Operating Knowledge adjudication. The atlas.* function remains authoritative.';
comment on function public.replace_operating_knowledge_practitioner_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) is
  'Browser membrane for proposing a replacement Operating Knowledge version through existing practitioner authority.';

commit;

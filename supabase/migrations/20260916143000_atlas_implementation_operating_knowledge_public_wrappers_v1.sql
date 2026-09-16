begin;

-- Browser/PostgREST membrane for implementation-case Operating Knowledge.
-- These public functions add no authority; they delegate to existing atlas.*
-- functions that own implementation-case custody and practitioner authorization.

do $preflight$
declare
  v_missing text[] := '{}'::text[];
begin
  if to_regprocedure('atlas.implementation_operating_knowledge_self_api_v1(uuid)') is null then
    v_missing := array_append(v_missing, 'atlas.implementation_operating_knowledge_self_api_v1(uuid)');
  end if;
  if to_regprocedure('atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)') is null then
    v_missing := array_append(v_missing, 'atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)');
  end if;
  if to_regprocedure('atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric)') is null then
    v_missing := array_append(v_missing, 'atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric)');
  end if;
  if to_regprocedure('atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)') is null then
    v_missing := array_append(v_missing, 'atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)');
  end if;
  if to_regprocedure('atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz)') is null then
    v_missing := array_append(v_missing, 'atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz)');
  end if;
  if to_regprocedure('atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz)') is null then
    v_missing := array_append(v_missing, 'atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz)');
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Implementation Operating Knowledge public membrane prerequisites are missing: %', array_to_string(v_missing, ', ');
  end if;
end;
$preflight$;

create or replace function public.implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.implementation_operating_knowledge_self_api_v1(p_implementation_case_id);
$function$;

create or replace function public.propose_implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
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
  select atlas.propose_implementation_operating_knowledge_self_api_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
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

create or replace function public.revise_implementation_operating_knowledge_candidate_self_v1(
  p_implementation_case_id uuid,
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
  select atlas.revise_implementation_operating_knowledge_candidate_self_v1(
    p_implementation_case_id,
    p_knowledge_id,
    p_title,
    p_statement,
    p_scope_match,
    p_effect,
    p_precedence,
    p_confidence
  );
$function$;

create or replace function public.replace_implementation_operating_knowledge_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
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
  select atlas.replace_implementation_operating_knowledge_self_api_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
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

create or replace function public.add_implementation_operating_knowledge_evidence_self_v1(
  p_implementation_case_id uuid,
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
  select atlas.add_implementation_operating_knowledge_evidence_self_v1(
    p_implementation_case_id,
    p_knowledge_id,
    p_evidence_kind,
    p_interpretation_kind,
    p_source_locator,
    p_evidence_snapshot,
    p_note,
    p_observed_at
  );
$function$;

create or replace function public.adjudicate_implementation_operating_knowledge_self_v1(
  p_implementation_case_id uuid,
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
  select atlas.adjudicate_implementation_operating_knowledge_self_v1(
    p_implementation_case_id,
    p_knowledge_id,
    p_decision_kind,
    p_basis,
    p_authority_label,
    p_effective_from
  );
$function$;

revoke all on function public.implementation_operating_knowledge_self_api_v1(uuid) from public, anon;
revoke all on function public.propose_implementation_operating_knowledge_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) from public, anon;
revoke all on function public.revise_implementation_operating_knowledge_candidate_self_v1(uuid, uuid, text, text, jsonb, jsonb, integer, numeric) from public, anon;
revoke all on function public.replace_implementation_operating_knowledge_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) from public, anon;
revoke all on function public.add_implementation_operating_knowledge_evidence_self_v1(uuid, uuid, text, text, jsonb, jsonb, text, timestamptz) from public, anon;
revoke all on function public.adjudicate_implementation_operating_knowledge_self_v1(uuid, uuid, text, text, text, timestamptz) from public, anon;

grant execute on function public.implementation_operating_knowledge_self_api_v1(uuid) to authenticated, service_role;
grant execute on function public.propose_implementation_operating_knowledge_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) to authenticated, service_role;
grant execute on function public.revise_implementation_operating_knowledge_candidate_self_v1(uuid, uuid, text, text, jsonb, jsonb, integer, numeric) to authenticated, service_role;
grant execute on function public.replace_implementation_operating_knowledge_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) to authenticated, service_role;
grant execute on function public.add_implementation_operating_knowledge_evidence_self_v1(uuid, uuid, text, text, jsonb, jsonb, text, timestamptz) to authenticated, service_role;
grant execute on function public.adjudicate_implementation_operating_knowledge_self_v1(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

comment on function public.implementation_operating_knowledge_self_api_v1(uuid) is
  'Browser membrane for implementation-case Operating Knowledge. Existing atlas.* implementation authority remains authoritative.';
comment on function public.propose_implementation_operating_knowledge_self_api_v1(uuid, uuid, text, text, text, text, text, jsonb, jsonb, integer, numeric, text, text) is
  'Browser membrane for proposing implementation-case Operating Knowledge through existing Atlas authority.';
comment on function public.revise_implementation_operating_knowledge_candidate_self_v1(uuid, uuid, text, text, jsonb, jsonb, integer, numeric) is
  'Browser membrane for revising an implementation-case Operating Knowledge candidate through existing Atlas authority.';
comment on function public.replace_implementation_operating_knowledge_self_api_v1(uuid, uuid, uuid, text, text, jsonb, jsonb, integer, numeric, text, text) is
  'Browser membrane for proposing a replacement implementation-case Operating Knowledge version through existing Atlas authority.';
comment on function public.add_implementation_operating_knowledge_evidence_self_v1(uuid, uuid, text, text, jsonb, jsonb, text, timestamptz) is
  'Browser membrane for implementation-case Operating Knowledge evidence through existing Atlas authority.';
comment on function public.adjudicate_implementation_operating_knowledge_self_v1(uuid, uuid, text, text, text, timestamptz) is
  'Browser membrane for implementation-case Operating Knowledge adjudication through existing Atlas authority.';

commit;

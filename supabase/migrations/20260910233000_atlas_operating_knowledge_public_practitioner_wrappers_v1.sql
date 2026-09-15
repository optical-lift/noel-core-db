-- Public PostgREST wrappers for the governed Atlas practitioner Operating Knowledge API.
-- The browser client only exposes public-schema RPCs; authority remains enforced inside atlas.*.

BEGIN;

create or replace function public.operating_knowledge_workbench_self_api_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.operating_knowledge_workbench_self_api_v1();
$$;

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
security definer
set search_path = pg_catalog
as $$
  select atlas.propose_operating_knowledge_practitioner_self_api_v1(
    p_organization_id,p_organization_unit_id,p_family_key,p_stable_key,p_knowledge_kind,
    p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence,p_evidence_kind,p_evidence_note
  );
$$;

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
security definer
set search_path = pg_catalog
as $$
  select atlas.revise_operating_knowledge_candidate_practitioner_self_v1(
    p_knowledge_id,p_title,p_statement,p_scope_match,p_effect,p_precedence,p_confidence
  );
$$;

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
security definer
set search_path = pg_catalog
as $$
  select atlas.add_operating_knowledge_evidence_practitioner_self_v1(
    p_knowledge_id,p_evidence_kind,p_interpretation_kind,p_source_locator,p_evidence_snapshot,p_note,p_observed_at
  );
$$;

create or replace function public.adjudicate_operating_knowledge_practitioner_self_v1(
  p_knowledge_id uuid,
  p_decision_kind text,
  p_basis text,
  p_authority_label text,
  p_effective_from timestamptz default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.adjudicate_operating_knowledge_practitioner_self_v1(
    p_knowledge_id,p_decision_kind,p_basis,p_authority_label,p_effective_from
  );
$$;

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
security definer
set search_path = pg_catalog
as $$
  select atlas.replace_operating_knowledge_practitioner_self_api_v1(
    p_organization_id,p_organization_unit_id,p_knowledge_id,p_title,p_statement,p_scope_match,p_effect,
    p_precedence,p_confidence,p_evidence_kind,p_evidence_note
  );
$$;

revoke all on function public.operating_knowledge_workbench_self_api_v1() from public, anon;
revoke all on function public.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) from public, anon;
revoke all on function public.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric) from public, anon;
revoke all on function public.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) from public, anon;
revoke all on function public.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz) from public, anon;
revoke all on function public.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) from public, anon;

grant execute on function public.operating_knowledge_workbench_self_api_v1() to authenticated;
grant execute on function public.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;
grant execute on function public.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric) to authenticated;
grant execute on function public.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamptz) to authenticated;
grant execute on function public.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamptz) to authenticated;
grant execute on function public.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text) to authenticated;

COMMIT;

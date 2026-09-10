-- Canonical postconditions for Company Operating Knowledge operator/practitioner API v1.
-- Runs only against the disposable production-schema clone.

do $$
declare
  v_missing text[];
  v_def text;
  v_status_def text;
begin
  select array_agg(name order by name) into v_missing
  from (values
    ('atlas.implementation_operating_knowledge_self_api_v1(uuid)'),
    ('atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)'),
    ('atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric)'),
    ('atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamp with time zone)'),
    ('atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamp with time zone)'),
    ('atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)'),
    ('atlas.company_operating_knowledge_service_api_v1(uuid,uuid,boolean)'),
    ('atlas.propose_company_operating_knowledge_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,text,integer,numeric,uuid,text)'),
    ('atlas.add_company_operating_knowledge_evidence_service_v1(uuid,text,text,jsonb,jsonb,text,timestamp with time zone)'),
    ('atlas.adjudicate_company_operating_knowledge_service_v1(uuid,text,text,text,text,timestamp with time zone)')
  ) x(name)
  where to_regprocedure(name) is null;
  if v_missing is not null then raise exception 'Operating Knowledge API functions missing: %',v_missing; end if;

  if not exists(select 1 from information_schema.columns where table_schema='atlas' and table_name='company_operating_knowledge_adjudications' and column_name='recorded_by_user_id')
     or not exists(select 1 from information_schema.columns where table_schema='atlas' and table_name='company_operating_knowledge_adjudications' and column_name='recorded_by_label') then
    raise exception 'Operating Knowledge adjudication recorder columns are missing.';
  end if;

  select pg_get_constraintdef(oid) into v_status_def
  from pg_constraint where conrelid='atlas.company_operating_knowledge'::regclass and conname='company_operating_knowledge_status_check';
  if v_status_def is null or position('rejected' in v_status_def)=0 then
    raise exception 'Rejected candidate status is not represented explicitly.';
  end if;

  select pg_get_functiondef('atlas.guard_established_company_operating_knowledge_mutation_v1()'::regprocedure) into v_def;
  if position('old.established_at is not null' in lower(v_def))=0 then
    raise exception 'Previously established semantics can become editable after status transition.';
  end if;

  -- Authenticated practitioners may call practitioner wrappers, but never internal/service seams.
  if not has_function_privilege('authenticated','atlas.implementation_operating_knowledge_self_api_v1(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamp with time zone)','EXECUTE') then
    raise exception 'Authenticated practitioner wrapper grants are incomplete.';
  end if;

  if has_function_privilege('anon','atlas.implementation_operating_knowledge_self_api_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)','EXECUTE') then
    raise exception 'Anonymous role can access Operating Knowledge practitioner APIs.';
  end if;

  if has_function_privilege('authenticated','atlas.company_operating_knowledge_service_api_v1(uuid,uuid,boolean)','EXECUTE')
     or has_function_privilege('authenticated','atlas.propose_company_operating_knowledge_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,text,integer,numeric,uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.adjudicate_company_operating_knowledge_service_v1(uuid,text,text,text,text,timestamp with time zone)','EXECUTE') then
    raise exception 'Authenticated users can call delegated/service Operating Knowledge APIs.';
  end if;

  if not has_function_privilege('service_role','atlas.company_operating_knowledge_service_api_v1(uuid,uuid,boolean)','EXECUTE')
     or not has_function_privilege('service_role','atlas.propose_company_operating_knowledge_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,text,integer,numeric,uuid,text)','EXECUTE')
     or not has_function_privilege('service_role','atlas.adjudicate_company_operating_knowledge_service_v1(uuid,text,text,text,text,timestamp with time zone)','EXECUTE') then
    raise exception 'Service-role Operating Knowledge API grants are incomplete.';
  end if;

  if has_function_privilege('authenticated','atlas.company_operating_knowledge_propose_internal_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('service_role','atlas.company_operating_knowledge_propose_internal_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,uuid,uuid,text,text)','EXECUTE') then
    raise exception 'Internal Operating Knowledge mutation primitive leaked direct EXECUTE.';
  end if;

  select pg_get_functiondef('atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)'::regprocedure) into v_def;
  if position('implementation_practitioner_authorized_self_v1' in v_def)=0
     or position('implementation_operating_scope_internal_v1' in v_def)=0 then
    raise exception 'Practitioner proposal lost practitioner authority or Ledger-binding scope enforcement.';
  end if;

  select pg_get_functiondef('atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamp with time zone)'::regprocedure) into v_def;
  if position('implementation_practitioner_authorized_self_v1' in v_def)=0
     or position('company_operating_knowledge_adjudicate_internal_v1' in v_def)=0 then
    raise exception 'Practitioner adjudication lost authority/lifecycle boundary.';
  end if;

  select pg_get_functiondef('atlas.company_operating_knowledge_adjudicate_internal_v1(uuid,text,text,text,uuid,text,timestamp with time zone)'::regprocedure) into v_def;
  if position('replacementKnowledgeId' in v_def)=0 or position('status=''superseded''' in replace(v_def,' ',''))=0 then
    raise exception 'Replacement establishment no longer accounts for supersession.';
  end if;

  -- Runtime resolver must remain established-only after adding rejected/disputed lifecycle states.
  select pg_get_functiondef('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)'::regprocedure) into v_def;
  if position('status = ''established''' in v_def)=0 then
    raise exception 'Runtime resolver no longer limits execution context to established knowledge.';
  end if;
end;
$$;

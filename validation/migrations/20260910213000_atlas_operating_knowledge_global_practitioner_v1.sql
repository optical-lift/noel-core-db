-- Postconditions for global practitioner Operating Knowledge workbench v1.

do $$
declare v_def text;
begin
  if to_regprocedure('atlas.operating_knowledge_workbench_self_api_v1()') is null
     or to_regprocedure('atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)') is null
     or to_regprocedure('atlas.revise_operating_knowledge_candidate_practitioner_self_v1(uuid,text,text,jsonb,jsonb,integer,numeric)') is null
     or to_regprocedure('atlas.add_operating_knowledge_evidence_practitioner_self_v1(uuid,text,text,jsonb,jsonb,text,timestamp with time zone)') is null
     or to_regprocedure('atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamp with time zone)') is null
     or to_regprocedure('atlas.replace_operating_knowledge_practitioner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)') is null then
    raise exception 'Global practitioner Operating Knowledge RPC surface is incomplete.';
  end if;

  if not has_function_privilege('authenticated','atlas.operating_knowledge_workbench_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamp with time zone)','EXECUTE') then
    raise exception 'Authenticated practitioner grants are incomplete.';
  end if;

  if has_function_privilege('anon','atlas.operating_knowledge_workbench_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)','EXECUTE') then
    raise exception 'Anonymous role can access global practitioner Operating Knowledge.';
  end if;

  select pg_get_functiondef('atlas.operating_knowledge_workbench_self_api_v1()'::regprocedure) into v_def;
  if position('implementation_practitioner_authorized_self_v1' in v_def)=0
     or position('organizationUnitName' in v_def)=0
     or position('knowledgeCount' in v_def)=0 then
    raise exception 'Global workbench lost practitioner gate or organization-unit projection.';
  end if;

  select pg_get_functiondef('atlas.propose_operating_knowledge_practitioner_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)'::regprocedure) into v_def;
  if position('implementation_practitioner_authorized_self_v1' in v_def)=0
     or position('company_operating_knowledge_propose_internal_v1' in v_def)=0
     or position('organization_units' in v_def)=0 then
    raise exception 'Global proposal lost practitioner gate, lifecycle primitive, or scope validation.';
  end if;

  select pg_get_functiondef('atlas.adjudicate_operating_knowledge_practitioner_self_v1(uuid,text,text,text,timestamp with time zone)'::regprocedure) into v_def;
  if position('company_operating_knowledge_adjudicate_internal_v1' in v_def)=0 then
    raise exception 'Global adjudication bypasses shared lifecycle primitive.';
  end if;
end;
$$;

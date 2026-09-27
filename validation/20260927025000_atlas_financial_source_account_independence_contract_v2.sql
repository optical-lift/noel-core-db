-- Contract validation: connector-independent financial source accounts v2

begin;

do $$
declare
  v_def text;
  v_bad_grants integer;
begin
  if to_regclass('atlas.financial_source_accounts') is null then
    raise exception 'Missing atlas.financial_source_accounts';
  end if;
  if to_regclass('atlas.financial_source_account_connector_links') is null then
    raise exception 'Missing atlas.financial_source_account_connector_links';
  end if;
  if to_regclass('atlas.financial_source_account_reality_holders') is null then
    raise exception 'Missing atlas.financial_source_account_reality_holders';
  end if;
  if to_regclass('atlas.financial_source_evidence_observations') is null then
    raise exception 'Missing atlas.financial_source_evidence_observations';
  end if;

  if to_regprocedure('atlas.register_financial_source_account_self_api_v2(text,text,text,text,text,text,text,jsonb,jsonb)') is null then
    raise exception 'Missing register_financial_source_account_self_api_v2';
  end if;
  if to_regprocedure('atlas.financial_source_account_authorized_self_v2(uuid)') is null then
    raise exception 'Missing financial_source_account_authorized_self_v2';
  end if;
  if to_regprocedure('atlas.link_financial_source_account_connector_self_api_v2(uuid,uuid,text,jsonb,jsonb)') is null then
    raise exception 'Missing link_financial_source_account_connector_self_api_v2';
  end if;
  if to_regprocedure('atlas.designate_financial_source_account_holder_self_api_v2(uuid,uuid,jsonb,jsonb)') is null then
    raise exception 'Missing designate_financial_source_account_holder_self_api_v2';
  end if;
  if to_regprocedure('atlas.financial_source_account_holders_self_api_v2(uuid)') is null then
    raise exception 'Missing financial_source_account_holders_self_api_v2';
  end if;
  if to_regprocedure('atlas.record_financial_source_evidence_service_v2(uuid,text,text,text,jsonb,timestamptz,uuid,jsonb,jsonb)') is null then
    raise exception 'Missing record_financial_source_evidence_service_v2';
  end if;

  if not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='financial_source_accounts' and c.relrowsecurity
  ) then
    raise exception 'financial_source_accounts must have RLS enabled';
  end if;
  if not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='financial_source_evidence_observations' and c.relrowsecurity
  ) then
    raise exception 'financial_source_evidence_observations must have RLS enabled';
  end if;

  select count(*) into v_bad_grants
  from information_schema.role_table_grants
  where table_schema='atlas'
    and table_name in (
      'financial_source_accounts',
      'financial_source_account_connector_links',
      'financial_source_account_reality_holders',
      'financial_source_evidence_observations'
    )
    and grantee in ('anon','authenticated');
  if v_bad_grants<>0 then
    raise exception 'Financial source account v2 tables must not expose direct anon/authenticated grants';
  end if;

  select pg_get_functiondef('atlas.register_financial_source_account_self_api_v2(text,text,text,text,text,text,text,jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('connectorAuthorizationRequired' in v_def)=0
     or position('document_reconstruction' in v_def)=0 then
    raise exception 'Account registration must preserve connector independence and document reconstruction';
  end if;

  select pg_get_functiondef('atlas.record_financial_source_evidence_service_v2(uuid,text,text,text,jsonb,timestamptz,uuid,jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('atlas.evidence_records' in v_def)=0 then
    raise exception 'Financial source observations must use the universal evidence kernel';
  end if;
  if position('p_connected_source_observation_id is not null' in lower(v_def))=0 then
    raise exception 'Connector observation must remain optional in the v2 evidence service';
  end if;
  if position('evidenceDoesNotCreateBookkeepingInterpretation' in v_def)=0 then
    raise exception 'Financial evidence service must state the evidence/interpretation boundary';
  end if;

  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='atlas'
      and t.relname='financial_source_accounts'
      and c.contype='u'
      and pg_get_constraintdef(c.oid) like '%custodian_user_id%source_system_key%source_account_key%'
  ) then
    raise exception 'Financial source account identity must be stable within technical custody';
  end if;

  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='atlas'
      and t.relname='financial_source_account_reality_holders'
      and c.contype='u'
      and pg_get_constraintdef(c.oid) like '%financial_source_account_id%holder_entity_id%'
  ) then
    raise exception 'Reality account holders must attach to the financial account, not connector custody';
  end if;
end;
$$;

rollback;

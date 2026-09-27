-- Contract validation: atomic provider-neutral financial statement packet ingestion v2

begin;

do $$
declare
  v_def text;
  v_service_granted boolean;
  v_authenticated_granted boolean;
begin
  if to_regprocedure('atlas.ingest_financial_statement_packet_service_v2(uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)') is null then
    raise exception 'Missing ingest_financial_statement_packet_service_v2';
  end if;

  select pg_get_functiondef(
    'atlas.ingest_financial_statement_packet_service_v2(uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)'::regprocedure
  ) into v_def;

  if position('record_financial_source_evidence_service_v2' in v_def)=0
     or position('record_financial_source_transaction_service_v2' in v_def)=0
     or position('record_financial_source_statement_service_v2' in v_def)=0
     or position('link_financial_source_statement_transactions_service_v2' in v_def)=0
     or position('financial_source_statement_reconciliation_core_v2' in v_def)=0 then
    raise exception 'Statement packet ingestion must orchestrate evidence, stable identities, statement membership, and reconciliation';
  end if;

  if position("v_item->>'key'" in v_def)=0
     or position("v_item->'sourcePayload'" in v_def)=0
     or position('stable source transaction key' in v_def)=0 then
    raise exception 'Packet ingestion must require adapter-supplied stable transaction identity and source row snapshots';
  end if;

  if position('replace_financial_source_transaction_review' in v_def)>0
     or position('financial_source_transaction_allocations' in v_def)>0
     or position('record_organization_spend' in v_def)>0
     or position('promote_financial_source_transaction_expense' in v_def)>0 then
    raise exception 'Statement packet ingestion must not create bookkeeping interpretation, allocation, or Spend';
  end if;

  if position('atomicPacket' in v_def)=0
     or position('reconciliationDoesNotClassifyBookkeepingMeaning' in v_def)=0
     or position("'reviewCreated',false" in v_def)=0
     or position("'spendCreated',false" in v_def)=0 then
    raise exception 'Packet ingestion must state its evidence/reconciliation truth boundary';
  end if;

  select has_function_privilege(
    'service_role',
    'atlas.ingest_financial_statement_packet_service_v2(uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)',
    'EXECUTE'
  ) into v_service_granted;
  select has_function_privilege(
    'authenticated',
    'atlas.ingest_financial_statement_packet_service_v2(uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)',
    'EXECUTE'
  ) into v_authenticated_granted;

  if not v_service_granted or v_authenticated_granted then
    raise exception 'Statement packet ingestion must remain service-side only';
  end if;
end;
$$;

rollback;

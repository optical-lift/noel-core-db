-- Governed financial transaction observation intake v1
--
-- Provider/document adapters submit exact raw source payload plus normalized transaction facts
-- in one service call. Raw payload custody is established first through the existing connected
-- source observation service; normalization then points to that exact observation.

create or replace function atlas.record_financial_source_transaction_observation_service_v1(
  p_connected_source_id uuid,
  p_provider_transaction_key text,
  p_raw_payload jsonb,
  p_provider_created_at timestamptz,
  p_observed_at timestamptz,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_source_amount numeric,
  p_currency text,
  p_raw_description text default null,
  p_source_party_label text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, extensions
as $$
declare
  v_key text:=btrim(coalesce(p_provider_transaction_key,''));
  v_payload jsonb:=coalesce(p_raw_payload,'{}'::jsonb);
  v_provenance jsonb:=coalesce(p_provenance,'{}'::jsonb);
  v_batch jsonb;
  v_hash text;
  v_observation_id uuid;
  v_transaction jsonb;
begin
  if p_connected_source_id is null or v_key='' or jsonb_typeof(v_payload)<>'object' then
    raise exception 'Connected source, provider transaction key, and raw object payload are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(v_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Financial observation provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  v_batch:=atlas.record_connected_source_observation_batch_service_v1(
    p_connected_source_id,
    'financial_transaction',
    jsonb_build_array(jsonb_build_object(
      'key',v_key,
      'providerCreatedAt',p_provider_created_at,
      'payload',v_payload
    )),
    coalesce(p_observed_at,now()),
    v_provenance || jsonb_build_object(
      'financialIntakeContract','record_financial_source_transaction_observation_service_v1'
    )
  );

  v_hash:=encode(extensions.digest(convert_to(v_payload::text,'utf8'),'sha256'),'hex');

  select observation.id
  into v_observation_id
  from atlas.connected_source_observations observation
  where observation.connected_source_id=p_connected_source_id
    and observation.provider_object_kind='financial_transaction'
    and observation.provider_object_key=v_key
    and observation.payload_sha256=v_hash
  order by observation.observed_at desc,observation.id desc
  limit 1;

  if v_observation_id is null then
    raise exception 'Connected-source observation was not established for the financial transaction.' using errcode='55000';
  end if;

  v_transaction:=atlas.record_financial_source_transaction_service_v1(
    p_connected_source_id,
    v_key,
    v_observation_id,
    p_occurred_on,
    p_occurred_at,
    p_source_amount,
    p_currency,
    p_raw_description,
    p_source_party_label,
    v_provenance || jsonb_build_object(
      'sourceObservationId',v_observation_id,
      'payloadSha256',v_hash
    ),
    p_metadata
  );

  return jsonb_build_object(
    'contractVersion','record_financial_source_transaction_observation_service_v1',
    'connectedSourceId',p_connected_source_id,
    'providerTransactionKey',v_key,
    'sourceObservationId',v_observation_id,
    'payloadSha256',v_hash,
    'observationBatch',v_batch,
    'transaction',v_transaction
  );
end;
$$;

revoke all on function atlas.record_financial_source_transaction_observation_service_v1(
  uuid,text,jsonb,timestamptz,timestamptz,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function atlas.record_financial_source_transaction_observation_service_v1(
  uuid,text,jsonb,timestamptz,timestamptz,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) to service_role;

comment on function atlas.record_financial_source_transaction_observation_service_v1(
  uuid,text,jsonb,timestamptz,timestamptz,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) is
  'Admits an exact connected-source financial transaction observation before establishing or refreshing its stable normalized transaction identity. Service-only; does not classify or promote accounting truth.';

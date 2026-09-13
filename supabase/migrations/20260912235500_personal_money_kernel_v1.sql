begin;

-- Personal Money v1 separates provider observations from economic truth.
-- connected_source_observations remain evidence. Only this adjudicated Money
-- layer may say that a movement is spend, income, transfer, refund, etc.

create table atlas.personal_money_transactions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  source_observation_id uuid references atlas.connected_source_observations(id) on delete restrict,
  source_system_key text not null check (length(btrim(source_system_key))>0),
  source_record_key text not null check (length(btrim(source_record_key))>0),
  occurred_at timestamptz not null,
  posted_at timestamptz,
  amount_minor bigint not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  economic_kind text not null check (economic_kind in ('spend','income','transfer','refund','fee','interest','adjustment','unknown')),
  classification_state text not null check (classification_state in ('established','ambiguous')),
  merchant_name text,
  description text,
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  revision integer not null default 1 check (revision>0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint personal_money_established_kind_ck check (classification_state<>'established' or economic_kind<>'unknown'),
  constraint personal_money_source_observation_pair_ck check (
    (connected_source_id is null and source_observation_id is null)
    or connected_source_id is not null
  ),
  unique(principal_id,source_system_key,source_record_key)
);

comment on table atlas.personal_money_transactions is
  'Canonical Personal Money interpretation of observed/manual movements. Provider rows are evidence only; this table owns economic classification such as spend versus transfer.';

create index personal_money_transactions_principal_time_idx
  on atlas.personal_money_transactions(principal_id,occurred_at,id);
create index personal_money_transactions_principal_kind_time_idx
  on atlas.personal_money_transactions(principal_id,economic_kind,occurred_at,id);
create index personal_money_transactions_source_idx
  on atlas.personal_money_transactions(connected_source_id,source_record_key) where connected_source_id is not null;

create table atlas.personal_money_transaction_events (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.personal_money_transactions(id) on delete cascade,
  revision integer not null check (revision>0),
  event_kind text not null check (event_kind in ('created','revised')),
  reason text not null check (length(btrim(reason))>0),
  snapshot jsonb not null check (jsonb_typeof(snapshot)='object'),
  created_at timestamptz not null default now(),
  unique(transaction_id,revision)
);

comment on table atlas.personal_money_transaction_events is
  'Append-only revision evidence for canonical Personal Money transaction interpretation.';

create or replace function atlas.reject_personal_money_transaction_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  raise exception 'Personal Money transaction events are append-only.' using errcode='55000';
end;
$function$;

create trigger personal_money_transaction_events_append_only
before update or delete on atlas.personal_money_transaction_events
for each row execute function atlas.reject_personal_money_transaction_event_mutation_v1();

alter table atlas.personal_money_transactions enable row level security;
alter table atlas.personal_money_transaction_events enable row level security;
revoke all on atlas.personal_money_transactions from public,anon,authenticated;
revoke all on atlas.personal_money_transaction_events from public,anon,authenticated;
grant select,insert,update on atlas.personal_money_transactions to service_role;
grant select,insert on atlas.personal_money_transaction_events to service_role;

create or replace function atlas.personal_money_transaction_snapshot_v1(p_row atlas.personal_money_transactions)
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select jsonb_build_object(
    'transactionId',p_row.id,
    'principalId',p_row.principal_id,
    'connectedSourceId',p_row.connected_source_id,
    'sourceObservationId',p_row.source_observation_id,
    'sourceSystemKey',p_row.source_system_key,
    'sourceRecordKey',p_row.source_record_key,
    'occurredAt',p_row.occurred_at,
    'postedAt',p_row.posted_at,
    'amountMinor',p_row.amount_minor,
    'currencyCode',p_row.currency_code,
    'economicKind',p_row.economic_kind,
    'classificationState',p_row.classification_state,
    'merchantName',p_row.merchant_name,
    'description',p_row.description,
    'basis',p_row.basis,
    'revision',p_row.revision
  );
$function$;

revoke all on function atlas.personal_money_transaction_snapshot_v1(atlas.personal_money_transactions) from public,anon,authenticated,service_role;

create or replace function atlas.set_personal_money_transaction_service_v1(
  p_principal_id uuid,
  p_source_system_key text,
  p_source_record_key text,
  p_occurred_at timestamptz,
  p_amount_minor bigint,
  p_currency_code text,
  p_economic_kind text,
  p_classification_state text,
  p_connected_source_id uuid default null,
  p_source_observation_id uuid default null,
  p_posted_at timestamptz default null,
  p_merchant_name text default null,
  p_description text default null,
  p_basis jsonb default '{}'::jsonb,
  p_reason text default 'source_adjudication'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_observation atlas.connected_source_observations%rowtype;
  v_row atlas.personal_money_transactions%rowtype;
  v_old atlas.personal_money_transactions%rowtype;
  v_currency text:=upper(btrim(coalesce(p_currency_code,'')));
  v_system text:=btrim(coalesce(p_source_system_key,''));
  v_record text:=btrim(coalesce(p_source_record_key,''));
  v_reason text:=btrim(coalesce(p_reason,''));
  v_basis jsonb:=coalesce(p_basis,'{}'::jsonb);
  v_changed boolean:=false;
begin
  if p_principal_id is null or v_system='' or v_record='' or p_occurred_at is null then
    raise exception 'Principal, source identity, and occurrence time are required.' using errcode='22023';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a three-letter uppercase code.' using errcode='22023'; end if;
  if p_economic_kind not in ('spend','income','transfer','refund','fee','interest','adjustment','unknown') then raise exception 'Unsupported economic kind.' using errcode='22023'; end if;
  if p_classification_state not in ('established','ambiguous') then raise exception 'Unsupported classification state.' using errcode='22023'; end if;
  if p_classification_state='established' and p_economic_kind='unknown' then raise exception 'Unknown economic kind cannot be established.' using errcode='22023'; end if;
  if jsonb_typeof(v_basis)<>'object' or v_reason='' then raise exception 'Basis object and reason are required.' using errcode='22023'; end if;

  select * into v_principal from atlas.principals where id=p_principal_id and status='active';
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='55000'; end if;

  if p_connected_source_id is not null then
    select * into v_source from atlas.connected_sources where id=p_connected_source_id;
    if v_source.id is null or v_source.authorization_state<>'connected' or v_source.custodian_user_id is distinct from v_principal.user_id then
      raise exception 'Personal Money source must be a connected source owned by the Principal user.' using errcode='42501';
    end if;
  elsif p_source_observation_id is not null then
    raise exception 'A source observation requires its connected source.' using errcode='22023';
  end if;

  if p_source_observation_id is not null then
    select * into v_observation from atlas.connected_source_observations where id=p_source_observation_id;
    if v_observation.id is null or v_observation.connected_source_id<>p_connected_source_id then
      raise exception 'Source observation does not belong to the connected source.' using errcode='42501';
    end if;
  end if;

  select * into v_old
  from atlas.personal_money_transactions t
  where t.principal_id=p_principal_id and t.source_system_key=v_system and t.source_record_key=v_record
  for update;

  if v_old.id is null then
    insert into atlas.personal_money_transactions(
      principal_id,connected_source_id,source_observation_id,source_system_key,source_record_key,
      occurred_at,posted_at,amount_minor,currency_code,economic_kind,classification_state,
      merchant_name,description,basis,revision
    ) values(
      p_principal_id,p_connected_source_id,p_source_observation_id,v_system,v_record,
      p_occurred_at,p_posted_at,p_amount_minor,v_currency,p_economic_kind,p_classification_state,
      nullif(btrim(coalesce(p_merchant_name,'')),''),nullif(btrim(coalesce(p_description,'')),''),v_basis,1
    ) returning * into v_row;
    v_changed:=true;
    insert into atlas.personal_money_transaction_events(transaction_id,revision,event_kind,reason,snapshot)
    values(v_row.id,v_row.revision,'created',v_reason,atlas.personal_money_transaction_snapshot_v1(v_row));
  else
    if v_old.connected_source_id is distinct from p_connected_source_id
       or v_old.source_observation_id is distinct from p_source_observation_id
       or v_old.occurred_at is distinct from p_occurred_at
       or v_old.posted_at is distinct from p_posted_at
       or v_old.amount_minor is distinct from p_amount_minor
       or v_old.currency_code is distinct from v_currency
       or v_old.economic_kind is distinct from p_economic_kind
       or v_old.classification_state is distinct from p_classification_state
       or v_old.merchant_name is distinct from nullif(btrim(coalesce(p_merchant_name,'')),'')
       or v_old.description is distinct from nullif(btrim(coalesce(p_description,'')),'')
       or v_old.basis is distinct from v_basis then
      update atlas.personal_money_transactions
      set connected_source_id=p_connected_source_id,
          source_observation_id=p_source_observation_id,
          occurred_at=p_occurred_at,
          posted_at=p_posted_at,
          amount_minor=p_amount_minor,
          currency_code=v_currency,
          economic_kind=p_economic_kind,
          classification_state=p_classification_state,
          merchant_name=nullif(btrim(coalesce(p_merchant_name,'')),''),
          description=nullif(btrim(coalesce(p_description,'')),''),
          basis=v_basis,
          revision=v_old.revision+1,
          updated_at=now()
      where id=v_old.id returning * into v_row;
      v_changed:=true;
      insert into atlas.personal_money_transaction_events(transaction_id,revision,event_kind,reason,snapshot)
      values(v_row.id,v_row.revision,'revised',v_reason,atlas.personal_money_transaction_snapshot_v1(v_row));
    else
      v_row:=v_old;
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,'changed',v_changed,'contractVersion','personal_money_transaction_service_v1',
    'transactionId',v_row.id,'revision',v_row.revision,
    'truthBoundary',jsonb_build_object(
      'providerObservationIsEvidenceOnly',true,
      'moneyLayerOwnsEconomicClassification',true,
      'transferIsNotSpend',true,
      'ambiguousMovementIsNotCountedAsSpend',true
    )
  );
end;
$function$;

revoke all on function atlas.set_personal_money_transaction_service_v1(uuid,text,text,timestamptz,bigint,text,text,text,uuid,uuid,timestamptz,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function atlas.set_personal_money_transaction_service_v1(uuid,text,text,timestamptz,bigint,text,text,text,uuid,uuid,timestamptz,text,text,jsonb,text) to service_role;

create or replace function public.set_personal_money_transaction_service_v1(
  p_principal_id uuid,
  p_source_system_key text,
  p_source_record_key text,
  p_occurred_at timestamptz,
  p_amount_minor bigint,
  p_currency_code text,
  p_economic_kind text,
  p_classification_state text,
  p_connected_source_id uuid default null,
  p_source_observation_id uuid default null,
  p_posted_at timestamptz default null,
  p_merchant_name text default null,
  p_description text default null,
  p_basis jsonb default '{}'::jsonb,
  p_reason text default 'source_adjudication'
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.set_personal_money_transaction_service_v1(
    p_principal_id,p_source_system_key,p_source_record_key,p_occurred_at,p_amount_minor,p_currency_code,
    p_economic_kind,p_classification_state,p_connected_source_id,p_source_observation_id,p_posted_at,
    p_merchant_name,p_description,p_basis,p_reason
  );
$function$;

revoke all on function public.set_personal_money_transaction_service_v1(uuid,text,text,timestamptz,bigint,text,text,text,uuid,uuid,timestamptz,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.set_personal_money_transaction_service_v1(uuid,text,text,timestamptz,bigint,text,text,text,uuid,uuid,timestamptz,text,text,jsonb,text) to service_role;

create or replace function atlas.personal_money_spending_window_for_principal_v1(
  p_principal_id uuid,
  p_start_date date,
  p_end_date date,
  p_currency_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_currency text:=case when nullif(btrim(coalesce(p_currency_code,'')),'') is null then null else upper(btrim(p_currency_code)) end;
  v_items jsonb;
  v_days jsonb;
  v_total bigint:=0;
  v_refund bigint:=0;
  v_transfer_count integer:=0;
  v_ambiguous_count integer:=0;
  v_currency_count integer:=0;
  v_detected_currency text;
begin
  select * into v_principal from atlas.principals where id=p_principal_id and status='active';
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='55000'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<=p_start_date or p_end_date-p_start_date>366 then
    raise exception 'A valid half-open Money date window of at most 366 days is required.' using errcode='22023';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a three-letter uppercase code.' using errcode='22023'; end if;

  select count(distinct t.currency_code),min(t.currency_code)
  into v_currency_count,v_detected_currency
  from atlas.personal_money_transactions t
  where t.principal_id=p_principal_id
    and (t.occurred_at at time zone v_principal.home_timezone)::date>=p_start_date
    and (t.occurred_at at time zone v_principal.home_timezone)::date<p_end_date
    and (v_currency is null or t.currency_code=v_currency);

  if v_currency is null and v_currency_count>1 then
    return jsonb_build_object(
      'ok',false,'contractVersion','personal_money_spending_window_v1','principalId',p_principal_id,
      'startDate',p_start_date,'endDate',p_end_date,'timezone',v_principal.home_timezone,
      'state','needs_currency','truthBoundary',jsonb_build_object('currenciesAreNotSilentlyConverted',true)
    );
  end if;
  v_currency:=coalesce(v_currency,v_detected_currency,'USD');

  with scoped as (
    select t.*,(t.occurred_at at time zone v_principal.home_timezone)::date as local_date,
      case
        when t.classification_state='established' and t.economic_kind in ('spend','fee') and t.amount_minor<0 then -t.amount_minor
        when t.classification_state='established' and t.economic_kind='refund' and t.amount_minor>0 then -t.amount_minor
        else 0
      end as spend_contribution_minor
    from atlas.personal_money_transactions t
    where t.principal_id=p_principal_id
      and t.currency_code=v_currency
      and (t.occurred_at at time zone v_principal.home_timezone)::date>=p_start_date
      and (t.occurred_at at time zone v_principal.home_timezone)::date<p_end_date
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'transactionId',id,'localDate',local_date,'occurredAt',occurred_at,'postedAt',posted_at,
      'amountMinor',amount_minor,'currencyCode',currency_code,'economicKind',economic_kind,
      'classificationState',classification_state,'merchantName',merchant_name,'description',description,
      'spendContributionMinor',spend_contribution_minor,'revision',revision
    ) order by occurred_at,id),'[]'::jsonb),
    coalesce(sum(spend_contribution_minor),0),
    coalesce(sum(case when economic_kind='refund' and classification_state='established' and amount_minor>0 then amount_minor else 0 end),0),
    count(*) filter(where economic_kind='transfer' and classification_state='established'),
    count(*) filter(where classification_state='ambiguous' or economic_kind='unknown')
  into v_items,v_total,v_refund,v_transfer_count,v_ambiguous_count
  from scoped;

  with days as (
    select (t.occurred_at at time zone v_principal.home_timezone)::date as local_date,
      sum(case
        when t.classification_state='established' and t.economic_kind in ('spend','fee') and t.amount_minor<0 then -t.amount_minor
        when t.classification_state='established' and t.economic_kind='refund' and t.amount_minor>0 then -t.amount_minor
        else 0
      end)::bigint as amount_minor
    from atlas.personal_money_transactions t
    where t.principal_id=p_principal_id
      and t.currency_code=v_currency
      and (t.occurred_at at time zone v_principal.home_timezone)::date>=p_start_date
      and (t.occurred_at at time zone v_principal.home_timezone)::date<p_end_date
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('date',local_date,'amountMinor',amount_minor) order by local_date),'[]'::jsonb)
  into v_days from days where amount_minor<>0;

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_money_spending_window_v1','principalId',p_principal_id,
    'startDate',p_start_date,'endDate',p_end_date,'timezone',v_principal.home_timezone,'currencyCode',v_currency,
    'spendTotalMinor',v_total,'refundInflowMinor',v_refund,'excludedTransferCount',v_transfer_count,
    'ambiguousMovementCount',v_ambiguous_count,'dailySpend',v_days,'items',v_items,
    'truthBoundary',jsonb_build_object(
      'providerObservationsAreNotReadDirectly',true,
      'onlyEstablishedMoneyClassificationsCount',true,
      'transfersDoNotCountAsSpend',true,
      'refundsReduceSpend',true,
      'ambiguousMovementsRemainVisibleButDoNotCount',true,
      'currenciesAreNotSilentlyConverted',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_money_spending_window_for_principal_v1(uuid,date,date,text) from public,anon,authenticated;
grant execute on function atlas.personal_money_spending_window_for_principal_v1(uuid,date,date,text) to service_role;

create or replace function atlas.personal_money_spending_window_self_api_v1(
  p_start_date date,
  p_end_date date,
  p_currency_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id into v_principal_id from atlas.principals p where p.user_id=auth.uid() and p.status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  return atlas.personal_money_spending_window_for_principal_v1(v_principal_id,p_start_date,p_end_date,p_currency_code);
end;
$function$;

revoke all on function atlas.personal_money_spending_window_self_api_v1(date,date,text) from public,anon,authenticated;

create or replace function public.personal_money_spending_window_self_api_v1(
  p_start_date date,
  p_end_date date,
  p_currency_code text default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.personal_money_spending_window_self_api_v1(p_start_date,p_end_date,p_currency_code);
$function$;

revoke all on function public.personal_money_spending_window_self_api_v1(date,date,text) from public,anon;
grant execute on function public.personal_money_spending_window_self_api_v1(date,date,text) to authenticated,service_role;

create or replace function atlas.bind_personal_money_spending_window_service_v1(
  p_spread_instance_id uuid,
  p_start_date date,
  p_end_date date,
  p_currency_code text default 'USD'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_spread atlas.notebook_spread_instances%rowtype;
  v_currency text:=upper(btrim(coalesce(p_currency_code,'USD')));
  v_binding jsonb;
begin
  select * into v_spread from atlas.notebook_spread_instances where id=p_spread_instance_id;
  if v_spread.id is null then raise exception 'Notebook spread not found.' using errcode='P0002'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<=p_start_date or p_end_date-p_start_date>366 then raise exception 'A valid half-open Money date window is required.' using errcode='22023'; end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a three-letter uppercase code.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.principals p where p.id=v_spread.principal_id and p.status='active') then raise exception 'Active Principal required.' using errcode='55000'; end if;

  v_binding:=atlas.bind_notebook_spread_source_v1(
    p_spread_instance_id=>v_spread.id,
    p_source_domain=>'money',
    p_source_kind=>'spending_window',
    p_source_id=>v_spread.principal_id::text,
    p_relationship_kind=>'cadence',
    p_binding_state=>'active',
    p_basis=>jsonb_build_object('kind','governed_money_projection','contractVersion','personal_money_spending_window_v1'),
    p_metadata=>jsonb_build_object('startDate',p_start_date,'endDate',p_end_date,'currencyCode',v_currency)
  );

  return jsonb_build_object(
    'ok',true,'contractVersion','bind_personal_money_spending_window_service_v1',
    'spreadInstanceId',v_spread.id,'binding',v_binding,
    'truthBoundary',jsonb_build_object('bindingGrantsReadOnlyProjection',true,'bindingDoesNotCreateMoneyFacts',true)
  );
end;
$function$;

revoke all on function atlas.bind_personal_money_spending_window_service_v1(uuid,date,date,text) from public,anon,authenticated;
grant execute on function atlas.bind_personal_money_spending_window_service_v1(uuid,date,date,text) to service_role;

create or replace function public.bind_personal_money_spending_window_service_v1(
  p_spread_instance_id uuid,
  p_start_date date,
  p_end_date date,
  p_currency_code text default 'USD'
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.bind_personal_money_spending_window_service_v1(p_spread_instance_id,p_start_date,p_end_date,p_currency_code);
$function$;

revoke all on function public.bind_personal_money_spending_window_service_v1(uuid,date,date,text) from public,anon,authenticated;
grant execute on function public.bind_personal_money_spending_window_service_v1(uuid,date,date,text) to service_role;

commit;

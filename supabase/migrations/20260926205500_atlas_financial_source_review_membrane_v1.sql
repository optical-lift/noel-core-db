-- Atlas financial-source review membrane v1
--
-- Purpose:
--   preserve raw financial-source evidence before business/personal interpretation,
--   reconcile transfers without double-counting them as income/expense,
--   and promote only human-confirmed organization allocations into Package 5 Spend.
--
-- Truth boundary:
--   source custody is not operational purpose;
--   source transactions remain immutable evidence;
--   transfer confirmation is separate from source ingestion;
--   organization Spend is created only from confirmed allocations.

create table atlas.financial_source_transactions (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  connected_source_observation_id uuid not null unique references atlas.connected_source_observations(id) on delete restrict,
  evidence_record_id uuid not null unique references atlas.evidence_records(id) on delete restrict,
  captured_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  provider_transaction_key text not null check (btrim(provider_transaction_key)<>''),
  transaction_date date not null,
  posted_at timestamptz,
  direction text not null check (direction in ('debit','credit')),
  amount numeric not null check (amount>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text not null check (btrim(description)<>''),
  counterparty_label text,
  source_transaction_kind text,
  truth_state text not null default 'observed' check (truth_state in ('observed','disputed','voided')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connected_source_id,provider_transaction_key),
  check (counterparty_label is null or btrim(counterparty_label)<>''),
  check (source_transaction_kind is null or btrim(source_transaction_kind)<>'')
);

create index financial_source_transactions_date_idx
  on atlas.financial_source_transactions(transaction_date desc,id);
create index financial_source_transactions_source_date_idx
  on atlas.financial_source_transactions(connected_source_id,transaction_date desc,id);

create table atlas.financial_transfer_reconciliations (
  id uuid primary key default gen_random_uuid(),
  from_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  to_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  amount numeric not null check (amount>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  transfer_kind text not null check (transfer_kind in (
    'internal_transfer','liability_payment','owner_contribution','owner_draw','reimbursement','other'
  )),
  reconciliation_state text not null default 'confirmed' check (reconciliation_state in ('confirmed','superseded')),
  confirmed_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  client_event_key text not null check (btrim(client_event_key)<>''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  unique (confirmed_by_principal_id,client_event_key),
  check (from_transaction_id<>to_transaction_id),
  check ((reconciliation_state='superseded')=(superseded_at is not null))
);

create index financial_transfer_from_idx
  on atlas.financial_transfer_reconciliations(from_transaction_id,reconciliation_state);
create index financial_transfer_to_idx
  on atlas.financial_transfer_reconciliations(to_transaction_id,reconciliation_state);

create table atlas.financial_transaction_allocation_events (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  actor_principal_id uuid not null references atlas.principals(id) on delete restrict,
  event_kind text not null check (event_kind in ('allocations_replaced')),
  client_event_key text not null check (btrim(client_event_key)<>''),
  reason text,
  before_state jsonb,
  after_state jsonb not null default '{}'::jsonb check (jsonb_typeof(after_state)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(actor_principal_id,client_event_key),
  check (before_state is null or jsonb_typeof(before_state)='object')
);

create table atlas.financial_transaction_allocations (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  established_by_event_id uuid not null references atlas.financial_transaction_allocation_events(id) on delete restrict,
  allocation_kind text not null check (allocation_kind in ('organization_spend','personal','household','nonbusiness','other')),
  allocated_amount numeric not null check (allocated_amount>0),
  subject_domain text,
  subject_kind text,
  subject_id text,
  target_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  target_organization_id uuid references atlas.organizations(id) on delete restrict,
  operational_purpose text,
  allocation_state text not null default 'active' check (allocation_state in ('active','superseded')),
  confirmed_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  promoted_spend_occurrence_id uuid references atlas.organization_spend_occurrences(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  superseded_by_event_id uuid references atlas.financial_transaction_allocation_events(id) on delete restrict,
  check ((subject_domain is null and subject_kind is null and subject_id is null) or
         (subject_domain is not null and subject_kind is not null and subject_id is not null)),
  check (subject_domain is null or btrim(subject_domain)<>''),
  check (subject_kind is null or btrim(subject_kind)<>''),
  check (subject_id is null or btrim(subject_id)<>''),
  check (operational_purpose is null or btrim(operational_purpose)<>''),
  check ((allocation_kind='organization_spend' and target_ledger_id is not null and target_organization_id is not null)
      or (allocation_kind<>'organization_spend' and target_ledger_id is null and target_organization_id is null)),
  check ((allocation_state='superseded')=(superseded_at is not null))
);

create index financial_transaction_allocations_tx_idx
  on atlas.financial_transaction_allocations(transaction_id,allocation_state);
create index financial_transaction_allocations_ledger_idx
  on atlas.financial_transaction_allocations(target_ledger_id,allocation_state)
  where target_ledger_id is not null;

alter table atlas.financial_source_transactions enable row level security;
alter table atlas.financial_transfer_reconciliations enable row level security;
alter table atlas.financial_transaction_allocation_events enable row level security;
alter table atlas.financial_transaction_allocations enable row level security;

revoke all on table atlas.financial_source_transactions from public,anon,authenticated;
revoke all on table atlas.financial_transfer_reconciliations from public,anon,authenticated;
revoke all on table atlas.financial_transaction_allocation_events from public,anon,authenticated;
revoke all on table atlas.financial_transaction_allocations from public,anon,authenticated;

create or replace function atlas.financial_source_authorized_self_v1(p_connected_source_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select auth.uid() is not null and exists(
    select 1
    from atlas.connected_sources source
    where source.id=p_connected_source_id
      and source.authorization_state='connected'
      and (
        source.custodian_user_id=auth.uid()
        or exists(
          select 1
          from atlas.organization_memberships membership
          where membership.organization_id=source.custodian_organization_id
            and membership.user_id=auth.uid()
            and atlas.organization_membership_present_effective_at_v1(
              membership.id,membership.organization_id,now()
            )
        )
        or exists(
          select 1
          from atlas.organization_onboarding_actors actor
          where actor.organization_id=source.custodian_organization_id
            and actor.human_user_id=auth.uid()
            and actor.active
        )
      )
  )
$function$;

create or replace function atlas.register_person_connected_source_self_api_v1(
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_authorization_state text default 'connected',
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_provider_key text:=btrim(coalesce(p_provider_key,''));
  v_provider_account_key text:=btrim(coalesce(p_provider_account_key,''));
  v_state text:=btrim(coalesce(p_authorization_state,''));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if atlas.current_principal_id_v1() is null then raise exception 'Principal binding required.' using errcode='42501'; end if;
  if v_provider_key='' or v_provider_account_key='' then raise exception 'Provider identity is required.' using errcode='22023'; end if;
  if v_state not in ('pending','connected') then raise exception 'A source may only be registered as pending or connected.' using errcode='22023'; end if;
  if jsonb_typeof(v_metadata)<>'object' then raise exception 'Source metadata must be an object.' using errcode='22023'; end if;
  if p_capabilities is not null and jsonb_typeof(p_capabilities)<>'object' then raise exception 'Source capabilities must be an object.' using errcode='22023'; end if;
  if lower(v_metadata::text) ~ '\"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)\"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023';
  end if;

  select source.* into v_source
  from atlas.connected_sources source
  where source.custodian_user_id=v_uid
    and source.provider_key=v_provider_key
    and source.provider_account_key=v_provider_account_key
  for update;

  if found then
    if v_source.authorization_state='revoked' then raise exception 'A revoked provider source cannot be silently rebound.' using errcode='55000'; end if;
    update atlas.connected_sources source
    set display_label=coalesce(nullif(btrim(p_display_label),''),source.display_label),
        account_hint=coalesce(nullif(btrim(p_account_hint),''),source.account_hint),
        authorization_state=v_state,
        granted_scopes=coalesce(p_granted_scopes,source.granted_scopes),
        capabilities=coalesce(p_capabilities,source.capabilities),
        revoked_at=null,
        metadata=source.metadata||v_metadata,
        updated_at=now()
    where source.id=v_source.id
    returning source.* into v_source;
  else
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,provider_key,provider_account_key,
      display_label,account_hint,authorization_state,granted_scopes,capabilities,metadata
    ) values(
      v_uid,null,v_provider_key,v_provider_account_key,
      nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),v_state,
      coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),v_metadata
    ) returning * into v_source;
  end if;

  return jsonb_build_object(
    'sourceId',v_source.id,
    'custodyKind','human',
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'capabilities',v_source.capabilities,
    'truthBoundary',jsonb_build_object(
      'sourceCustodyDoesNotEstablishOperationalPurpose',true,
      'sourceCustodyDoesNotEstablishTaxTreatment',true
    )
  );
end;
$function$;

create or replace function atlas.record_financial_statement_transactions_self_api_v1(
  p_connected_source_id uuid,
  p_statement_key text,
  p_records jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','extensions'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_principal uuid:=atlas.current_principal_id_v1();
  v_statement_key text:=btrim(coalesce(p_statement_key,''));
  v_record jsonb;
  v_record_key text;
  v_object_key text;
  v_date date;
  v_posted_at timestamptz;
  v_direction text;
  v_amount numeric;
  v_currency text;
  v_description text;
  v_counterparty text;
  v_kind text;
  v_metadata jsonb;
  v_payload jsonb;
  v_hash text;
  v_observation_id uuid;
  v_transaction_id uuid;
  v_evidence_id uuid;
  v_existing atlas.financial_source_transactions%rowtype;
  v_total integer:=0;
  v_inserted integer:=0;
  v_duplicate integer:=0;
begin
  if v_uid is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if not atlas.financial_source_authorized_self_v1(p_connected_source_id) then raise exception 'Connected source custody required.' using errcode='42501'; end if;
  if v_statement_key='' or p_records is null or jsonb_typeof(p_records)<>'array' then raise exception 'Statement key and transaction array are required.' using errcode='22023'; end if;
  if jsonb_array_length(p_records)>500 then raise exception 'A statement transaction batch may contain at most 500 records.' using errcode='22023'; end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then raise exception 'Statement provenance must be an object.' using errcode='22023'; end if;

  for v_record in select value from jsonb_array_elements(p_records)
  loop
    v_total:=v_total+1;
    if jsonb_typeof(v_record)<>'object' then raise exception 'Each statement transaction must be an object.' using errcode='22023'; end if;
    v_record_key:=btrim(coalesce(v_record->>'key',''));
    v_object_key:=v_statement_key||':'||v_record_key;
    begin v_date:=(v_record->>'transactionDate')::date; exception when others then raise exception 'Each statement transaction requires transactionDate.' using errcode='22023'; end;
    begin v_posted_at:=nullif(v_record->>'postedAt','')::timestamptz; exception when others then raise exception 'postedAt must be a timestamp.' using errcode='22023'; end;
    v_direction:=lower(btrim(coalesce(v_record->>'direction','')));
    begin v_amount:=(v_record->>'amount')::numeric; exception when others then raise exception 'Each statement transaction requires numeric amount.' using errcode='22023'; end;
    v_currency:=upper(btrim(coalesce(v_record->>'currency','USD')));
    v_description:=btrim(coalesce(v_record->>'description',''));
    v_counterparty:=nullif(btrim(coalesce(v_record->>'counterpartyLabel','')),'');
    v_kind:=nullif(btrim(coalesce(v_record->>'transactionKind','')),'');
    v_metadata:=coalesce(v_record->'metadata','{}'::jsonb);

    if v_record_key='' or v_date is null or v_direction not in ('debit','credit') or v_amount is null or v_amount<=0 or v_currency !~ '^[A-Z]{3}$' or v_description='' then
      raise exception 'Each statement transaction requires key, date, debit/credit direction, positive amount, currency, and description.' using errcode='22023';
    end if;
    if jsonb_typeof(v_metadata)<>'object' then raise exception 'Transaction metadata must be an object.' using errcode='22023'; end if;

    v_payload:=jsonb_strip_nulls(jsonb_build_object(
      'statementKey',v_statement_key,'transactionKey',v_record_key,'transactionDate',v_date,
      'postedAt',v_posted_at,'direction',v_direction,'amount',v_amount,'currency',v_currency,
      'description',v_description,'counterpartyLabel',v_counterparty,'transactionKind',v_kind,'metadata',v_metadata
    ));
    v_hash:=encode(extensions.digest(convert_to(v_payload::text,'utf8'),'sha256'),'hex');

    insert into atlas.connected_source_observations(
      connected_source_id,provider_object_kind,provider_object_key,provider_created_at,
      observed_at,payload,payload_sha256,provenance
    ) values(
      p_connected_source_id,'financial_transaction',v_object_key,v_posted_at,now(),v_payload,v_hash,
      coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('ingestionKind','statement','statementKey',v_statement_key)
    ) on conflict(connected_source_id,provider_object_kind,provider_object_key,payload_sha256) do nothing
    returning id into v_observation_id;

    if v_observation_id is null then
      select o.id into v_observation_id
      from atlas.connected_source_observations o
      where o.connected_source_id=p_connected_source_id
        and o.provider_object_kind='financial_transaction'
        and o.provider_object_key=v_object_key
        and o.payload_sha256=v_hash
      order by o.created_at,o.id limit 1;
    end if;

    select * into v_existing
    from atlas.financial_source_transactions t
    where t.connected_source_id=p_connected_source_id and t.provider_transaction_key=v_object_key;

    if v_existing.id is not null then
      if v_existing.connected_source_observation_id is distinct from v_observation_id
         or v_existing.transaction_date is distinct from v_date
         or v_existing.posted_at is distinct from v_posted_at
         or v_existing.direction is distinct from v_direction
         or v_existing.amount is distinct from v_amount
         or v_existing.currency is distinct from v_currency
         or v_existing.description is distinct from v_description
         or v_existing.counterparty_label is distinct from v_counterparty
         or v_existing.source_transaction_kind is distinct from v_kind then
        raise exception 'Statement transaction key already has different evidence; use a correction flow rather than rewriting source evidence.' using errcode='23514';
      end if;
      v_duplicate:=v_duplicate+1;
      continue;
    end if;

    v_transaction_id:=gen_random_uuid();
    insert into atlas.evidence_records(
      scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,
      actor_user_id,value,confidence,observed_at,provenance,metadata
    ) values(
      'principal',v_principal,'financial','source_transaction',v_transaction_id::text,
      'financial_source_observation','connected_source_observation',v_observation_id::text,
      v_uid,v_payload,1,coalesce(v_posted_at,v_date::timestamp at time zone 'UTC'),
      jsonb_build_object('connectedSourceId',p_connected_source_id,'connectedSourceObservationId',v_observation_id,'statementKey',v_statement_key),
      jsonb_build_object('rawSourceEvidencePreserved',true)
    ) returning id into v_evidence_id;

    insert into atlas.financial_source_transactions(
      id,connected_source_id,connected_source_observation_id,evidence_record_id,captured_by_principal_id,
      provider_transaction_key,transaction_date,posted_at,direction,amount,currency,description,
      counterparty_label,source_transaction_kind,metadata
    ) values(
      v_transaction_id,p_connected_source_id,v_observation_id,v_evidence_id,v_principal,
      v_object_key,v_date,v_posted_at,v_direction,v_amount,v_currency,v_description,
      v_counterparty,v_kind,v_metadata
    );
    v_inserted:=v_inserted+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','financial_statement_transactions_self_v1',
    'connectedSourceId',p_connected_source_id,'statementKey',v_statement_key,
    'recordCount',v_total,'insertedCount',v_inserted,'duplicateCount',v_duplicate,
    'truthBoundary',jsonb_build_object(
      'transactionsRemainSourceEvidence',true,
      'noOperationalPurposeInferred',true,
      'noTaxTreatmentInferred',true,
      'noOrganizationSpendCreated',true
    )
  );
end;
$function$;

create or replace function atlas.financial_review_self_api_v1(p_start_on date,p_end_on date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid financial review window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'contractVersion','financial_review_self_v1',
    'startOn',p_start_on,'endOn',p_end_on,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'transactionId',t.id,
        'source',jsonb_build_object(
          'sourceId',s.id,'custodyKind',case when s.custodian_user_id is not null then 'human' else 'organization' end,
          'custodianOrganizationId',s.custodian_organization_id,'providerKey',s.provider_key,
          'providerAccountKey',s.provider_account_key,'displayLabel',s.display_label,'accountHint',s.account_hint,
          'capabilities',s.capabilities,'metadata',s.metadata
        ),
        'transactionDate',t.transaction_date,'postedAt',t.posted_at,'direction',t.direction,
        'amount',t.amount,'currency',t.currency,'description',t.description,
        'counterpartyLabel',t.counterparty_label,'sourceTransactionKind',t.source_transaction_kind,
        'truthState',t.truth_state,'evidenceRecordId',t.evidence_record_id,
        'confirmedTransferAmount',coalesce(x.transfer_amount,0),
        'activeAllocationAmount',coalesce(a.allocation_amount,0),
        'resolutionState',case
          when coalesce(x.transfer_amount,0)+coalesce(a.allocation_amount,0)=0 then 'unresolved'
          when coalesce(x.transfer_amount,0)+coalesce(a.allocation_amount,0)<t.amount then 'partial'
          else 'resolved' end,
        'transfers',coalesce(x.transfers,'[]'::jsonb),
        'allocations',coalesce(a.allocations,'[]'::jsonb)
      ) order by t.transaction_date desc,t.id)
      from atlas.financial_source_transactions t
      join atlas.connected_sources s on s.id=t.connected_source_id
      left join lateral (
        select sum(r.amount) as transfer_amount,
               jsonb_agg(jsonb_build_object(
                 'reconciliationId',r.id,'fromTransactionId',r.from_transaction_id,'toTransactionId',r.to_transaction_id,
                 'amount',r.amount,'currency',r.currency,'transferKind',r.transfer_kind,'state',r.reconciliation_state
               ) order by r.created_at,r.id) as transfers
        from atlas.financial_transfer_reconciliations r
        where r.reconciliation_state='confirmed' and (r.from_transaction_id=t.id or r.to_transaction_id=t.id)
      ) x on true
      left join lateral (
        select sum(fa.allocated_amount) as allocation_amount,
               jsonb_agg(jsonb_build_object(
                 'allocationId',fa.id,'allocationKind',fa.allocation_kind,'amount',fa.allocated_amount,
                 'subjectDomain',fa.subject_domain,'subjectKind',fa.subject_kind,'subjectId',fa.subject_id,
                 'targetLedgerId',fa.target_ledger_id,'targetOrganizationId',fa.target_organization_id,
                 'operationalPurpose',fa.operational_purpose,'promotedSpendOccurrenceId',fa.promoted_spend_occurrence_id
               ) order by fa.created_at,fa.id) as allocations
        from atlas.financial_transaction_allocations fa
        where fa.transaction_id=t.id and fa.allocation_state='active'
      ) a on true
      where t.transaction_date between p_start_on and p_end_on
        and atlas.financial_source_authorized_self_v1(t.connected_source_id)
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sourceCustodyIsNotPurpose',true,
      'transferIsNotExpense',true,
      'allocationRequiresHumanConfirmation',true,
      'organizationSpendPromotionIsSeparateFromSourceEvidence',true
    )
  );
end;
$function$;

create or replace function atlas.confirm_financial_transfer_self_api_v1(
  p_from_transaction_id uuid,
  p_to_transaction_id uuid,
  p_amount numeric,
  p_transfer_kind text,
  p_client_event_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_from atlas.financial_source_transactions%rowtype;
  v_to atlas.financial_source_transactions%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_kind text:=lower(btrim(coalesce(p_transfer_kind,'')));
  v_existing atlas.financial_transfer_reconciliations%rowtype;
  v_from_used numeric;
  v_to_used numeric;
  v_id uuid;
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_amount is null or p_amount<=0 then raise exception 'Client event key and positive transfer amount are required.' using errcode='22023'; end if;
  if v_kind not in ('internal_transfer','liability_payment','owner_contribution','owner_draw','reimbursement','other') then raise exception 'Unsupported transfer kind.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Transfer metadata must be an object.' using errcode='22023'; end if;

  select * into v_existing from atlas.financial_transfer_reconciliations r
  where r.confirmed_by_principal_id=v_principal and r.client_event_key=v_key;
  if v_existing.id is not null then
    if v_existing.from_transaction_id is distinct from p_from_transaction_id or v_existing.to_transaction_id is distinct from p_to_transaction_id
       or v_existing.amount is distinct from p_amount or v_existing.transfer_kind is distinct from v_kind then
      raise exception 'Client event key already belongs to a different transfer confirmation.' using errcode='23514';
    end if;
    return jsonb_build_object('contractVersion','confirm_financial_transfer_self_api_v1','state','unchanged','reconciliationId',v_existing.id);
  end if;

  select * into v_from from atlas.financial_source_transactions where id=p_from_transaction_id for update;
  select * into v_to from atlas.financial_source_transactions where id=p_to_transaction_id for update;
  if v_from.id is null or v_to.id is null then raise exception 'Both source transactions are required.' using errcode='P0002'; end if;
  if not atlas.financial_source_authorized_self_v1(v_from.connected_source_id) or not atlas.financial_source_authorized_self_v1(v_to.connected_source_id) then raise exception 'Source custody required for both sides of a transfer.' using errcode='42501'; end if;
  if v_from.direction<>'debit' or v_to.direction<>'credit' then raise exception 'A transfer must reconcile a debit source transaction to a credit source transaction.' using errcode='23514'; end if;
  if v_from.currency<>v_to.currency then raise exception 'Transfer sides must use the same currency.' using errcode='23514'; end if;
  if v_from.connected_source_id=v_to.connected_source_id then raise exception 'Transfer sides must belong to different financial sources.' using errcode='23514'; end if;

  select coalesce(sum(r.amount),0)+coalesce((select sum(a.allocated_amount) from atlas.financial_transaction_allocations a where a.transaction_id=v_from.id and a.allocation_state='active'),0)
  into v_from_used from atlas.financial_transfer_reconciliations r where r.from_transaction_id=v_from.id and r.reconciliation_state='confirmed';
  select coalesce(sum(r.amount),0) into v_to_used from atlas.financial_transfer_reconciliations r where r.to_transaction_id=v_to.id and r.reconciliation_state='confirmed';
  if v_from_used+p_amount>v_from.amount or v_to_used+p_amount>v_to.amount then raise exception 'Transfer amount exceeds the unreconciled source amount.' using errcode='23514'; end if;

  insert into atlas.financial_transfer_reconciliations(
    from_transaction_id,to_transaction_id,amount,currency,transfer_kind,confirmed_by_principal_id,client_event_key,metadata
  ) values(v_from.id,v_to.id,p_amount,v_from.currency,v_kind,v_principal,v_key,p_metadata)
  returning id into v_id;

  return jsonb_build_object(
    'contractVersion','confirm_financial_transfer_self_api_v1','state','confirmed','reconciliationId',v_id,
    'truthBoundary',jsonb_build_object('expenseCreated',false,'incomeCreated',false,'sourceEvidenceMutated',false)
  );
end;
$function$;

create or replace function atlas.financial_transaction_allocation_snapshot_v1(p_transaction_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select jsonb_build_object(
    'transactionId',p_transaction_id,
    'allocations',coalesce(jsonb_agg(jsonb_build_object(
      'allocationId',a.id,'allocationKind',a.allocation_kind,'amount',a.allocated_amount,
      'subjectDomain',a.subject_domain,'subjectKind',a.subject_kind,'subjectId',a.subject_id,
      'targetLedgerId',a.target_ledger_id,'targetOrganizationId',a.target_organization_id,
      'operationalPurpose',a.operational_purpose,'promotedSpendOccurrenceId',a.promoted_spend_occurrence_id
    ) order by a.created_at,a.id) filter(where a.id is not null),'[]'::jsonb)
  )
  from atlas.financial_transaction_allocations a
  where a.transaction_id=p_transaction_id and a.allocation_state='active'
$function$;

create or replace function atlas.replace_financial_transaction_allocations_self_api_v1(
  p_transaction_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_tx atlas.financial_source_transactions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_event atlas.financial_transaction_allocation_events%rowtype;
  v_item jsonb;
  v_kind text;
  v_amount numeric;
  v_total numeric:=0;
  v_transfer_amount numeric:=0;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_ledger_id uuid;
  v_organization_id uuid;
  v_purpose text;
  v_item_metadata jsonb;
  v_membership uuid;
  v_funding_kind text;
  v_allocation_id uuid;
  v_spend jsonb;
  v_spend_id uuid;
  v_spend_allocations jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'Client event key and allocation array are required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Allocation event metadata must be an object.' using errcode='22023'; end if;

  select * into v_event from atlas.financial_transaction_allocation_events e
  where e.actor_principal_id=v_principal and e.client_event_key=v_key;
  if v_event.id is not null then
    return jsonb_build_object('contractVersion','replace_financial_transaction_allocations_self_api_v1','state','unchanged','eventId',v_event.id,'afterState',v_event.after_state);
  end if;

  select * into v_tx from atlas.financial_source_transactions where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Financial source transaction not found.' using errcode='P0002'; end if;
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then raise exception 'Financial source custody required.' using errcode='42501'; end if;
  if v_tx.direction<>'debit' then raise exception 'Expense-purpose allocations apply to debit source transactions only.' using errcode='23514'; end if;
  if exists(select 1 from atlas.financial_transaction_allocations a where a.transaction_id=v_tx.id and a.allocation_state='active' and a.promoted_spend_occurrence_id is not null) then
    raise exception 'A promoted business allocation cannot be silently replaced; correct the governed Spend instead.' using errcode='55000';
  end if;

  select * into v_source from atlas.connected_sources where id=v_tx.connected_source_id;
  select coalesce(sum(r.amount),0) into v_transfer_amount
  from atlas.financial_transfer_reconciliations r
  where r.from_transaction_id=v_tx.id and r.reconciliation_state='confirmed';

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each financial allocation must be an object.' using errcode='22023'; end if;
    v_kind:=lower(btrim(coalesce(v_item->>'allocationKind','')));
    begin v_amount:=(v_item->>'amount')::numeric; exception when others then raise exception 'Each financial allocation requires numeric amount.' using errcode='22023'; end;
    if v_kind not in ('organization_spend','personal','household','nonbusiness','other') or v_amount is null or v_amount<=0 then raise exception 'Each financial allocation requires a supported kind and positive amount.' using errcode='22023'; end if;
    v_total:=v_total+v_amount;
    if v_kind='organization_spend' then
      begin v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid; v_organization_id:=nullif(v_item->>'organizationId','')::uuid; exception when others then raise exception 'Business allocation Ledger and Organization IDs must be UUIDs.' using errcode='22023'; end;
      if v_ledger_id is null or v_organization_id is null then raise exception 'Business allocation requires Ledger and Organization.' using errcode='22023'; end if;
      if not atlas.principal_has_ledger_authority_v1(v_principal,v_ledger_id) then raise exception 'Ledger authority required for business allocation.' using errcode='42501'; end if;
      perform atlas.organization_spend_assert_custody_v1(v_ledger_id,v_organization_id);
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      if v_membership is null then raise exception 'Organization membership required to promote business Spend.' using errcode='42501'; end if;
    end if;
  end loop;
  if v_transfer_amount+v_total>v_tx.amount then raise exception 'Transfer plus allocation amounts exceed the source transaction amount.' using errcode='23514'; end if;

  v_before:=atlas.financial_transaction_allocation_snapshot_v1(v_tx.id);
  insert into atlas.financial_transaction_allocation_events(transaction_id,actor_principal_id,event_kind,client_event_key,reason,before_state,metadata)
  values(v_tx.id,v_principal,'allocations_replaced',v_key,nullif(btrim(coalesce(p_reason,'')),''),v_before,p_metadata)
  returning * into v_event;

  update atlas.financial_transaction_allocations
  set allocation_state='superseded',superseded_at=now(),superseded_by_event_id=v_event.id
  where transaction_id=v_tx.id and allocation_state='active';

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    v_kind:=lower(btrim(v_item->>'allocationKind'));
    v_amount:=(v_item->>'amount')::numeric;
    v_subject_domain:=nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_subject_kind:=nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id:=nullif(btrim(coalesce(v_item->>'subjectId','')),'');
    v_purpose:=nullif(btrim(coalesce(v_item->>'operationalPurpose','')),'');
    v_item_metadata:=coalesce(v_item->'metadata','{}'::jsonb);
    if jsonb_typeof(v_item_metadata)<>'object' then raise exception 'Financial allocation metadata must be an object.' using errcode='22023'; end if;
    if (v_subject_domain is null or v_subject_kind is null or v_subject_id is null) and not (v_subject_domain is null and v_subject_kind is null and v_subject_id is null) then raise exception 'Allocation subject coordinates must be complete or omitted.' using errcode='22023'; end if;

    v_ledger_id:=null;
    v_organization_id:=null;
    if v_kind='organization_spend' then
      v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
      v_organization_id:=nullif(v_item->>'organizationId','')::uuid;
    end if;

    insert into atlas.financial_transaction_allocations(
      transaction_id,established_by_event_id,allocation_kind,allocated_amount,
      subject_domain,subject_kind,subject_id,target_ledger_id,target_organization_id,
      operational_purpose,confirmed_by_principal_id,metadata
    ) values(
      v_tx.id,v_event.id,v_kind,v_amount,
      v_subject_domain,v_subject_kind,v_subject_id,v_ledger_id,v_organization_id,
      v_purpose,v_principal,v_item_metadata
    ) returning id into v_allocation_id;

    if v_kind='organization_spend' then
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      v_funding_kind:=case when v_source.custodian_organization_id=v_organization_id then 'organization' else 'organization_member' end;
      v_spend_allocations:=case when v_purpose is not null or v_subject_domain is not null then
        jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'amount',v_amount,'operationalPurpose',v_purpose,
          'subjectDomain',v_subject_domain,'subjectKind',v_subject_kind,'subjectId',v_subject_id
        ))) else null end;

      v_spend:=atlas.record_organization_spend_core_v1(
        v_ledger_id,v_organization_id,v_principal,v_membership,null,
        v_tx.transaction_date,v_tx.posted_at,v_amount,v_tx.currency,
        v_funding_kind,case when v_funding_kind='organization_member' then v_membership else null end,
        null,coalesce(v_tx.counterparty_label,v_tx.description),coalesce(v_source.display_label,v_source.provider_key),
        'financial_source_transaction',v_allocation_id::text,v_spend_allocations,
        jsonb_build_object(
          'financialSourceTransactionId',v_tx.id,'financialAllocationId',v_allocation_id,
          'connectedSourceId',v_tx.connected_source_id,'evidenceRecordId',v_tx.evidence_record_id
        ),
        jsonb_build_object('promotedFromFinancialReview',true)
      );
      v_spend_id:=nullif(v_spend->>'spendOccurrenceId','')::uuid;
      perform atlas.link_organization_spend_evidence_core_v1(
        v_ledger_id,v_organization_id,v_spend_id,null,v_tx.evidence_record_id,
        'transaction_observation',v_principal,v_membership,
        jsonb_build_object('financialAllocationId',v_allocation_id)
      );
      update atlas.financial_transaction_allocations
      set promoted_spend_occurrence_id=v_spend_id
      where id=v_allocation_id;
    end if;
  end loop;

  v_after:=atlas.financial_transaction_allocation_snapshot_v1(v_tx.id);
  update atlas.financial_transaction_allocation_events set after_state=v_after where id=v_event.id;

  return jsonb_build_object(
    'contractVersion','replace_financial_transaction_allocations_self_api_v1','state','replaced',
    'eventId',v_event.id,'transactionId',v_tx.id,'afterState',v_after,
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceMutated',false,
      'transferAmountsExcludedFromSpend',true,
      'organizationSpendCreatedOnlyForConfirmedBusinessAllocations',true,
      'nonbusinessAllocationsDoNotCreateOrganizationSpend',true
    )
  );
end;
$function$;

revoke all on function atlas.financial_source_authorized_self_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.register_person_connected_source_self_api_v1(text,text,text,text,text,text[],jsonb,jsonb) from public,anon,service_role;
revoke all on function atlas.record_financial_statement_transactions_self_api_v1(uuid,text,jsonb,jsonb) from public,anon,service_role;
revoke all on function atlas.financial_review_self_api_v1(date,date) from public,anon,service_role;
revoke all on function atlas.confirm_financial_transfer_self_api_v1(uuid,uuid,numeric,text,text,jsonb) from public,anon,service_role;
revoke all on function atlas.financial_transaction_allocation_snapshot_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.replace_financial_transaction_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) from public,anon,service_role;

grant execute on function atlas.register_person_connected_source_self_api_v1(text,text,text,text,text,text[],jsonb,jsonb) to authenticated;
grant execute on function atlas.record_financial_statement_transactions_self_api_v1(uuid,text,jsonb,jsonb) to authenticated;
grant execute on function atlas.financial_review_self_api_v1(date,date) to authenticated;
grant execute on function atlas.confirm_financial_transfer_self_api_v1(uuid,uuid,numeric,text,text,jsonb) to authenticated;
grant execute on function atlas.replace_financial_transaction_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) to authenticated;

comment on table atlas.financial_source_transactions is
  'Normalized financial-source facts backed by immutable connected-source observations. Source custody does not imply business purpose or tax treatment.';
comment on table atlas.financial_transfer_reconciliations is
  'Human-confirmed links between source transactions representing one movement of money. Confirmed transfers are excluded from expense-purpose allocation capacity.';
comment on table atlas.financial_transaction_allocations is
  'Human-confirmed purpose allocations of debit source transactions. Only organization_spend allocations promote into Package 5 Spend.';
comment on function atlas.record_financial_statement_transactions_self_api_v1(uuid,text,jsonb,jsonb) is
  'Admits normalized statement rows as source evidence only. It does not infer transfer, personal/business purpose, tax category, income, or Spend.';
comment on function atlas.replace_financial_transaction_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) is
  'Principal-confirmed source-transaction purpose allocation. Confirmed organization allocations are promoted into governed Package 5 Spend with original source evidence linked.';

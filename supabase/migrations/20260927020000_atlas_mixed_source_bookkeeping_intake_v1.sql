-- Atlas mixed-source bookkeeping intake v1
--
-- Keeps source custody, bookkeeping interpretation, and canonical Spend distinct:
--   connected source observation -> financial source transaction -> reviewed allocation
--   -> optional canonical organization Spend promotion
--
-- The connected source owner is never treated as the operational beneficiary by default.
-- Raw source evidence remains in connected_source_observations. This layer gives a stable
-- transaction identity across observation versions and snapshots the exact source observation
-- approved by each review.

create table if not exists atlas.financial_source_transactions (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_transaction_key text not null,
  first_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  current_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  occurred_on date not null,
  occurred_at timestamptz,
  source_amount numeric not null,
  currency text not null,
  raw_description text,
  source_party_label text,
  transaction_state text not null default 'observed',
  normalization_provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_source_transactions_provider_key_nonempty check (btrim(provider_transaction_key) <> ''),
  constraint financial_source_transactions_amount_nonzero check (source_amount <> 0),
  constraint financial_source_transactions_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_source_transactions_state_check check (transaction_state in ('observed','voided')),
  constraint financial_source_transactions_description_nonempty check (raw_description is null or btrim(raw_description) <> ''),
  constraint financial_source_transactions_party_nonempty check (source_party_label is null or btrim(source_party_label) <> ''),
  constraint financial_source_transactions_provenance_object check (jsonb_typeof(normalization_provenance) = 'object'),
  constraint financial_source_transactions_metadata_object check (jsonb_typeof(metadata) = 'object'),
  unique (connected_source_id, provider_transaction_key)
);

create index if not exists financial_source_transactions_source_date_idx
  on atlas.financial_source_transactions(connected_source_id, occurred_on desc, id);

create table if not exists atlas.financial_source_transaction_review_events (
  id uuid primary key default gen_random_uuid(),
  financial_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  source_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  review_revision bigint generated always as identity,
  client_event_key text not null,
  input_sha256 text not null,
  review_state text not null default 'confirmed',
  reviewed_by_principal_id uuid references atlas.principals(id) on delete restrict,
  reviewed_by_user_id uuid references auth.users(id) on delete restrict,
  review_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_source_transaction_review_client_key_nonempty check (btrim(client_event_key) <> ''),
  constraint financial_source_transaction_review_hash_nonempty check (btrim(input_sha256) <> ''),
  constraint financial_source_transaction_review_state_check check (review_state in ('confirmed')),
  constraint financial_source_transaction_review_basis_object check (jsonb_typeof(review_basis) = 'object'),
  constraint financial_source_transaction_review_metadata_object check (jsonb_typeof(metadata) = 'object'),
  unique (financial_transaction_id, client_event_key)
);

create index if not exists financial_source_transaction_review_latest_idx
  on atlas.financial_source_transaction_review_events(financial_transaction_id, review_revision desc);

create table if not exists atlas.financial_source_transaction_allocations (
  id uuid primary key default gen_random_uuid(),
  review_event_id uuid not null references atlas.financial_source_transaction_review_events(id) on delete restrict,
  allocation_ordinal integer not null,
  treatment_kind text not null,
  allocated_amount numeric not null,
  target_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  operational_purpose text,
  subject_domain text,
  subject_kind text,
  subject_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_source_transaction_allocation_ordinal_check check (allocation_ordinal > 0),
  constraint financial_source_transaction_allocation_amount_check check (allocated_amount > 0),
  constraint financial_source_transaction_allocation_treatment_check check (
    treatment_kind in (
      'operating_expense',
      'operating_revenue',
      'owner_funding',
      'transfer',
      'personal',
      'refund_adjustment',
      'unresolved'
    )
  ),
  constraint financial_source_transaction_allocation_ledger_check check (
    treatment_kind not in ('operating_expense','operating_revenue') or target_ledger_id is not null
  ),
  constraint financial_source_transaction_allocation_purpose_nonempty check (
    operational_purpose is null or btrim(operational_purpose) <> ''
  ),
  constraint financial_source_transaction_allocation_subject_check check (
    (subject_domain is null and subject_kind is null and subject_id is null)
    or (
      nullif(btrim(coalesce(subject_domain,'')),'') is not null
      and nullif(btrim(coalesce(subject_kind,'')),'') is not null
      and nullif(btrim(coalesce(subject_id,'')),'') is not null
    )
  ),
  constraint financial_source_transaction_allocation_metadata_object check (jsonb_typeof(metadata) = 'object'),
  unique (review_event_id, allocation_ordinal)
);

create index if not exists financial_source_transaction_allocations_target_idx
  on atlas.financial_source_transaction_allocations(target_ledger_id, treatment_kind, review_event_id)
  where target_ledger_id is not null;

create table if not exists atlas.financial_source_transaction_spend_promotions (
  id uuid primary key default gen_random_uuid(),
  financial_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  review_event_id uuid not null references atlas.financial_source_transaction_review_events(id) on delete restrict,
  target_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  spend_occurrence_id uuid not null references atlas.organization_spend_occurrences(id) on delete restrict,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  promoted_by_principal_id uuid references atlas.principals(id) on delete restrict,
  promoted_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  promoted_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint financial_source_transaction_spend_promotion_metadata_object check (jsonb_typeof(metadata) = 'object'),
  unique (financial_transaction_id, target_ledger_id),
  unique (spend_occurrence_id)
);

create index if not exists financial_source_transaction_spend_promotions_review_idx
  on atlas.financial_source_transaction_spend_promotions(review_event_id, target_ledger_id);

alter table atlas.financial_source_transactions enable row level security;
alter table atlas.financial_source_transaction_review_events enable row level security;
alter table atlas.financial_source_transaction_allocations enable row level security;
alter table atlas.financial_source_transaction_spend_promotions enable row level security;

revoke all on table atlas.financial_source_transactions from public, anon, authenticated;
revoke all on table atlas.financial_source_transaction_review_events from public, anon, authenticated;
revoke all on table atlas.financial_source_transaction_allocations from public, anon, authenticated;
revoke all on table atlas.financial_source_transaction_spend_promotions from public, anon, authenticated;

create or replace function atlas.financial_connected_source_authorized_self_v1(p_connected_source_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
  select auth.uid() is not null and exists (
    select 1
    from atlas.connected_sources source
    where source.id = p_connected_source_id
      and (
        source.custodian_user_id = auth.uid()
        or exists (
          select 1
          from atlas.organization_memberships membership
          where membership.organization_id = source.custodian_organization_id
            and membership.user_id = auth.uid()
            and atlas.organization_membership_present_effective_at_v1(
              membership.id,
              membership.organization_id,
              now()
            )
        )
        or exists (
          select 1
          from atlas.organization_onboarding_actors actor
          where actor.organization_id = source.custodian_organization_id
            and actor.human_user_id = auth.uid()
            and actor.active
        )
      )
  );
$$;

revoke all on function atlas.financial_connected_source_authorized_self_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.financial_connected_source_authorized_self_v1(uuid) to authenticated, service_role;

create or replace function atlas.record_financial_source_transaction_service_v1(
  p_connected_source_id uuid,
  p_provider_transaction_key text,
  p_observation_id uuid,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_source_amount numeric,
  p_currency text,
  p_raw_description text default null,
  p_source_party_label text default null,
  p_normalization_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_key text := btrim(coalesce(p_provider_transaction_key,''));
  v_currency text := upper(btrim(coalesce(p_currency,'')));
  v_description text := nullif(p_raw_description,'');
  v_party text := nullif(p_source_party_label,'');
  v_existing atlas.financial_source_transactions%rowtype;
  v_transaction atlas.financial_source_transactions%rowtype;
  v_state text;
begin
  if p_connected_source_id is null or p_observation_id is null or v_key = ''
     or p_occurred_on is null or p_source_amount is null or p_source_amount = 0
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Connected source, observation, transaction key, date, nonzero amount, and three-letter currency are required.' using errcode='22023';
  end if;

  if p_normalization_provenance is null or jsonb_typeof(p_normalization_provenance) <> 'object'
     or p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Normalization provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  if not exists (
    select 1
    from atlas.connected_sources source
    where source.id = p_connected_source_id
      and source.authorization_state = 'connected'
  ) then
    raise exception 'Financial transaction intake requires a connected source.' using errcode='55000';
  end if;

  if not exists (
    select 1
    from atlas.connected_source_observations observation
    where observation.id = p_observation_id
      and observation.connected_source_id = p_connected_source_id
      and observation.provider_object_kind = 'financial_transaction'
      and observation.provider_object_key = v_key
  ) then
    raise exception 'Financial transaction observation does not match the connected source and provider key.' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_source_transaction:' || p_connected_source_id::text || ':' || v_key,
    0
  ));

  select * into v_existing
  from atlas.financial_source_transactions transaction
  where transaction.connected_source_id = p_connected_source_id
    and transaction.provider_transaction_key = v_key
  for update;

  if v_existing.id is null then
    insert into atlas.financial_source_transactions(
      connected_source_id,
      provider_transaction_key,
      first_observation_id,
      current_observation_id,
      occurred_on,
      occurred_at,
      source_amount,
      currency,
      raw_description,
      source_party_label,
      normalization_provenance,
      metadata
    ) values (
      p_connected_source_id,
      v_key,
      p_observation_id,
      p_observation_id,
      p_occurred_on,
      p_occurred_at,
      p_source_amount,
      v_currency,
      v_description,
      v_party,
      p_normalization_provenance,
      p_metadata
    ) returning * into v_transaction;
    v_state := 'admitted';
  else
    if v_existing.current_observation_id = p_observation_id
       and v_existing.occurred_on = p_occurred_on
       and v_existing.occurred_at is not distinct from p_occurred_at
       and v_existing.source_amount = p_source_amount
       and v_existing.currency = v_currency
       and v_existing.raw_description is not distinct from v_description
       and v_existing.source_party_label is not distinct from v_party then
      return jsonb_build_object(
        'contractVersion','record_financial_source_transaction_service_v1',
        'state','unchanged',
        'financialTransactionId',v_existing.id,
        'connectedSourceId',v_existing.connected_source_id,
        'currentObservationId',v_existing.current_observation_id
      );
    end if;

    update atlas.financial_source_transactions transaction
    set current_observation_id = p_observation_id,
        occurred_on = p_occurred_on,
        occurred_at = p_occurred_at,
        source_amount = p_source_amount,
        currency = v_currency,
        raw_description = v_description,
        source_party_label = v_party,
        normalization_provenance = p_normalization_provenance,
        metadata = transaction.metadata || p_metadata,
        updated_at = now()
    where transaction.id = v_existing.id
    returning * into v_transaction;
    v_state := 'refreshed';
  end if;

  return jsonb_build_object(
    'contractVersion','record_financial_source_transaction_service_v1',
    'state',v_state,
    'financialTransactionId',v_transaction.id,
    'connectedSourceId',v_transaction.connected_source_id,
    'firstObservationId',v_transaction.first_observation_id,
    'currentObservationId',v_transaction.current_observation_id,
    'sourceAmount',v_transaction.source_amount,
    'currency',v_transaction.currency
  );
end;
$$;

revoke all on function atlas.record_financial_source_transaction_service_v1(
  uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function atlas.record_financial_source_transaction_service_v1(
  uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) to service_role;

create or replace function atlas.replace_financial_source_transaction_review_self_api_v1(
  p_financial_transaction_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth, extensions
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_principal_id uuid;
  v_event_key text := btrim(coalesce(p_client_event_key,''));
  v_allocations jsonb := coalesce(p_allocations,'[]'::jsonb);
  v_input_hash text;
  v_existing_event atlas.financial_source_transaction_review_events%rowtype;
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_item jsonb;
  v_ordinal integer := 0;
  v_amount numeric;
  v_total numeric := 0;
  v_treatment text;
  v_target_ledger_id uuid;
  v_domain text;
  v_kind text;
  v_subject_id text;
  v_unresolved_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if v_event_key = '' or jsonb_typeof(v_allocations) <> 'array'
     or jsonb_array_length(v_allocations) = 0
     or jsonb_array_length(v_allocations) > 50 then
    raise exception 'Client event key and one to fifty review allocations are required.' using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Review metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id = p_financial_transaction_id
  for update;

  if v_transaction.id is null then
    raise exception 'Financial source transaction not found.' using errcode='23503';
  end if;

  if not atlas.financial_connected_source_authorized_self_v1(v_transaction.connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Principal context required.' using errcode='42501';
  end if;

  v_input_hash := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'sourceObservationId',v_transaction.current_observation_id,
      'allocations',v_allocations,
      'metadata',p_metadata
    )::text,
    'utf8'
  ),'sha256'),'hex');

  select * into v_existing_event
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id = p_financial_transaction_id
    and review.client_event_key = v_event_key;

  if v_existing_event.id is not null then
    if v_existing_event.input_sha256 <> v_input_hash then
      raise exception 'Financial transaction review event key was reused with different content.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'contractVersion','replace_financial_source_transaction_review_self_api_v1',
      'state','unchanged',
      'financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_existing_event.id,
      'sourceObservationId',v_existing_event.source_observation_id
    );
  end if;

  for v_item in select value from jsonb_array_elements(v_allocations)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Each financial transaction review allocation must be an object.' using errcode='22023';
    end if;

    begin
      v_amount := (v_item->>'amount')::numeric;
    exception when others then
      raise exception 'Each review allocation requires a numeric amount.' using errcode='22023';
    end;
    if v_amount is null or v_amount <= 0 then
      raise exception 'Each review allocation amount must be greater than zero.' using errcode='22023';
    end if;

    v_treatment := btrim(coalesce(v_item->>'treatmentKind',''));
    if v_treatment not in (
      'operating_expense','operating_revenue','owner_funding','transfer',
      'personal','refund_adjustment','unresolved'
    ) then
      raise exception 'Unsupported financial transaction treatment kind.' using errcode='22023';
    end if;

    begin
      v_target_ledger_id := nullif(v_item->>'targetLedgerId','')::uuid;
    exception when others then
      raise exception 'Review allocation targetLedgerId must be a UUID.' using errcode='22023';
    end;

    if v_treatment in ('operating_expense','operating_revenue') and v_target_ledger_id is null then
      raise exception 'Operating expense and revenue allocations require a target Ledger.' using errcode='22023';
    end if;
    if v_treatment = 'operating_expense' and v_transaction.source_amount >= 0 then
      raise exception 'An operating expense allocation requires a source outflow.' using errcode='22023';
    end if;
    if v_treatment = 'operating_revenue' and v_transaction.source_amount <= 0 then
      raise exception 'An operating revenue allocation requires a source inflow.' using errcode='22023';
    end if;
    if v_treatment = 'owner_funding' and v_transaction.source_amount <= 0 then
      raise exception 'Owner funding requires a source inflow.' using errcode='22023';
    end if;

    if v_target_ledger_id is not null then
      if not exists(select 1 from atlas.ledgers ledger where ledger.id=v_target_ledger_id and ledger.status='active') then
        raise exception 'Review allocation target Ledger is not active.' using errcode='23503';
      end if;
      if not atlas.principal_has_ledger_authority_v1(v_principal_id,v_target_ledger_id) then
        raise exception 'Target Ledger authority required.' using errcode='42501';
      end if;
    end if;

    v_domain := nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_kind := nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id := nullif(btrim(coalesce(v_item->>'subjectId','')),'');
    if not (
      (v_domain is null and v_kind is null and v_subject_id is null)
      or (v_domain is not null and v_kind is not null and v_subject_id is not null)
    ) then
      raise exception 'Review allocation subjectDomain, subjectKind, and subjectId must be supplied together.' using errcode='22023';
    end if;

    v_total := v_total + v_amount;
    if v_treatment = 'unresolved' then v_unresolved_count := v_unresolved_count + 1; end if;
  end loop;

  if v_total <> abs(v_transaction.source_amount) then
    raise exception 'Confirmed review allocations must account for the full absolute source amount.' using errcode='23514';
  end if;

  insert into atlas.financial_source_transaction_review_events(
    financial_transaction_id,
    source_observation_id,
    client_event_key,
    input_sha256,
    reviewed_by_principal_id,
    reviewed_by_user_id,
    review_basis,
    metadata
  ) values (
    p_financial_transaction_id,
    v_transaction.current_observation_id,
    v_event_key,
    v_input_hash,
    v_principal_id,
    auth.uid(),
    jsonb_build_object(
      'authority','replace_financial_source_transaction_review_self_api_v1',
      'fullAmountAccounted',true
    ),
    p_metadata
  ) returning * into v_review;

  v_ordinal := 0;
  for v_item in select value from jsonb_array_elements(v_allocations)
  loop
    v_ordinal := v_ordinal + 1;
    v_amount := (v_item->>'amount')::numeric;
    v_treatment := btrim(v_item->>'treatmentKind');
    v_target_ledger_id := nullif(v_item->>'targetLedgerId','')::uuid;

    insert into atlas.financial_source_transaction_allocations(
      review_event_id,
      allocation_ordinal,
      treatment_kind,
      allocated_amount,
      target_ledger_id,
      operational_purpose,
      subject_domain,
      subject_kind,
      subject_id,
      metadata
    ) values (
      v_review.id,
      v_ordinal,
      v_treatment,
      v_amount,
      v_target_ledger_id,
      nullif(btrim(coalesce(v_item->>'operationalPurpose','')),''),
      nullif(btrim(coalesce(v_item->>'subjectDomain','')),''),
      nullif(btrim(coalesce(v_item->>'subjectKind','')),''),
      nullif(btrim(coalesce(v_item->>'subjectId','')),''),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb)
        else '{}'::jsonb end
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','replace_financial_source_transaction_review_self_api_v1',
    'state','confirmed',
    'financialTransactionId',p_financial_transaction_id,
    'reviewEventId',v_review.id,
    'reviewRevision',v_review.review_revision,
    'sourceObservationId',v_review.source_observation_id,
    'allocationCount',jsonb_array_length(v_allocations),
    'unresolvedAllocationCount',v_unresolved_count,
    'fullyAccounted',true
  );
end;
$$;

revoke all on function atlas.replace_financial_source_transaction_review_self_api_v1(uuid,text,jsonb,jsonb) from public, anon;
grant execute on function atlas.replace_financial_source_transaction_review_self_api_v1(uuid,text,jsonb,jsonb) to authenticated;

create or replace function atlas.financial_source_transaction_review_window_self_api_v1(
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  if p_start_on is null or p_end_on is null or p_end_on < p_start_on then
    raise exception 'A valid financial transaction review date window is required.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_transaction_review_window_self_v1',
    'startOn',p_start_on,
    'endOn',p_end_on,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'financialTransactionId',transaction.id,
        'connectedSourceId',transaction.connected_source_id,
        'providerTransactionKey',transaction.provider_transaction_key,
        'currentObservationId',transaction.current_observation_id,
        'occurredOn',transaction.occurred_on,
        'occurredAt',transaction.occurred_at,
        'sourceAmount',transaction.source_amount,
        'currency',transaction.currency,
        'direction',case when transaction.source_amount < 0 then 'outflow' else 'inflow' end,
        'rawDescription',transaction.raw_description,
        'sourcePartyLabel',transaction.source_party_label,
        'transactionState',transaction.transaction_state,
        'review',case when review.id is null then null else jsonb_build_object(
          'reviewEventId',review.id,
          'reviewRevision',review.review_revision,
          'sourceObservationId',review.source_observation_id,
          'current',review.source_observation_id = transaction.current_observation_id,
          'reviewedAt',review.created_at,
          'allocations',coalesce(review_allocations.items,'[]'::jsonb)
        ) end,
        'promotionCount',coalesce(promotions.promotion_count,0),
        'needsReview',review.id is null or review.source_observation_id <> transaction.current_observation_id
      ) order by transaction.occurred_on,transaction.id)
      from atlas.financial_source_transactions transaction
      left join lateral (
        select r.*
        from atlas.financial_source_transaction_review_events r
        where r.financial_transaction_id=transaction.id
        order by r.review_revision desc
        limit 1
      ) review on true
      left join lateral (
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'allocationId',allocation.id,
          'ordinal',allocation.allocation_ordinal,
          'treatmentKind',allocation.treatment_kind,
          'amount',allocation.allocated_amount,
          'targetLedgerId',allocation.target_ledger_id,
          'operationalPurpose',allocation.operational_purpose,
          'subjectDomain',allocation.subject_domain,
          'subjectKind',allocation.subject_kind,
          'subjectId',allocation.subject_id
        )) order by allocation.allocation_ordinal) as items
        from atlas.financial_source_transaction_allocations allocation
        where allocation.review_event_id=review.id
      ) review_allocations on true
      left join lateral (
        select count(*)::integer as promotion_count
        from atlas.financial_source_transaction_spend_promotions promotion
        where promotion.financial_transaction_id=transaction.id
      ) promotions on true
      where transaction.occurred_on between p_start_on and p_end_on
        and atlas.financial_connected_source_authorized_self_v1(transaction.connected_source_id)
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sourceOwnershipDoesNotDetermineOperationalBeneficiary',true,
      'sourceObservationIsPreservedOutsideReview',true,
      'reviewDoesNotRewriteSourceEvidence',true,
      'spendPromotionIsSeparate',true
    )
  );
end;
$$;

revoke all on function atlas.financial_source_transaction_review_window_self_api_v1(date,date) from public, anon;
grant execute on function atlas.financial_source_transaction_review_window_self_api_v1(date,date) to authenticated;

create or replace function atlas.promote_financial_source_transaction_expense_self_api_v1(
  p_financial_transaction_id uuid,
  p_target_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_ledger atlas.ledgers%rowtype;
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_existing atlas.financial_source_transaction_spend_promotions%rowtype;
  v_principal_id uuid;
  v_membership_id uuid;
  v_funding_kind text;
  v_payer_membership_id uuid;
  v_amount numeric;
  v_allocations jsonb;
  v_spend jsonb;
  v_spend_occurrence_id uuid;
  v_observation_hash text;
  v_observed_at timestamptz;
  v_evidence_record_id uuid;
  v_link_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id=p_financial_transaction_id
  for update;
  if v_transaction.id is null then
    raise exception 'Financial source transaction not found.' using errcode='23503';
  end if;
  if v_transaction.source_amount >= 0 then
    raise exception 'Only source outflows may be promoted as Spend.' using errcode='22023';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(v_transaction.connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  select * into v_source from atlas.connected_sources source where source.id=v_transaction.connected_source_id;
  select * into v_ledger from atlas.ledgers ledger where ledger.id=p_target_ledger_id and ledger.status='active';
  if v_ledger.id is null or v_ledger.organization_id is null then
    raise exception 'Spend promotion requires an active Ledger with a compatibility organization carrier.' using errcode='23503';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null or not atlas.principal_has_ledger_authority_v1(v_principal_id,p_target_ledger_id) then
    raise exception 'Target Ledger authority required.' using errcode='42501';
  end if;
  v_membership_id:=atlas.current_organization_membership_v1(v_ledger.organization_id);
  if v_membership_id is null then
    raise exception 'Target organization membership required for Spend promotion.' using errcode='42501';
  end if;

  select * into v_review
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=p_financial_transaction_id
  order by review.review_revision desc
  limit 1;
  if v_review.id is null then
    raise exception 'A confirmed financial transaction review is required before Spend promotion.' using errcode='55000';
  end if;
  if v_review.source_observation_id <> v_transaction.current_observation_id then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','requires_review',
      'financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_review.id,
      'reviewedObservationId',v_review.source_observation_id,
      'currentObservationId',v_transaction.current_observation_id
    );
  end if;

  select * into v_existing
  from atlas.financial_source_transaction_spend_promotions promotion
  where promotion.financial_transaction_id=p_financial_transaction_id
    and promotion.target_ledger_id=p_target_ledger_id;
  if v_existing.id is not null then
    if v_existing.review_event_id=v_review.id then
      return jsonb_build_object(
        'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
        'state','unchanged',
        'financialTransactionId',p_financial_transaction_id,
        'reviewEventId',v_review.id,
        'spendOccurrenceId',v_existing.spend_occurrence_id
      );
    end if;
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','requires_correction',
      'financialTransactionId',p_financial_transaction_id,
      'previousReviewEventId',v_existing.review_event_id,
      'currentReviewEventId',v_review.id,
      'spendOccurrenceId',v_existing.spend_occurrence_id
    );
  end if;

  select sum(allocation.allocated_amount),
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'amount',allocation.allocated_amount,
           'operationalPurpose',allocation.operational_purpose,
           'subjectDomain',allocation.subject_domain,
           'subjectKind',allocation.subject_kind,
           'subjectId',allocation.subject_id
         )) order by allocation.allocation_ordinal)
  into v_amount,v_allocations
  from atlas.financial_source_transaction_allocations allocation
  where allocation.review_event_id=v_review.id
    and allocation.treatment_kind='operating_expense'
    and allocation.target_ledger_id=p_target_ledger_id;

  if v_amount is null or v_amount <= 0 then
    raise exception 'Current review has no operating expense allocation for the target Ledger.' using errcode='22023';
  end if;

  if v_source.custodian_organization_id=v_ledger.organization_id then
    v_funding_kind:='organization';
    v_payer_membership_id:=null;
  elsif v_source.custodian_user_id=auth.uid() then
    v_funding_kind:='organization_member';
    v_payer_membership_id:=v_membership_id;
  else
    v_funding_kind:='external_party';
    v_payer_membership_id:=null;
  end if;

  v_spend:=atlas.record_organization_spend_core_v1(
    p_target_ledger_id,
    v_ledger.organization_id,
    v_principal_id,
    v_membership_id,
    null,
    v_transaction.occurred_on,
    v_transaction.occurred_at,
    v_amount,
    v_transaction.currency,
    v_funding_kind,
    v_payer_membership_id,
    null,
    coalesce(v_transaction.source_party_label,v_transaction.raw_description),
    'connected_source',
    'financial_source_transaction',
    v_transaction.id::text,
    v_allocations,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v1',
      'financialTransactionId',v_transaction.id,
      'connectedSourceId',v_transaction.connected_source_id,
      'sourceObservationId',v_transaction.current_observation_id,
      'reviewEventId',v_review.id,
      'sourceCustodyIndependentOfOperationalTarget',true
    ),
    jsonb_build_object(
      'importedFromFinancialSource',true,
      'providerTransactionKey',v_transaction.provider_transaction_key
    )
  );
  v_spend_occurrence_id:=(v_spend->>'spendOccurrenceId')::uuid;

  select observation.payload_sha256,observation.observed_at
  into v_observation_hash,v_observed_at
  from atlas.connected_source_observations observation
  where observation.id=v_transaction.current_observation_id;

  insert into atlas.evidence_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    evidence_kind,
    source_kind,
    source_key,
    actor_user_id,
    value,
    confidence,
    observed_at,
    provenance,
    metadata
  ) values (
    'ledger',
    p_target_ledger_id,
    'finance',
    'financial_source_transaction',
    v_transaction.id::text,
    'transaction_observation',
    'connected_source_observation',
    v_transaction.id::text,
    auth.uid(),
    jsonb_build_object(
      'financialTransactionId',v_transaction.id,
      'connectedSourceId',v_transaction.connected_source_id,
      'sourceObservationId',v_transaction.current_observation_id,
      'payloadSha256',v_observation_hash,
      'providerTransactionKey',v_transaction.provider_transaction_key
    ),
    1,
    v_observed_at,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v1',
      'rawEvidenceRemainsInConnectedSourceObservation',true
    ),
    '{}'::jsonb
  ) on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_record_id;

  if v_evidence_record_id is null then
    select evidence.id into v_evidence_record_id
    from atlas.evidence_records evidence
    where evidence.scope_kind='ledger'
      and evidence.scope_id=p_target_ledger_id
      and evidence.source_kind='connected_source_observation'
      and evidence.source_key=v_transaction.id::text;
  end if;

  v_link_id:=atlas.link_organization_spend_evidence_core_v1(
    p_target_ledger_id,
    v_ledger.organization_id,
    v_spend_occurrence_id,
    null,
    v_evidence_record_id,
    'transaction_observation',
    v_principal_id,
    v_membership_id,
    jsonb_build_object('financialTransactionId',v_transaction.id)
  );

  insert into atlas.financial_source_transaction_spend_promotions(
    financial_transaction_id,
    review_event_id,
    target_ledger_id,
    spend_occurrence_id,
    evidence_record_id,
    promoted_by_principal_id,
    promoted_by_membership_id,
    metadata
  ) values (
    v_transaction.id,
    v_review.id,
    p_target_ledger_id,
    v_spend_occurrence_id,
    v_evidence_record_id,
    v_principal_id,
    v_membership_id,
    jsonb_build_object('evidenceLinkId',v_link_id)
  );

  return jsonb_build_object(
    'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
    'state','promoted',
    'financialTransactionId',v_transaction.id,
    'reviewEventId',v_review.id,
    'targetLedgerId',p_target_ledger_id,
    'spendOccurrenceId',v_spend_occurrence_id,
    'evidenceRecordId',v_evidence_record_id,
    'grossAmount',v_amount,
    'currency',v_transaction.currency,
    'fundingKind',v_funding_kind
  );
end;
$$;

revoke all on function atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid) from public, anon;
grant execute on function atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid) to authenticated;

comment on table atlas.financial_source_transactions is
  'Stable normalized financial transaction identity over versioned connected-source observations. Source custody does not establish operational beneficiary or accounting treatment.';
comment on table atlas.financial_source_transaction_review_events is
  'Append-only operator reviews that snapshot the exact connected-source observation being interpreted.';
comment on table atlas.financial_source_transaction_allocations is
  'Review allocations describing what a source transaction was actually for. Target Ledger is independent of source custody.';
comment on table atlas.financial_source_transaction_spend_promotions is
  'Audit bridge from a reviewed source transaction to canonical organization Spend. Promotion never rewrites source evidence.';

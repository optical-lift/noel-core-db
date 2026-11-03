-- Atlas Money Collection Kernel v1 — domain adapter/cutover tranche.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- This tranche deliberately does NOT activate coverage rows. The generated
-- migration must call activate_money_source_adapter_coverage_core_v1 with its
-- real governed migration/release provenance in the same transaction as these
-- writer replacements. No timestamp or migration identity is fabricated here.

create or replace function atlas.activate_money_source_adapter_coverage_core_v1(
  p_source_domain text,
  p_source_kind text,
  p_obligation_kind text,
  p_adapter_contract text,
  p_coverage_started_at timestamptz,
  p_release_provenance text,
  p_source_lower_bound text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain text := lower(nullif(btrim(p_source_domain),''));
  v_kind text := lower(nullif(btrim(p_source_kind),''));
  v_obligation_kind text := lower(nullif(btrim(p_obligation_kind),''));
  v_contract text := lower(nullif(btrim(p_adapter_contract),''));
  v_release text := nullif(btrim(p_release_provenance),'');
  v_existing atlas.money_source_adapter_coverage%rowtype;
begin
  if v_domain is null or v_kind is null or v_obligation_kind is null or v_contract is null
     or p_coverage_started_at is null or v_release is null then
    raise exception 'Money source-adapter activation identity is incomplete.' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_domain||':'||v_kind||':'||v_obligation_kind,0)
  );

  select * into v_existing
  from atlas.money_source_adapter_coverage c
  where c.source_domain=v_domain
    and c.source_kind=v_kind
    and c.obligation_kind=v_obligation_kind
    and c.adapter_contract=v_contract;
  if v_existing.id is not null then
    if v_existing.status is distinct from 'active'
       or v_existing.coverage_started_at is distinct from p_coverage_started_at
       or v_existing.release_provenance is distinct from v_release then
      raise exception 'Money source-adapter activation retry conflicts with existing coverage.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists(
    select 1 from atlas.money_source_adapter_coverage c
    where c.source_domain=v_domain
      and c.source_kind=v_kind
      and c.obligation_kind=v_obligation_kind
      and c.status='active'
  ) then
    raise exception 'Another money source-adapter contract is already active for this source.' using errcode='23505';
  end if;

  insert into atlas.money_source_adapter_coverage(
    source_domain,source_kind,obligation_kind,adapter_contract,
    coverage_started_at,status,release_provenance,source_lower_bound,metadata
  ) values (
    v_domain,v_kind,v_obligation_kind,v_contract,
    p_coverage_started_at,'active',v_release,nullif(btrim(coalesce(p_source_lower_bound,'')),''),
    coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.ensure_community_registration_money_obligation_v1(
  p_registration_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registration atlas.community_registrations%rowtype;
  v_offering atlas.community_registration_offerings%rowtype;
  v_organization_id uuid;
  v_coverage atlas.money_source_adapter_coverage%rowtype;
begin
  if p_registration_id is null then
    raise exception 'Registration id is required.' using errcode='22023';
  end if;

  select r.* into v_registration
  from atlas.community_registrations r
  where r.id=p_registration_id
  for update;
  if v_registration.id is null then
    raise exception 'Community Registration not found.' using errcode='P0002';
  end if;

  select o.* into v_offering
  from atlas.community_registration_offerings o
  where o.id=v_registration.offering_id;
  select f.organization_id into v_organization_id
  from atlas.farms f
  where f.id=v_offering.farm_id;
  if v_offering.id is null or v_organization_id is null then
    raise exception 'Community Registration source custody is incomplete.' using errcode='23503';
  end if;

  if v_offering.fee_amount=0 then
    return null;
  end if;
  if v_offering.fee_amount<0 then
    raise exception 'Community Registration fee cannot be negative.' using errcode='23514';
  end if;

  select * into v_coverage
  from atlas.money_source_adapter_coverage c
  where c.source_domain='community_registration'
    and c.source_kind='registration'
    and c.obligation_kind='participation_fee'
    and c.coverage_started_at<=v_registration.created_at
    and (c.coverage_ended_at is null or v_registration.created_at<c.coverage_ended_at)
  order by c.coverage_started_at desc
  limit 1;

  if v_coverage.id is null then
    if exists(
      select 1 from atlas.money_source_adapter_coverage c
      where c.source_domain='community_registration'
        and c.source_kind='registration'
        and c.obligation_kind='participation_fee'
        and c.status='active'
        and v_registration.created_at<c.coverage_started_at
    ) then
      return null; -- explicitly historical/pre-kernel source
    end if;
    raise exception 'Community Registration money adapter is not active for this source time.' using errcode='23514';
  end if;

  return atlas.ensure_money_obligation_core_v1(
    v_organization_id,
    'community_registration',
    'registration',
    v_registration.id::text,
    'participation_fee',
    v_offering.fee_amount,
    v_offering.fee_currency,
    null,
    'community_registration:'||v_registration.id::text||':participation_fee',
    auth.uid(),
    jsonb_build_object(
      'adapterContract',v_coverage.adapter_contract,
      'coverageId',v_coverage.id,
      'offeringId',v_offering.id,
      'feeSnapshotAuthority','community_registration_offerings'
    )
  );
end;
$$;

create or replace function atlas.community_registration_money_position_v1(
  p_registration_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_registration atlas.community_registrations%rowtype;
  v_offering atlas.community_registration_offerings%rowtype;
  v_organization_id uuid;
begin
  select r.* into v_registration from atlas.community_registrations r where r.id=p_registration_id;
  if v_registration.id is null then raise exception 'Community Registration not found.' using errcode='P0002'; end if;
  select o.* into v_offering from atlas.community_registration_offerings o where o.id=v_registration.offering_id;
  select f.organization_id into v_organization_id from atlas.farms f where f.id=v_offering.farm_id;
  if v_organization_id is null then raise exception 'Community Registration source custody is incomplete.' using errcode='23503'; end if;

  return atlas.money_source_coverage_state_core_v1(
    v_organization_id,'community_registration','registration',v_registration.id::text,
    'participation_fee',v_registration.created_at,v_offering.fee_amount
  );
end;
$$;

create or replace function atlas.ensure_flower_sale_money_obligation_v1(
  p_sale_order_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale atlas.flower_sale_orders%rowtype;
  v_organization_id uuid;
  v_coverage atlas.money_source_adapter_coverage%rowtype;
begin
  if p_sale_order_id is null then raise exception 'Flower Sale id is required.' using errcode='22023'; end if;

  select s.* into v_sale
  from atlas.flower_sale_orders s
  where s.id=p_sale_order_id
  for update;
  if v_sale.id is null then raise exception 'Flower Sale not found.' using errcode='P0002'; end if;
  select f.organization_id into v_organization_id from atlas.farms f where f.id=v_sale.farm_id;
  if v_organization_id is null then raise exception 'Flower Sale source custody is incomplete.' using errcode='23503'; end if;

  if v_sale.total_amount=0 then return null; end if;
  if v_sale.total_amount<0 then raise exception 'Flower Sale total cannot be negative.' using errcode='23514'; end if;

  select * into v_coverage
  from atlas.money_source_adapter_coverage c
  where c.source_domain='flower_commerce'
    and c.source_kind='flower_sale_order'
    and c.obligation_kind='sale_total'
    and c.coverage_started_at<=v_sale.created_at
    and (c.coverage_ended_at is null or v_sale.created_at<c.coverage_ended_at)
  order by c.coverage_started_at desc
  limit 1;

  if v_coverage.id is null then
    if exists(
      select 1 from atlas.money_source_adapter_coverage c
      where c.source_domain='flower_commerce'
        and c.source_kind='flower_sale_order'
        and c.obligation_kind='sale_total'
        and c.status='active'
        and v_sale.created_at<c.coverage_started_at
    ) then
      return null; -- pre-kernel Sale remains payment-unknown; never backfill from absence
    end if;
    raise exception 'Flower Sale money adapter is not active for this source time.' using errcode='23514';
  end if;

  return atlas.ensure_money_obligation_core_v1(
    v_organization_id,
    'flower_commerce',
    'flower_sale_order',
    v_sale.id::text,
    'sale_total',
    v_sale.total_amount,
    v_sale.currency,
    null,
    'flower_sale:'||v_sale.id::text||':sale_total',
    v_sale.created_by_user_id,
    jsonb_build_object(
      'adapterContract',v_coverage.adapter_contract,
      'coverageId',v_coverage.id,
      'saleTotalAuthority','flower_sale_orders',
      'farmId',v_sale.farm_id
    )
  );
end;
$$;

create or replace function atlas.flower_sale_money_position_v1(
  p_sale_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sale atlas.flower_sale_orders%rowtype;
  v_organization_id uuid;
begin
  select s.* into v_sale from atlas.flower_sale_orders s where s.id=p_sale_order_id;
  if v_sale.id is null then raise exception 'Flower Sale not found.' using errcode='P0002'; end if;
  select f.organization_id into v_organization_id from atlas.farms f where f.id=v_sale.farm_id;
  if v_organization_id is null then raise exception 'Flower Sale source custody is incomplete.' using errcode='23503'; end if;

  return atlas.money_source_coverage_state_core_v1(
    v_organization_id,'flower_commerce','flower_sale_order',v_sale.id::text,
    'sale_total',v_sale.created_at,v_sale.total_amount
  );
end;
$$;

-- Clean-cutover precondition. If this assertion ever fails, the release must
-- stop for explicit Registration/payment reconciliation instead of guessing.
do $$
begin
  if exists(select 1 from atlas.community_registrations) then
    raise exception 'Money kernel clean Registration cutover aborted: canonical registrations now exist.' using errcode='23514';
  end if;
  if exists(select 1 from atlas.community_registration_payments) then
    raise exception 'Money kernel clean Registration cutover aborted: legacy payment rows now exist.' using errcode='23514';
  end if;
end;
$$;

-- Flower v1 writer fence. PL/pgSQL call sites are body text rather than reliable
-- pg_depend edges, so inspect every Atlas function body immediately at release.
do $$
declare
  v_consumer text;
begin
  select string_agg(p.oid::regprocedure::text,E'\n' order by p.oid::regprocedure::text)
  into v_consumer
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.oid <> 'atlas.record_flower_sale_core_v1(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)'::regprocedure
    and pg_catalog.pg_get_functiondef(p.oid) like '%record_flower_sale_core_v1%';

  if v_consumer is not null then
    raise exception 'Cannot fence record_flower_sale_core_v1; consumers remain: %',v_consumer using errcode='23514';
  end if;
end;
$$;

revoke execute on function atlas.record_flower_sale_core_v1(
  uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,
  uuid,uuid,text,text,boolean
) from public,anon,authenticated,service_role;

-- Preserve the current proven v2 Flower domain implementation as an unexposed
-- subordinate implementation, then make the canonical v2 name carry the money
-- postcondition on BOTH new-sale and existing-sale/idempotent branches.
alter function atlas.record_flower_sale_core_v2(
  uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,
  uuid,uuid,text,text,boolean
) rename to record_flower_sale_core_v2_domain_impl;

revoke execute on function atlas.record_flower_sale_core_v2_domain_impl(
  uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,
  uuid,uuid,text,text,boolean
) from public,anon,authenticated,service_role;

create or replace function atlas.record_flower_sale_core_v2(
  p_farm_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_buyer_relationship_id uuid,
  p_customer_label text,
  p_sales_channel text,
  p_event_key text,
  p_lines jsonb,
  p_tax_amount numeric,
  p_tip_amount numeric,
  p_fulfillment_mode text,
  p_fulfillment_due_date date,
  p_fulfillment_due_time time without time zone,
  p_fulfillment_membership_id uuid,
  p_source_task_id uuid,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_sale_order_id uuid;
begin
  v_result := atlas.record_flower_sale_core_v2_domain_impl(
    p_farm_id,p_effective_membership_id,p_effective_role,p_buyer_relationship_id,
    p_customer_label,p_sales_channel,p_event_key,p_lines,p_tax_amount,p_tip_amount,
    p_fulfillment_mode,p_fulfillment_due_date,p_fulfillment_due_time,
    p_fulfillment_membership_id,p_source_task_id,p_note,p_idempotency_key,p_operator_mode
  );

  begin
    v_sale_order_id := nullif(v_result->>'saleOrderId','')::uuid;
  exception when others then
    raise exception 'Flower Sale v2 domain result omitted canonical Sale identity.' using errcode='23514';
  end;
  if v_sale_order_id is null then
    raise exception 'Flower Sale v2 domain result omitted canonical Sale identity.' using errcode='23514';
  end if;

  perform atlas.ensure_flower_sale_money_obligation_v1(v_sale_order_id);
  return v_result;
end;
$$;

revoke execute on function atlas.record_flower_sale_core_v2(
  uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,
  uuid,uuid,text,text,boolean
) from public,anon,authenticated,service_role;

-- Replace provisional Registration-local payment-row creation with the canonical
-- participation-fee obligation postcondition. Registration lifecycle remains
-- registration-owned; the Money kernel does not confirm the registration.
create or replace function atlas.submit_public_household_registration_v1(
  p_offering_key text,
  p_primary_name text,
  p_primary_email text,
  p_primary_phone text default null,
  p_household_name text default null,
  p_participant_names text[] default '{}'::text[],
  p_terms_accepted boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','atlas'
as $$
declare
  v_offering atlas.community_registration_offerings%rowtype;
  v_registration atlas.community_registrations%rowtype;
  v_name text := trim(coalesce(p_primary_name,''));
  v_email text := lower(trim(coalesce(p_primary_email,'')));
  v_phone text := nullif(trim(coalesce(p_primary_phone,'')), '');
  v_household text := nullif(trim(coalesce(p_household_name,'')), '');
  v_participant text;
  v_registration_number text;
  v_registration_status text;
begin
  if not p_terms_accepted then
    raise exception using errcode='22023',message='Participation terms must be accepted.';
  end if;
  if length(v_name)<2 or length(v_name)>120 then
    raise exception using errcode='22023',message='Primary adult name is required.';
  end if;
  if length(v_email)<5 or length(v_email)>254 or position('@' in v_email)<2 then
    raise exception using errcode='22023',message='A valid email address is required.';
  end if;
  if v_phone is not null and length(v_phone)>40 then
    raise exception using errcode='22023',message='Phone number is too long.';
  end if;
  if v_household is not null and length(v_household)>120 then
    raise exception using errcode='22023',message='Household name is too long.';
  end if;

  select * into v_offering
  from atlas.community_registration_offerings o
  where o.stable_key=trim(p_offering_key)
    and o.registration_type='household_participation'
    and o.status='open'
    and (o.opens_at is null or o.opens_at<=now())
    and (o.closes_at is null or o.closes_at>=now())
  limit 1;
  if not found then
    raise exception using errcode='P0002',message='Registration is not currently open for this program.';
  end if;

  if exists(
    select 1 from atlas.community_registrations r
    where r.offering_id=v_offering.id
      and lower(r.primary_email)=v_email
      and r.status not in ('cancelled','refunded')
  ) then
    raise exception using errcode='23505',message='This email is already registered for this program.';
  end if;

  v_registration_number := 'ELM-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_registration_status := case when v_offering.fee_amount>0 then 'payment_pending' else 'confirmed' end;

  insert into atlas.community_registrations(
    offering_id,registration_number,registrant_type,status,
    primary_name,primary_email,primary_phone,household_name,
    submitted_at,confirmed_at,metadata
  ) values (
    v_offering.id,v_registration_number,'household',v_registration_status,
    v_name,v_email,v_phone,v_household,
    now(),case when v_offering.fee_amount=0 then now() else null end,
    jsonb_build_object(
      'source','public_registration_v1',
      'terms_version',v_offering.terms_version,
      'terms_accepted_at',now()
    )
  ) returning * into v_registration;

  insert into atlas.community_registration_participants(registration_id,display_name,participant_role)
  values(v_registration.id,v_name,'adult');

  foreach v_participant in array coalesce(p_participant_names,'{}'::text[])
  loop
    v_participant := trim(v_participant);
    if v_participant<>'' then
      if length(v_participant)>120 then
        raise exception using errcode='22023',message='Participant name is too long.';
      end if;
      insert into atlas.community_registration_participants(registration_id,display_name,participant_role)
      values(v_registration.id,v_participant,'family_member');
    end if;
  end loop;

  perform atlas.ensure_community_registration_money_obligation_v1(v_registration.id);

  return jsonb_build_object(
    'ok',true,
    'registration_id',v_registration.id,
    'registration_number',v_registration.registration_number,
    'status',v_registration.status,
    'payment_status',case when v_offering.fee_amount>0 then 'pending' else 'not_required' end,
    'amount_due',v_offering.fee_amount,
    'currency',v_offering.fee_currency,
    'message',case
      when v_offering.fee_amount>0 then 'Registration received. Payment instructions will follow.'
      else 'Registration confirmed.'
    end
  );
end;
$$;

revoke all on function atlas.submit_public_household_registration_v1(text,text,text,text,text,text[],boolean) from public;
grant execute on function atlas.submit_public_household_registration_v1(text,text,text,text,text,text[],boolean)
  to anon,authenticated,service_role;

-- The provisional table has no historical rows at the asserted cutover boundary
-- and no longer has a business writer. Remove it rather than preserve a second
-- mutable payment clock.
drop table atlas.community_registration_payments;

insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,consumer_surfaces,
  known_competitors,source_custody,rationale,updated_at
) values (
  'money_collection_effective_position',
  'money_collection',
  'What money is canonically owed, received, allocated, reversed, and still open for a covered source transaction?',
  'atlas.money_obligation_position_v1',
  'canonical',
  array['atlas.money_obligations','atlas.money_receipts','atlas.money_receipt_allocations','atlas.money_receipt_reversal_events','atlas.money_receipt_allocation_reversal_events'],
  array['atlas.money_obligation_position_v1','atlas.money_receipt_position_v1'],
  array['atlas.money_collection_attempts','atlas.money_provider_events'],
  array[]::text[],
  array['provider payment status','community_registration_payments.status','flower fulfillment state as payment evidence'],
  'optical-lift/noel-core-db:supabase/migrations',
  'Domain price and lifecycle truth remain upstream. Canonical paid/open truth is derived only from obligation, admissible receipt/allocation, and reversal evidence.',
  now()
),(
  'money_collection_source_coverage',
  'money_collection',
  'Is this source transaction inside canonical Money Collection coverage, and what may Atlas conclude if no obligation exists?',
  'atlas.money_source_adapter_coverage',
  'canonical',
  array['atlas.money_source_adapter_coverage'],
  array['atlas.money_source_coverage_state_core_v1'],
  array['atlas.money_obligations'],
  array[]::text[],
  array['assuming historical sources are covered','missing obligation treated as unpaid','provider connection status treated as coverage','per-organization activation for globally installed adapters'],
  'optical-lift/noel-core-db:supabase/migrations',
  'Coverage is global to a shared source-adapter contract. Organization custody remains on each source transaction and money object; historical absence of an obligation is not fabricated into payment truth.',
  now()
)
on conflict(authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

revoke execute on function atlas.activate_money_source_adapter_coverage_core_v1(text,text,text,text,timestamptz,text,text,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.ensure_community_registration_money_obligation_v1(uuid)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.community_registration_money_position_v1(uuid)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.ensure_flower_sale_money_obligation_v1(uuid)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.flower_sale_money_position_v1(uuid)
  from public,anon,authenticated,service_role;

-- Generated-migration-only activation calls (shown conceptually, not executed
-- here because release provenance must be the real generated migration identity):
--
-- select atlas.activate_money_source_adapter_coverage_core_v1(
--   'community_registration','registration','participation_fee',
--   'community_registration_money_v1',transaction_timestamp(),<REAL_RELEASE_PROVENANCE>,null,
--   '{"cleanCutover":true}'::jsonb
-- );
-- select atlas.activate_money_source_adapter_coverage_core_v1(
--   'flower_commerce','flower_sale_order','sale_total',
--   'flower_sale_money_v1',transaction_timestamp(),<REAL_RELEASE_PROVENANCE>,null,
--   '{"historicalAbsenceMeans":"payment_truth_unknown_pre_kernel"}'::jsonb
-- );

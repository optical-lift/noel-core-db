-- Atlas Money Collection Kernel v1 — Community Registration fee snapshot correction.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- This tranche must be assembled AFTER atlas-money-collection-kernel-v1-domain-adapters.sql.
-- That prior tranche asserts the clean Registration cutover (zero registrations and
-- zero legacy payment rows). This tranche then makes accepted fee truth explicit on
-- the Registration birth row and replaces the provisional adapter definitions.
--
-- Governing rule:
--   offering fee at Registration birth -> typed immutable Registration snapshot
--   Registration snapshot -> participation_fee obligation
--   later offering edits DO NOT rewrite an existing family receivable.

alter table atlas.community_registrations
  add column fee_amount_at_submission numeric(14,2) not null
    check (fee_amount_at_submission >= 0),
  add column fee_currency_at_submission text not null
    check (fee_currency_at_submission ~ '^[A-Z]{3}$'),
  add column fee_basis_at_submission text not null
    check (btrim(fee_basis_at_submission) <> '');

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

  if v_registration.fee_amount_at_submission=0 then
    return null;
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
      return null;
    end if;
    raise exception 'Community Registration money adapter is not active for this source time.' using errcode='23514';
  end if;

  return atlas.ensure_money_obligation_core_v1(
    v_organization_id,
    'community_registration',
    'registration',
    v_registration.id::text,
    'participation_fee',
    v_registration.fee_amount_at_submission,
    v_registration.fee_currency_at_submission,
    null,
    'community_registration:'||v_registration.id::text||':participation_fee',
    auth.uid(),
    jsonb_build_object(
      'adapterContract',v_coverage.adapter_contract,
      'coverageId',v_coverage.id,
      'offeringId',v_registration.offering_id,
      'feeSnapshotAuthority','community_registrations',
      'feeSnapshotVersion','community_registration_fee_snapshot_v1'
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
  select r.* into v_registration
  from atlas.community_registrations r
  where r.id=p_registration_id;
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

  return atlas.money_source_coverage_state_core_v1(
    v_organization_id,
    'community_registration',
    'registration',
    v_registration.id::text,
    'participation_fee',
    v_registration.created_at,
    v_registration.fee_amount_at_submission
  );
end;
$$;

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
    fee_amount_at_submission,fee_currency_at_submission,fee_basis_at_submission,
    submitted_at,confirmed_at,metadata
  ) values (
    v_offering.id,v_registration_number,'household',v_registration_status,
    v_name,v_email,v_phone,v_household,
    round(v_offering.fee_amount,2),upper(v_offering.fee_currency),v_offering.fee_basis,
    now(),case when v_offering.fee_amount=0 then now() else null end,
    jsonb_build_object(
      'source','public_registration_v1',
      'terms_version',v_offering.terms_version,
      'terms_accepted_at',now(),
      'fee_snapshot_version','community_registration_fee_snapshot_v1'
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
    'payment_status',case when v_registration.fee_amount_at_submission>0 then 'pending' else 'not_required' end,
    'amount_due',v_registration.fee_amount_at_submission,
    'currency',v_registration.fee_currency_at_submission,
    'message',case
      when v_registration.fee_amount_at_submission>0 then 'Registration received. Payment instructions will follow.'
      else 'Registration confirmed.'
    end
  );
end;
$$;

revoke all on function atlas.ensure_community_registration_money_obligation_v1(uuid)
  from public,anon,authenticated,service_role;
revoke all on function atlas.community_registration_money_position_v1(uuid)
  from public,anon,authenticated,service_role;
revoke all on function atlas.submit_public_household_registration_v1(text,text,text,text,text,text[],boolean)
  from public;
grant execute on function atlas.submit_public_household_registration_v1(text,text,text,text,text,text[],boolean)
  to anon,authenticated,service_role;

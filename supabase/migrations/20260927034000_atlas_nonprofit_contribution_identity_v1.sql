-- Atlas nonprofit contribution identity kernel v1.
--
-- Contributions, pledges, and grant awards are fundraising facts about canonical Reality
-- entities. They do not own donor/funder identity, copied contact data, donor restrictions,
-- accounting recognition, or journal truth.

create table if not exists atlas.fundraising_contributions (
  id uuid primary key default gen_random_uuid(),
  fundraising_entity_id uuid not null references reality.entities(id) on delete restrict,
  contributor_entity_id uuid not null references reality.entities(id) on delete restrict,
  client_event_key text not null,
  received_on date not null,
  contribution_kind text not null,
  stated_amount numeric,
  currency text,
  record_state text not null default 'confirmed',
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete set null,
  establishment_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fundraising_contributions_entities_distinct check (fundraising_entity_id<>contributor_entity_id),
  constraint fundraising_contributions_event_key_nonempty check (btrim(client_event_key)<>''),
  constraint fundraising_contributions_kind_check check (
    contribution_kind in ('cash','check','card','ach','wire','stock','noncash','in_kind','other')
  ),
  constraint fundraising_contributions_amount_check check (stated_amount is null or stated_amount>0),
  constraint fundraising_contributions_currency_check check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint fundraising_contributions_value_pair_check check (
    (stated_amount is null and currency is null) or (stated_amount is not null and currency is not null)
  ),
  constraint fundraising_contributions_state_check check (record_state in ('observed','confirmed','voided')),
  constraint fundraising_contributions_basis_object check (jsonb_typeof(establishment_basis)='object'),
  constraint fundraising_contributions_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(fundraising_entity_id,client_event_key)
);

create index if not exists fundraising_contributions_contributor_idx
  on atlas.fundraising_contributions(fundraising_entity_id,contributor_entity_id,received_on desc,id)
  where record_state<>'voided';

create table if not exists atlas.fundraising_pledges (
  id uuid primary key default gen_random_uuid(),
  fundraising_entity_id uuid not null references reality.entities(id) on delete restrict,
  contributor_entity_id uuid not null references reality.entities(id) on delete restrict,
  client_event_key text not null,
  pledged_on date not null,
  promised_amount numeric not null,
  currency text not null,
  due_on date,
  pledge_state text not null default 'open',
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete set null,
  establishment_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fundraising_pledges_entities_distinct check (fundraising_entity_id<>contributor_entity_id),
  constraint fundraising_pledges_event_key_nonempty check (btrim(client_event_key)<>''),
  constraint fundraising_pledges_amount_check check (promised_amount>0),
  constraint fundraising_pledges_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint fundraising_pledges_date_check check (due_on is null or due_on>=pledged_on),
  constraint fundraising_pledges_state_check check (pledge_state in ('open','fulfilled','cancelled','expired')),
  constraint fundraising_pledges_basis_object check (jsonb_typeof(establishment_basis)='object'),
  constraint fundraising_pledges_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(fundraising_entity_id,client_event_key)
);

create index if not exists fundraising_pledges_contributor_idx
  on atlas.fundraising_pledges(fundraising_entity_id,contributor_entity_id,pledged_on desc,id);

create table if not exists atlas.fundraising_grant_awards (
  id uuid primary key default gen_random_uuid(),
  fundraising_entity_id uuid not null references reality.entities(id) on delete restrict,
  funder_entity_id uuid not null references reality.entities(id) on delete restrict,
  award_key text not null,
  awarded_on date not null,
  authorized_amount numeric,
  currency text,
  award_start_on date,
  award_end_on date,
  award_state text not null default 'active',
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete set null,
  establishment_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fundraising_grant_awards_entities_distinct check (fundraising_entity_id<>funder_entity_id),
  constraint fundraising_grant_awards_key_nonempty check (btrim(award_key)<>''),
  constraint fundraising_grant_awards_amount_check check (authorized_amount is null or authorized_amount>0),
  constraint fundraising_grant_awards_currency_check check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint fundraising_grant_awards_value_pair_check check (
    (authorized_amount is null and currency is null) or (authorized_amount is not null and currency is not null)
  ),
  constraint fundraising_grant_awards_period_check check (
    award_start_on is null or award_end_on is null or award_end_on>=award_start_on
  ),
  constraint fundraising_grant_awards_state_check check (award_state in ('announced','active','closed','cancelled')),
  constraint fundraising_grant_awards_basis_object check (jsonb_typeof(establishment_basis)='object'),
  constraint fundraising_grant_awards_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(fundraising_entity_id,award_key)
);

create index if not exists fundraising_grant_awards_funder_idx
  on atlas.fundraising_grant_awards(fundraising_entity_id,funder_entity_id,awarded_on desc,id);

alter table atlas.fundraising_contributions enable row level security;
alter table atlas.fundraising_pledges enable row level security;
alter table atlas.fundraising_grant_awards enable row level security;
revoke all on table atlas.fundraising_contributions from public,anon,authenticated;
revoke all on table atlas.fundraising_pledges from public,anon,authenticated;
revoke all on table atlas.fundraising_grant_awards from public,anon,authenticated;

create or replace function atlas.guard_fundraising_financial_party_identity_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_fundraising_entity_id uuid;
  v_counterparty_entity_id uuid;
  v_fundraising_kind text;
  v_counterparty_kind text;
begin
  v_fundraising_entity_id:=new.fundraising_entity_id;
  if tg_table_name='fundraising_grant_awards' then
    v_counterparty_entity_id:=new.funder_entity_id;
  else
    v_counterparty_entity_id:=new.contributor_entity_id;
  end if;

  select e.entity_kind into v_fundraising_kind
  from reality.entities e
  where e.id=v_fundraising_entity_id and e.identity_state='canonical';
  if v_fundraising_kind is null or v_fundraising_kind not in ('business','organization') then
    raise exception 'Fundraising financial record requires canonical Reality business/organization.' using errcode='23514';
  end if;

  select e.entity_kind into v_counterparty_kind
  from reality.entities e
  where e.id=v_counterparty_entity_id and e.identity_state='canonical';
  if v_counterparty_kind is null or v_counterparty_kind not in ('person','business','organization') then
    raise exception 'Contributor/funder must be a canonical Reality entity.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_fundraising_financial_party_identity_v1()
  from public,anon,authenticated;

create trigger fundraising_contributions_party_identity_guard_v1
before insert or update of fundraising_entity_id,contributor_entity_id
on atlas.fundraising_contributions
for each row execute function atlas.guard_fundraising_financial_party_identity_v1();

create trigger fundraising_pledges_party_identity_guard_v1
before insert or update of fundraising_entity_id,contributor_entity_id
on atlas.fundraising_pledges
for each row execute function atlas.guard_fundraising_financial_party_identity_v1();

create trigger fundraising_grant_awards_party_identity_guard_v1
before insert or update of fundraising_entity_id,funder_entity_id
on atlas.fundraising_grant_awards
for each row execute function atlas.guard_fundraising_financial_party_identity_v1();

create or replace function atlas.record_fundraising_contribution_self_api_v1(
  p_fundraising_entity_id uuid,
  p_contributor_entity_id uuid,
  p_client_event_key text,
  p_received_on date,
  p_contribution_kind text,
  p_stated_amount numeric default null,
  p_currency text default null,
  p_establishment_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_kind text:=lower(btrim(coalesce(p_contribution_kind,'')));
  v_currency text:=nullif(upper(btrim(coalesce(p_currency,''))),'');
  v_principal_id uuid;
  v_row atlas.fundraising_contributions%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;
  if v_key='' or p_received_on is null then raise exception 'Contribution event key and received date required.' using errcode='22023'; end if;
  if v_kind not in ('cash','check','card','ach','wire','stock','noncash','in_kind','other') then
    raise exception 'Unsupported contribution kind.' using errcode='22023';
  end if;
  if (p_stated_amount is null)<>(v_currency is null) then
    raise exception 'Contribution amount and currency must be supplied together.' using errcode='22023';
  end if;
  if p_stated_amount is not null and p_stated_amount<=0 then raise exception 'Contribution stated amount must be positive.' using errcode='22023'; end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then raise exception 'Contribution currency must be a three-letter code.' using errcode='22023'; end if;
  if p_establishment_basis is null or jsonb_typeof(p_establishment_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Contribution basis and metadata must be JSON objects.' using errcode='22023';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();

  insert into atlas.fundraising_contributions(
    fundraising_entity_id,contributor_entity_id,client_event_key,received_on,contribution_kind,
    stated_amount,currency,record_state,established_by_principal_id,established_by_user_id,
    establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_contributor_entity_id,v_key,p_received_on,v_kind,
    p_stated_amount,v_currency,'confirmed',v_principal_id,auth.uid(),
    p_establishment_basis||jsonb_build_object(
      'authority','record_fundraising_contribution_self_api_v1',
      'canonicalContributorRequired',true,
      'accountingRecognitionEstablished',false,
      'restrictionEstablished',false
    ),p_metadata
  ) on conflict(fundraising_entity_id,client_event_key)
  do update set
    contributor_entity_id=excluded.contributor_entity_id,
    received_on=excluded.received_on,
    contribution_kind=excluded.contribution_kind,
    stated_amount=excluded.stated_amount,
    currency=excluded.currency,
    record_state='confirmed',
    establishment_basis=atlas.fundraising_contributions.establishment_basis||excluded.establishment_basis,
    metadata=atlas.fundraising_contributions.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_row;

  insert into atlas.fundraising_constituent_relationships(
    fundraising_entity_id,constituent_entity_id,relationship_kind,relationship_state,
    established_by_principal_id,established_by_user_id,establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_contributor_entity_id,'supporter','active',
    v_principal_id,auth.uid(),jsonb_build_object(
      'authority','record_fundraising_contribution_self_api_v1',
      'derivedFromConfirmedContributionId',v_row.id
    ),'{}'::jsonb
  ) on conflict(fundraising_entity_id,constituent_entity_id,relationship_kind)
  do update set relationship_state='active',ended_at=null,updated_at=now();

  return jsonb_build_object(
    'contractVersion','fundraising_contribution_v1',
    'contributionId',v_row.id,
    'fundraisingEntityId',v_row.fundraising_entity_id,
    'contributorEntityId',v_row.contributor_entity_id,
    'receivedOn',v_row.received_on,
    'contributionKind',v_row.contribution_kind,
    'statedAmount',v_row.stated_amount,
    'currency',v_row.currency,
    'recordState',v_row.record_state,
    'truthBoundary',jsonb_build_object(
      'canonicalContributorOwnedByReality',true,
      'donorNameCopied',false,
      'accountingRecognitionEstablished',false,
      'restrictionEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;

revoke all on function atlas.record_fundraising_contribution_self_api_v1(uuid,uuid,text,date,text,numeric,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.record_fundraising_contribution_self_api_v1(uuid,uuid,text,date,text,numeric,text,jsonb,jsonb)
  to authenticated;

create or replace function atlas.record_fundraising_pledge_self_api_v1(
  p_fundraising_entity_id uuid,
  p_contributor_entity_id uuid,
  p_client_event_key text,
  p_pledged_on date,
  p_promised_amount numeric,
  p_currency text,
  p_due_on date default null,
  p_establishment_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_principal_id uuid;
  v_row atlas.fundraising_pledges%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then raise exception 'Fundraising entity authority required.' using errcode='42501'; end if;
  if v_key='' or p_pledged_on is null or p_promised_amount is null or p_promised_amount<=0 or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Pledge key, date, positive amount, and three-letter currency required.' using errcode='22023';
  end if;
  if p_due_on is not null and p_due_on<p_pledged_on then raise exception 'Pledge due date cannot precede pledge date.' using errcode='22023'; end if;
  if p_establishment_basis is null or jsonb_typeof(p_establishment_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Pledge basis and metadata must be JSON objects.' using errcode='22023'; end if;

  v_principal_id:=atlas.current_principal_id_v1();
  insert into atlas.fundraising_pledges(
    fundraising_entity_id,contributor_entity_id,client_event_key,pledged_on,promised_amount,currency,due_on,
    pledge_state,established_by_principal_id,established_by_user_id,establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_contributor_entity_id,v_key,p_pledged_on,p_promised_amount,v_currency,p_due_on,
    'open',v_principal_id,auth.uid(),p_establishment_basis||jsonb_build_object(
      'authority','record_fundraising_pledge_self_api_v1','canonicalContributorRequired',true,
      'accountingRecognitionEstablished',false
    ),p_metadata
  ) on conflict(fundraising_entity_id,client_event_key)
  do update set contributor_entity_id=excluded.contributor_entity_id,pledged_on=excluded.pledged_on,
    promised_amount=excluded.promised_amount,currency=excluded.currency,due_on=excluded.due_on,
    establishment_basis=atlas.fundraising_pledges.establishment_basis||excluded.establishment_basis,
    metadata=atlas.fundraising_pledges.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;

  insert into atlas.fundraising_constituent_relationships(
    fundraising_entity_id,constituent_entity_id,relationship_kind,relationship_state,
    established_by_principal_id,established_by_user_id,establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_contributor_entity_id,'prospect','active',v_principal_id,auth.uid(),
    jsonb_build_object('authority','record_fundraising_pledge_self_api_v1','derivedFromPledgeId',v_row.id),'{}'::jsonb
  ) on conflict(fundraising_entity_id,constituent_entity_id,relationship_kind)
  do update set relationship_state='active',ended_at=null,updated_at=now();

  return jsonb_build_object(
    'contractVersion','fundraising_pledge_v1','pledgeId',v_row.id,
    'fundraisingEntityId',v_row.fundraising_entity_id,'contributorEntityId',v_row.contributor_entity_id,
    'pledgedOn',v_row.pledged_on,'promisedAmount',v_row.promised_amount,'currency',v_row.currency,
    'dueOn',v_row.due_on,'pledgeState',v_row.pledge_state,
    'truthBoundary',jsonb_build_object('canonicalContributorOwnedByReality',true,'accountingRecognitionEstablished',false)
  );
end;
$$;

revoke all on function atlas.record_fundraising_pledge_self_api_v1(uuid,uuid,text,date,numeric,text,date,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.record_fundraising_pledge_self_api_v1(uuid,uuid,text,date,numeric,text,date,jsonb,jsonb)
  to authenticated;

create or replace function atlas.record_fundraising_grant_award_self_api_v1(
  p_fundraising_entity_id uuid,
  p_funder_entity_id uuid,
  p_award_key text,
  p_awarded_on date,
  p_authorized_amount numeric default null,
  p_currency text default null,
  p_award_start_on date default null,
  p_award_end_on date default null,
  p_establishment_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=btrim(coalesce(p_award_key,''));
  v_currency text:=nullif(upper(btrim(coalesce(p_currency,''))),'');
  v_principal_id uuid;
  v_row atlas.fundraising_grant_awards%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then raise exception 'Fundraising entity authority required.' using errcode='42501'; end if;
  if v_key='' or p_awarded_on is null then raise exception 'Grant award key and award date required.' using errcode='22023'; end if;
  if (p_authorized_amount is null)<>(v_currency is null) then raise exception 'Grant amount and currency must be supplied together.' using errcode='22023'; end if;
  if p_authorized_amount is not null and p_authorized_amount<=0 then raise exception 'Grant authorized amount must be positive.' using errcode='22023'; end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then raise exception 'Grant currency must be a three-letter code.' using errcode='22023'; end if;
  if p_award_start_on is not null and p_award_end_on is not null and p_award_end_on<p_award_start_on then raise exception 'Grant award end date cannot precede start date.' using errcode='22023'; end if;
  if p_establishment_basis is null or jsonb_typeof(p_establishment_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Grant basis and metadata must be JSON objects.' using errcode='22023'; end if;

  v_principal_id:=atlas.current_principal_id_v1();
  insert into atlas.fundraising_grant_awards(
    fundraising_entity_id,funder_entity_id,award_key,awarded_on,authorized_amount,currency,
    award_start_on,award_end_on,award_state,established_by_principal_id,established_by_user_id,
    establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_funder_entity_id,v_key,p_awarded_on,p_authorized_amount,v_currency,
    p_award_start_on,p_award_end_on,'active',v_principal_id,auth.uid(),
    p_establishment_basis||jsonb_build_object(
      'authority','record_fundraising_grant_award_self_api_v1','canonicalFunderRequired',true,
      'restrictionEstablished',false,'accountingRecognitionEstablished',false
    ),p_metadata
  ) on conflict(fundraising_entity_id,award_key)
  do update set funder_entity_id=excluded.funder_entity_id,awarded_on=excluded.awarded_on,
    authorized_amount=excluded.authorized_amount,currency=excluded.currency,
    award_start_on=excluded.award_start_on,award_end_on=excluded.award_end_on,
    award_state='active',establishment_basis=atlas.fundraising_grant_awards.establishment_basis||excluded.establishment_basis,
    metadata=atlas.fundraising_grant_awards.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;

  insert into atlas.fundraising_constituent_relationships(
    fundraising_entity_id,constituent_entity_id,relationship_kind,relationship_state,
    established_by_principal_id,established_by_user_id,establishment_basis,metadata
  ) values (
    p_fundraising_entity_id,p_funder_entity_id,'grant_funder','active',v_principal_id,auth.uid(),
    jsonb_build_object('authority','record_fundraising_grant_award_self_api_v1','derivedFromGrantAwardId',v_row.id),'{}'::jsonb
  ) on conflict(fundraising_entity_id,constituent_entity_id,relationship_kind)
  do update set relationship_state='active',ended_at=null,updated_at=now();

  return jsonb_build_object(
    'contractVersion','fundraising_grant_award_v1','grantAwardId',v_row.id,
    'fundraisingEntityId',v_row.fundraising_entity_id,'funderEntityId',v_row.funder_entity_id,
    'awardKey',v_row.award_key,'awardedOn',v_row.awarded_on,
    'authorizedAmount',v_row.authorized_amount,'currency',v_row.currency,
    'awardState',v_row.award_state,
    'truthBoundary',jsonb_build_object(
      'canonicalFunderOwnedByReality',true,'restrictionEstablished',false,
      'accountingRecognitionEstablished',false,'journalPosted',false
    )
  );
end;
$$;

revoke all on function atlas.record_fundraising_grant_award_self_api_v1(uuid,uuid,text,date,numeric,text,date,date,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.record_fundraising_grant_award_self_api_v1(uuid,uuid,text,date,numeric,text,date,date,jsonb,jsonb)
  to authenticated;

create or replace function atlas.fundraising_constituent_financial_history_self_api_v1(
  p_fundraising_entity_id uuid,
  p_constituent_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_entity reality.entities%rowtype;
  v_contribution_count integer;
  v_contribution_total numeric;
  v_currency text;
  v_grant_count integer;
begin
  if not atlas.fundraising_entity_authorized_self_v1(p_fundraising_entity_id) then
    raise exception 'Fundraising entity authority required.' using errcode='42501';
  end if;
  select * into v_entity from reality.entities e
  where e.id=p_constituent_entity_id and e.identity_state='canonical';
  if v_entity.id is null then raise exception 'Canonical constituent Reality entity required.' using errcode='23503'; end if;

  select count(*)::integer,
         case when count(distinct currency)=1 then coalesce(sum(stated_amount),0) else null end,
         case when count(distinct currency)=1 then min(currency) else null end
  into v_contribution_count,v_contribution_total,v_currency
  from atlas.fundraising_contributions c
  where c.fundraising_entity_id=p_fundraising_entity_id
    and c.contributor_entity_id=p_constituent_entity_id
    and c.record_state='confirmed';

  select count(*)::integer into v_grant_count
  from atlas.fundraising_grant_awards g
  where g.fundraising_entity_id=p_fundraising_entity_id
    and g.funder_entity_id=p_constituent_entity_id
    and g.award_state<>'cancelled';

  return jsonb_build_object(
    'contractVersion','fundraising_constituent_financial_history_v1',
    'fundraisingEntityId',p_fundraising_entity_id,
    'constituentEntityId',v_entity.id,
    'displayName',v_entity.display_name,
    'entityKind',v_entity.entity_kind,
    'derivedStanding',jsonb_build_object(
      'donor',v_contribution_count>0,
      'grantFunder',v_grant_count>0
    ),
    'contributionSummary',jsonb_build_object(
      'confirmedCount',v_contribution_count,
      'singleCurrencyTotal',v_contribution_total,
      'currency',v_currency
    ),
    'contributions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'contributionId',c.id,'receivedOn',c.received_on,'contributionKind',c.contribution_kind,
        'statedAmount',c.stated_amount,'currency',c.currency,'recordState',c.record_state
      ) order by c.received_on desc,c.id),'[]'::jsonb)
      from atlas.fundraising_contributions c
      where c.fundraising_entity_id=p_fundraising_entity_id
        and c.contributor_entity_id=p_constituent_entity_id
    ),
    'pledges',coalesce((
      select jsonb_agg(jsonb_build_object(
        'pledgeId',p.id,'pledgedOn',p.pledged_on,'promisedAmount',p.promised_amount,
        'currency',p.currency,'dueOn',p.due_on,'pledgeState',p.pledge_state
      ) order by p.pledged_on desc,p.id),'[]'::jsonb)
      from atlas.fundraising_pledges p
      where p.fundraising_entity_id=p_fundraising_entity_id
        and p.contributor_entity_id=p_constituent_entity_id
    ),
    'grantAwards',coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantAwardId',g.id,'awardKey',g.award_key,'awardedOn',g.awarded_on,
        'authorizedAmount',g.authorized_amount,'currency',g.currency,
        'awardStartOn',g.award_start_on,'awardEndOn',g.award_end_on,'awardState',g.award_state
      ) order by g.awarded_on desc,g.id),'[]'::jsonb)
      from atlas.fundraising_grant_awards g
      where g.fundraising_entity_id=p_fundraising_entity_id
        and g.funder_entity_id=p_constituent_entity_id
    ),
    'truthBoundary',jsonb_build_object(
      'canonicalIdentityOwnedByReality',true,
      'donorStandingDerivedFromContributionHistory',true,
      'accountingRecognitionEstablishedHere',false,
      'restrictionEstablishedHere',false
    )
  );
end;
$$;

revoke all on function atlas.fundraising_constituent_financial_history_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.fundraising_constituent_financial_history_self_api_v1(uuid,uuid)
  to authenticated;

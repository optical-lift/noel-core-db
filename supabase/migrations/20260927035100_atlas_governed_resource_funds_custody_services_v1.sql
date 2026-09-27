-- Atlas governed resource funds / custody service membrane v1
--
-- Browser/user access remains service-only. A resource pool is accounting governance, not Reality
-- identity. Canonical parties always arrive as reality.entities ids.

-- Reconciliation history must be retained. Convert the initial one-row-per-date shape to versioned runs.
do $$
declare
  v_constraint text;
begin
  select c.conname into v_constraint
  from pg_constraint c
  where c.conrelid='atlas.accounting_custody_reconciliations'::regclass
    and c.contype='u'
    and pg_get_constraintdef(c.oid) ilike '%resource_pool_id%reconciliation_on%'
  limit 1;
  if v_constraint is not null then
    execute format('alter table atlas.accounting_custody_reconciliations drop constraint %I',v_constraint);
  end if;
end;
$$;

alter table atlas.accounting_custody_reconciliations
  add column if not exists reconciliation_version integer not null default 1,
  add column if not exists supersedes_reconciliation_id uuid references atlas.accounting_custody_reconciliations(id) on delete restrict;

alter table atlas.accounting_custody_reconciliations
  drop constraint if exists accounting_custody_reconciliations_version_check;
alter table atlas.accounting_custody_reconciliations
  add constraint accounting_custody_reconciliations_version_check check (reconciliation_version>0);

create unique index if not exists accounting_custody_reconciliations_version_uq
  on atlas.accounting_custody_reconciliations(resource_pool_id,reconciliation_on,reconciliation_version);
create index if not exists accounting_custody_reconciliations_date_idx
  on atlas.accounting_custody_reconciliations(resource_pool_id,reconciliation_on desc,reconciliation_version desc);

create or replace function atlas.prevent_accounting_custody_reconciliation_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Custody reconciliation history is append-only. Create a superseding reconciliation run.' using errcode='55000';
end;
$$;

revoke all on function atlas.prevent_accounting_custody_reconciliation_mutation_v1() from public,anon,authenticated;
drop trigger if exists accounting_custody_reconciliation_immutable_v1 on atlas.accounting_custody_reconciliations;
create trigger accounting_custody_reconciliation_immutable_v1
before update or delete on atlas.accounting_custody_reconciliations
for each row execute function atlas.prevent_accounting_custody_reconciliation_mutation_v1();

create or replace function atlas.upsert_accounting_resource_pool_self_api_v1(
  p_accounting_book_id uuid,
  p_pool_key text,
  p_pool_name text,
  p_ownership_posture text,
  p_governance_posture text,
  p_nonprofit_net_asset_class text default null,
  p_custody_asset_account_id uuid default null,
  p_custody_liability_account_id uuid default null,
  p_ledger_ids uuid[] default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=lower(btrim(coalesce(p_pool_key,'')));
  v_name text:=btrim(coalesce(p_pool_name,''));
  v_owner text:=lower(btrim(coalesce(p_ownership_posture,'')));
  v_governance text:=lower(btrim(coalesce(p_governance_posture,'')));
  v_net text:=nullif(lower(btrim(coalesce(p_nonprofit_net_asset_class,''))),'');
  v_pool atlas.accounting_resource_pools%rowtype;
  v_ledger uuid;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or v_name='' then raise exception 'Resource pool key and name required.' using errcode='22023'; end if;
  if v_owner not in ('reporting_entity_owned','third_party_custody')
     or v_governance not in ('unrestricted','externally_restricted','internally_designated','custodial') then
    raise exception 'Supported resource ownership/governance posture required.' using errcode='22023';
  end if;
  if (v_owner='third_party_custody')<>(v_governance='custodial') then
    raise exception 'Third-party ownership and custodial governance must occur together.' using errcode='22023';
  end if;
  if v_net is not null and v_net not in ('without_donor_restrictions','with_donor_restrictions') then
    raise exception 'Unsupported nonprofit net-asset class.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Resource pool provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.accounting_resource_pools(
    accounting_book_id,pool_key,pool_name,ownership_posture,governance_posture,
    nonprofit_net_asset_class,custody_asset_account_id,custody_liability_account_id,
    pool_state,provenance,metadata
  ) values (
    p_accounting_book_id,v_key,v_name,v_owner,v_governance,v_net,
    p_custody_asset_account_id,p_custody_liability_account_id,'active',
    p_provenance||jsonb_build_object(
      'authority','upsert_accounting_resource_pool_self_api_v1',
      'resourceGovernanceDoesNotCreateRealityIdentity',true,
      'custodialMoneyIsNotReportingEntityRevenue',v_owner='third_party_custody'
    ),p_metadata
  ) on conflict(accounting_book_id,pool_key)
  do update set
    pool_name=excluded.pool_name,
    nonprofit_net_asset_class=excluded.nonprofit_net_asset_class,
    pool_state='active',
    provenance=atlas.accounting_resource_pools.provenance||excluded.provenance,
    metadata=atlas.accounting_resource_pools.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_pool;

  -- Ownership/governance/control-account posture is intentionally immutable after first establishment.
  if v_pool.ownership_posture<>v_owner or v_pool.governance_posture<>v_governance
     or v_pool.custody_asset_account_id is distinct from p_custody_asset_account_id
     or v_pool.custody_liability_account_id is distinct from p_custody_liability_account_id then
    raise exception 'Resource pool ownership/governance/control-account posture is immutable; establish a new pool for a materially different posture.' using errcode='23514';
  end if;

  if p_ledger_ids is not null then
    foreach v_ledger in array p_ledger_ids loop
      if not exists(
        select 1 from atlas.accounting_book_ledger_scopes s
        where s.accounting_book_id=p_accounting_book_id and s.ledger_id=v_ledger
          and s.scope_state='active' and s.ended_at is null
      ) then
        raise exception 'Every resource-pool Ledger scope must already belong to the accounting book.' using errcode='23514';
      end if;
      insert into atlas.accounting_resource_pool_ledger_scopes(resource_pool_id,ledger_id,scope_state,provenance)
      values(v_pool.id,v_ledger,'active',jsonb_build_object('authority','upsert_accounting_resource_pool_self_api_v1'))
      on conflict(resource_pool_id,ledger_id)
      do update set scope_state='active',ended_at=null,metadata=atlas.accounting_resource_pool_ledger_scopes.metadata,provenance=atlas.accounting_resource_pool_ledger_scopes.provenance;
    end loop;
  end if;

  return jsonb_build_object(
    'contractVersion','accounting_resource_pool_v1',
    'resourcePoolId',v_pool.id,
    'accountingBookId',v_pool.accounting_book_id,
    'poolKey',v_pool.pool_key,
    'poolName',v_pool.pool_name,
    'ownershipPosture',v_pool.ownership_posture,
    'governancePosture',v_pool.governance_posture,
    'nonprofitNetAssetClass',v_pool.nonprofit_net_asset_class,
    'truthBoundary',jsonb_build_object(
      'canonicalIdentityOwnedByReality',true,
      'thirdPartyCustodyIsNotRevenue',v_pool.ownership_posture='third_party_custody',
      'resourcePoolIsAccountingGovernance',true
    )
  );
end;
$$;

revoke all on function atlas.upsert_accounting_resource_pool_self_api_v1(uuid,text,text,text,text,text,uuid,uuid,uuid[],jsonb,jsonb) from public,anon;
grant execute on function atlas.upsert_accounting_resource_pool_self_api_v1(uuid,text,text,text,text,text,uuid,uuid,uuid[],jsonb,jsonb) to authenticated;

create or replace function atlas.upsert_accounting_resource_constraint_self_api_v1(
  p_resource_pool_id uuid,
  p_constraint_key text,
  p_constraint_kind text,
  p_imposed_by_entity_id uuid default null,
  p_purpose_text text default null,
  p_starts_on date default null,
  p_ends_on date default null,
  p_evidence_record_id uuid default null,
  p_rule_spec jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_key text:=lower(btrim(coalesce(p_constraint_key,'')));
  v_kind text:=lower(btrim(coalesce(p_constraint_kind,'')));
  v_row atlas.accounting_resource_constraints%rowtype;
begin
  select accounting_book_id into v_book from atlas.accounting_resource_pools where id=p_resource_pool_id and pool_state='active';
  if v_book is null then raise exception 'Active resource pool required.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_key='' or v_kind not in ('purpose','time','purpose_and_time','perpetual','contractual','legal_custody','internal_designation','other') then
    raise exception 'Constraint key and supported kind required.' using errcode='22023';
  end if;
  if p_rule_spec is null or jsonb_typeof(p_rule_spec)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Constraint rule/provenance/metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.accounting_resource_constraints(
    resource_pool_id,constraint_key,constraint_kind,imposed_by_entity_id,constraint_state,
    purpose_text,starts_on,ends_on,evidence_record_id,rule_spec,provenance,metadata
  ) values (
    p_resource_pool_id,v_key,v_kind,p_imposed_by_entity_id,'active',nullif(btrim(coalesce(p_purpose_text,'')),''),
    p_starts_on,p_ends_on,p_evidence_record_id,p_rule_spec,
    p_provenance||jsonb_build_object('authority','upsert_accounting_resource_constraint_self_api_v1'),p_metadata
  ) on conflict(resource_pool_id,constraint_key)
  do update set
    purpose_text=excluded.purpose_text,
    starts_on=excluded.starts_on,
    ends_on=excluded.ends_on,
    evidence_record_id=coalesce(excluded.evidence_record_id,atlas.accounting_resource_constraints.evidence_record_id),
    rule_spec=atlas.accounting_resource_constraints.rule_spec||excluded.rule_spec,
    provenance=atlas.accounting_resource_constraints.provenance||excluded.provenance,
    metadata=atlas.accounting_resource_constraints.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_row;

  if v_row.constraint_kind<>v_kind or v_row.imposed_by_entity_id is distinct from p_imposed_by_entity_id then
    raise exception 'Constraint kind and imposing Reality entity are immutable; establish a new constraint for changed governing meaning.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','accounting_resource_constraint_v1',
    'resourceConstraintId',v_row.id,'resourcePoolId',v_row.resource_pool_id,
    'constraintKind',v_row.constraint_kind,'imposedByEntityId',v_row.imposed_by_entity_id,
    'constraintState',v_row.constraint_state,
    'truthBoundary',jsonb_build_object('constraintDoesNotCreateIdentity',true,'accountingRecognitionNotChanged',true)
  );
end;
$$;

revoke all on function atlas.upsert_accounting_resource_constraint_self_api_v1(uuid,text,text,uuid,text,date,date,uuid,jsonb,jsonb,jsonb) from public,anon;
grant execute on function atlas.upsert_accounting_resource_constraint_self_api_v1(uuid,text,text,uuid,text,date,date,uuid,jsonb,jsonb,jsonb) to authenticated;

create or replace function atlas.upsert_accounting_resource_interest_self_api_v1(
  p_resource_pool_id uuid,
  p_interest_key text,
  p_interest_kind text,
  p_holder_entity_id uuid,
  p_ledger_id uuid default null,
  p_context_kind text default null,
  p_context_key text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_key text:=lower(btrim(coalesce(p_interest_key,'')));
  v_kind text:=lower(btrim(coalesce(p_interest_kind,'')));
  v_row atlas.accounting_resource_interests%rowtype;
begin
  select accounting_book_id into v_book from atlas.accounting_resource_pools where id=p_resource_pool_id and pool_state='active';
  if v_book is null then raise exception 'Active resource pool required.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_key='' or v_kind not in ('beneficiary','restrictor','grantor','client','tenant','escrow_party','designator','other') then
    raise exception 'Interest key and supported kind required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Interest provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.accounting_resource_interests(
    resource_pool_id,interest_key,interest_kind,holder_entity_id,ledger_id,context_kind,context_key,
    interest_state,provenance,metadata
  ) values (
    p_resource_pool_id,v_key,v_kind,p_holder_entity_id,p_ledger_id,
    nullif(lower(btrim(coalesce(p_context_kind,''))),''),nullif(btrim(coalesce(p_context_key,'')),''),
    'active',p_provenance||jsonb_build_object('authority','upsert_accounting_resource_interest_self_api_v1'),p_metadata
  ) on conflict(resource_pool_id,interest_key)
  do update set
    ledger_id=excluded.ledger_id,
    context_kind=excluded.context_kind,
    context_key=excluded.context_key,
    interest_state='active',ended_at=null,
    provenance=atlas.accounting_resource_interests.provenance||excluded.provenance,
    metadata=atlas.accounting_resource_interests.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_row;

  if v_row.interest_kind<>v_kind or v_row.holder_entity_id<>p_holder_entity_id then
    raise exception 'Resource-interest kind and canonical Reality holder are immutable.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','accounting_resource_interest_v1',
    'resourceInterestId',v_row.id,'resourcePoolId',v_row.resource_pool_id,
    'interestKind',v_row.interest_kind,'holderEntityId',v_row.holder_entity_id,
    'ledgerId',v_row.ledger_id,'contextKind',v_row.context_kind,'contextKey',v_row.context_key,
    'truthBoundary',jsonb_build_object('holderIsCanonicalRealityEntity',true,'copiedPartyNameStored',false)
  );
end;
$$;

revoke all on function atlas.upsert_accounting_resource_interest_self_api_v1(uuid,text,text,uuid,uuid,text,text,jsonb,jsonb) from public,anon;
grant execute on function atlas.upsert_accounting_resource_interest_self_api_v1(uuid,text,text,uuid,uuid,text,text,jsonb,jsonb) to authenticated;

create or replace function atlas.add_accounting_resource_movement_self_api_v1(
  p_journal_line_id uuid,
  p_resource_pool_id uuid,
  p_resource_interest_id uuid,
  p_movement_kind text,
  p_amount_delta numeric,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_state text;
  v_kind text:=lower(btrim(coalesce(p_movement_kind,'')));
  v_row atlas.accounting_resource_movements%rowtype;
begin
  select e.accounting_book_id,e.entry_state into v_book,v_state
  from atlas.accounting_journal_lines l join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where l.id=p_journal_line_id;
  if v_book is null or v_state<>'draft' then raise exception 'Draft accounting journal line required.' using errcode='23514'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_kind not in ('increase','decrease','release','reclassification','custody_increase','custody_decrease','adjustment')
     or p_amount_delta is null or p_amount_delta=0 then
    raise exception 'Supported movement kind and nonzero resource delta required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Movement provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.accounting_resource_movements(
    journal_line_id,resource_pool_id,resource_interest_id,movement_kind,amount_delta,provenance,metadata
  ) values (
    p_journal_line_id,p_resource_pool_id,p_resource_interest_id,v_kind,p_amount_delta,
    p_provenance||jsonb_build_object('authority','add_accounting_resource_movement_self_api_v1'),p_metadata
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','accounting_resource_movement_v1',
    'resourceMovementId',v_row.id,'journalLineId',v_row.journal_line_id,
    'resourcePoolId',v_row.resource_pool_id,'resourceInterestId',v_row.resource_interest_id,
    'movementKind',v_row.movement_kind,'amountDelta',v_row.amount_delta,
    'truthBoundary',jsonb_build_object('journalStillDraft',true,'postingNotPerformed',true)
  );
end;
$$;

revoke all on function atlas.add_accounting_resource_movement_self_api_v1(uuid,uuid,uuid,text,numeric,jsonb,jsonb) from public,anon;
grant execute on function atlas.add_accounting_resource_movement_self_api_v1(uuid,uuid,uuid,text,numeric,jsonb,jsonb) to authenticated;

create or replace function atlas.accounting_resource_pool_position_self_api_v1(
  p_resource_pool_id uuid,
  p_as_of_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_pool atlas.accounting_resource_pools%rowtype;
  v_total numeric:=0;
  v_interests jsonb;
begin
  select * into v_pool from atlas.accounting_resource_pools where id=p_resource_pool_id;
  if v_pool.id is null then raise exception 'Resource pool not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_pool.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_as_of_on is null then raise exception 'Position as-of date required.' using errcode='22023'; end if;

  with posted as (
    select m.resource_interest_id,m.amount_delta
    from atlas.accounting_resource_movements m
    join atlas.accounting_journal_lines l on l.id=m.journal_line_id
    join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
    where m.resource_pool_id=p_resource_pool_id and e.entry_state='posted' and e.entry_date<=p_as_of_on
  ), by_interest as (
    select i.id,i.interest_key,i.interest_kind,i.holder_entity_id,i.ledger_id,i.context_kind,i.context_key,
      coalesce(sum(p.amount_delta),0) as balance
    from atlas.accounting_resource_interests i
    left join posted p on p.resource_interest_id=i.id
    where i.resource_pool_id=p_resource_pool_id
    group by i.id,i.interest_key,i.interest_kind,i.holder_entity_id,i.ledger_id,i.context_kind,i.context_key
  )
  select coalesce(sum(balance),0),coalesce(jsonb_agg(jsonb_build_object(
    'resourceInterestId',id,'interestKey',interest_key,'interestKind',interest_kind,
    'holderEntityId',holder_entity_id,'ledgerId',ledger_id,'contextKind',context_kind,'contextKey',context_key,
    'balance',balance
  ) order by interest_kind,interest_key,id),'[]'::jsonb)
  into v_total,v_interests from by_interest;

  if not exists(select 1 from atlas.accounting_resource_interests where resource_pool_id=p_resource_pool_id) then
    select coalesce(sum(m.amount_delta),0) into v_total
    from atlas.accounting_resource_movements m
    join atlas.accounting_journal_lines l on l.id=m.journal_line_id
    join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
    where m.resource_pool_id=p_resource_pool_id and e.entry_state='posted' and e.entry_date<=p_as_of_on;
    v_interests:='[]'::jsonb;
  end if;

  return jsonb_build_object(
    'contractVersion','accounting_resource_pool_position_v1',
    'resourcePoolId',v_pool.id,'accountingBookId',v_pool.accounting_book_id,
    'asOfOn',p_as_of_on,'ownershipPosture',v_pool.ownership_posture,
    'governancePosture',v_pool.governance_posture,'balance',coalesce(v_total,0),
    'interests',v_interests,
    'truthBoundary',jsonb_build_object('postedEntriesOnly',true,'readOnly',true,'canonicalPartiesReadById',true)
  );
end;
$$;

revoke all on function atlas.accounting_resource_pool_position_self_api_v1(uuid,date) from public,anon;
grant execute on function atlas.accounting_resource_pool_position_self_api_v1(uuid,date) to authenticated;

create or replace function atlas.reconcile_accounting_custody_pool_self_api_v1(
  p_resource_pool_id uuid,
  p_reconciliation_on date,
  p_bank_statement_balance numeric,
  p_bank_statement_evidence_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_pool atlas.accounting_resource_pools%rowtype;
  v_control numeric:=0;
  v_subledger numeric:=0;
  v_asset_book numeric:=0;
  v_bank_variance numeric:=0;
  v_subledger_variance numeric:=0;
  v_state text;
  v_version integer;
  v_prior uuid;
  v_principal uuid;
  v_row atlas.accounting_custody_reconciliations%rowtype;
begin
  select * into v_pool from atlas.accounting_resource_pools where id=p_resource_pool_id and pool_state='active';
  if v_pool.id is null or v_pool.ownership_posture<>'third_party_custody' then
    raise exception 'Active third-party custodial resource pool required.' using errcode='23514';
  end if;
  if not atlas.accounting_book_authorized_self_v1(v_pool.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_reconciliation_on is null or p_bank_statement_balance is null then raise exception 'Reconciliation date and bank statement balance required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Reconciliation metadata must be a JSON object.' using errcode='22023'; end if;

  select coalesce(sum(l.credit_amount-l.debit_amount),0) into v_control
  from atlas.accounting_journal_lines l
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where e.accounting_book_id=v_pool.accounting_book_id and e.entry_state='posted' and e.entry_date<=p_reconciliation_on
    and l.accounting_account_id=v_pool.custody_liability_account_id;

  select coalesce(sum(m.amount_delta),0) into v_subledger
  from atlas.accounting_resource_movements m
  join atlas.accounting_journal_lines l on l.id=m.journal_line_id
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where m.resource_pool_id=v_pool.id and e.entry_state='posted' and e.entry_date<=p_reconciliation_on;

  select coalesce(sum(l.debit_amount-l.credit_amount),0) into v_asset_book
  from atlas.accounting_journal_lines l
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where e.accounting_book_id=v_pool.accounting_book_id and e.entry_state='posted' and e.entry_date<=p_reconciliation_on
    and l.accounting_account_id=v_pool.custody_asset_account_id;

  v_bank_variance:=p_bank_statement_balance-v_control;
  v_subledger_variance:=v_control-v_subledger;
  v_state:=case when v_bank_variance=0 and v_subledger_variance=0 then 'balanced' else 'exception' end;

  select id,reconciliation_version into v_prior,v_version
  from atlas.accounting_custody_reconciliations
  where resource_pool_id=v_pool.id and reconciliation_on=p_reconciliation_on
  order by reconciliation_version desc limit 1;
  v_version:=coalesce(v_version,0)+1;
  v_principal:=atlas.current_principal_id_v1();

  insert into atlas.accounting_custody_reconciliations(
    resource_pool_id,reconciliation_on,bank_statement_balance,bank_statement_evidence_id,
    control_liability_balance,beneficiary_subledger_balance,reconciliation_state,
    variance_bank_to_control,variance_control_to_subledger,prepared_by_principal_id,prepared_by_user_id,
    provenance,metadata,reconciliation_version,supersedes_reconciliation_id
  ) values (
    v_pool.id,p_reconciliation_on,p_bank_statement_balance,p_bank_statement_evidence_id,
    v_control,v_subledger,v_state,v_bank_variance,v_subledger_variance,v_principal,auth.uid(),
    jsonb_build_object(
      'authority','reconcile_accounting_custody_pool_self_api_v1',
      'threeWayReconciliation',true,
      'bankStatementVsControlLiabilityVsBeneficiarySubledgers',true
    ),p_metadata||jsonb_build_object('bookAssetBalance',v_asset_book),v_version,v_prior
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','accounting_custody_reconciliation_v1',
    'custodyReconciliationId',v_row.id,'resourcePoolId',v_row.resource_pool_id,
    'reconciliationOn',v_row.reconciliation_on,'reconciliationVersion',v_row.reconciliation_version,
    'bankStatementBalance',v_row.bank_statement_balance,'controlLiabilityBalance',v_row.control_liability_balance,
    'beneficiarySubledgerBalance',v_row.beneficiary_subledger_balance,'bookAssetBalance',v_asset_book,
    'bankToControlVariance',v_row.variance_bank_to_control,
    'controlToSubledgerVariance',v_row.variance_control_to_subledger,
    'state',v_row.reconciliation_state,
    'truthBoundary',jsonb_build_object(
      'appendOnlyReconciliationHistory',true,
      'postedEntriesOnly',true,
      'bankStatementEvidencePreservedSeparately',true
    )
  );
end;
$$;

revoke all on function atlas.reconcile_accounting_custody_pool_self_api_v1(uuid,date,numeric,uuid,jsonb) from public,anon;
grant execute on function atlas.reconcile_accounting_custody_pool_self_api_v1(uuid,date,numeric,uuid,jsonb) to authenticated;

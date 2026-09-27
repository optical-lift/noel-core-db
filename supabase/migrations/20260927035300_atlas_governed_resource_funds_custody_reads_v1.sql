-- Governed resource source links and read models v1.

-- Control accounts are historical identities for a custodial pool. Do not reuse one control account
-- for a different pool after closing the first pool, otherwise historical three-way reconciliation
-- becomes ambiguous.
drop index if exists atlas.accounting_resource_pools_custody_liability_uq;
drop index if exists atlas.accounting_resource_pools_custody_asset_uq;
create unique index if not exists accounting_resource_pools_custody_liability_uq
  on atlas.accounting_resource_pools(accounting_book_id,custody_liability_account_id)
  where ownership_posture='third_party_custody';
create unique index if not exists accounting_resource_pools_custody_asset_uq
  on atlas.accounting_resource_pools(accounting_book_id,custody_asset_account_id)
  where ownership_posture='third_party_custody';

create or replace function atlas.link_accounting_resource_source_self_api_v1(
  p_resource_pool_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_relation_kind text,
  p_related_entity_id uuid default null,
  p_evidence_record_id uuid default null,
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
  v_domain text:=lower(btrim(coalesce(p_source_domain,'')));
  v_kind text:=lower(btrim(coalesce(p_source_kind,'')));
  v_id text:=btrim(coalesce(p_source_id,''));
  v_relation text:=lower(btrim(coalesce(p_relation_kind,'')));
  v_row atlas.accounting_resource_source_links%rowtype;
begin
  select accounting_book_id into v_book from atlas.accounting_resource_pools where id=p_resource_pool_id;
  if v_book is null then raise exception 'Resource pool not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_domain='' or v_kind='' or v_id='' or v_relation='' then raise exception 'Source domain, kind, id, and relation required.' using errcode='22023'; end if;
  if p_related_entity_id is not null and not exists(
    select 1 from reality.entities e where e.id=p_related_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Related resource party must be a canonical Reality entity.' using errcode='23514';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Source-link provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into atlas.accounting_resource_source_links(
    resource_pool_id,source_domain,source_kind,source_id,relation_kind,
    related_entity_id,evidence_record_id,provenance,metadata
  ) values (
    p_resource_pool_id,v_domain,v_kind,v_id,v_relation,p_related_entity_id,p_evidence_record_id,
    p_provenance||jsonb_build_object(
      'authority','link_accounting_resource_source_self_api_v1',
      'sourceDoesNotOwnIdentity',true
    ),p_metadata
  ) on conflict(resource_pool_id,source_domain,source_kind,source_id,relation_kind)
  do update set
    evidence_record_id=coalesce(excluded.evidence_record_id,atlas.accounting_resource_source_links.evidence_record_id),
    provenance=atlas.accounting_resource_source_links.provenance||excluded.provenance,
    metadata=atlas.accounting_resource_source_links.metadata||excluded.metadata
  returning * into v_row;

  if v_row.related_entity_id is distinct from p_related_entity_id then
    raise exception 'Canonical related party on an established resource source link is immutable.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','accounting_resource_source_link_v1',
    'resourceSourceLinkId',v_row.id,'resourcePoolId',v_row.resource_pool_id,
    'sourceDomain',v_row.source_domain,'sourceKind',v_row.source_kind,'sourceId',v_row.source_id,
    'relationKind',v_row.relation_kind,'relatedEntityId',v_row.related_entity_id,
    'truthBoundary',jsonb_build_object('canonicalIdentityOwnedByReality',true,'copiedPartyNameStored',false)
  );
end;
$$;

revoke all on function atlas.link_accounting_resource_source_self_api_v1(uuid,text,text,text,text,uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function atlas.link_accounting_resource_source_self_api_v1(uuid,text,text,text,text,uuid,uuid,jsonb,jsonb) to authenticated;

create or replace function atlas.accounting_resource_pool_governance_self_api_v1(
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
  v_position jsonb;
begin
  select * into v_pool from atlas.accounting_resource_pools where id=p_resource_pool_id;
  if v_pool.id is null then raise exception 'Resource pool not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_pool.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  v_position:=atlas.accounting_resource_pool_position_self_api_v1(p_resource_pool_id,p_as_of_on);

  return jsonb_build_object(
    'contractVersion','accounting_resource_pool_governance_v1',
    'resourcePool',jsonb_build_object(
      'resourcePoolId',v_pool.id,'accountingBookId',v_pool.accounting_book_id,
      'poolKey',v_pool.pool_key,'poolName',v_pool.pool_name,
      'ownershipPosture',v_pool.ownership_posture,'governancePosture',v_pool.governance_posture,
      'nonprofitNetAssetClass',v_pool.nonprofit_net_asset_class,'poolState',v_pool.pool_state,
      'custodyAssetAccountId',v_pool.custody_asset_account_id,'custodyLiabilityAccountId',v_pool.custody_liability_account_id
    ),
    'position',v_position,
    'constraints',coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceConstraintId',c.id,'constraintKey',c.constraint_key,'constraintKind',c.constraint_kind,
        'imposedByEntityId',c.imposed_by_entity_id,'constraintState',c.constraint_state,
        'purposeText',c.purpose_text,'startsOn',c.starts_on,'endsOn',c.ends_on,
        'evidenceRecordId',c.evidence_record_id,'ruleSpec',c.rule_spec
      ) order by c.constraint_key,c.id)
      from atlas.accounting_resource_constraints c where c.resource_pool_id=v_pool.id
    ),'[]'::jsonb),
    'ledgerScopes',coalesce((
      select jsonb_agg(jsonb_build_object('ledgerId',s.ledger_id,'scopeState',s.scope_state) order by s.ledger_id)
      from atlas.accounting_resource_pool_ledger_scopes s where s.resource_pool_id=v_pool.id
    ),'[]'::jsonb),
    'sourceLinks',coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceSourceLinkId',s.id,'sourceDomain',s.source_domain,'sourceKind',s.source_kind,
        'sourceId',s.source_id,'relationKind',s.relation_kind,'relatedEntityId',s.related_entity_id,
        'evidenceRecordId',s.evidence_record_id
      ) order by s.source_domain,s.source_kind,s.source_id,s.id)
      from atlas.accounting_resource_source_links s where s.resource_pool_id=v_pool.id
    ),'[]'::jsonb),
    'latestCustodyReconciliation',case when v_pool.ownership_posture='third_party_custody' then (
      select jsonb_build_object(
        'custodyReconciliationId',r.id,'reconciliationOn',r.reconciliation_on,
        'reconciliationVersion',r.reconciliation_version,'state',r.reconciliation_state,
        'bankStatementBalance',r.bank_statement_balance,'controlLiabilityBalance',r.control_liability_balance,
        'beneficiarySubledgerBalance',r.beneficiary_subledger_balance,
        'bankToControlVariance',r.variance_bank_to_control,
        'controlToSubledgerVariance',r.variance_control_to_subledger
      )
      from atlas.accounting_custody_reconciliations r
      where r.resource_pool_id=v_pool.id
      order by r.reconciliation_on desc,r.reconciliation_version desc limit 1
    ) else null end,
    'truthBoundary',jsonb_build_object(
      'postedEntriesOnlyForPosition',true,'canonicalPartiesOwnedByReality',true,
      'custodialMoneyIsNotReportingEntityRevenue',v_pool.ownership_posture='third_party_custody'
    )
  );
end;
$$;

revoke all on function atlas.accounting_resource_pool_governance_self_api_v1(uuid,date) from public,anon;
grant execute on function atlas.accounting_resource_pool_governance_self_api_v1(uuid,date) to authenticated;

create or replace function atlas.accounting_custody_interest_ledger_self_api_v1(
  p_resource_interest_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_interest atlas.accounting_resource_interests%rowtype;
  v_pool atlas.accounting_resource_pools%rowtype;
  v_opening numeric:=0;
  v_activity numeric:=0;
begin
  select * into v_interest from atlas.accounting_resource_interests where id=p_resource_interest_id;
  if v_interest.id is null then raise exception 'Resource interest not found.' using errcode='P0002'; end if;
  select * into v_pool from atlas.accounting_resource_pools where id=v_interest.resource_pool_id;
  if v_pool.id is null or v_pool.ownership_posture<>'third_party_custody' then
    raise exception 'Custodial beneficiary/client interest required.' using errcode='23514';
  end if;
  if not atlas.accounting_book_authorized_self_v1(v_pool.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid custody-ledger date range required.' using errcode='22023'; end if;

  select coalesce(sum(m.amount_delta),0) into v_opening
  from atlas.accounting_resource_movements m
  join atlas.accounting_journal_lines l on l.id=m.journal_line_id
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where m.resource_interest_id=v_interest.id and e.entry_state='posted' and e.entry_date<p_start_on;

  select coalesce(sum(m.amount_delta),0) into v_activity
  from atlas.accounting_resource_movements m
  join atlas.accounting_journal_lines l on l.id=m.journal_line_id
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where m.resource_interest_id=v_interest.id and e.entry_state='posted' and e.entry_date between p_start_on and p_end_on;

  return jsonb_build_object(
    'contractVersion','accounting_custody_interest_ledger_v1',
    'resourcePoolId',v_pool.id,'resourceInterestId',v_interest.id,
    'holderEntityId',v_interest.holder_entity_id,'interestKind',v_interest.interest_kind,
    'ledgerId',v_interest.ledger_id,'contextKind',v_interest.context_kind,'contextKey',v_interest.context_key,
    'startOn',p_start_on,'endOn',p_end_on,'openingBalance',v_opening,
    'activity',coalesce((
      select jsonb_agg(jsonb_build_object(
        'entryDate',e.entry_date,'journalEntryId',e.id,'journalLineId',l.id,
        'movementKind',m.movement_kind,'amountDelta',m.amount_delta,'memo',coalesce(l.memo,e.memo),
        'balanceAfter',v_opening+sum(m.amount_delta) over(order by e.entry_date,e.id,m.id rows unbounded preceding)
      ) order by e.entry_date,e.id,m.id)
      from atlas.accounting_resource_movements m
      join atlas.accounting_journal_lines l on l.id=m.journal_line_id
      join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
      where m.resource_interest_id=v_interest.id and e.entry_state='posted' and e.entry_date between p_start_on and p_end_on
    ),'[]'::jsonb),
    'closingBalance',v_opening+v_activity,
    'truthBoundary',jsonb_build_object(
      'postedEntriesOnly',true,'canonicalBeneficiaryEntityId',v_interest.holder_entity_id,
      'clientOrTenantNameCopiedIntoAccounting',false
    )
  );
end;
$$;

revoke all on function atlas.accounting_custody_interest_ledger_self_api_v1(uuid,date,date) from public,anon;
grant execute on function atlas.accounting_custody_interest_ledger_self_api_v1(uuid,date,date) to authenticated;

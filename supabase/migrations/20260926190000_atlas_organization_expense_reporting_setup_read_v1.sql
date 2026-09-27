-- Atlas Package 5 usability continuation: expose the already-governed
-- Expense Reporting setup state to an authorized Ledger principal.
--
-- This is a read membrane only. It does not create reporting policy,
-- categories, periods, Spend, or accounting truth.

create or replace function atlas.organization_expense_reporting_setup_self_api_v1(
  p_ledger_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_principal uuid;
begin
  if p_ledger_id is null then
    raise exception 'Ledger is required.' using errcode='22023';
  end if;

  -- Reuse Package 5's existing root-Ledger authority gate. The returned
  -- principal is intentionally not promoted into reporting or accounting
  -- truth; it only proves this read is authorized.
  v_principal := atlas.organization_expense_reporting_root_principal_v1(p_ledger_id);

  return jsonb_build_object(
    'schemaVersion','atlas_organization_expense_reporting_setup_v1',
    'ledgerId',p_ledger_id,
    'configured',exists(
      select 1
      from atlas.organization_expense_reporting_contracts c
      where c.ledger_id=p_ledger_id
        and c.status='active'
    ),
    'contracts',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'contractId',c.id,
          'organizationId',c.organization_id,
          'organizationUnitId',c.organization_unit_id,
          'contractKey',c.contract_key,
          'displayName',c.display_name,
          'reportingBodyName',c.reporting_body_name,
          'cadence',c.cadence,
          'reportCurrency',c.report_currency,
          'status',c.status,
          'effectiveFrom',c.effective_from,
          'effectiveTo',c.effective_to,
          'accountingHandoffConfig',c.accounting_handoff_config,
          'categories',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'categoryId',cat.id,
                'categoryKey',cat.category_key,
                'canonicalLabel',cat.canonical_label,
                'exportLabel',cat.export_label,
                'policyDefinition',cat.policy_definition,
                'mappingState',cat.mapping_state,
                'sortOrder',cat.sort_order
              ) order by cat.sort_order,cat.canonical_label,cat.id
            )
            from atlas.organization_expense_reporting_categories cat
            where cat.contract_id=c.id
              and cat.is_active
          ),'[]'::jsonb),
          'periods',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'periodId',p.id,
                'periodStart',p.period_start,
                'periodEnd',p.period_end,
                'state',p.state,
                'organizationUnitId',p.organization_unit_id,
                'interpretedCount',(
                  select count(*)
                  from atlas.organization_expense_reporting_fact_links fl
                  where fl.period_id=p.id
                ),
                'blockingExceptionCount',(
                  select count(*)
                  from atlas.organization_expense_reporting_exception_position_v1 e
                  where e.period_id=p.id
                    and e.severity='blocking'
                )
              ) order by p.period_start desc,p.period_end desc,p.id
            )
            from atlas.organization_expense_reporting_periods p
            where p.contract_id=c.id
          ),'[]'::jsonb)
        ) order by c.effective_from desc,c.created_at desc,c.id
      )
      from atlas.organization_expense_reporting_contracts c
      where c.ledger_id=p_ledger_id
        and c.status='active'
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'spendRemainsCanonicalOutsideReporting',true,
      'reportingInterpretationDoesNotRewriteSpend',true,
      'accountingHandoffIsProjectionNotAccountingAuthority',true
    )
  );
end;
$function$;

revoke all on function atlas.organization_expense_reporting_setup_self_api_v1(uuid) from public,anon,service_role;
grant execute on function atlas.organization_expense_reporting_setup_self_api_v1(uuid) to authenticated;

comment on function atlas.organization_expense_reporting_setup_self_api_v1(uuid) is
  'Read-only Package 5 setup projection for an authorized Ledger principal. Exposes configured reporting contracts, categories, and periods without creating or changing Spend or accounting truth.';

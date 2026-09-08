begin;

create or replace function atlas.atlas_operations_summary_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select case
    when not atlas.implementation_practitioner_authorized_self_v1() then
      jsonb_build_object(
        'ok', false,
        'code', 'practitioner_authority_required'
      )
    else
      jsonb_build_object(
        'ok', true,
        'contractVersion', 'atlas_operations_summary_self_api_v1',
        'atlasAccounts', (
          select count(*)
          from auth.users u
          where u.deleted_at is null
            and u.email_confirmed_at is not null
        ),
        'ledgers', (
          select count(*)
          from atlas.ledger_entitlement_bindings b
          where b.ended_at is null
            and b.state in ('bound','activated')
        ),
        'employeeSeats', (
          select count(*)
          from atlas.organization_employee_seats s
          where s.status = 'active'
        ),
        'openImplementations', (
          select count(*)
          from atlas.implementation_cases c
          where c.state not in ('closed','cancelled')
        ),
        'ledgerAccountConnections', null,
        'ledgerAccountConnectionsState', 'not_yet_canonical'
      )
  end;
$function$;

comment on function atlas.atlas_operations_summary_self_api_v1() is
  'Atlas-team global operating counts. Atlas accounts count confirmed non-deleted Auth users; Ledgers count live bound or activated Ledger scopes; employee seats count active organization employee seats; open implementations exclude closed/cancelled cases. Per-Ledger account connection count remains null until a canonical Ledger-account access relationship exists.';

revoke all on function atlas.atlas_operations_summary_self_api_v1() from public, anon;
grant execute on function atlas.atlas_operations_summary_self_api_v1() to authenticated, service_role;

create or replace function public.atlas_operations_summary_self_api_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.atlas_operations_summary_self_api_v1();
$function$;

comment on function public.atlas_operations_summary_self_api_v1() is
  'Browser-facing PostgREST membrane for the Atlas-team operations summary. Canonical logic remains in atlas schema.';

revoke all on function public.atlas_operations_summary_self_api_v1() from public, anon;
grant execute on function public.atlas_operations_summary_self_api_v1() to authenticated;

commit;

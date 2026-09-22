begin;

do $validation$
declare
  v_grant jsonb;
  v_authority jsonb;
  v_row atlas.company_work_adjudication_authority_grants%rowtype;
  v_def text;
begin
  -- Historical compatibility remains historical; migration must not relabel it.
  select * into v_row
  from atlas.company_work_adjudication_authority_grants
  where id='f4c00000-0000-4000-8000-000000000121'::uuid;

  if v_row.grant_basis_kind<>'organization_owner_compatibility_cutover'
     or v_row.granted_by_principal_id is not null
     or v_row.granted_by_principal_ledger_authority_id is not null
     or v_row.grant_state<>'active' then
    raise exception 'Historical owner compatibility grant was rewritten during root-authority cutover: %',row_to_json(v_row);
  end if;

  -- A role=owner member with no Principal root-governing authority is denied.
  perform set_config(
    'request.jwt.claim.sub',
    'f4c00000-0000-4000-8000-000000000002',
    true
  );

  begin
    perform atlas.set_company_work_adjudication_authority_self_api_v1(
      'f4c00000-0000-4000-8000-000000000033'::uuid,
      'work_item',
      'f4c00000-0000-4000-8000-000000000101'::uuid,
      true,
      'owner role must not grant'
    );
    raise exception 'Organization owner administered Company Work authority without root-governing Ledger authority.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform atlas.set_company_work_adjudication_authority_self_api_v1(
      'f4c00000-0000-4000-8000-000000000032'::uuid,
      'organization',
      'f4c00000-0000-4000-8000-000000000020'::uuid,
      false,
      'owner role must not revoke'
    );
    raise exception 'Organization owner revoked Company Work authority without root-governing Ledger authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Root-governing Principal is only an Organization member, not owner.
  perform set_config(
    'request.jwt.claim.sub',
    'f4c00000-0000-4000-8000-000000000001',
    true
  );

  v_grant:=atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4c00000-0000-4000-8000-000000000033'::uuid,
    'work_item',
    'f4c00000-0000-4000-8000-000000000101'::uuid,
    true,
    'root-governing Principal exact Work grant'
  );

  if v_grant->>'grantBasisKind'<>'explicit_root_governing_grant'
     or v_grant#>>'{grantRoot,principalId}'
        <>'f4c00000-0000-4000-8000-000000000041'
     or v_grant#>>'{grantRoot,principalLedgerAuthorityId}'
        <>'f4c00000-0000-4000-8000-000000000042'
     or v_grant#>>'{grantRoot,ledgerId}'
        <>'f4c00000-0000-4000-8000-000000000021'
     or v_grant->>'scopeKind'<>'work_item' then
    raise exception 'Root-governing grant administration returned wrong provenance: %',v_grant;
  end if;

  select * into v_row
  from atlas.company_work_adjudication_authority_grants
  where id=(v_grant->>'grantId')::uuid;

  if v_row.grant_basis_kind<>'explicit_root_governing_grant'
     or v_row.granted_by_membership_id is not null
     or v_row.granted_by_principal_id
        <>'f4c00000-0000-4000-8000-000000000041'::uuid
     or v_row.granted_by_principal_ledger_authority_id
        <>'f4c00000-0000-4000-8000-000000000042'::uuid then
    raise exception 'Stored root-governing grant provenance is incorrect: %',row_to_json(v_row);
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4c00000-0000-4000-8000-000000000111'::uuid,
    'f4c00000-0000-4000-8000-000000000033'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,false)=false
     or v_authority->>'grantBasisKind'<>'explicit_root_governing_grant'
     or v_authority->>'scopeKind'<>'work_item' then
    raise exception 'Existing Result authority resolver did not honor root-established grant: %',v_authority;
  end if;

  -- Root governance can revoke the historical owner compatibility grant.
  v_grant:=atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4c00000-0000-4000-8000-000000000032'::uuid,
    'organization',
    'f4c00000-0000-4000-8000-000000000020'::uuid,
    false,
    'retire historical owner compatibility'
  );

  if v_grant->>'grantState'<>'revoked'
     or v_grant->>'grantBasisKind'<>'organization_owner_compatibility_cutover' then
    raise exception 'Root governance did not revoke historical compatibility grant: %',v_grant;
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4c00000-0000-4000-8000-000000000111'::uuid,
    'f4c00000-0000-4000-8000-000000000032'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,true) then
    raise exception 'Owner role regenerated Result authority after compatibility grant revocation: %',v_authority;
  end if;

  -- Root governance can revoke the new exact-Work grant too.
  v_grant:=atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4c00000-0000-4000-8000-000000000033'::uuid,
    'work_item',
    'f4c00000-0000-4000-8000-000000000101'::uuid,
    false,
    'root-governing revocation proof'
  );

  if v_grant->>'grantState'<>'revoked'
     or v_grant->>'grantBasisKind'<>'explicit_root_governing_grant' then
    raise exception 'Root-governing explicit grant did not revoke: %',v_grant;
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4c00000-0000-4000-8000-000000000111'::uuid,
    'f4c00000-0000-4000-8000-000000000033'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,true) then
    raise exception 'Revoked root-governing grant still authorized Result adjudication: %',v_authority;
  end if;

  -- Grant administration must rely on exact root-governing Ledger authority,
  -- not owner/Farm-role shortcuts.
  select lower(pg_get_functiondef(
    'atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)'::regprocedure
  )) into v_def;

  if v_def like '%role=''owner''%'
     or v_def like '%is_organization_owner%'
     or v_def like '%is_effective_organization_owner%'
     or v_def like '%is_farm_owner%'
     or v_def like '%is_farm_manager_or_owner%'
     or v_def not like '%company_work_adjudication_grant_root_context_self_v1%' then
    raise exception 'Company Work grant administration still contains role/adapter authority shortcuts.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.company_work_adjudication_grant_root_context_self_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%capability_root_authority_context_self_v1%'
     or v_def not like '%participation_kind=''governing''%'
     or v_def not like '%is_compatibility_primary%' then
    raise exception 'Company Work grant root context does not bind exact governing Ledger root authority.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.company_work_adjudication_grant_root_context_self_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.company_work_adjudication_grant_root_context_self_v1(uuid)',
       'EXECUTE'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.company_work_adjudication_authority_grants',
       'SELECT'
     ) then
    raise exception 'Company Work grant-root internal boundary leaked to browser roles.';
  end if;

  if to_regclass('atlas.institutional_grant_authority') is not null
     or to_regclass('atlas.universal_authority_grants') is not null
     or to_regclass('atlas.permission_grants') is not null then
    raise exception 'Company Work grant-root tranche introduced forbidden universal authority storage.';
  end if;
end;
$validation$;

rollback;

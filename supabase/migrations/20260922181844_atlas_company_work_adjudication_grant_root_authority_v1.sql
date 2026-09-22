begin;

-- Atlas Company Work Adjudication Grant Root Authority v1
--
-- Rebinds Company Work grant administration from Organization owner role
-- to existing Principal root_governing authority over the Organization's
-- exact primary governing Ledger.

alter table atlas.company_work_adjudication_authority_grants
  add column if not exists granted_by_principal_id uuid,
  add column if not exists granted_by_principal_ledger_authority_id uuid;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='atlas.company_work_adjudication_authority_grants'::regclass
      and conname='company_work_adjudication_grants_grantor_principal_fkey'
  ) then
    alter table atlas.company_work_adjudication_authority_grants
      add constraint company_work_adjudication_grants_grantor_principal_fkey
      foreign key (granted_by_principal_id)
      references atlas.principals(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='atlas.company_work_adjudication_authority_grants'::regclass
      and conname='company_work_adjudication_grants_grantor_ledger_authority_fkey'
  ) then
    alter table atlas.company_work_adjudication_authority_grants
      add constraint company_work_adjudication_grants_grantor_ledger_authority_fkey
      foreign key (granted_by_principal_ledger_authority_id)
      references atlas.principal_ledger_authorities(id) on delete restrict;
  end if;
end;
$constraints$;

alter table atlas.company_work_adjudication_authority_grants
  drop constraint if exists company_work_adjudication_authority_gran_grant_basis_kind_check;

alter table atlas.company_work_adjudication_authority_grants
  add constraint company_work_adjudication_authority_gran_grant_basis_kind_check
  check (grant_basis_kind in (
    'organization_owner_compatibility_cutover',
    'explicit_owner_grant',
    'explicit_root_governing_grant'
  ));


create or replace function atlas.company_work_adjudication_grant_root_context_self_v1(
  p_organization_id uuid
)
returns table(
  person_id uuid,
  principal_id uuid,
  principal_ledger_authority_id uuid,
  ledger_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_ledger_id uuid;
  v_count integer;
  v_person_id uuid;
  v_principal_id uuid;
  v_authority_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_organization_id is null then
    raise exception 'Organization required.' using errcode='22023';
  end if;

  select count(*)::integer
  into v_count
  from atlas.ledger_organization_participations lop
  join atlas.ledgers l on l.id=lop.ledger_id
  where lop.organization_id=p_organization_id
    and lop.status='active'
    and lop.participation_kind='governing'
    and lop.is_compatibility_primary
    and l.status='active';

  if v_count<>1 then
    raise exception 'Exactly one active primary governing Ledger is required for Company Work grant administration.'
      using errcode='23514';
  end if;

  select lop.ledger_id
  into v_ledger_id
  from atlas.ledger_organization_participations lop
  join atlas.ledgers l on l.id=lop.ledger_id
  where lop.organization_id=p_organization_id
    and lop.status='active'
    and lop.participation_kind='governing'
    and lop.is_compatibility_primary
    and l.status='active'
  limit 1;

  select c.person_id,c.principal_id,c.principal_ledger_authority_id
  into v_person_id,v_principal_id,v_authority_id
  from atlas.capability_root_authority_context_self_v1(v_ledger_id) c;

  if v_person_id is null or v_principal_id is null or v_authority_id is null then
    raise exception 'Root-governing Principal authority over the Organization governing Ledger is required.'
      using errcode='42501';
  end if;

  return query
  select v_person_id,v_principal_id,v_authority_id,v_ledger_id;
end;
$function$;

comment on function atlas.company_work_adjudication_grant_root_context_self_v1(uuid) is
  'Internal Company Work grant-administration root resolver. Requires exactly one active primary governing Ledger for the Organization and reuses capability_root_authority_context_self_v1 to prove current Principal root_governing authority over it.';

revoke all on function atlas.company_work_adjudication_grant_root_context_self_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.guard_company_work_adjudication_authority_grant_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_target atlas.organization_memberships%rowtype;
  v_grantor atlas.organization_memberships%rowtype;
  v_root_authority atlas.principal_ledger_authorities%rowtype;
  v_work_org uuid;
  v_root_ledger_id uuid;
  v_root_count integer;
begin
  select * into v_target
  from atlas.organization_memberships m
  where m.id=new.membership_id;

  if v_target.id is null
     or v_target.organization_id<>new.organization_id then
    raise exception 'Adjudication authority target must belong to the grant Organization.'
      using errcode='23514';
  end if;

  if tg_op='INSERT' and new.grant_state='active'
     and not atlas.organization_membership_present_effective_at_v1(
       v_target.id,v_target.organization_id,now()
     ) then
    raise exception 'New adjudication authority requires a present-effective target Membership.'
      using errcode='23514';
  end if;

  if new.granted_by_membership_id is not null then
    select * into v_grantor
    from atlas.organization_memberships m
    where m.id=new.granted_by_membership_id;

    if v_grantor.id is null
       or v_grantor.organization_id<>new.organization_id then
      raise exception 'Adjudication grantor Membership must belong to the same Organization.'
        using errcode='23514';
    end if;
  end if;

  if new.scope_kind='organization' then
    if new.scope_id<>new.organization_id then
      raise exception 'Organization-scoped adjudication authority must identify its own Organization.'
        using errcode='23514';
    end if;
  elsif new.scope_kind='work_item' then
    v_work_org:=atlas.effective_work_item_organization_v1(new.scope_id);
    if v_work_org is null or v_work_org<>new.organization_id then
      raise exception 'Work-scoped adjudication authority must identify Company Work in the same Organization.'
        using errcode='23514';
    end if;
  else
    raise exception 'Unsupported Company Work adjudication scope.'
      using errcode='22023';
  end if;

  if new.grant_basis_kind='explicit_root_governing_grant' then
    if new.granted_by_principal_id is null
       or new.granted_by_principal_ledger_authority_id is null then
      raise exception 'Root-governing adjudication grants require exact Principal and Principal Ledger Authority provenance.'
        using errcode='23514';
    end if;

    select * into v_root_authority
    from atlas.principal_ledger_authorities a
    where a.id=new.granted_by_principal_ledger_authority_id
      and a.principal_id=new.granted_by_principal_id
      and a.authority_kind='root_governing'
      and a.status='active';

    if v_root_authority.id is null then
      raise exception 'Root-governing adjudication grant provenance is not an active matching Principal Ledger Authority.'
        using errcode='23514';
    end if;

    select count(*)::integer
    into v_root_count
    from atlas.ledger_organization_participations lop
    join atlas.ledgers l on l.id=lop.ledger_id
    where lop.organization_id=new.organization_id
      and lop.status='active'
      and lop.participation_kind='governing'
      and lop.is_compatibility_primary
      and l.status='active';

    if v_root_count<>1 then
      raise exception 'Root-governing adjudication grant provenance requires exactly one Organization primary governing Ledger.'
        using errcode='23514';
    end if;

    select lop.ledger_id
    into v_root_ledger_id
    from atlas.ledger_organization_participations lop
    join atlas.ledgers l on l.id=lop.ledger_id
    where lop.organization_id=new.organization_id
      and lop.status='active'
      and lop.participation_kind='governing'
      and lop.is_compatibility_primary
      and l.status='active'
    limit 1;

    if v_root_authority.ledger_id<>v_root_ledger_id then
      raise exception 'Root-governing adjudication grant provenance must match the Organization exact primary governing Ledger.'
        using errcode='23514';
    end if;
  else
    if new.granted_by_principal_id is not null
       or new.granted_by_principal_ledger_authority_id is not null then
      raise exception 'Historical owner-based adjudication grant bases cannot claim Principal root-governing provenance.'
        using errcode='23514';
    end if;
  end if;

  if tg_op='UPDATE' then
    if old.organization_id is distinct from new.organization_id
       or old.membership_id is distinct from new.membership_id
       or old.authority_kind is distinct from new.authority_kind
       or old.scope_kind is distinct from new.scope_kind
       or old.scope_id is distinct from new.scope_id
       or old.granted_by_membership_id is distinct from new.granted_by_membership_id
       or old.granted_by_principal_id is distinct from new.granted_by_principal_id
       or old.granted_by_principal_ledger_authority_id is distinct from new.granted_by_principal_ledger_authority_id
       or old.grant_basis_kind is distinct from new.grant_basis_kind
       or old.granted_at is distinct from new.granted_at then
      raise exception 'Company Work adjudication grant identity/provenance is immutable.'
        using errcode='23514';
    end if;

    if old.grant_state='revoked' and new.grant_state<>'revoked' then
      raise exception 'Revoked Company Work adjudication authority cannot be reactivated.'
        using errcode='23514';
    end if;
  end if;

  if new.grant_state='active' and new.revoked_at is not null then
    raise exception 'Active adjudication authority cannot have a revocation timestamp.'
      using errcode='23514';
  end if;

  if new.grant_state='revoked' and new.revoked_at is null then
    new.revoked_at:=now();
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;


create or replace function atlas.set_company_work_adjudication_authority_self_api_v1(
  p_membership_id uuid,
  p_scope_kind text,
  p_scope_id uuid,
  p_enabled boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_scope_kind text:=lower(btrim(coalesce(p_scope_kind,'')));
  v_organization_id uuid;
  v_target atlas.organization_memberships%rowtype;
  v_existing atlas.company_work_adjudication_authority_grants%rowtype;
  v_person_id uuid;
  v_principal_id uuid;
  v_root_authority_id uuid;
  v_root_ledger_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_membership_id is null or p_scope_id is null then
    raise exception 'Target Membership and adjudication scope are required.'
      using errcode='22023';
  end if;

  if v_scope_kind='organization' then
    v_organization_id:=p_scope_id;
  elsif v_scope_kind='work_item' then
    v_organization_id:=atlas.effective_work_item_organization_v1(p_scope_id);
    if v_organization_id is null then
      raise exception 'Company Work scope was not found.' using errcode='P0002';
    end if;
  else
    raise exception 'Adjudication scope must be organization or work_item.'
      using errcode='22023';
  end if;

  select r.person_id,r.principal_id,r.principal_ledger_authority_id,r.ledger_id
  into v_person_id,v_principal_id,v_root_authority_id,v_root_ledger_id
  from atlas.company_work_adjudication_grant_root_context_self_v1(v_organization_id) r;

  if v_principal_id is null or v_root_authority_id is null then
    raise exception 'Root-governing Principal authority required for Company Work grant administration.'
      using errcode='42501';
  end if;

  select * into v_target
  from atlas.organization_memberships m
  where m.id=p_membership_id
    and m.organization_id=v_organization_id;

  if v_target.id is null then
    raise exception 'Adjudication grant target must belong to the scoped Organization.'
      using errcode='23514';
  end if;

  if p_enabled
     and not atlas.organization_membership_present_effective_at_v1(
       v_target.id,v_target.organization_id,now()
     ) then
    raise exception 'New adjudication authority requires a present-effective target Membership.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.company_work_adjudication_authority_grants g
  where g.organization_id=v_organization_id
    and g.membership_id=v_target.id
    and g.authority_kind='result_acceptance'
    and g.scope_kind=v_scope_kind
    and g.scope_id=p_scope_id
    and g.grant_state='active'
  order by g.granted_at desc,g.id
  limit 1
  for update;

  if p_enabled then
    if v_existing.id is null then
      insert into atlas.company_work_adjudication_authority_grants(
        organization_id,membership_id,authority_kind,scope_kind,scope_id,
        granted_by_membership_id,granted_by_principal_id,
        granted_by_principal_ledger_authority_id,
        grant_basis_kind,metadata
      ) values(
        v_organization_id,v_target.id,'result_acceptance',v_scope_kind,p_scope_id,
        null,v_principal_id,v_root_authority_id,
        'explicit_root_governing_grant',
        jsonb_build_object(
          'source','set_company_work_adjudication_authority_self_api_v1',
          'rootLedgerId',v_root_ledger_id,
          'reason',nullif(btrim(coalesce(p_reason,'')),'')
        )
      )
      returning * into v_existing;
    elsif v_existing.grant_basis_kind<>'explicit_root_governing_grant' then
      update atlas.company_work_adjudication_authority_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'revocationReason','superseded_by_explicit_root_governing_grant',
            'revokedByPrincipalId',v_principal_id,
            'revokedByPrincipalLedgerAuthorityId',v_root_authority_id,
            'reason',nullif(btrim(coalesce(p_reason,'')),'')
          )
      where id=v_existing.id;

      insert into atlas.company_work_adjudication_authority_grants(
        organization_id,membership_id,authority_kind,scope_kind,scope_id,
        granted_by_membership_id,granted_by_principal_id,
        granted_by_principal_ledger_authority_id,
        grant_basis_kind,metadata
      ) values(
        v_organization_id,v_target.id,'result_acceptance',v_scope_kind,p_scope_id,
        null,v_principal_id,v_root_authority_id,
        'explicit_root_governing_grant',
        jsonb_build_object(
          'source','set_company_work_adjudication_authority_self_api_v1',
          'rootLedgerId',v_root_ledger_id,
          'reason',nullif(btrim(coalesce(p_reason,'')),''),
          'supersedesGrantId',v_existing.id
        )
      )
      returning * into v_existing;
    end if;
  else
    if v_existing.id is not null then
      update atlas.company_work_adjudication_authority_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'revocationReason',coalesce(
              nullif(btrim(coalesce(p_reason,'')),''),
              'explicit_root_governing_revocation'
            ),
            'revokedByPrincipalId',v_principal_id,
            'revokedByPrincipalLedgerAuthorityId',v_root_authority_id
          )
      where id=v_existing.id
      returning * into v_existing;
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_adjudication_authority_grant_v2',
    'organizationId',v_organization_id,
    'membershipId',v_target.id,
    'authorityKind','result_acceptance',
    'scopeKind',v_scope_kind,
    'scopeId',p_scope_id,
    'enabled',p_enabled,
    'grantId',v_existing.id,
    'grantBasisKind',v_existing.grant_basis_kind,
    'grantState',v_existing.grant_state,
    'grantRoot',jsonb_build_object(
      'principalId',v_principal_id,
      'principalLedgerAuthorityId',v_root_authority_id,
      'ledgerId',v_root_ledger_id,
      'authorityKind','root_governing'
    )
  );
end;
$function$;

comment on function atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text) is
  'Company Work adjudication grant administration. Requires current Principal root_governing authority over the Organization exact active primary governing Ledger; Organization owner role is not grant-establishment authority.';


update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'source','atlas_company_work_adjudication_grant_root_authority_v1',
      'purpose','Establish or revoke bounded Company Work Result-adjudication authority under exact Principal root-governing authority over the Organization governing Ledger.',
      'truthBoundary','Grant administration only. Organization owner/Farm role does not imply grant-establishment authority; Principal status alone is insufficient without exact root-governing Ledger authority.',
      'classificationRuleVersion',3
    ),
    reviewed_at=now()
where signature='atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)';

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.company_work_adjudication_grant_root_context_self_v1(uuid)',
  'service_internal','verified','active',
  false,true,false,0,1,
  jsonb_build_object(
    'source','atlas_company_work_adjudication_grant_root_authority_v1',
    'purpose','Resolve exact Company Work grant-administration root from the Organization primary governing Ledger and existing Principal root-governing authority.',
    'truthBoundary','Internal read-only self context. Does not grant authority and does not infer root from Organization role or Principal status alone.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;

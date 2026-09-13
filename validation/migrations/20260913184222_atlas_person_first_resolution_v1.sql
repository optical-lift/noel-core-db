-- Canonical postconditions for Atlas Person-First Resolution v1.
-- Runs only against the disposable production-schema clone after the candidate migration.

do $proof$
declare
  v_def text;
begin
  if to_regprocedure('atlas.current_person_id_v1()') is null
     or to_regprocedure('atlas.current_principal_id_v1()') is null
     or to_regprocedure('atlas.current_organization_membership_v1(uuid)') is null
     or to_regprocedure('atlas.is_organization_member(uuid)') is null
     or to_regprocedure('atlas.is_organization_owner(uuid)') is null
     or to_regprocedure('atlas.atlas_home_identity_self_api_v1()') is null
     or to_regprocedure('atlas.organization_access_self_api_v1()') is null
     or to_regprocedure('atlas.personal_atlas_access_status_self_api_v1()') is null
     or to_regprocedure('atlas.principal_self_context_api_v1()') is null then
    raise exception 'Person-first resolution function set is incomplete.';
  end if;

  select pg_get_functiondef('atlas.current_principal_id_v1()'::regprocedure) into v_def;
  if position('p.person_id = atlas.current_person_id_v1()' in v_def) = 0
     or position('p.user_id=auth.uid()' in replace(v_def,' ','')) > 0 then
    raise exception 'Current Principal resolution is not canonically Person-first.';
  end if;

  select pg_get_functiondef('atlas.current_organization_membership_v1(uuid)'::regprocedure) into v_def;
  if position('om.person_id = atlas.current_person_id_v1()' in v_def) = 0 then
    raise exception 'Current Organization Membership resolution is not Person-first.';
  end if;

  select pg_get_functiondef('atlas.is_organization_member(uuid)'::regprocedure) into v_def;
  if position('om.person_id = atlas.current_person_id_v1()' in v_def) = 0 then
    raise exception 'Organization member predicate is not Person-first.';
  end if;

  select pg_get_functiondef('atlas.is_organization_owner(uuid)'::regprocedure) into v_def;
  if position('om.person_id = atlas.current_person_id_v1()' in v_def) = 0 then
    raise exception 'Organization owner predicate is not Person-first.';
  end if;

  select pg_get_functiondef('atlas.atlas_home_identity_self_api_v1()'::regprocedure) into v_def;
  if position('atlas.current_principal_id_v1()' in v_def) = 0 then
    raise exception 'Atlas home identity does not use the Person-first Principal resolver.';
  end if;

  select pg_get_functiondef('atlas.organization_access_self_api_v1()'::regprocedure) into v_def;
  if position('c.auth_user_id = v_uid' in v_def) = 0
     or position('m.person_id = v_person_id' in v_def) = 0 then
    raise exception 'Organization access did not preserve credential proof plus Person membership proof.';
  end if;

  if position('m.user_id=v_uid' in replace(v_def,' ','')) > 0 then
    raise exception 'Organization access still roots durable membership in auth user id.';
  end if;

  select pg_get_functiondef('atlas.personal_atlas_access_status_self_api_v1()'::regprocedure) into v_def;
  if position('v_principal_id := atlas.current_principal_id_v1();' in v_def) = 0 then
    raise exception 'Personal Atlas access does not resolve Principal through canonical Person.';
  end if;
  if position('claimed_by_user_id=v_user_id' in replace(v_def,' ','')) = 0 then
    raise exception 'Credential-bound purchase claim evidence was removed from Personal Atlas access.';
  end if;

  select pg_get_functiondef('atlas.principal_self_context_api_v1()'::regprocedure) into v_def;
  if position('v_principal_id := atlas.current_principal_id_v1();' in v_def) = 0 then
    raise exception 'Principal self context does not use the Person-first resolver.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    left join atlas.person_auth_credentials c
      on c.auth_user_id = p.user_id
     and c.status = 'active'
    where p.user_id is not null
      and (p.person_id is null or c.person_id is distinct from p.person_id)
  ) then
    raise exception 'Principal legacy credential and canonical Person identity disagree.';
  end if;

  if exists (
    select 1
    from atlas.organization_memberships m
    left join atlas.person_auth_credentials c
      on c.auth_user_id = m.user_id
     and c.status = 'active'
    where m.user_id is not null
      and (m.person_id is null or c.person_id is distinct from m.person_id)
  ) then
    raise exception 'Organization Membership legacy credential and canonical Person identity disagree.';
  end if;

  if exists (
    select 1
    from atlas.organization_member_credentials c
    join atlas.organization_memberships m
      on m.id = c.organization_membership_id
     and m.organization_id = c.organization_id
    left join atlas.person_auth_credentials pc
      on pc.auth_user_id = c.auth_user_id
     and pc.status = 'active'
    where c.credential_kind = 'auth_user'
      and c.status = 'active'
      and (pc.person_id is null or m.person_id is distinct from pc.person_id)
  ) then
    raise exception 'Active organization credential is not bound to the canonical Person that owns its Membership.';
  end if;

  if has_table_privilege('anon','atlas.people','SELECT')
     or has_table_privilege('authenticated','atlas.people','SELECT')
     or has_table_privilege('anon','atlas.person_auth_credentials','SELECT')
     or has_table_privilege('authenticated','atlas.person_auth_credentials','SELECT') then
    raise exception 'Person-first resolution widened direct browser table access.';
  end if;

  if has_function_privilege('anon','atlas.current_person_id_v1()','EXECUTE')
     or has_function_privilege('authenticated','atlas.current_person_id_v1()','EXECUTE') then
    raise exception 'Canonical current-Person helper became directly browser-callable.';
  end if;
end;
$proof$;

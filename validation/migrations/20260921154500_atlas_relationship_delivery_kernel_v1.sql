begin;

do $validation$
declare
  v_org uuid:=gen_random_uuid();
  v_person uuid:=gen_random_uuid();
  v_ipr uuid;
  v_issue jsonb;
  v_issue2 jsonb;
  v_bootstrap text;
  v_bootstrap2 text;
  v_grant uuid;
  v_grant2 uuid;
  v_credential uuid;
  v_stored_bootstrap_hash text;
  v_redeem jsonb;
  v_redeem2 jsonb;
  v_session_token text;
  v_session_token2 text;
  v_session_id uuid;
  v_stored_session_hash text;
  v_context jsonb;
  v_contract_context jsonb;
begin
  if to_regclass('atlas.relationship_delivery_grants') is null
     or to_regclass('atlas.relationship_delivery_institution_bindings') is null
     or to_regclass('atlas.relationship_delivery_bootstrap_credentials') is null
     or to_regclass('atlas.relationship_delivery_sessions') is null then
    raise exception 'Relationship Delivery kernel tables are missing.';
  end if;

  insert into atlas.organizations(id,stable_key,name)
  values(
    v_org,
    'relationship-delivery-proof-'||substr(v_org::text,1,8),
    'Relationship Delivery Proof'
  );

  insert into atlas.people(id,display_name,status,metadata)
  values(
    v_person,
    'Accountless Relationship Recipient',
    'active',
    '{"proof":"relationship_delivery_kernel_v1"}'::jsonb
  );

  insert into atlas.institutional_person_records(
    organization_id,
    person_id,
    status,
    establishment_basis
  ) values(
    v_org,
    v_person,
    'active',
    '{"contractVersion":"institutional_person_record_v1","basisKind":"relationship_delivery_validation"}'::jsonb
  )
  returning id into v_ipr;

  if exists(
    select 1 from atlas.person_auth_credentials c
    where c.person_id=v_person and c.status='active'
  ) or exists(
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_org and m.person_id=v_person
  ) then
    raise exception 'Relationship Delivery validation recipient unexpectedly requires an Atlas login or Organization Membership.';
  end if;

  v_issue:=atlas.issue_institutional_relationship_delivery_service_v1(
    v_ipr,
    array[
      ' company_work.worker_day.v1 ',
      'company_work.worker_day.v1'
    ],
    array['company_work.result_report.v1'],
    now()+interval '14 days',
    now()+interval '2 days',
    '{"basis":"validation","issuerContext":"organization"}'::jsonb
  );

  v_grant:=(v_issue->>'grantId')::uuid;
  v_credential:=(v_issue->>'bootstrapCredentialId')::uuid;
  v_bootstrap:=v_issue->>'bootstrapSecret';

  if v_bootstrap is null or length(v_bootstrap)<40 then
    raise exception 'Relationship Delivery issuance did not return one-time bootstrap material.';
  end if;

  select c.secret_hash
  into v_stored_bootstrap_hash
  from atlas.relationship_delivery_bootstrap_credentials c
  where c.id=v_credential;

  if v_stored_bootstrap_hash is null
     or v_stored_bootstrap_hash=v_bootstrap
     or v_stored_bootstrap_hash<>atlas.relationship_delivery_secret_hash_v1(v_bootstrap) then
    raise exception 'Relationship Delivery bootstrap secret was not stored hash-only.';
  end if;

  if exists(
    select 1
    from atlas.relationship_delivery_grants g
    where g.id=v_grant
      and (
        g.recipient_person_id<>v_person
        or g.projection_contracts<>array['company_work.worker_day.v1']::text[]
        or g.response_contracts<>array['company_work.result_report.v1']::text[]
      )
  ) then
    raise exception 'Relationship Delivery grant did not normalize/admit the expected bounded contracts.';
  end if;

  if not exists(
    select 1
    from atlas.relationship_delivery_institution_bindings b
    where b.grant_id=v_grant
      and b.organization_id=v_org
      and b.institutional_person_record_id=v_ipr
  ) then
    raise exception 'Relationship Delivery grant lacks its typed Institutional Person binding.';
  end if;

  v_redeem:=atlas.redeem_relationship_delivery_bootstrap_service_v1(
    v_bootstrap,
    86400,
    '{"deviceClass":"validation"}'::jsonb
  );

  v_session_id:=(v_redeem->>'sessionId')::uuid;
  v_session_token:=v_redeem->>'sessionToken';

  if v_session_token is null or length(v_session_token)<40 then
    raise exception 'Relationship Delivery redemption did not return one-time session material.';
  end if;

  select s.token_hash
  into v_stored_session_hash
  from atlas.relationship_delivery_sessions s
  where s.id=v_session_id;

  if v_stored_session_hash is null
     or v_stored_session_hash=v_session_token
     or v_stored_session_hash<>atlas.relationship_delivery_secret_hash_v1(v_session_token) then
    raise exception 'Relationship Delivery session token was not stored hash-only.';
  end if;

  if not exists(
    select 1
    from atlas.relationship_delivery_bootstrap_credentials c
    where c.id=v_credential
      and c.status='redeemed'
      and c.redeemed_at is not null
  ) then
    raise exception 'Relationship Delivery bootstrap credential was not consumed after redemption.';
  end if;

  begin
    perform atlas.redeem_relationship_delivery_bootstrap_service_v1(
      v_bootstrap,
      86400,
      '{}'::jsonb
    );
    raise exception 'One-time Relationship Delivery bootstrap credential was redeemable twice.';
  exception when insufficient_privilege then
    null;
  end;

  v_context:=atlas.relationship_delivery_session_context_service_v1(
    v_session_token
  );

  if (v_context->>'recipientPersonId')::uuid<>v_person
     or (v_context#>>'{relationship,kind}')<>'institutional_person_record'
     or (v_context#>>'{relationship,organizationId}')::uuid<>v_org
     or (v_context#>>'{relationship,institutionalPersonRecordId}')::uuid<>v_ipr then
    raise exception 'Relationship Delivery session context resolved the wrong recipient relationship.';
  end if;

  v_contract_context:=
    atlas.relationship_delivery_session_contract_internal_v1(
      v_session_token,
      'projection',
      'company_work.worker_day.v1'
    );

  if (v_contract_context->>'grantId')::uuid<>v_grant then
    raise exception 'Relationship Delivery admitted projection contract did not resolve the same grant.';
  end if;

  perform atlas.relationship_delivery_session_contract_internal_v1(
    v_session_token,
    'response',
    'company_work.result_report.v1'
  );

  begin
    perform atlas.relationship_delivery_session_contract_internal_v1(
      v_session_token,
      'projection',
      'household.grocery.v1'
    );
    raise exception 'Relationship Delivery admitted a projection contract not named by the grant.';
  exception when insufficient_privilege then
    null;
  end;

  perform atlas.revoke_relationship_delivery_grant_service_v1(
    v_grant,
    'validation revocation',
    '{"basis":"validation"}'::jsonb
  );

  if not exists(
    select 1 from atlas.relationship_delivery_grants
    where id=v_grant and status='revoked' and revoked_at is not null
  ) or not exists(
    select 1 from atlas.relationship_delivery_sessions
    where id=v_session_id and status='revoked' and revoked_at is not null
  ) then
    raise exception 'Relationship Delivery revocation did not close the grant and active session.';
  end if;

  begin
    perform atlas.relationship_delivery_session_context_service_v1(
      v_session_token
    );
    raise exception 'Revoked Relationship Delivery session still resolved.';
  exception when insufficient_privilege then
    null;
  end;

  if not exists(
    select 1 from atlas.institutional_person_records
    where id=v_ipr and status='active'
  ) then
    raise exception 'Delivery revocation improperly rewrote the underlying institutional relationship.';
  end if;

  -- Relationship invalidation must fail closed even if the grant/session rows
  -- themselves have not yet been prospectively revoked.
  v_issue2:=atlas.issue_institutional_relationship_delivery_service_v1(
    v_ipr,
    array['company_work.worker_day.v1'],
    array['company_work.result_report.v1'],
    now()+interval '14 days',
    now()+interval '2 days',
    '{"basis":"relationship-retirement-validation"}'::jsonb
  );

  v_grant2:=(v_issue2->>'grantId')::uuid;
  v_bootstrap2:=v_issue2->>'bootstrapSecret';

  v_redeem2:=atlas.redeem_relationship_delivery_bootstrap_service_v1(
    v_bootstrap2,
    86400,
    '{}'::jsonb
  );
  v_session_token2:=v_redeem2->>'sessionToken';

  update atlas.institutional_person_records
  set status='retired'
  where id=v_ipr;

  begin
    perform atlas.relationship_delivery_session_context_service_v1(
      v_session_token2
    );
    raise exception 'Relationship Delivery session survived retirement of its source relationship.';
  exception when insufficient_privilege then
    null;
  end;

  if not exists(
    select 1
    from atlas.relationship_delivery_grants
    where id=v_grant2 and status='active'
  ) then
    raise exception 'Relationship retirement should invalidate delivery resolution without rewriting grant history.';
  end if;

  if has_table_privilege('anon','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('service_role','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('anon','atlas.relationship_delivery_bootstrap_credentials','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_sessions','SELECT') then
    raise exception 'Relationship Delivery raw tables gained direct client/service table read authority.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.relationship_delivery_session_context_service_v1(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.relationship_delivery_session_context_service_v1(text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.relationship_delivery_session_context_service_v1(text)',
       'EXECUTE'
     ) then
    raise exception 'Relationship Delivery service read privilege boundary is invalid.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.issue_institutional_relationship_delivery_service_v1(uuid,text[],text[],timestamptz,timestamptz,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.issue_institutional_relationship_delivery_service_v1(uuid,text[],text[],timestamptz,timestamptz,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Relationship Delivery issuance privilege boundary is invalid.';
  end if;

  if not exists(
    select 1
    from atlas.architecture_truth_authorities
    where authority_key='relationship_delivery_grant'
      and authority_status='canonical'
      and authority_owner='atlas.relationship_delivery_grants'
  ) then
    raise exception 'Relationship Delivery truth authority registration is missing.';
  end if;
end;
$validation$;

rollback;

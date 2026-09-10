begin;

-- Gate 1: canonical organization employee entry.
-- An invitation is an access offer only. Acceptance creates/attaches institutional
-- identity, organization membership, an employee billing seat, and an auth credential.
-- It does NOT create a position, responsibility, Principal authority, execution
-- authority, or semantic exposure grant.

create table if not exists atlas.organization_access_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  invitee_email text not null,
  display_name text not null,
  access_class text not null default 'employee' check (access_class in ('employee')),
  status text not null default 'draft' check (status in ('draft','issued','accepted','revoked','expired')),
  issuer_kind text not null check (issuer_kind in ('organization_owner','setup_actor')),
  issued_by_user_id uuid not null references auth.users(id) on delete restrict,
  issued_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  intended_identity_subject_id uuid references atlas.identity_subjects(id) on delete restrict,
  accepted_by_user_id uuid references auth.users(id) on delete restrict,
  issued_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_access_invitations_email_check
    check (invitee_email=lower(btrim(invitee_email)) and position('@' in invitee_email)>1),
  constraint organization_access_invitations_name_check check (btrim(display_name)<>''),
  constraint organization_access_invitations_issuer_shape check (
    (issuer_kind='organization_owner' and issued_by_membership_id is not null)
    or (issuer_kind='setup_actor' and issued_by_membership_id is null)
  ),
  constraint organization_access_invitations_time_check check (
    expires_at is null or issued_at is null or expires_at > issued_at
  )
);

create unique index if not exists organization_access_invitations_open_email_uq
  on atlas.organization_access_invitations(organization_id, invitee_email)
  where status in ('draft','issued');
create index if not exists organization_access_invitations_status_idx
  on atlas.organization_access_invitations(organization_id,status,created_at desc);

comment on table atlas.organization_access_invitations is
  'Typed institutional access offers. An invitation may establish membership/seat/credential on acceptance, but never implies position, responsibility, Principal authority, execution authority, or semantic exposure.';

alter table atlas.organization_access_invitations enable row level security;
revoke all on table atlas.organization_access_invitations from public, anon, authenticated;
grant select,insert,update,delete on table atlas.organization_access_invitations to service_role;

create or replace function atlas.organization_access_inviter_context_self_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_membership_id uuid;
begin
  if v_uid is null or p_organization_id is null then return null; end if;

  -- Bounded bootstrap rule: an active durable owner may issue employee access.
  -- This role check is deliberately local to this membrane; it is not a general
  -- role-to-permission inference rule.
  select m.id into v_membership_id
  from atlas.organization_memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.active
    and m.role='owner'
  order by m.created_at
  limit 1;

  if v_membership_id is not null then
    return jsonb_build_object('issuerKind','organization_owner','membershipId',v_membership_id,'userId',v_uid);
  end if;

  if exists (
    select 1 from atlas.organization_onboarding_actors a
    where a.organization_id=p_organization_id
      and a.human_user_id=v_uid
      and a.active
      and a.ended_at is null
  ) then
    return jsonb_build_object('issuerKind','setup_actor','membershipId',null,'userId',v_uid);
  end if;

  return null;
end;
$function$;

revoke all on function atlas.organization_access_inviter_context_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.organization_access_inviter_context_self_v1(uuid) to service_role;

create or replace function atlas.prepare_organization_employee_invitation_self_api_v1(
  p_organization_id uuid,
  p_email text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_name text:=btrim(coalesce(p_display_name,''));
  v_ctx jsonb;
  v_invite atlas.organization_access_invitations%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if v_email='' or position('@' in v_email)<=1 then raise exception 'A valid email is required.' using errcode='22023'; end if;
  if v_name='' then raise exception 'A display name is required.' using errcode='22023'; end if;

  v_ctx:=atlas.organization_access_inviter_context_self_v1(p_organization_id);
  if v_ctx is null then raise exception 'Organization employee invitation authority required.' using errcode='42501'; end if;

  if exists (
    select 1 from atlas.organization_member_credentials c
    join auth.users u on u.id=c.auth_user_id
    where c.organization_id=p_organization_id
      and c.credential_kind='auth_user'
      and c.status='active'
      and lower(u.email)=v_email
  ) then
    raise exception 'This authenticated account already has active organization access.' using errcode='23505';
  end if;

  select * into v_invite
  from atlas.organization_access_invitations i
  where i.organization_id=p_organization_id
    and i.invitee_email=v_email
    and i.status in ('draft','issued')
  for update;

  if v_invite.id is null then
    insert into atlas.organization_access_invitations(
      organization_id,invitee_email,display_name,access_class,status,
      issuer_kind,issued_by_user_id,issued_by_membership_id,metadata
    ) values (
      p_organization_id,v_email,v_name,'employee','draft',
      v_ctx->>'issuerKind',v_uid,nullif(v_ctx->>'membershipId','')::uuid,
      jsonb_build_object('contractVersion','organization_access_invitation_v1')
    ) returning * into v_invite;
  else
    update atlas.organization_access_invitations
    set display_name=v_name,
        status='draft',
        issuer_kind=v_ctx->>'issuerKind',
        issued_by_user_id=v_uid,
        issued_by_membership_id=nullif(v_ctx->>'membershipId','')::uuid,
        issued_at=null,
        expires_at=null,
        revoked_at=null,
        updated_at=now()
    where id=v_invite.id
    returning * into v_invite;
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','organization_access_invitation_v1',
    'invitationId',v_invite.id,'organizationId',v_invite.organization_id,
    'email',v_invite.invitee_email,'displayName',v_invite.display_name,
    'status',v_invite.status,'accessClass',v_invite.access_class
  );
end;
$function$;

create or replace function atlas.issue_organization_employee_invitation_service_v1(
  p_invitation_id uuid,
  p_expires_at timestamptz default null,
  p_auth_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_invite atlas.organization_access_invitations%rowtype;
begin
  select * into v_invite
  from atlas.organization_access_invitations i
  where i.id=p_invitation_id and i.status='draft'
  for update;
  if v_invite.id is null then raise exception 'Draft organization invitation not found.' using errcode='P0002'; end if;
  if p_expires_at is not null and p_expires_at<=now() then raise exception 'Invitation expiry must be in the future.' using errcode='22023'; end if;

  update atlas.organization_access_invitations
  set status='issued',issued_at=now(),expires_at=p_expires_at,
      metadata=metadata || jsonb_strip_nulls(jsonb_build_object('providerAuthUserId',p_auth_user_id)),
      updated_at=now()
  where id=v_invite.id
  returning * into v_invite;

  return jsonb_build_object('ok',true,'invitationId',v_invite.id,'status',v_invite.status,'issuedAt',v_invite.issued_at,'expiresAt',v_invite.expires_at);
end;
$function$;

create or replace function atlas.revoke_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_invite atlas.organization_access_invitations%rowtype;
  v_ctx jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into v_invite from atlas.organization_access_invitations where id=p_invitation_id for update;
  if v_invite.id is null then raise exception 'Organization invitation not found.' using errcode='P0002'; end if;
  v_ctx:=atlas.organization_access_inviter_context_self_v1(v_invite.organization_id);
  if v_ctx is null then raise exception 'Organization employee invitation authority required.' using errcode='42501'; end if;
  if v_invite.status not in ('draft','issued') then raise exception 'Only open invitations can be revoked.' using errcode='55000'; end if;
  update atlas.organization_access_invitations
  set status='revoked',revoked_at=now(),updated_at=now()
  where id=v_invite.id;
  return jsonb_build_object('ok',true,'invitationId',v_invite.id,'status','revoked');
end;
$function$;

create or replace function atlas.pending_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_email text;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null;
  if v_email is null then return jsonb_build_object('ok',false,'reason','authenticated_email_unavailable'); end if;

  select jsonb_build_object(
    'ok',true,'contractVersion','organization_access_invitation_v1',
    'invitationId',i.id,'organizationId',i.organization_id,'organizationName',o.name,
    'displayName',i.display_name,'email',i.invitee_email,'accessClass',i.access_class,
    'status',case when i.expires_at is not null and i.expires_at<=now() then 'expired' else i.status end,
    'expiresAt',i.expires_at
  ) into v_result
  from atlas.organization_access_invitations i
  join atlas.organizations o on o.id=i.organization_id
  where i.id=p_invitation_id
    and i.status in ('issued','accepted')
    and i.invitee_email=v_email
    and (i.accepted_by_user_id is null or i.accepted_by_user_id=v_uid);

  return coalesce(v_result,jsonb_build_object('ok',false,'reason','invitation_not_available'));
end;
$function$;

create or replace function atlas.accept_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_email text;
  v_invite atlas.organization_access_invitations%rowtype;
  v_issuer_ok boolean:=false;
  v_subject_id uuid;
  v_membership_id uuid;
  v_seat_id uuid;
  v_credential_id uuid;
  v_existing_credential atlas.organization_member_credentials%rowtype;
  v_candidate_count integer:=0;
  v_candidate_subject uuid;
  v_review_id uuid;
  v_source_record_id uuid;
  v_email_claim_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
  if v_email is null then raise exception 'Authenticated email unavailable.' using errcode='42501'; end if;

  select * into v_invite
  from atlas.organization_access_invitations i
  where i.id=p_invitation_id
  for update;
  if v_invite.id is null then raise exception 'Organization invitation not found.' using errcode='P0002'; end if;
  if v_invite.invitee_email<>v_email then raise exception 'This invitation is not available to the signed-in account.' using errcode='42501'; end if;

  -- Idempotent replay by the same accepted credential carrier.
  if v_invite.status='accepted' and v_invite.accepted_by_user_id=v_uid then
    select c.* into v_existing_credential
    from atlas.organization_member_credentials c
    where c.organization_id=v_invite.organization_id
      and c.auth_user_id=v_uid and c.credential_kind='auth_user' and c.status='active'
    order by c.created_at limit 1;
    if v_existing_credential.id is not null then
      return jsonb_build_object('ok',true,'replayed',true,'invitationId',v_invite.id,
        'identitySubjectId',v_existing_credential.identity_subject_id,
        'organizationMembershipId',v_existing_credential.organization_membership_id,
        'employeeSeatId',v_existing_credential.employee_seat_id,
        'credentialId',v_existing_credential.id);
    end if;
  end if;

  if v_invite.status<>'issued' then raise exception 'Invitation is not open for acceptance.' using errcode='55000'; end if;
  if v_invite.expires_at is not null and v_invite.expires_at<=now() then
    update atlas.organization_access_invitations set status='expired',updated_at=now() where id=v_invite.id;
    return jsonb_build_object('ok',false,'reason','invitation_expired','invitationId',v_invite.id);
  end if;

  -- Revalidate the original issuer at the moment of acceptance.
  if v_invite.issuer_kind='organization_owner' then
    v_issuer_ok:=exists(
      select 1 from atlas.organization_memberships m
      where m.id=v_invite.issued_by_membership_id
        and m.organization_id=v_invite.organization_id
        and m.user_id=v_invite.issued_by_user_id
        and m.active and m.role='owner'
    );
  elsif v_invite.issuer_kind='setup_actor' then
    v_issuer_ok:=exists(
      select 1 from atlas.organization_onboarding_actors a
      where a.organization_id=v_invite.organization_id
        and a.human_user_id=v_invite.issued_by_user_id
        and a.active and a.ended_at is null
    );
  end if;
  if not v_issuer_ok then raise exception 'Invitation issuer authority is no longer valid.' using errcode='42501'; end if;

  -- Existing active credential is the strongest local binding.
  select c.* into v_existing_credential
  from atlas.organization_member_credentials c
  where c.organization_id=v_invite.organization_id
    and c.auth_user_id=v_uid and c.credential_kind='auth_user' and c.status='active'
  order by c.created_at limit 1;
  if v_existing_credential.id is not null then
    v_subject_id:=v_existing_credential.identity_subject_id;
    v_membership_id:=v_existing_credential.organization_membership_id;
    v_seat_id:=v_existing_credential.employee_seat_id;
    v_credential_id:=v_existing_credential.id;
  else
    select m.id,m.identity_subject_id into v_membership_id,v_subject_id
    from atlas.organization_memberships m
    where m.organization_id=v_invite.organization_id and m.user_id=v_uid and m.active
    order by m.created_at limit 1;

    if v_subject_id is null and v_invite.intended_identity_subject_id is not null then
      if not exists(select 1 from atlas.identity_subjects s where s.id=v_invite.intended_identity_subject_id and s.organization_id=v_invite.organization_id and s.state='active') then
        raise exception 'Prebound institutional identity is outside invitation custody.' using errcode='23514';
      end if;
      v_subject_id:=v_invite.intended_identity_subject_id;
    end if;

    -- Never attach an authenticated employee to pre-existing identity evidence by
    -- string similarity alone. Exact prior email evidence is either supported by an
    -- explicit accept_claim adjudication or contained for reconciliation.
    if v_subject_id is null then
      with candidates as (
        select distinct c.subject_id
        from atlas.identity_claims c
        left join atlas.identity_reconciliation_adjudications a
          on a.organization_id=c.organization_id
         and a.claim_id=c.id
         and a.subject_id=c.subject_id
         and a.decision_kind='accept_claim'
        where c.organization_id=v_invite.organization_id
          and c.claim_kind in ('email','email_address')
          and lower(btrim(case
            when jsonb_typeof(c.claim_value)='string' then c.claim_value#>>'{}'
            else coalesce(c.claim_value->>'value',c.claim_value->>'email',c.claim_value->>'address','')
          end))=v_email
      )
      select count(*),min(subject_id) into v_candidate_count,v_candidate_subject from candidates;

      if v_candidate_count>0 then
        select c.subject_id into v_subject_id
        from atlas.identity_claims c
        join atlas.identity_reconciliation_adjudications a
          on a.organization_id=c.organization_id
         and a.claim_id=c.id
         and a.subject_id=c.subject_id
         and a.decision_kind='accept_claim'
        where c.organization_id=v_invite.organization_id
          and c.claim_kind in ('email','email_address')
          and lower(btrim(case
            when jsonb_typeof(c.claim_value)='string' then c.claim_value#>>'{}'
            else coalesce(c.claim_value->>'value',c.claim_value->>'email',c.claim_value->>'address','')
          end))=v_email
        group by c.subject_id
        having count(distinct c.subject_id)=1
        limit 1;

        if v_subject_id is null then
          insert into atlas.identity_reconciliation_reviews(
            organization_id,review_kind,left_subject_id,status,priority,candidate_data,opened_by
          ) values (
            v_invite.organization_id,'other',v_candidate_subject,'open','high',
            jsonb_build_object('reason','employee_invitation_email_matches_existing_unadjudicated_identity_evidence','invitationId',v_invite.id,'email',v_email,'candidateCount',v_candidate_count),
            'organization_access_invitation_v1'
          ) returning id into v_review_id;
          return jsonb_build_object('ok',false,'reason','identity_reconciliation_required','invitationId',v_invite.id,'reviewId',v_review_id,'candidateCount',v_candidate_count);
        end if;
      end if;
    end if;

    if v_subject_id is null then
      insert into atlas.identity_subjects(organization_id,state,created_by_user_id,creation_basis)
      values(v_invite.organization_id,'active',v_uid,jsonb_build_object('source','accepted_organization_access_invitation','invitationId',v_invite.id))
      returning id into v_subject_id;
    end if;

    insert into atlas.identity_source_records(
      organization_id,source_system_key,source_record_kind,source_record_key,
      source_observed_at,source_authority,custody_ref,metadata
    ) values (
      v_invite.organization_id,'atlas_access','organization_employee_invitation',v_invite.id::text,
      now(),'authoritative_source',jsonb_build_object('invitationId',v_invite.id),
      jsonb_build_object('authenticatedUserId',v_uid,'inviteeEmail',v_email,'displayName',v_invite.display_name)
    ) on conflict (organization_id,source_system_key,source_record_kind,source_record_key)
    do nothing;
    select id into v_source_record_id from atlas.identity_source_records
    where organization_id=v_invite.organization_id and source_system_key='atlas_access'
      and source_record_kind='organization_employee_invitation' and source_record_key=v_invite.id::text;

    if not exists(select 1 from atlas.identity_claims c where c.source_record_id=v_source_record_id and c.subject_id=v_subject_id and c.claim_kind='email') then
      insert into atlas.identity_claims(organization_id,subject_id,source_record_id,claim_kind,claim_value,confidence,basis,metadata)
      values(v_invite.organization_id,v_subject_id,v_source_record_id,'email',to_jsonb(v_email),1.0,'Authenticated account accepted an invitation addressed to this email.',jsonb_build_object('credentialVerified',true))
      returning id into v_email_claim_id;
      insert into atlas.identity_reconciliation_adjudications(
        organization_id,decision_kind,source_record_id,subject_id,claim_id,evidence_snapshot,basis,adjudicated_by_user_id,adjudicated_by_label
      ) values (
        v_invite.organization_id,'accept_claim',v_source_record_id,v_subject_id,v_email_claim_id,
        jsonb_build_object('invitationId',v_invite.id,'authenticatedUserId',v_uid,'email',v_email),
        'The authenticated credential carrier accepted the invitation addressed to the same verified email.',v_uid,'organization_access_invitation_v1'
      );
    end if;
    if not exists(select 1 from atlas.identity_claims c where c.source_record_id=v_source_record_id and c.subject_id=v_subject_id and c.claim_kind='display_name') then
      insert into atlas.identity_claims(organization_id,subject_id,source_record_id,claim_kind,claim_value,confidence,basis)
      values(v_invite.organization_id,v_subject_id,v_source_record_id,'display_name',to_jsonb(v_invite.display_name),0.9,'Display name supplied by the authorized organization inviter.');
    end if;
    if not exists(select 1 from atlas.identity_source_subject_assertions a where a.source_record_id=v_source_record_id and a.subject_id=v_subject_id and a.assertion_kind='supports') then
      insert into atlas.identity_source_subject_assertions(organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id)
      values(v_invite.organization_id,v_source_record_id,v_subject_id,'supports',1.0,'Authenticated invitation acceptance binds this access record to the institutional subject.','access_invite:'||v_invite.id::text,v_uid);
    end if;

    insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,contact_points,unresolved_identity,confidence,projection_basis)
    values(v_subject_id,v_invite.organization_id,'person',v_invite.display_name,
      jsonb_build_array(jsonb_build_object('kind','email','value',v_email)),false,1.0,
      jsonb_build_object('source','accepted_organization_access_invitation','invitationId',v_invite.id))
    on conflict (subject_id) do update set
      subject_kind=case when atlas.identity_subject_projections.subject_kind='unknown' then 'person' else atlas.identity_subject_projections.subject_kind end,
      display_name=coalesce(atlas.identity_subject_projections.display_name,excluded.display_name),
      contact_points=case when atlas.identity_subject_projections.contact_points='[]'::jsonb then excluded.contact_points else atlas.identity_subject_projections.contact_points end,
      unresolved_identity=false,
      projection_basis=atlas.identity_subject_projections.projection_basis || excluded.projection_basis,
      updated_at=now();

    if v_membership_id is null then
      insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions,identity_subject_id,updated_at)
      values(v_invite.organization_id,v_uid,'member',true,'{}'::jsonb,v_subject_id,now())
      on conflict (organization_id,user_id) do update set
        active=true,
        identity_subject_id=coalesce(atlas.organization_memberships.identity_subject_id,excluded.identity_subject_id),
        updated_at=now()
      returning id into v_membership_id;
    else
      update atlas.organization_memberships
      set identity_subject_id=coalesce(identity_subject_id,v_subject_id),updated_at=now()
      where id=v_membership_id;
    end if;

    select s.id into v_seat_id from atlas.organization_employee_seats s where s.organization_membership_id=v_membership_id limit 1;
    if v_seat_id is null then
      insert into atlas.organization_employee_seats(
        organization_id,organization_membership_id,identity_subject_id,seat_class,status,billing_state,billing_unit_price_cents,metadata
      ) values (
        v_invite.organization_id,v_membership_id,v_subject_id,'employee','active','active',700,
        jsonb_build_object('sourceInvitationId',v_invite.id)
      ) returning id into v_seat_id;
    else
      update atlas.organization_employee_seats
      set identity_subject_id=v_subject_id,status='active',billing_state=case when billing_state='ended' then 'active' else billing_state end,updated_at=now()
      where id=v_seat_id;
    end if;

    insert into atlas.organization_member_credentials(
      organization_id,organization_membership_id,employee_seat_id,identity_subject_id,
      credential_kind,auth_user_id,status,issued_by_organization_id,provenance
    ) values (
      v_invite.organization_id,v_membership_id,v_seat_id,v_subject_id,
      'auth_user',v_uid,'active',v_invite.organization_id,
      jsonb_build_object('sourceInvitationId',v_invite.id,'verifiedEmail',v_email)
    ) returning id into v_credential_id;
  end if;

  update atlas.organization_access_invitations
  set status='accepted',accepted_by_user_id=v_uid,accepted_at=now(),updated_at=now()
  where id=v_invite.id;

  return jsonb_build_object(
    'ok',true,'replayed',false,'contractVersion','organization_access_invitation_v1',
    'invitationId',v_invite.id,'organizationId',v_invite.organization_id,
    'identitySubjectId',v_subject_id,'organizationMembershipId',v_membership_id,
    'employeeSeatId',v_seat_id,'credentialId',v_credential_id,
    'authorityCreated',false,'positionCreated',false,'responsibilityCreated',false,'exposureGrantCreated',false
  );
end;
$function$;

revoke all on function atlas.prepare_organization_employee_invitation_self_api_v1(uuid,text,text) from public,anon;
grant execute on function atlas.prepare_organization_employee_invitation_self_api_v1(uuid,text,text) to authenticated,service_role;
revoke all on function atlas.issue_organization_employee_invitation_service_v1(uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function atlas.issue_organization_employee_invitation_service_v1(uuid,timestamptz,uuid) to service_role;
revoke all on function atlas.revoke_organization_employee_invitation_self_api_v1(uuid) from public,anon;
grant execute on function atlas.revoke_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;
revoke all on function atlas.pending_organization_employee_invitation_self_api_v1(uuid) from public,anon;
grant execute on function atlas.pending_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;
revoke all on function atlas.accept_organization_employee_invitation_self_api_v1(uuid) from public,anon;
grant execute on function atlas.accept_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,
  security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
('atlas.prepare_organization_employee_invitation_self_api_v1(uuid,text,text)','owner_admin_endpoint','verified','active',true,true,true,1,1,
 jsonb_build_object('source','atlas_organization_access_invitation_v1','purpose','Prepare a bounded employee access offer.','truthBoundary','Creates no membership, seat, position, responsibility, authority, or exposure.','classificationRuleVersion',3),false),
('atlas.revoke_organization_employee_invitation_self_api_v1(uuid)','owner_admin_endpoint','verified','active',true,true,true,1,1,
 jsonb_build_object('source','atlas_organization_access_invitation_v1','purpose','Revoke an open employee access offer.','truthBoundary','Invitation state only.','classificationRuleVersion',3),false),
('atlas.pending_organization_employee_invitation_self_api_v1(uuid)','app_endpoint','verified','active',true,true,true,1,1,
 jsonb_build_object('source','atlas_organization_access_invitation_v1','purpose','Show the signed-in human an invitation addressed to their verified email.','truthBoundary','Read only; email-bound.','classificationRuleVersion',3),false),
('atlas.accept_organization_employee_invitation_self_api_v1(uuid)','app_endpoint','verified','active',true,true,true,1,1,
 jsonb_build_object('source','atlas_organization_access_invitation_v1','purpose','Accept employee access after credential/email and issuer-authority revalidation.','truthBoundary','May create identity subject, member access, employee seat and credential only; no position, responsibility, Principal/execution authority, or exposure.','classificationRuleVersion',3),false),
('atlas.issue_organization_employee_invitation_service_v1(uuid,timestamptz,uuid)','service_internal','verified','active',false,true,true,1,1,
 jsonb_build_object('source','atlas_organization_access_invitation_v1','purpose','Mark a prepared invitation issued after server-side delivery/auth bootstrap.','truthBoundary','Invitation transport state only.','classificationRuleVersion',3),false)
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,reviewed_at=now();

commit;

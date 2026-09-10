begin;

alter table atlas.organization_access_invitations
  add column if not exists declined_at timestamptz,
  add column if not exists declined_by_user_id uuid references auth.users(id) on delete restrict;

alter table atlas.organization_access_invitations
  drop constraint if exists organization_access_invitations_status_check;

alter table atlas.organization_access_invitations
  add constraint organization_access_invitations_status_check
  check (status in ('draft','issued','accepted','declined','revoked','expired'));

create or replace function atlas.list_pending_organization_employee_invitations_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_email text;
  v_items jsonb;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
  if v_email is null then return jsonb_build_object('ok',false,'reason','authenticated_email_unavailable','items','[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('invitationId',i.id,'organizationId',i.organization_id,'organizationName',o.name,'displayName',i.display_name,'email',i.invitee_email,'accessClass',i.access_class,'status','issued','expiresAt',i.expires_at) order by i.created_at desc),'[]'::jsonb)
  into v_items
  from atlas.organization_access_invitations i join atlas.organizations o on o.id=i.organization_id
  where i.status='issued' and i.invitee_email=v_email and (i.expires_at is null or i.expires_at>now());
  return jsonb_build_object('ok',true,'contractVersion','organization_access_invitation_v1','items',v_items);
end;
$function$;

create or replace function atlas.decline_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_uid uuid:=auth.uid(); v_email text; v_invite atlas.organization_access_invitations%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
  if v_email is null then raise exception 'Authenticated email unavailable.' using errcode='42501'; end if;
  select * into v_invite from atlas.organization_access_invitations i where i.id=p_invitation_id for update;
  if v_invite.id is null then raise exception 'Organization invitation not found.' using errcode='P0002'; end if;
  if v_invite.invitee_email<>v_email then raise exception 'This invitation is not available to the signed-in account.' using errcode='42501'; end if;
  if v_invite.status='declined' and v_invite.declined_by_user_id=v_uid then return jsonb_build_object('ok',true,'replayed',true,'invitationId',v_invite.id,'status','declined'); end if;
  if v_invite.status<>'issued' then raise exception 'Invitation is not open for decline.' using errcode='55000'; end if;
  if v_invite.expires_at is not null and v_invite.expires_at<=now() then update atlas.organization_access_invitations set status='expired',updated_at=now() where id=v_invite.id; return jsonb_build_object('ok',false,'reason','invitation_expired','invitationId',v_invite.id); end if;
  update atlas.organization_access_invitations set status='declined',declined_by_user_id=v_uid,declined_at=now(),metadata=metadata||jsonb_build_object('declineContractVersion','organization_access_invitation_v1'),updated_at=now() where id=v_invite.id;
  return jsonb_build_object('ok',true,'replayed',false,'invitationId',v_invite.id,'status','declined');
end;
$function$;

create or replace function atlas.mark_organization_employee_invitation_not_me_self_api_v1(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_uid uuid:=auth.uid(); v_email text; v_invite atlas.organization_access_invitations%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
  if v_email is null then raise exception 'Authenticated email unavailable.' using errcode='42501'; end if;
  select * into v_invite from atlas.organization_access_invitations i where i.id=p_invitation_id for update;
  if v_invite.id is null then raise exception 'Organization invitation not found.' using errcode='P0002'; end if;
  if v_invite.invitee_email<>v_email then raise exception 'This invitation is not available to the signed-in account.' using errcode='42501'; end if;
  if v_invite.status<>'issued' then return jsonb_build_object('ok',false,'reason','invitation_not_open','invitationId',v_invite.id,'status',v_invite.status); end if;
  update atlas.organization_access_invitations set metadata=metadata||jsonb_build_object('recipientDispute',jsonb_build_object('kind','not_me','reportedByUserId',v_uid,'reportedAt',now())),updated_at=now() where id=v_invite.id;
  return jsonb_build_object('ok',true,'invitationId',v_invite.id,'status','issued','flagged','not_me');
end;
$function$;

create or replace function atlas.organization_access_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth
as $function$
declare v_uid uuid:=auth.uid(); v_items jsonb;
begin
  if v_uid is null then return jsonb_build_object('ok',true,'authenticated',false,'items','[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('organizationId',o.id,'organizationName',o.name,'organizationMembershipId',m.id,'identitySubjectId',m.identity_subject_id,'employeeSeatId',s.id,'accessClass',s.seat_class,'seatStatus',s.status,'billingState',s.billing_state,'membershipRole',m.role) order by o.name,o.id),'[]'::jsonb)
  into v_items
  from atlas.organization_member_credentials c
  join atlas.organization_memberships m on m.id=c.organization_membership_id and m.organization_id=c.organization_id
  join atlas.organization_employee_seats s on s.id=c.employee_seat_id and s.organization_membership_id=m.id and s.organization_id=m.organization_id
  join atlas.organizations o on o.id=m.organization_id
  where c.credential_kind='auth_user' and c.auth_user_id=v_uid and c.status='active' and (c.expires_at is null or c.expires_at>now()) and m.user_id=v_uid and m.active and s.status='active' and o.status='active';
  return jsonb_build_object('ok',true,'authenticated',true,'contractVersion','organization_access_self_v1','items',v_items);
end;
$function$;

revoke all on function atlas.list_pending_organization_employee_invitations_self_api_v1() from public,anon;
grant execute on function atlas.list_pending_organization_employee_invitations_self_api_v1() to authenticated,service_role;
revoke all on function atlas.decline_organization_employee_invitation_self_api_v1(uuid) from public,anon;
grant execute on function atlas.decline_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;
revoke all on function atlas.mark_organization_employee_invitation_not_me_self_api_v1(uuid) from public,anon;
grant execute on function atlas.mark_organization_employee_invitation_not_me_self_api_v1(uuid) to authenticated,service_role;
revoke all on function atlas.organization_access_self_api_v1() from public,anon;
grant execute on function atlas.organization_access_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected) values
('atlas.list_pending_organization_employee_invitations_self_api_v1()','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_organization_access_entry_completion_v1','purpose','List only open organization employee invitations addressed to the signed-in verified email.','truthBoundary','Read only; invitation visibility does not create access.','classificationRuleVersion',3),false),
('atlas.decline_organization_employee_invitation_self_api_v1(uuid)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_organization_access_entry_completion_v1','purpose','Decline an organization employee invitation addressed to the signed-in verified email.','truthBoundary','Invitation state only; does not erase institutional identity/history.','classificationRuleVersion',3),false),
('atlas.mark_organization_employee_invitation_not_me_self_api_v1(uuid)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_organization_access_entry_completion_v1','purpose','Flag that the verified recipient disputes being the intended human without accepting or silently merging identity.','truthBoundary','Invitation evidence only; invitation remains unaccepted.','classificationRuleVersion',3),false),
('atlas.organization_access_self_api_v1()','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_organization_access_entry_completion_v1','purpose','Return active organization employee access relationships for the signed-in credential carrier.','truthBoundary','Read projection only; no responsibility, authority, execution, exposure, or Personal Atlas inference.','classificationRuleVersion',3),false)
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,anonymous_execute_expected=excluded.anonymous_execute_expected,reviewed_at=now();

commit;
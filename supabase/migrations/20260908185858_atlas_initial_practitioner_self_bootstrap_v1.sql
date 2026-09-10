begin;

create or replace function atlas.bootstrap_initial_implementation_practitioner_self_v1()
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_existing_count integer;
begin
  if v_uid is null then
    raise exception 'Authenticated Atlas human required.' using errcode='42501';
  end if;

  select lower(u.email) into v_email
  from auth.users u
  where u.id=v_uid
    and u.deleted_at is null
    and u.email_confirmed_at is not null;

  if v_email is null then
    raise exception 'Confirmed email credential required.' using errcode='42501';
  end if;

  if v_email <> 'helpdesk@opticallift.com' then
    raise exception 'Initial practitioner bootstrap is not available for this credential.' using errcode='42501';
  end if;

  select count(*) into v_existing_count
  from atlas.implementation_practitioners p
  where p.status='active';

  if v_existing_count > 0 and not exists (
    select 1 from atlas.implementation_practitioners p
    where p.human_user_id=v_uid and p.status='active'
  ) then
    raise exception 'Initial practitioner bootstrap is already closed.' using errcode='42501';
  end if;

  if exists (
    select 1 from atlas.principals pr
    where pr.user_id=v_uid and pr.status='active'
  ) then
    raise exception 'Practitioner credential must be separate from an active Principal credential.' using errcode='23514';
  end if;

  insert into atlas.implementation_practitioners(
    human_user_id,status,authorized_at,authorization_basis,metadata
  ) values(
    v_uid,'active',now(),
    jsonb_build_object(
      'source','bootstrap_initial_implementation_practitioner_self_v1',
      'decision','PMD-022',
      'email','helpdesk@opticallift.com',
      'credentialSeparation','separate_from_principal'
    ),
    jsonb_build_object('initialPractitioner',true,'testCredential',true)
  )
  on conflict (human_user_id) do update
    set status='active',ended_at=null,updated_at=now();

  return jsonb_build_object(
    'ok',true,
    'humanUserId',v_uid,
    'email',v_email,
    'practitionerAuthorized',true,
    'principalCreated',false,
    'organizationMembershipCreated',false
  );
end;
$function$;

comment on function atlas.bootstrap_initial_implementation_practitioner_self_v1() is
  'One-time V1 bootstrap for the confirmed helpdesk@opticallift.com credential while no other active implementation practitioner exists. Creates vendor-side practitioner authority only.';

revoke all on function atlas.bootstrap_initial_implementation_practitioner_self_v1() from public,anon;
grant execute on function atlas.bootstrap_initial_implementation_practitioner_self_v1() to authenticated,service_role;

commit;
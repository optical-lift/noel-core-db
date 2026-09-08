begin;

create or replace function atlas.enforce_practitioner_principal_identity_separation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if tg_table_name = 'implementation_practitioners' then
    if new.status = 'active' and exists (
      select 1 from atlas.principals p
      where p.user_id = new.human_user_id
        and p.status = 'active'
    ) then
      raise exception 'Practitioner credential must be separate from an active Principal credential.' using errcode='23514';
    end if;
    return new;
  end if;

  if tg_table_name = 'principals' then
    if new.status = 'active' and exists (
      select 1 from atlas.implementation_practitioners ip
      where ip.human_user_id = new.user_id
        and ip.status = 'active'
    ) then
      raise exception 'Principal credential must be separate from an active practitioner credential.' using errcode='23514';
    end if;
    return new;
  end if;

  return new;
end;
$function$;

comment on function atlas.enforce_practitioner_principal_identity_separation_v1() is
  'Enforces the selected Atlas identity boundary: vendor-side practitioner access and Personal Atlas Principal identity must use separate authenticated credentials.';

drop trigger if exists implementation_practitioners_principal_separation_v1 on atlas.implementation_practitioners;
create trigger implementation_practitioners_principal_separation_v1
before insert or update of human_user_id,status
on atlas.implementation_practitioners
for each row execute function atlas.enforce_practitioner_principal_identity_separation_v1();

drop trigger if exists principals_practitioner_separation_v1 on atlas.principals;
create trigger principals_practitioner_separation_v1
before insert or update of user_id,status
on atlas.principals
for each row execute function atlas.enforce_practitioner_principal_identity_separation_v1();

create or replace function atlas.implementation_practitioner_authorized_self_v1()
returns boolean
language sql stable security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null
    and exists (
      select 1 from atlas.implementation_practitioners p
      where p.human_user_id=auth.uid() and p.status='active'
    )
    and not exists (
      select 1 from atlas.principals pr
      where pr.user_id=auth.uid() and pr.status='active'
    );
$function$;

comment on function atlas.implementation_practitioner_authorized_self_v1() is
  'Returns true only for an active vendor-side practitioner credential that is not also an active Principal credential.';

revoke all on function atlas.enforce_practitioner_principal_identity_separation_v1() from public,anon,authenticated;
grant execute on function atlas.enforce_practitioner_principal_identity_separation_v1() to service_role;

commit;

-- Fixed fictional data only. No production schema or rows.
begin;
insert into auth.users
(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 confirmation_token,recovery_token,email_change,email_change_token_new,
 email_change_token_current,phone_change,phone_change_token,reauthentication_token,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid,id,'authenticated','authenticated',
 'dev-boundary-'||name||'@example.invalid',
 extensions.crypt('Fictional-development-boundary-2026!',extensions.gen_salt('bf')),
 now(),'','','','','','','','',
 '{"provider":"email","providers":["email"]}'::jsonb,
 case when name='outsider' then '{"is_owner":true}'::jsonb else '{}'::jsonb end,now(),now()
from (values
 ('e5300000-0000-4000-8000-000000000001'::uuid,'owner'),
 ('e5300000-0000-4000-8000-000000000002'::uuid,'worker'),
 ('e5300000-0000-4000-8000-000000000003'::uuid,'outsider')) f(id,name);
insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at)
select gen_random_uuid(),email,id,jsonb_build_object('sub',id::text,'email',email),'email',now(),now()
from auth.users where id in ('e5300000-0000-4000-8000-000000000001','e5300000-0000-4000-8000-000000000002','e5300000-0000-4000-8000-000000000003');
create table public.development_boundary_fixture_v1
(id integer primary key, owner_id uuid not null, worker_id uuid not null, active boolean not null, value text not null);
alter table public.development_boundary_fixture_v1 enable row level security;
revoke all on public.development_boundary_fixture_v1 from public,anon,authenticated;
grant select,update(active) on public.development_boundary_fixture_v1 to authenticated;
create policy fictional_read on public.development_boundary_fixture_v1 for select to authenticated
using ((select auth.uid())=owner_id or ((select auth.uid())=worker_id and active));
create policy fictional_revoke on public.development_boundary_fixture_v1 for update to authenticated
using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
insert into public.development_boundary_fixture_v1 values
(1,'e5300000-0000-4000-8000-000000000001','e5300000-0000-4000-8000-000000000002',true,'fictional-original');
create function public.development_boundary_read_v1() returns text
language plpgsql security invoker set search_path='' as $$
declare result text;
begin
 select value into result from public.development_boundary_fixture_v1 where id=1;
 if not found then raise insufficient_privilege using message='fictional scope denied'; end if;
 return result;
end $$;
create function public.development_boundary_revoke_v1() returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 update public.development_boundary_fixture_v1 set active=false where id=1;
 if not found then raise insufficient_privilege using message='fictional scope denied'; end if;
 return true;
end $$;
revoke all on function public.development_boundary_read_v1(),public.development_boundary_revoke_v1() from public,anon,authenticated;
grant execute on function public.development_boundary_read_v1(),public.development_boundary_revoke_v1() to authenticated;
commit;
notify pgrst,'reload schema';

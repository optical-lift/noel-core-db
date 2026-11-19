begin;
insert into transcript_core.workspaces values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
insert into transcript_core.productions values ('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001');
insert into transcript_core.assets values
('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000001','generated_render','transcript-core-generated-renders','00000000-0000-0000-0000-000000000001/master.wav',repeat('a',64),'audio/wav',100),
('00000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000001','generated_render','transcript-core-generated-renders','00000000-0000-0000-0000-000000000001/episode.mp3',repeat('b',64),'audio/mpeg',50);
insert into transcript_core.production_masters values ('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000020');
insert into transcript_core.delivery_profiles values ('00000000-0000-0000-0000-000000000040','00000000-0000-0000-0000-000000000001');
insert into transcript_core.delivery_packages select ('00000000-0000-0000-0000-0000000000'||i)::uuid,'00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000040','valid' from generate_series(50,51) i;

create function pg_temp.bind(p uuid default '00000000-0000-0000-0000-000000000051', a uuid default '00000000-0000-0000-0000-000000000021', h text default repeat('b',64), s bigint default 50, m text default repeat('a',64), e text default repeat('c',64)) returns void language sql as $$
insert into transcript_core.delivery_package_artifacts(delivery_package_id,asset_id,artifact_role,artifact_sha256,byte_size,source_master_sha256,export_receipt_sha256) values(p,a,'listening_mp3',h,s,m,e);
$$;
create function pg_temp.deny(statement text, expected text default '23514') returns void language plpgsql as $$
begin
  begin
    execute statement;
    raise exception 'Unexpected success: %', statement;
  exception when others then
    if sqlstate<>expected then raise; end if;
  end;
end;
$$;
select pg_temp.bind(p=>'00000000-0000-0000-0000-000000000050');
select pg_temp.deny('select pg_temp.bind(h=>repeat(''d'',64))');
select pg_temp.deny('select pg_temp.bind(m=>repeat(''d'',64))');
select pg_temp.deny('select pg_temp.bind(s=>49)');
select pg_temp.deny('select pg_temp.bind(a=>''00000000-0000-0000-0000-000000000020'')');
select pg_temp.deny('select pg_temp.bind(h=>null)');
select pg_temp.deny('select pg_temp.bind(e=>null)','23502');
select pg_temp.deny('select pg_temp.bind(e=>''unverified'')');
update transcript_core.delivery_packages set status='invalid' where id='00000000-0000-0000-0000-000000000051';
select pg_temp.deny('select pg_temp.bind()');
update transcript_core.delivery_packages set status='exported' where id='00000000-0000-0000-0000-000000000051';
do $$
declare col text; val text;
begin
  for col,val in select * from (values
   ('workspace_id','00000000-0000-0000-0000-000000000002'),
   ('mime_type','audio/wav'),
   ('provenance_class','observed_original'),
   ('storage_bucket','public'),
   ('storage_path','00000000-0000-0000-0000-000000000002/episode.mp3'),
   ('storage_path','not-a-uuid/episode.mp3')) q(c,v)
  loop
    begin
      execute format('update transcript_core.assets set %I=%L where id=%L',col,val,'00000000-0000-0000-0000-000000000021');
      perform pg_temp.deny('select pg_temp.bind()');
      raise exception 'restore fixture' using errcode='P0002';
    exception when no_data_found then null;
    end;
  end loop;
end;
$$;
update transcript_core.delivery_profiles set workspace_id='00000000-0000-0000-0000-000000000002';
select pg_temp.deny('select pg_temp.bind()');
update transcript_core.delivery_profiles set workspace_id='00000000-0000-0000-0000-000000000001';
update transcript_core.assets set workspace_id='00000000-0000-0000-0000-000000000002' where id='00000000-0000-0000-0000-000000000020';
select pg_temp.deny('select pg_temp.bind()');
update transcript_core.assets set workspace_id='00000000-0000-0000-0000-000000000001' where id='00000000-0000-0000-0000-000000000020';
select pg_temp.bind();
select pg_temp.deny('select pg_temp.bind()','23505');
select pg_temp.deny('update transcript_core.delivery_package_artifacts set byte_size=byte_size','55000');
select pg_temp.deny('delete from transcript_core.delivery_package_artifacts','55000');
do $$
declare r text; privilege text;
begin
 if not (select relrowsecurity from pg_class where oid='transcript_core.delivery_package_artifacts'::regclass) then raise exception 'RLS missing'; end if;
 foreach r in array array['anon','authenticated','service_role'] loop
   foreach privilege in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
     if has_table_privilege(r,'transcript_core.delivery_package_artifacts',privilege) then raise exception 'Unexpected % permission for %',privilege,r; end if;
   end loop;
   if has_function_privilege(r,'transcript_core.guard_listening_delivery_artifact_v1()','EXECUTE') then raise exception 'Unexpected trigger function permission'; end if;
 end loop;
 if (select count(*) from transcript_core.delivery_package_artifacts)<>2 then raise exception 'Unexpected fixture results'; end if;
end;
$$;
rollback;
select 'PASS isolated lineage, mutation and role privilege checks' as result;

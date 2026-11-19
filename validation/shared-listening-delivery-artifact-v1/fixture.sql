-- Synthetic subset of inspected source; not a full schema clone.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema transcript_core;
grant usage on schema transcript_core to anon,authenticated,service_role;
create type transcript_core.asset_provenance_class as enum ('observed_original','observed_derivative','script_source','generated_take','generated_render','authored_performance_take','authored_performance_master','authored_performance_recording');
create table transcript_core.workspaces(id uuid primary key);
create table transcript_core.assets(id uuid primary key, workspace_id uuid not null references transcript_core.workspaces(id), provenance_class transcript_core.asset_provenance_class not null, storage_bucket text not null, storage_path text not null, content_hash text, mime_type text not null, byte_size bigint not null check(byte_size>=0));
create table transcript_core.productions(id uuid primary key,workspace_id uuid not null references transcript_core.workspaces(id));
create table transcript_core.production_masters(id uuid primary key,production_id uuid not null references transcript_core.productions(id),audio_asset_id uuid not null references transcript_core.assets(id));
create table transcript_core.delivery_profiles(id uuid primary key,workspace_id uuid not null references transcript_core.workspaces(id));
create table transcript_core.delivery_packages(id uuid primary key,production_master_id uuid not null references transcript_core.production_masters(id),delivery_profile_id uuid not null references transcript_core.delivery_profiles(id),status text not null check(status in ('pending','valid','invalid','exported')));
CREATE OR REPLACE FUNCTION public.transcript_core_path_workspace(object_name text)
 RETURNS uuid LANGUAGE plpgsql IMMUTABLE
AS $function$
declare result uuid;
begin
  begin
    result := split_part(object_name, '/', 1)::uuid;
  exception when others then
    return null;
  end;
  return result;
end;
$function$;
-- Exercise explicit revocations even when deployment defaults grant broadly.
alter default privileges in schema transcript_core grant all on tables to anon,authenticated,service_role;

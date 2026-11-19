-- Held source candidate, not a release migration.
-- No public writer or storage policy changes. Exact package-to-artifact
-- relation; existing master, production and asset identities stay original.
begin;
create table transcript_core.delivery_package_artifacts (
  delivery_package_id uuid not null references transcript_core.delivery_packages(id) on delete restrict,
  asset_id uuid not null references transcript_core.assets(id) on delete restrict,
  artifact_role text not null check (artifact_role = 'listening_mp3'),
  artifact_sha256 text not null check (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size > 0),
  source_master_sha256 text not null check (source_master_sha256 ~ '^[0-9a-f]{64}$'),
  export_receipt_sha256 text not null check (export_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  bound_at timestamptz not null default now(),
  primary key (delivery_package_id, artifact_role)
);
alter table transcript_core.delivery_package_artifacts enable row level security;
revoke all on transcript_core.delivery_package_artifacts from public, anon, authenticated, service_role;

-- This internal check does not authorize admission, issue or listening.
-- A separate trusted carrier must verify actual bytes before any binding.
create function transcript_core.guard_listening_delivery_artifact_v1()
returns trigger language plpgsql set search_path = '' as $fn$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Existing delivery artifact binding is immutable' using errcode='55000';
  end if;
  if not exists (
    select 1
    from transcript_core.delivery_packages dp
    join transcript_core.production_masters pm on pm.id=dp.production_master_id
    join transcript_core.productions p on p.id=pm.production_id
    join transcript_core.delivery_profiles profile on profile.id=dp.delivery_profile_id
    join transcript_core.assets master on master.id=pm.audio_asset_id
    join transcript_core.assets artifact on artifact.id=new.asset_id
    where dp.id=new.delivery_package_id
      and dp.status in ('valid','exported')
      and master.workspace_id=p.workspace_id
      and profile.workspace_id=p.workspace_id
      and artifact.workspace_id=p.workspace_id
      and artifact.id<>master.id
      and master.content_hash=new.source_master_sha256
      and artifact.content_hash=new.artifact_sha256
      and artifact.mime_type='audio/mpeg'
      and artifact.byte_size=new.byte_size
      and artifact.provenance_class='generated_render'
      and artifact.storage_bucket='transcript-core-generated-renders'
      and public.transcript_core_path_workspace(artifact.storage_path)=p.workspace_id
  ) then
    raise exception 'Listening artifact does not match its production and delivery lineage' using errcode='23514';
  end if;
  return new;
end;
$fn$;
revoke all on function transcript_core.guard_listening_delivery_artifact_v1() from public, anon, authenticated, service_role;
create trigger guard_listening_delivery_artifact_v1
before insert or update or delete on transcript_core.delivery_package_artifacts
for each row execute function transcript_core.guard_listening_delivery_artifact_v1();
-- Internal, invoker-only operation for a trusted intake transaction after
-- actual bytes have been verified by the carrier. Not an exposed RPC.
create function transcript_core.bind_verified_listening_delivery_artifact_v1(
  p_delivery_package_id uuid,
  p_asset_id uuid,
  p_artifact_sha256 text,
  p_byte_size bigint,
  p_source_master_sha256 text,
  p_export_receipt_sha256 text
) returns jsonb language plpgsql security invoker set search_path = '' as $fn$
declare
  v_binding transcript_core.delivery_package_artifacts%rowtype;
begin
  if p_delivery_package_id is null or p_asset_id is null
     or p_artifact_sha256 is null or p_artifact_sha256 !~ '^[0-9a-f]{64}$'
     or p_byte_size is null or p_byte_size <= 0
     or p_source_master_sha256 is null or p_source_master_sha256 !~ '^[0-9a-f]{64}$'
     or p_export_receipt_sha256 is null or p_export_receipt_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Exact verified delivery evidence required' using errcode='22023';
  end if;
  -- Hold the existing lineage rows stable through admission/replay.
  perform dp.id
  from transcript_core.delivery_packages dp
  join transcript_core.production_masters pm on pm.id=dp.production_master_id
  join transcript_core.productions p on p.id=pm.production_id
  join transcript_core.delivery_profiles profile on profile.id=dp.delivery_profile_id
  join transcript_core.assets master on master.id=pm.audio_asset_id
  join transcript_core.assets artifact on artifact.id=p_asset_id
  where dp.id=p_delivery_package_id
  for share of dp,pm,p,profile,master,artifact;
  if not found then
    raise exception 'Delivery lineage not found' using errcode='23514';
  end if;
  -- BEFORE INSERT validates the current lineage even on conflict/replay.
  insert into transcript_core.delivery_package_artifacts(
    delivery_package_id,asset_id,artifact_role,artifact_sha256,byte_size,
    source_master_sha256,export_receipt_sha256
  ) values (
    p_delivery_package_id,p_asset_id,'listening_mp3',p_artifact_sha256,p_byte_size,
    p_source_master_sha256,p_export_receipt_sha256
  ) on conflict (delivery_package_id,artifact_role) do nothing;
  select * into strict v_binding from transcript_core.delivery_package_artifacts
  where delivery_package_id=p_delivery_package_id and artifact_role='listening_mp3';
  if v_binding.asset_id is distinct from p_asset_id
    or v_binding.artifact_sha256 is distinct from p_artifact_sha256
    or v_binding.byte_size is distinct from p_byte_size
    or v_binding.source_master_sha256 is distinct from p_source_master_sha256
    or v_binding.export_receipt_sha256 is distinct from p_export_receipt_sha256 then
    raise exception 'Delivery artifact binding conflicts with prior receipt' using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object(
    'delivery_package_id',v_binding.delivery_package_id,
    'asset_id',v_binding.asset_id,'artifact_sha256',v_binding.artifact_sha256,
    'byte_size',v_binding.byte_size,'export_receipt_sha256',v_binding.export_receipt_sha256,
    'publication_approved',false);
end;
$fn$;
revoke all on function transcript_core.bind_verified_listening_delivery_artifact_v1(uuid,uuid,text,bigint,text,text) from public,anon,authenticated,service_role;

commit;

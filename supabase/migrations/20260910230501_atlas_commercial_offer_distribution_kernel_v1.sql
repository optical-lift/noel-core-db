begin;

create table atlas.commercial_offer_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  snapshot_key text not null,
  title text not null,
  offer_state text not null default 'complete' check (offer_state in ('complete','incomplete_evidence')),
  valid_from timestamptz,
  valid_until timestamptz,
  snapshot_sha256 text not null,
  source_kind text not null,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offer_snapshots_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_offer_snapshots_key_nonblank check (btrim(snapshot_key)<>''),
  constraint commercial_offer_snapshots_title_nonblank check (btrim(title)<>''),
  constraint commercial_offer_snapshots_hash_shape check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  constraint commercial_offer_snapshots_source_kind_check check (source_kind in ('domain_snapshot','manual_capture','provider_observation','imported_record')),
  constraint commercial_offer_snapshots_window_check check (valid_until is null or valid_from is null or valid_until>=valid_from)
);
create unique index commercial_offer_snapshots_org_key_uq on atlas.commercial_offer_snapshots(organization_id,snapshot_key) where organization_unit_id is null;
create unique index commercial_offer_snapshots_unit_key_uq on atlas.commercial_offer_snapshots(organization_id,organization_unit_id,snapshot_key) where organization_unit_id is not null;
create index commercial_offer_snapshots_scope_time_idx on atlas.commercial_offer_snapshots(organization_id,organization_unit_id,created_at desc,id);
comment on table atlas.commercial_offer_snapshots is 'Immutable evidence of the exact commercial selection/terms an organization was prepared to present at a point in time. It is not inventory, Demand, Sale, reservation, fulfillment, or payment truth.';

create table atlas.commercial_offer_snapshot_lines (
  id uuid primary key default gen_random_uuid(),
  offer_snapshot_id uuid not null references atlas.commercial_offer_snapshots(id) on delete restrict,
  line_key text not null,
  commercial_offering_id uuid references atlas.commercial_offerings(id) on delete restrict,
  description text not null,
  quantity_available numeric(14,3) check (quantity_available is null or quantity_available>=0),
  unit text,
  unit_price numeric(14,2) check (unit_price is null or unit_price>=0),
  price_min numeric(14,2) check (price_min is null or price_min>=0),
  price_max numeric(14,2) check (price_max is null or price_max>=0),
  currency text,
  price_basis text,
  terms jsonb not null default '{}'::jsonb check (jsonb_typeof(terms)='object'),
  source_ref text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offer_snapshot_lines_key_nonblank check (btrim(line_key)<>''),
  constraint commercial_offer_snapshot_lines_description_nonblank check (btrim(description)<>''),
  constraint commercial_offer_snapshot_lines_unit_nonblank check (unit is null or btrim(unit)<>''),
  constraint commercial_offer_snapshot_lines_currency_shape check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint commercial_offer_snapshot_lines_price_window check (price_min is null or price_max is null or price_max>=price_min),
  constraint commercial_offer_snapshot_lines_price_currency check ((unit_price is null and price_min is null and price_max is null) or currency is not null),
  unique(offer_snapshot_id,line_key)
);
create index commercial_offer_snapshot_lines_offering_idx on atlas.commercial_offer_snapshot_lines(commercial_offering_id) where commercial_offering_id is not null;
comment on table atlas.commercial_offer_snapshot_lines is 'Exact lines presented in one commercial offer snapshot. quantity_available is the quantity represented to the recipient, not canonical inventory authority.';

create table atlas.commercial_offer_snapshot_assets (
  id uuid primary key default gen_random_uuid(),
  offer_snapshot_id uuid not null references atlas.commercial_offer_snapshots(id) on delete restrict,
  asset_key text not null,
  asset_role text not null,
  capture_state text not null default 'captured' check (capture_state in ('captured','missing_evidence')),
  transfer_name text,
  mime_type text,
  source_content_hash text,
  custody_locator text,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offer_snapshot_assets_key_nonblank check (btrim(asset_key)<>''),
  constraint commercial_offer_snapshot_assets_role_nonblank check (btrim(asset_role)<>''),
  constraint commercial_offer_snapshot_assets_captured_has_custody check (capture_state<>'captured' or source_content_hash is not null or custody_locator is not null or source_ref is not null),
  unique(offer_snapshot_id,asset_key)
);
comment on table atlas.commercial_offer_snapshot_assets is 'Source-backed assets that formed part of an offer presentation, such as price sheets, example images, catalogs, terms, or other attachments. missing_evidence records a known referenced asset whose exact bytes/reference were not captured.';

create table atlas.commercial_offer_distributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  offer_snapshot_id uuid not null references atlas.commercial_offer_snapshots(id) on delete restrict,
  distribution_key text not null,
  channel text not null,
  sender_label text,
  sender_address text,
  subject text,
  body_text text,
  content_sha256 text not null,
  occurred_at timestamptz not null,
  source_kind text not null,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offer_distributions_unit_org_fk foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_offer_distributions_key_nonblank check (btrim(distribution_key)<>''),
  constraint commercial_offer_distributions_channel_nonblank check (btrim(channel)<>''),
  constraint commercial_offer_distributions_hash_shape check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint commercial_offer_distributions_source_kind_check check (source_kind in ('manual_report','provider_observation','imported_record','action_result'))
);
create unique index commercial_offer_distributions_org_key_uq on atlas.commercial_offer_distributions(organization_id,distribution_key) where organization_unit_id is null;
create unique index commercial_offer_distributions_unit_key_uq on atlas.commercial_offer_distributions(organization_id,organization_unit_id,distribution_key) where organization_unit_id is not null;
create index commercial_offer_distributions_scope_time_idx on atlas.commercial_offer_distributions(organization_id,organization_unit_id,occurred_at desc,id);
comment on table atlas.commercial_offer_distributions is 'Immutable evidence that one exact commercial offer snapshot was presented through a channel. Recording a distribution does not send a message, reserve stock, create Demand/Sale, or grant outbound communication authority.';

create table atlas.commercial_offer_distribution_recipients (
  id uuid primary key default gen_random_uuid(),
  distribution_id uuid not null references atlas.commercial_offer_distributions(id) on delete restrict,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  interaction_id uuid not null references atlas.external_relationship_interactions(id) on delete restrict,
  contact_kind text,
  contact_value text,
  contact_normalized text,
  recipient_role text not null default 'primary',
  source_label text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offer_distribution_recipients_contact_kind_nonblank check (contact_kind is null or btrim(contact_kind)<>''),
  constraint commercial_offer_distribution_recipients_contact_value_nonblank check (contact_value is null or btrim(contact_value)<>''),
  constraint commercial_offer_distribution_recipients_contact_pair check ((contact_value is null and contact_normalized is null) or (contact_value is not null and contact_normalized is not null)),
  constraint commercial_offer_distribution_recipients_role_key check (recipient_role ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);
create unique index commercial_offer_distribution_recipients_contact_uq on atlas.commercial_offer_distribution_recipients(distribution_id,coalesce(contact_kind,''),coalesce(contact_normalized,''),external_relationship_id);
create unique index commercial_offer_distribution_recipients_interaction_uq on atlas.commercial_offer_distribution_recipients(interaction_id);
create index commercial_offer_distribution_recipients_relationship_idx on atlas.commercial_offer_distribution_recipients(external_relationship_id,distribution_id);
comment on table atlas.commercial_offer_distribution_recipients is 'Per-relationship receipt target for one commercial offer distribution. Contact coordinates are evidence used for the transmission; the durable business history remains on External Relationship.';

create or replace function atlas.guard_commercial_offer_scope_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_snapshot atlas.commercial_offer_snapshots%rowtype; v_distribution atlas.commercial_offer_distributions%rowtype; v_relationship atlas.external_relationships%rowtype;
begin
  if tg_table_name='commercial_offer_snapshot_lines' then
    select * into v_snapshot from atlas.commercial_offer_snapshots where id=new.offer_snapshot_id;
    if v_snapshot.id is null then raise exception 'Commercial offer line requires a snapshot.' using errcode='23514'; end if;
    if new.commercial_offering_id is not null and not exists(select 1 from atlas.commercial_offerings o where o.id=new.commercial_offering_id and o.organization_id=v_snapshot.organization_id and o.organization_unit_id is not distinct from v_snapshot.organization_unit_id) then raise exception 'Commercial offering is outside the offer snapshot scope.' using errcode='23514'; end if;
    new.line_key:=btrim(new.line_key); new.description:=btrim(new.description); new.unit:=nullif(btrim(new.unit),''); new.currency:=case when new.currency is null then null else upper(btrim(new.currency)) end; new.price_basis:=nullif(btrim(new.price_basis),''); new.source_ref:=nullif(btrim(new.source_ref),''); return new;
  elsif tg_table_name='commercial_offer_snapshot_assets' then
    new.asset_key:=btrim(new.asset_key); new.asset_role:=lower(btrim(new.asset_role)); new.transfer_name:=nullif(btrim(new.transfer_name),''); new.mime_type:=nullif(lower(btrim(new.mime_type)),''); new.source_content_hash:=nullif(lower(btrim(new.source_content_hash)),''); new.custody_locator:=nullif(btrim(new.custody_locator),''); new.source_ref:=nullif(btrim(new.source_ref),''); return new;
  elsif tg_table_name='commercial_offer_distributions' then
    select * into v_snapshot from atlas.commercial_offer_snapshots where id=new.offer_snapshot_id;
    if v_snapshot.id is null or v_snapshot.organization_id is distinct from new.organization_id or v_snapshot.organization_unit_id is distinct from new.organization_unit_id then raise exception 'Commercial offer distribution must share the offer snapshot organization/unit.' using errcode='23514'; end if;
    new.distribution_key:=btrim(new.distribution_key); new.channel:=lower(btrim(new.channel)); new.sender_label:=nullif(btrim(new.sender_label),''); new.sender_address:=nullif(lower(btrim(new.sender_address)),''); new.subject:=nullif(btrim(new.subject),''); new.source_ref:=nullif(btrim(new.source_ref),''); return new;
  elsif tg_table_name='commercial_offer_distribution_recipients' then
    select * into v_distribution from atlas.commercial_offer_distributions where id=new.distribution_id;
    select * into v_relationship from atlas.external_relationships where id=new.external_relationship_id;
    if v_distribution.id is null or v_relationship.id is null or v_relationship.organization_id is distinct from v_distribution.organization_id or v_relationship.organization_unit_id is distinct from v_distribution.organization_unit_id or v_relationship.subject_id is distinct from new.identity_subject_id then raise exception 'Offer recipient relationship is outside the distribution scope.' using errcode='23514'; end if;
    if not exists(select 1 from atlas.external_relationship_interactions i where i.id=new.interaction_id and i.external_relationship_id=new.external_relationship_id and i.organization_id=v_distribution.organization_id) then raise exception 'Offer recipient interaction must belong to the same external relationship.' using errcode='23514'; end if;
    new.contact_kind:=nullif(lower(btrim(new.contact_kind)),''); new.contact_value:=nullif(btrim(new.contact_value),''); new.contact_normalized:=case when new.contact_value is null then null else coalesce(nullif(btrim(new.contact_normalized),''),atlas.normalize_external_party_identifier_v1(new.contact_kind,new.contact_value)) end; new.recipient_role:=lower(btrim(new.recipient_role)); new.source_label:=nullif(btrim(new.source_label),''); return new;
  else
    if new.organization_unit_id is not null and not exists(select 1 from atlas.organization_units ou where ou.organization_id=new.organization_id and ou.id=new.organization_unit_id) then raise exception 'Commercial offer snapshot organization unit is outside organization.' using errcode='23514'; end if;
    new.snapshot_key:=btrim(new.snapshot_key); new.title:=btrim(new.title); new.source_ref:=nullif(btrim(new.source_ref),''); return new;
  end if;
end;$function$;

create trigger commercial_offer_snapshots_scope_guard_v1 before insert on atlas.commercial_offer_snapshots for each row execute function atlas.guard_commercial_offer_scope_v1();
create trigger commercial_offer_snapshot_lines_scope_guard_v1 before insert on atlas.commercial_offer_snapshot_lines for each row execute function atlas.guard_commercial_offer_scope_v1();
create trigger commercial_offer_snapshot_assets_scope_guard_v1 before insert on atlas.commercial_offer_snapshot_assets for each row execute function atlas.guard_commercial_offer_scope_v1();
create trigger commercial_offer_distributions_scope_guard_v1 before insert on atlas.commercial_offer_distributions for each row execute function atlas.guard_commercial_offer_scope_v1();
create trigger commercial_offer_distribution_recipients_scope_guard_v1 before insert on atlas.commercial_offer_distribution_recipients for each row execute function atlas.guard_commercial_offer_scope_v1();

create or replace function atlas.prevent_commercial_offer_history_mutation_v1()
returns trigger language plpgsql set search_path=pg_catalog,atlas as $function$
begin raise exception 'Commercial offer snapshots and distributions are append-only evidence; record a later snapshot/distribution instead.' using errcode='55000'; end;$function$;
create trigger commercial_offer_snapshots_append_only_v1 before update or delete on atlas.commercial_offer_snapshots for each row execute function atlas.prevent_commercial_offer_history_mutation_v1();
create trigger commercial_offer_snapshot_lines_append_only_v1 before update or delete on atlas.commercial_offer_snapshot_lines for each row execute function atlas.prevent_commercial_offer_history_mutation_v1();
create trigger commercial_offer_snapshot_assets_append_only_v1 before update or delete on atlas.commercial_offer_snapshot_assets for each row execute function atlas.prevent_commercial_offer_history_mutation_v1();
create trigger commercial_offer_distributions_append_only_v1 before update or delete on atlas.commercial_offer_distributions for each row execute function atlas.prevent_commercial_offer_history_mutation_v1();
create trigger commercial_offer_distribution_recipients_append_only_v1 before update or delete on atlas.commercial_offer_distribution_recipients for each row execute function atlas.prevent_commercial_offer_history_mutation_v1();

create or replace function atlas.record_commercial_offer_snapshot_service_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid default null,
  p_snapshot_key text default null,
  p_title text default null,
  p_offer_state text default 'complete',
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null,
  p_lines jsonb default '[]'::jsonb,
  p_assets jsonb default '[]'::jsonb,
  p_source_kind text default 'manual_capture',
  p_source_ref text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare
  v_key text:=btrim(coalesce(p_snapshot_key,'')); v_title text:=btrim(coalesce(p_title,'')); v_state text:=lower(btrim(coalesce(p_offer_state,'complete'))); v_source_kind text:=lower(btrim(coalesce(p_source_kind,'manual_capture')));
  v_lines jsonb:=coalesce(p_lines,'[]'::jsonb); v_assets jsonb:=coalesce(p_assets,'[]'::jsonb); v_hash text; v_existing atlas.commercial_offer_snapshots%rowtype; v_snapshot_id uuid; v_line jsonb; v_asset jsonb; v_offering_id uuid; v_capture_state text; v_currency text;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id) then raise exception 'Organization not found.' using errcode='P0002'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units ou where ou.organization_id=p_organization_id and ou.id=p_organization_unit_id) then raise exception 'Organization unit is outside organization.' using errcode='23514'; end if;
  if v_key='' or v_title='' then raise exception 'Snapshot key and title are required.' using errcode='22023'; end if;
  if v_state not in ('complete','incomplete_evidence') then raise exception 'offer_state must be complete or incomplete_evidence.' using errcode='22023'; end if;
  if v_source_kind not in ('domain_snapshot','manual_capture','provider_observation','imported_record') then raise exception 'Unsupported source kind.' using errcode='22023'; end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until<p_valid_from then raise exception 'Offer validity window is invalid.' using errcode='22023'; end if;
  if jsonb_typeof(v_lines)<>'array' or jsonb_typeof(v_assets)<>'array' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Lines/assets must be arrays and metadata must be an object.' using errcode='22023'; end if;
  if v_state='complete' and jsonb_array_length(v_lines)=0 then raise exception 'A complete commercial offer snapshot requires at least one line.' using errcode='22023'; end if;
  if v_state='complete' and exists(select 1 from jsonb_array_elements(v_assets) x where lower(coalesce(x->>'captureState','captured'))<>'captured') then raise exception 'A complete offer snapshot cannot contain missing asset evidence.' using errcode='22023'; end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('title',v_title,'offerState',v_state,'validFrom',p_valid_from,'validUntil',p_valid_until,'lines',v_lines,'assets',v_assets)::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from atlas.commercial_offer_snapshots s where s.organization_id=p_organization_id and s.organization_unit_id is not distinct from p_organization_unit_id and s.snapshot_key=v_key;
  if v_existing.id is not null then
    if v_existing.snapshot_sha256 is distinct from v_hash then raise exception 'Snapshot key already exists with different offer content.' using errcode='23505'; end if;
    return jsonb_build_object('contractVersion','record_commercial_offer_snapshot_service_v1','offerSnapshotId',v_existing.id,'created',false,'offerState',v_existing.offer_state,'snapshotSha256',v_existing.snapshot_sha256,'lineCount',(select count(*) from atlas.commercial_offer_snapshot_lines l where l.offer_snapshot_id=v_existing.id),'assetCount',(select count(*) from atlas.commercial_offer_snapshot_assets a where a.offer_snapshot_id=v_existing.id));
  end if;

  insert into atlas.commercial_offer_snapshots(organization_id,organization_unit_id,snapshot_key,title,offer_state,valid_from,valid_until,snapshot_sha256,source_kind,source_ref,metadata)
  values(p_organization_id,p_organization_unit_id,v_key,v_title,v_state,p_valid_from,p_valid_until,v_hash,v_source_kind,nullif(btrim(p_source_ref),''),coalesce(p_metadata,'{}'::jsonb)) returning id into v_snapshot_id;

  for v_line in select value from jsonb_array_elements(v_lines) loop
    begin v_offering_id:=nullif(btrim(v_line->>'commercialOfferingId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid commercialOfferingId in offer line.' using errcode='22023'; end;
    if nullif(btrim(v_line->>'lineKey'),'') is null or nullif(btrim(v_line->>'description'),'') is null then raise exception 'Every offer line requires lineKey and description.' using errcode='22023'; end if;
    v_currency:=nullif(upper(btrim(v_line->>'currency')),'');
    insert into atlas.commercial_offer_snapshot_lines(offer_snapshot_id,line_key,commercial_offering_id,description,quantity_available,unit,unit_price,price_min,price_max,currency,price_basis,terms,source_ref,metadata)
    values(v_snapshot_id,btrim(v_line->>'lineKey'),v_offering_id,btrim(v_line->>'description'),nullif(v_line->>'quantityAvailable','')::numeric,nullif(btrim(v_line->>'unit'),''),nullif(v_line->>'unitPrice','')::numeric,nullif(v_line->>'priceMin','')::numeric,nullif(v_line->>'priceMax','')::numeric,v_currency,nullif(btrim(v_line->>'priceBasis'),''),coalesce(v_line->'terms','{}'::jsonb),nullif(btrim(v_line->>'sourceRef'),''),coalesce(v_line->'metadata','{}'::jsonb));
  end loop;

  for v_asset in select value from jsonb_array_elements(v_assets) loop
    v_capture_state:=lower(coalesce(nullif(btrim(v_asset->>'captureState'),''),'captured'));
    if nullif(btrim(v_asset->>'assetKey'),'') is null or nullif(btrim(v_asset->>'assetRole'),'') is null then raise exception 'Every offer asset requires assetKey and assetRole.' using errcode='22023'; end if;
    insert into atlas.commercial_offer_snapshot_assets(offer_snapshot_id,asset_key,asset_role,capture_state,transfer_name,mime_type,source_content_hash,custody_locator,source_ref,metadata)
    values(v_snapshot_id,btrim(v_asset->>'assetKey'),lower(btrim(v_asset->>'assetRole')),v_capture_state,nullif(btrim(v_asset->>'transferName'),''),nullif(lower(btrim(v_asset->>'mimeType')),''),nullif(lower(btrim(v_asset->>'sourceContentHash')),''),nullif(btrim(v_asset->>'custodyLocator'),''),nullif(btrim(v_asset->>'sourceRef'),''),coalesce(v_asset->'metadata','{}'::jsonb));
  end loop;

  return jsonb_build_object('contractVersion','record_commercial_offer_snapshot_service_v1','offerSnapshotId',v_snapshot_id,'created',true,'offerState',v_state,'snapshotSha256',v_hash,'lineCount',jsonb_array_length(v_lines),'assetCount',jsonb_array_length(v_assets));
end;$function$;
comment on function atlas.record_commercial_offer_snapshot_service_v1(uuid,uuid,text,text,text,timestamptz,timestamptz,jsonb,jsonb,text,text,jsonb) is 'Service-only writer for one immutable commercial offer snapshot and its exact presented lines/assets. Complete snapshots require at least one line and no missing asset evidence.';

create or replace function atlas.record_commercial_offer_distribution_service_v1(
  p_offer_snapshot_id uuid,
  p_distribution_key text,
  p_occurred_at timestamptz,
  p_channel text,
  p_recipients jsonb,
  p_subject text default null,
  p_body text default null,
  p_sender_label text default null,
  p_sender_address text default null,
  p_source_kind text default 'manual_report',
  p_source_ref text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_allow_create_prospects boolean default false
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare
  v_snapshot atlas.commercial_offer_snapshots%rowtype; v_key text:=btrim(coalesce(p_distribution_key,'')); v_channel text:=lower(btrim(coalesce(p_channel,''))); v_source_kind text:=lower(btrim(coalesce(p_source_kind,'manual_report'))); v_recipients jsonb:=coalesce(p_recipients,'[]'::jsonb); v_content_hash text; v_existing atlas.commercial_offer_distributions%rowtype; v_recipient jsonb; v_index integer:=0; v_relationship_id uuid; v_subject_id uuid; v_contact_kind text; v_contact_value text; v_contact_normalized text; v_role text; v_display_name text; v_source_label text; v_identifiers jsonb; v_source_record_key text; v_source_record_id uuid; v_resolution jsonb; v_state text; v_pending jsonb:='[]'::jsonb; v_resolutions jsonb:='{}'::jsonb; v_distribution_id uuid; v_interaction_id uuid; v_recipient_id uuid; v_result_recipients jsonb:='[]'::jsonb; v_outcome text;
begin
  select * into v_snapshot from atlas.commercial_offer_snapshots where id=p_offer_snapshot_id;
  if v_snapshot.id is null then raise exception 'Commercial offer snapshot not found.' using errcode='P0002'; end if;
  if v_key='' or v_channel='' then raise exception 'Distribution key and channel are required.' using errcode='22023'; end if;
  if p_occurred_at is null then raise exception 'Distribution occurred_at is required.' using errcode='22023'; end if;
  if v_source_kind not in ('manual_report','provider_observation','imported_record','action_result') then raise exception 'Unsupported distribution source kind.' using errcode='22023'; end if;
  if v_snapshot.offer_state='incomplete_evidence' and v_source_kind='action_result' then raise exception 'Atlas may not execute/record an authorized outbound commercial offer from an incomplete offer snapshot.' using errcode='55000'; end if;
  if jsonb_typeof(v_recipients)<>'array' or jsonb_array_length(v_recipients)=0 then raise exception 'Recipients must be a non-empty JSON array.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Metadata must be an object.' using errcode='22023'; end if;
  v_content_hash:=encode(extensions.digest(convert_to(jsonb_build_object('channel',v_channel,'subject',p_subject,'body',p_body)::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from atlas.commercial_offer_distributions d where d.organization_id=v_snapshot.organization_id and d.organization_unit_id is not distinct from v_snapshot.organization_unit_id and d.distribution_key=v_key;
  if v_existing.id is not null then
    if v_existing.offer_snapshot_id is distinct from v_snapshot.id or v_existing.content_sha256 is distinct from v_content_hash then raise exception 'Distribution key already exists with different offer/content.' using errcode='23505'; end if;
    return jsonb_build_object('contractVersion','record_commercial_offer_distribution_service_v1','distributionId',v_existing.id,'created',false,'recipientCount',(select count(*) from atlas.commercial_offer_distribution_recipients r where r.distribution_id=v_existing.id));
  end if;

  for v_recipient in select value from jsonb_array_elements(v_recipients) loop
    v_index:=v_index+1; v_relationship_id:=null; v_subject_id:=null;
    begin v_relationship_id:=nullif(btrim(v_recipient->>'externalRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid externalRelationshipId at recipient %.',v_index using errcode='22023'; end;
    v_contact_kind:=nullif(lower(btrim(v_recipient->>'contactKind')),''); v_contact_value:=nullif(btrim(v_recipient->>'contactValue'),''); v_contact_normalized:=case when v_contact_value is null then null else coalesce(nullif(btrim(v_recipient->>'contactNormalized'),''),atlas.normalize_external_party_identifier_v1(v_contact_kind,v_contact_value)) end;
    v_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'primary')); v_display_name:=nullif(btrim(v_recipient->>'displayName'),''); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),'');
    if v_role !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then raise exception 'Invalid recipientRole at recipient %.',v_index using errcode='22023'; end if;
    if jsonb_typeof(coalesce(v_recipient->'identifiers','[]'::jsonb))<>'array' then raise exception 'Recipient identifiers must be an array.' using errcode='22023'; end if;
    v_identifiers:=coalesce(v_recipient->'identifiers','[]'::jsonb);
    if v_contact_kind in ('email','phone') and v_contact_value is not null then v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object('type',v_contact_kind,'value',v_contact_value,'normalized',v_contact_normalized,'identityScoped',true)); end if;
    v_source_record_key:='distribution:'||v_key||':recipient:'||v_index::text||':'||coalesce(v_contact_kind||':'||v_contact_normalized,coalesce(v_relationship_id::text,''));

    if v_relationship_id is not null then
      select r.subject_id into v_subject_id from atlas.external_relationships r where r.id=v_relationship_id and r.organization_id=v_snapshot.organization_id and r.organization_unit_id is not distinct from v_snapshot.organization_unit_id;
      if v_subject_id is null then raise exception 'Recipient relationship % is outside offer scope.',v_relationship_id using errcode='23514'; end if;
      insert into atlas.identity_source_records(organization_id,source_system_key,source_record_kind,source_record_key,source_observed_at,source_authority,custody_ref,metadata)
      values(v_snapshot.organization_id,'commercial_offer_distribution','recipient',v_source_record_key,p_occurred_at,'evidence_only',jsonb_build_object('offerSnapshotId',v_snapshot.id,'distributionKey',v_key,'recipientIndex',v_index),jsonb_build_object('externalRelationshipId',v_relationship_id,'contactKind',v_contact_kind,'contactValue',v_contact_value,'sourceLabel',v_source_label))
      on conflict (organization_id,source_system_key,source_record_kind,source_record_key) do nothing;
      select id into v_source_record_id from atlas.identity_source_records where organization_id=v_snapshot.organization_id and source_system_key='commercial_offer_distribution' and source_record_kind='recipient' and source_record_key=v_source_record_key;
      insert into atlas.identity_source_subject_assertions(organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key)
      values(v_snapshot.organization_id,v_source_record_id,v_subject_id,'supports',1,'Caller supplied an established Atlas external relationship for this distribution recipient.','commercial-offer-recipient:'||v_source_record_id::text||':'||v_subject_id::text)
      on conflict (organization_id,idempotency_key) where idempotency_key is not null do nothing;
    end if;

    v_resolution:=atlas.resolve_external_relationship_service_v1(p_organization_id=>v_snapshot.organization_id,p_organization_unit_id=>v_snapshot.organization_unit_id,p_role_key=>'customer',p_display_name=>v_display_name,p_subject_kind=>'organization',p_identifiers=>v_identifiers,p_source_system_key=>'commercial_offer_distribution',p_source_record_kind=>'recipient',p_source_record_key=>v_source_record_key,p_source_observed_at=>p_occurred_at,p_source_authority=>'evidence_only',p_custody_ref=>jsonb_build_object('offerSnapshotId',v_snapshot.id,'distributionKey',v_key,'recipientIndex',v_index),p_basis=>jsonb_build_object('sourceLabel',v_source_label,'contactKind',v_contact_kind,'contactValue',v_contact_value)||coalesce(v_recipient->'metadata','{}'::jsonb),p_allow_create=>false,p_new_relationship_state=>'prospective');
    v_state:=v_resolution->>'state';
    if v_state in ('identity_review_required','relationship_inactive','relationship_role_inactive','resolved_with_identifier_conflict') or (v_state in ('no_match','matched_subject_no_relationship','matched_relationship_without_role') and not p_allow_create_prospects) then
      v_pending:=v_pending||jsonb_build_array(jsonb_build_object('recipientIndex',v_index,'contactKind',v_contact_kind,'contactValue',v_contact_value,'state',v_state,'resolution',v_resolution));
    else
      if v_state in ('no_match','matched_subject_no_relationship','matched_relationship_without_role') then
        v_resolution:=atlas.resolve_external_relationship_service_v1(p_organization_id=>v_snapshot.organization_id,p_organization_unit_id=>v_snapshot.organization_unit_id,p_role_key=>'customer',p_display_name=>v_display_name,p_subject_kind=>'organization',p_identifiers=>v_identifiers,p_source_system_key=>'commercial_offer_distribution',p_source_record_kind=>'recipient',p_source_record_key=>v_source_record_key,p_source_observed_at=>p_occurred_at,p_source_authority=>'evidence_only',p_custody_ref=>jsonb_build_object('offerSnapshotId',v_snapshot.id,'distributionKey',v_key,'recipientIndex',v_index),p_basis=>jsonb_build_object('sourceLabel',v_source_label,'contactKind',v_contact_kind,'contactValue',v_contact_value)||coalesce(v_recipient->'metadata','{}'::jsonb),p_allow_create=>true,p_new_relationship_state=>'prospective');
      end if;
      if v_resolution->>'state' not in ('resolved') then v_pending:=v_pending||jsonb_build_array(jsonb_build_object('recipientIndex',v_index,'contactKind',v_contact_kind,'contactValue',v_contact_value,'state',v_resolution->>'state','resolution',v_resolution)); else v_resolutions:=jsonb_set(v_resolutions,array[v_index::text],v_resolution,true); end if;
    end if;
  end loop;

  if jsonb_array_length(v_pending)>0 then return jsonb_build_object('contractVersion','record_commercial_offer_distribution_service_v1','state','identity_resolution_required','distributionId',null,'created',false,'pendingCount',jsonb_array_length(v_pending),'pending',v_pending,'message','No distribution record was created. Resolve recipient identity/relationship state and retry the same distribution key.'); end if;

  insert into atlas.commercial_offer_distributions(organization_id,organization_unit_id,offer_snapshot_id,distribution_key,channel,sender_label,sender_address,subject,body_text,content_sha256,occurred_at,source_kind,source_ref,metadata)
  values(v_snapshot.organization_id,v_snapshot.organization_unit_id,v_snapshot.id,v_key,v_channel,nullif(btrim(p_sender_label),''),nullif(lower(btrim(p_sender_address)),''),nullif(btrim(p_subject),''),p_body,v_content_hash,p_occurred_at,v_source_kind,nullif(btrim(p_source_ref),''),coalesce(p_metadata,'{}'::jsonb)) returning id into v_distribution_id;

  v_index:=0; v_outcome:=case when v_source_kind in ('action_result','provider_observation') then 'sent' else 'reported_sent' end;
  for v_recipient in select value from jsonb_array_elements(v_recipients) loop
    v_index:=v_index+1; v_resolution:=v_resolutions->(v_index::text); v_relationship_id:=(v_resolution->>'externalRelationshipId')::uuid; v_subject_id:=(v_resolution->>'subjectId')::uuid;
    v_contact_kind:=nullif(lower(btrim(v_recipient->>'contactKind')),''); v_contact_value:=nullif(btrim(v_recipient->>'contactValue'),''); v_contact_normalized:=case when v_contact_value is null then null else coalesce(nullif(btrim(v_recipient->>'contactNormalized'),''),atlas.normalize_external_party_identifier_v1(v_contact_kind,v_contact_value)) end; v_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'primary')); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),'');
    insert into atlas.external_relationship_interactions(organization_id,organization_unit_id,external_relationship_id,occurred_at,interaction_kind,channel,outcome,contact_label,follow_up,note,metadata)
    values(v_snapshot.organization_id,v_snapshot.organization_unit_id,v_relationship_id,p_occurred_at,'commercial_offer_distributed',v_channel,v_outcome,coalesce(v_source_label,v_contact_value),null,nullif(btrim(p_subject),''),jsonb_build_object('direction','outgoing','commercialOfferSnapshotId',v_snapshot.id,'commercialOfferDistributionId',v_distribution_id,'contactKind',v_contact_kind,'contactValue',v_contact_value,'contentSha256',v_content_hash,'identitySourceRecordId',v_resolution->>'sourceRecordId')||coalesce(v_recipient->'metadata','{}'::jsonb)) returning id into v_interaction_id;
    insert into atlas.commercial_offer_distribution_recipients(distribution_id,external_relationship_id,identity_subject_id,interaction_id,contact_kind,contact_value,contact_normalized,recipient_role,source_label,metadata)
    values(v_distribution_id,v_relationship_id,v_subject_id,v_interaction_id,v_contact_kind,v_contact_value,v_contact_normalized,v_role,v_source_label,coalesce(v_recipient->'metadata','{}'::jsonb)||jsonb_build_object('identitySourceRecordId',v_resolution->>'sourceRecordId','identityMatchState',v_resolution->>'matchState')) returning id into v_recipient_id;
    v_result_recipients:=v_result_recipients||jsonb_build_array(jsonb_build_object('recipientIndex',v_index,'recipientId',v_recipient_id,'externalRelationshipId',v_relationship_id,'subjectId',v_subject_id,'interactionId',v_interaction_id,'contactKind',v_contact_kind,'contactValue',v_contact_value));
  end loop;
  return jsonb_build_object('contractVersion','record_commercial_offer_distribution_service_v1','state','recorded','distributionId',v_distribution_id,'offerSnapshotId',v_snapshot.id,'created',true,'recipientCount',jsonb_array_length(v_result_recipients),'contentSha256',v_content_hash,'recipients',v_result_recipients);
end;$function$;
comment on function atlas.record_commercial_offer_distribution_service_v1(uuid,text,timestamptz,text,jsonb,text,text,text,text,text,text,jsonb,boolean) is 'Service-only evidence writer for presenting one immutable commercial offer snapshot to resolved external relationships. It delegates recipient identity to the canonical resolver, creates no distribution when identity is unresolved, and never sends externally or creates/reserves commercial commitment state.';

create or replace function atlas.commercial_offer_snapshot_self_v1(p_offer_snapshot_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_snapshot atlas.commercial_offer_snapshots%rowtype; v_lines jsonb; v_assets jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  select * into v_snapshot from atlas.commercial_offer_snapshots where id=p_offer_snapshot_id;
  if v_snapshot.id is null then raise exception 'Commercial offer snapshot not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_member(v_snapshot.organization_id) then raise exception 'Commercial offer snapshot is outside your organization.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at,l.id),'[]'::jsonb) into v_lines from atlas.commercial_offer_snapshot_lines l where l.offer_snapshot_id=v_snapshot.id;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at,a.id),'[]'::jsonb) into v_assets from atlas.commercial_offer_snapshot_assets a where a.offer_snapshot_id=v_snapshot.id;
  return jsonb_build_object('contractVersion','commercial_offer_snapshot_self_v1','snapshot',to_jsonb(v_snapshot),'lines',v_lines,'assets',v_assets);
end;$function$;

create or replace function atlas.commercial_offer_distribution_history_self_v1(p_organization_id uuid,p_external_relationship_id uuid default null,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_items jsonb;
begin
  if auth.uid() is null or not atlas.is_organization_member(p_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;
  if p_external_relationship_id is not null and not exists(select 1 from atlas.external_relationships r where r.id=p_external_relationship_id and r.organization_id=p_organization_id) then raise exception 'External relationship is outside organization.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(x.item order by x.occurred_at desc,x.recipient_id desc),'[]'::jsonb) into v_items from (
    select r.id recipient_id,d.occurred_at,jsonb_build_object('distributionId',d.id,'distributionKey',d.distribution_key,'occurredAt',d.occurred_at,'channel',d.channel,'senderLabel',d.sender_label,'senderAddress',d.sender_address,'subject',d.subject,'body',d.body_text,'contentSha256',d.content_sha256,'sourceKind',d.source_kind,'sourceRef',d.source_ref,'offerSnapshotId',s.id,'offerSnapshotKey',s.snapshot_key,'offerTitle',s.title,'offerState',s.offer_state,'snapshotSha256',s.snapshot_sha256,'externalRelationshipId',r.external_relationship_id,'identitySubjectId',r.identity_subject_id,'contactKind',r.contact_kind,'contactValue',r.contact_value,'recipientRole',r.recipient_role,'interactionId',r.interaction_id) item
    from atlas.commercial_offer_distribution_recipients r join atlas.commercial_offer_distributions d on d.id=r.distribution_id join atlas.commercial_offer_snapshots s on s.id=d.offer_snapshot_id
    where d.organization_id=p_organization_id and (p_external_relationship_id is null or r.external_relationship_id=p_external_relationship_id)
    order by d.occurred_at desc,r.id desc limit p_limit
  ) x;
  return jsonb_build_object('contractVersion','commercial_offer_distribution_history_self_v1','organizationId',p_organization_id,'externalRelationshipId',p_external_relationship_id,'items',v_items);
end;$function$;

alter table atlas.commercial_offer_snapshots enable row level security;
alter table atlas.commercial_offer_snapshot_lines enable row level security;
alter table atlas.commercial_offer_snapshot_assets enable row level security;
alter table atlas.commercial_offer_distributions enable row level security;
alter table atlas.commercial_offer_distribution_recipients enable row level security;

revoke all on table atlas.commercial_offer_snapshots from public,anon,authenticated;
revoke all on table atlas.commercial_offer_snapshot_lines from public,anon,authenticated;
revoke all on table atlas.commercial_offer_snapshot_assets from public,anon,authenticated;
revoke all on table atlas.commercial_offer_distributions from public,anon,authenticated;
revoke all on table atlas.commercial_offer_distribution_recipients from public,anon,authenticated;
grant all on table atlas.commercial_offer_snapshots to service_role;
grant all on table atlas.commercial_offer_snapshot_lines to service_role;
grant all on table atlas.commercial_offer_snapshot_assets to service_role;
grant all on table atlas.commercial_offer_distributions to service_role;
grant all on table atlas.commercial_offer_distribution_recipients to service_role;

revoke all on function atlas.guard_commercial_offer_scope_v1() from public,anon,authenticated;
revoke all on function atlas.prevent_commercial_offer_history_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.record_commercial_offer_snapshot_service_v1(uuid,uuid,text,text,text,timestamptz,timestamptz,jsonb,jsonb,text,text,jsonb) from public,anon,authenticated;
revoke all on function atlas.record_commercial_offer_distribution_service_v1(uuid,text,timestamptz,text,jsonb,text,text,text,text,text,text,jsonb,boolean) from public,anon,authenticated;
revoke all on function atlas.commercial_offer_snapshot_self_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.commercial_offer_distribution_history_self_v1(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function atlas.guard_commercial_offer_scope_v1() to service_role;
grant execute on function atlas.prevent_commercial_offer_history_mutation_v1() to service_role;
grant execute on function atlas.record_commercial_offer_snapshot_service_v1(uuid,uuid,text,text,text,timestamptz,timestamptz,jsonb,jsonb,text,text,jsonb) to service_role;
grant execute on function atlas.record_commercial_offer_distribution_service_v1(uuid,text,timestamptz,text,jsonb,text,text,text,text,text,text,jsonb,boolean) to service_role;
grant execute on function atlas.commercial_offer_snapshot_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.commercial_offer_distribution_history_self_v1(uuid,uuid,integer) to authenticated,service_role;

commit;

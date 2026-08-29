create table if not exists draft.canon_manuscript_image_collation_protocols (
  protocol_key text primary key,
  protocol_title text not null,
  protocol_version text not null,
  image_authority text not null,
  transcription_control text not null,
  workflow jsonb not null,
  evidence_rule text not null,
  direct_mark_claim_rule text not null,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists draft.canon_manuscript_image_collations (
  image_collation_id bigserial primary key,
  discovery_run_id bigint references draft.canon_discovery_runs(discovery_run_id) on delete cascade,
  protocol_key text not null references draft.canon_manuscript_image_collation_protocols(protocol_key),
  witness_key text not null,
  canonical_book_code text not null,
  chapter_num integer not null,
  verse_num integer not null,
  fragment_label text,
  line_labels text[] not null default '{}',
  target_reading text not null,
  transcription_source text not null,
  transcription_version text,
  transcription_surface text,
  transcription_status text not null default 'located' check (transcription_status in ('not_located','located','independently_confirmed','pressured','unresolved')),
  image_authority text not null,
  manuscript_page_url text,
  image_page_url text,
  image_identifier text,
  image_type text,
  image_status text not null default 'not_located' check (image_status in ('not_located','manuscript_page_located','fragment_image_located','viewed','collated','unresolved')),
  physical_observation jsonb,
  collation_verdict text not null default 'pending' check (collation_verdict in ('pending','supports_transcription','pressures_transcription','unresolved')),
  evidence_tier text not null default 'transcription_only' check (evidence_tier in ('transcription_only','independent_transcription_concordance','image_located','image_viewed','image_collated_physical_mark')),
  direct_physical_mark_claim_allowed boolean not null default false,
  semantic_unblinding_allowed boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint canon_manuscript_image_collations_direct_mark_guard check (
    direct_physical_mark_claim_allowed = false
    or (evidence_tier='image_collated_physical_mark' and image_status='collated')
  ),
  constraint canon_manuscript_image_collations_unblind_guard check (
    semantic_unblinding_allowed = false
    or collation_verdict in ('supports_transcription','pressures_transcription','unresolved')
  ),
  unique (protocol_key,witness_key,canonical_book_code,chapter_num,verse_num,target_reading)
);

comment on table draft.canon_manuscript_image_collation_protocols is 'Raw-mark-first image collation protocol. Keeps transcription concordance distinct from direct image/physical-mark verification.';
comment on table draft.canon_manuscript_image_collations is 'Per-reading manuscript image custody. A direct physical-mark claim is structurally blocked until an image has actually been collated.';
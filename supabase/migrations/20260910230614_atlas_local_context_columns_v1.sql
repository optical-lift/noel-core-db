alter table local_intel.entities add column local_context_id uuid;
alter table local_intel.search_queries add column local_context_id uuid;
alter table local_intel.entity_ingestion_candidates add column local_context_id uuid;
alter table local_intel.research_attempts add column local_context_id uuid;

comment on column local_intel.entities.local_context_id is 'Owning Organization Local Context. V1 Local entities are organization-owned, not shared cross-customer registry rows.';
comment on column local_intel.search_queries.local_context_id is 'Local Context whose external world this discovery query is building.';
comment on column local_intel.entity_ingestion_candidates.local_context_id is 'Local Context whose discovery pipeline owns this pre-resolution candidate.';
comment on column local_intel.research_attempts.local_context_id is 'Owning Local Context for new attempts. Historical append-only attempts may remain null and inherit context through entity_id.';

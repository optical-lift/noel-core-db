-- Reality Witness adapter registry v1

insert into draft.reality_query_dimension_registry
(dimension_key,display_name,dimension_family,value_mode,neutral_definition,ui_selectable,status)
values
('state','State','state','free_text','A recorded state or condition without assigning it to a disciplinary ontology.',false,'active'),
('action','Action','operation','free_text','An action performed, applied, or enacted.',false,'active'),
('input','Input','operation','free_text','A material, informational, environmental, or other input entering an occurrence.',false,'active'),
('response','Response','transition','free_text','A recorded response or change following or accompanying an occurrence.',false,'active'),
('direction','Direction','transition','controlled_text','The recorded direction of change or movement.',false,'active'),
('measurement','Measurement','measurement','free_text','A measured quantity or measured state expressed in source-native form.',false,'active'),
('process','Process','process','free_text','A process, event family, or operation observed or asserted by a witness.',false,'active'),
('relation','Relation','relation','free_text','A recorded relation between objects or states.',false,'active'),
('source_term','Source term','vocabulary','free_text','A source-native term retained for alignment without rewriting its vocabulary.',false,'active'),
('question','Question','context','free_text','A question or proposition under examination.',false,'active')
on conflict (dimension_key) do update set
  display_name=excluded.display_name,
  dimension_family=excluded.dimension_family,
  value_mode=excluded.value_mode,
  neutral_definition=excluded.neutral_definition,
  ui_selectable=excluded.ui_selectable,
  status=excluded.status,
  updated_at=now();

create table if not exists draft.reality_witness_adapter_registry (
  adapter_key text primary key,
  adapter_name text not null,
  source_schema text not null,
  source_object_name text not null,
  source_object_type text not null,
  emitted_object_type text not null,
  witness_strategy text not null,
  subject_strategy text,
  time_strategy text,
  coordinate_strategy text not null,
  adapter_status text not null default 'active',
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reality_witness_adapter_strategy_check
    check (witness_strategy in ('fixed','framework_key','source_jurisdiction','source_native'))
);

comment on table draft.reality_witness_adapter_registry is
'Registry of thin adapters that expose native source objects to Reality Alignment. Adapters declare how witness identity, subject/time, and coordinate candidates are projected; they do not replace source tables.';

alter table draft.reality_witness_adapter_registry enable row level security;
revoke all on draft.reality_witness_adapter_registry from anon,authenticated;
grant select,insert,update,delete on draft.reality_witness_adapter_registry to service_role;

insert into draft.reality_witness_adapter_registry
(adapter_key,adapter_name,source_schema,source_object_name,source_object_type,emitted_object_type,witness_strategy,subject_strategy,time_strategy,coordinate_strategy,adapter_status,metadata)
values
('practice_body_observation','Practice body observation','practice','body_observations','table','practice_body_observation','fixed','session -> person','observed_at || session.started_at || created_at','body region + side + observation type + normalized state + intensity + onset','active','{"witness_key":"practice:observation"}'),
('practice_context_observation','Practice context observation','practice','context_observations','table','practice_context_observation','fixed','session -> person','observed_at || session.started_at || created_at','context type + normalized context + valence + intensity','active','{"witness_key":"practice:observation"}'),
('practice_intervention','Practice intervention','practice','interventions','table','practice_intervention','fixed','session -> person','session.started_at || created_at','target region + side + intervention type + practice label + material/input + operator intent','active','{"witness_key":"practice:intervention"}'),
('practice_outcome','Practice outcome','practice','outcomes','table','practice_outcome','fixed','session -> person','observed_at || session.started_at || created_at','outcome type + response text + direction + magnitude + durability','active','{"witness_key":"practice:outcome"}'),
('practice_discernment_signal','Practice discernment signal','practice','discernment_signals','table','practice_discernment_signal','fixed','session -> person','observed_at || session.started_at || created_at','signal type + question + normalized response + response direction + linked function/Song object','active','{"witness_key":"practice:discernment"}'),
('celestial_body_state','Celestial measured body state','draft','celestial_chart_body_states','table','celestial_body_state','fixed','snapshot -> chart input subject_ref','sample_time_utc','body identity + coordinates + visibility + retrograde + magnitude + measured motion','active','{"witness_key":"celestial:measurement"}'),
('celestial_chart_event','Celestial recognized event','draft','celestial_chart_events','table','celestial_chart_event','fixed','snapshot -> chart input subject_ref','event_exact_utc || event_start_utc','event family + grammar + participating bodies + event parameters','active','{"witness_key":"celestial:event_recognition"}'),
('framework_concept','Framework-native concept','draft','reality_framework_concepts','table','framework_concept','framework_key',null,'created_at','source-native term + native definition + concept kind','active','{}'),
('canon_organic_term','Canon organic term','draft','canon_organic_terms','table','canon_organic_term','fixed',null,'created_at','source-native lexical term + language + Strong id + term kind','active','{"witness_key":"jurisdiction:canon_vocabulary"}'),
('function_registry','Noel function','draft','function_registry','table','function','fixed',null,'created_at','function name + before/operation/after + intended fruit + failure mode','active','{"witness_key":"jurisdiction:noel_function"}'),
('song_object','Song object','draft','song_objects','table','song_object','fixed',null,'created_at','object name + object type + provisional function lane','active','{"witness_key":"jurisdiction:song"}'),
('research_claim','Research claim','draft','research_claims','table','research_claim','fixed',null,'created_at','claim title + claim kind + current category + live test','active','{"witness_key":"jurisdiction:research_claim"}')
on conflict (adapter_key) do update set
  adapter_name=excluded.adapter_name,
  source_schema=excluded.source_schema,
  source_object_name=excluded.source_object_name,
  source_object_type=excluded.source_object_type,
  emitted_object_type=excluded.emitted_object_type,
  witness_strategy=excluded.witness_strategy,
  subject_strategy=excluded.subject_strategy,
  time_strategy=excluded.time_strategy,
  coordinate_strategy=excluded.coordinate_strategy,
  adapter_status=excluded.adapter_status,
  metadata=excluded.metadata,
  updated_at=now();

insert into draft.reality_witness_registry
(witness_key,witness_name,witness_kind,native_domain,source_role,provenance_status,is_active,metadata)
values
('practice:observation','Practice observation','record_system','practice','observation','registered',true,'{"source_schema":"practice"}'),
('practice:intervention','Practice intervention','record_system','practice','intervention','registered',true,'{"source_schema":"practice"}'),
('practice:outcome','Practice outcome','record_system','practice','outcome','registered',true,'{"source_schema":"practice"}'),
('practice:discernment','Practice discernment','record_system','practice','discernment_signal','registered',true,'{"source_schema":"practice"}'),
('celestial:measurement','Celestial measurement','measurement_system','celestial','measurement','registered',true,'{"source_schema":"draft","source_family":"celestial"}'),
('celestial:event_recognition','Celestial event recognition','recognition_system','celestial','event_recognition','registered',true,'{"source_schema":"draft","source_family":"celestial"}')
on conflict (witness_key) do update set
  witness_name=excluded.witness_name,
  witness_kind=excluded.witness_kind,
  native_domain=excluded.native_domain,
  source_role=excluded.source_role,
  provenance_status=excluded.provenance_status,
  is_active=excluded.is_active,
  metadata=excluded.metadata,
  updated_at=now();

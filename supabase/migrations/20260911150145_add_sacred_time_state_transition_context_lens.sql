begin;

create table if not exists draft.noel_context_lenses (
  lens_id bigint generated always as identity primary key,
  lens_key text not null unique,
  lens_name text not null,
  lens_kind text not null default 'constitutional_lens',
  scope text not null default 'global',
  authority_level text not null default 'constitutional_working',
  inheritance_mode text not null default 'global_inherited',
  summary text not null,
  application_rule text not null,
  non_forcing_boundary text not null,
  status text not null default 'active',
  priority integer not null default 1000,
  source_basis jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists noel_context_lenses_status_priority_idx
  on draft.noel_context_lenses(status, priority desc, lens_key);

create table if not exists draft.noel_context_lens_elements (
  lens_element_id bigint generated always as identity primary key,
  lens_id bigint not null references draft.noel_context_lenses(lens_id) on delete cascade,
  element_key text not null,
  element_name text not null,
  element_kind text not null,
  sequence_group text,
  sequence_ordinal integer,
  clarity_state text not null,
  statement text not null,
  functional_role text,
  does_not_establish text,
  evidence_needed text,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lens_id, element_key)
);

create index if not exists noel_context_lens_elements_lookup_idx
  on draft.noel_context_lens_elements(lens_id, status, clarity_state, sequence_group, sequence_ordinal);

insert into draft.noel_context_lenses (
  lens_key, lens_name, lens_kind, scope, authority_level, inheritance_mode,
  summary, application_rule, non_forcing_boundary, status, priority, source_basis, notes
)
values (
  'sacred_time_state_transition_v1',
  'Sacred Time / State Transition',
  'constitutional_lens',
  'global',
  'constitutional_working',
  'global_inherited',
  'Sacred time is a Source-governed state-transition framework: created time markers make appointed order legible, while actual condition, lawful operation, custody, access, preparation, restoration, dwelling, release, and rest remain distinct parts of the operation. The framework is larger than feast-date arithmetic and must travel with canon-wide work involving time.',
  'Inherit this lens whenever Noel works with appointed time, Sabbath, feast cycles, calendar questions, temporal boundaries, readiness, access, release, Jubilee, celestial time markers, or time-gated operations. Clear elements constrain interpretation. Fuzzy elements may organize hypotheses but may not be presented as settled. Missing elements remain explicit open sockets rather than being silently filled by inherited calendar tradition, astronomy, arithmetic convention, or later theology.',
  'This lens organizes evidence and preserves relationships; it does not force every temporal text into one symbolic meaning, does not make astronomy the source of sacred order, does not make a civil date the identity of an appointed state, and does not promote unresolved physical markers or counting conventions into canon rules.',
  'active',
  2500,
  jsonb_build_object(
    'canon_controls', jsonb_build_array(
      'Exodus 12','Leviticus 23','Numbers 9-10','Deuteronomy 15-16','Leviticus 25'
    ),
    'research_claim_keys', jsonb_build_array(
      'canon_function_by_time_repair_map_candidate',
      'chodesh_renewed_month_cycle_head_public_state_candidate_20260819',
      'canon_calendar_custody_differentiated_reception_proclamation_signal_execution_20260819',
      'canon_appointed_time_multidomain_phase_alignment_20260819',
      'canon_created_heavens_witness_subordinate_source_boundary_20260819',
      'canon_time_marker_downstream_of_known_human_state_operation_fitness_20260819'
    )
  ),
  'Global inherited canon context. Designed to hold clear, fuzzy, and missing states in one packet rather than forcing feast-specific interpretation into isolated date rules.'
)
on conflict (lens_key) do update set
  lens_name = excluded.lens_name,
  lens_kind = excluded.lens_kind,
  scope = excluded.scope,
  authority_level = excluded.authority_level,
  inheritance_mode = excluded.inheritance_mode,
  summary = excluded.summary,
  application_rule = excluded.application_rule,
  non_forcing_boundary = excluded.non_forcing_boundary,
  status = excluded.status,
  priority = excluded.priority,
  source_basis = excluded.source_basis,
  notes = excluded.notes,
  updated_at = now();

with l as (
  select lens_id from draft.noel_context_lenses where lens_key='sacred_time_state_transition_v1'
), seed(element_key, element_name, element_kind, sequence_group, sequence_ordinal, clarity_state, statement, functional_role, does_not_establish, evidence_needed, metadata) as (
  values
  ('source_owned_time','Source-Owned Appointed Time','framework_state','governance',10,'clear',
   'Appointed time belongs to YHWH as Source. Created bodies, calendars, officers, and communities may receive, mark, proclaim, signal, or execute that order, but they do not originate its authority.',
   'Keeps source distinct from carriers and execution.',
   'Does not identify a physical lunar marker or civil calendar.',null,'{}'::jsonb),
  ('created_markers_subordinate','Created Time Markers as Subordinate Witness','framework_state','governance',20,'clear',
   'The created heavens can serve signs, appointed times, days, years, and bounded witness functions under God. Their state can make order legible without becoming the source of the order.',
   'Places astronomy downstream of Source while preserving real temporal measurement.',
   'Does not authorize horoscope-style diagnosis or autonomous celestial rule.',null,'{}'::jsonb),
  ('state_before_projection','State and Operation Before Civil Projection','framework_state','method',30,'clear',
   'Sacred-time work begins with the canonically relevant state, relation, operation, coordinate, or counted transition. A Gregorian or other civil date is a later projection through an explicitly named model.',
   'Prevents the projected date from replacing the canonically governed state.',
   'Does not make one modern calendar the biblical calendar.',null,'{}'::jsonb),
  ('differentiated_custody','Reception, Proclamation, Signal, and Execution Are Distinct','framework_state','governance',40,'clear',
   'Canonical calendar custody differentiates Source, instruction reception, public proclamation or call, priestly signal, and communal or ritual execution.',
   'Preserves custody roles instead of flattening them into a single calendar authority.',
   'Does not yet determine who adjudicates the physical month-head marker.',null,'{}'::jsonb),
  ('governing_lanes','Governing Lanes: Access, Preparation, Time, Orientation','lane','operations',50,'clear',
   'Sacred-time texts repeatedly govern when a body may act or receive, what preparation is required, how time is measured or bounded, and how the community is oriented to the appointed state.',
   'Provides four non-exclusive lanes for sorting temporal operations.',
   'Does not require every feast or time text to instantiate all four lanes equally.',null,'{}'::jsonb),
  ('sabbath_base_rhythm','Sabbath as Base Rhythm','cycle_stage','weekly',100,'clear',
   'The seventh-day Sabbath is a recurring work/rest rhythm and stands at the head of Leviticus 23 before the annual appointed-time sequence.',
   'Establishes the recurring base rhythm without deriving it from lunar month numbering.',
   'Does not by itself settle historical weekday continuity.',null,'{}'::jsonb),
  ('spring_cluster','Spring Cluster: Passover, Unleavened Bread, Wave Sheaf / Firstfruits','cycle_stage','annual',110,'clear',
   'The spring appointed times form a clustered sequence rather than three unrelated date tokens: Passover, the seven-day Unleavened Bread span, and the wave-sheaf / firstfruits operation tied to harvest beginning.',
   'Preserves sequence, preparation, intake, harvest readiness, and transition relations.',
   'Does not settle the Sabbath referent for the wave-sheaf day.',null,'{}'::jsonb),
  ('weeks_counted_response','Weeks / Pentecost as Counted Transition','cycle_stage','annual',120,'clear',
   'Feast of Weeks is generated through a canonically specified count connected to the wave sheaf and to beginning the sickle in standing grain, rather than by an independent fixed month/day coordinate.',
   'Makes the counted interval itself part of the state transition.',
   'Does not silently choose an unresolved Firstfruits anchor or a modern inclusive/exclusive arithmetic convention.',null,'{}'::jsonb),
  ('seventh_month_cluster','Seventh-Month Cluster: Blasting, Atonement, Booths / Dwelling','cycle_stage','annual',130,'clear',
   'The seventh-month movement preserves a sequence from memorial/blasting to affliction/atonement and then to Booths, dwelling, ingathering, and rejoicing, followed by the distinct eighth-day assembly.',
   'Keeps proclamation, repair, dwelling, harvest, and rest-related operations connected without collapsing them.',
   'Does not make the sequence a complete symbolic dictionary for every later use.',null,'{}'::jsonb),
  ('seventh_year_release','Seventh-Year Release','cycle_stage','multi_year',140,'clear',
   'Sacred-time structure extends beyond annual feasts into seventh-year land, debt, and service release operations.',
   'Shows that appointed time can govern social, economic, and land-state transitions at a larger scale.',
   'Does not establish a modern civil-year synchronization.',null,'{}'::jsonb),
  ('jubilee_reset','Jubilee-Scale Restoration','cycle_stage','multi_year',150,'clear',
   'Jubilee extends the pattern to inheritance, possession, liberty, household, and land restoration after the counted sabbatical structure.',
   'Preserves large-scale restoration as a time-governed state transition.',
   'Does not establish an uninterrupted historical Jubilee chronology.',null,'{}'::jsonb),
  ('cross_scale_homology','Cross-Scale Homology','framework_relation','cross_scale',200,'fuzzy',
   'Weekly, annual, seventh-year, and Jubilee structures appear to share a recurring grammar of bounded time, preparation, release, restoration, dwelling, and rest, but the exact one-to-one mapping across scales is not fully established.',
   'Allows cross-scale comparison without forcing equivalence.',
   'Does not permit a function at one scale to be copied automatically into another.',
   'Continue canon-wide pressure testing of repeated functions across scales.','{}'::jsonb),
  ('compressed_feast_semantics','Compressed Feast-Semantics Shorthand','interpretive_summary','annual',210,'fuzzy',
   'Existing working shorthand such as spring as received deliverance/desire, Weeks as counted response, and the fall movement as blasting -> affliction/atonement -> dwelling/rejoicing can be useful as a memory aid only when the underlying textual operations remain visible.',
   'Provides a human-readable compression for a larger sequence.',
   'Does not replace the text with a slogan or make the shorthand itself canonical terminology.',
   'Keep testing the shorthand against the full operations and boundaries of each appointed time.','{}'::jsonb),
  ('function_to_feast_mapping','Exact Function-to-Feast Mapping','framework_relation','annual',220,'fuzzy',
   'Some functions are strongly visible in individual appointed times, but the complete operational function of each feast should remain open to refinement rather than being inferred solely from sequence position.',
   'Preserves useful functional reconstruction while preventing premature closure.',
   'Does not authorize one generic spiritual meaning for all sacred time.',
   'Continue function-by-time audit across canon passages and execution rules.','{}'::jsonb),
  ('month_head_marker','Physical Month-Head Marker','missing_socket','calendar',300,'missing',
   'The physical phenomenon that establishes the head of a chodesh remains unresolved in Noel.',
   null,
   'No conjunction, predicted crescent, observed crescent, administrative declaration, or later fixed-calendar rule may be silently promoted as the canonical marker.',
   'Resolve only through focused canon/witness work while preserving Source/custody distinctions.','{}'::jsonb),
  ('abib_operational_threshold','Operational Abib / First-Month Threshold','missing_socket','calendar',310,'missing',
   'The canon preserves a first-month / Abib relation and an agricultural ear-stage relation, but Noel does not yet have a fully adjudicated operational threshold that converts that relation into one modern year-start date.',
   null,
   'A sky-only year-start rule is not established merely because astronomy is measurable.',
   'Continue H24 Abib, land-state, harvest, and year-start audit.','{}'::jsonb),
  ('firstfruits_sabbath_referent','Firstfruits Sabbath Referent','missing_socket','calendar',320,'missing',
   'The Sabbath referred to in Leviticus 23:11 and 23:15 for the wave-sheaf relation remains unresolved in the current Noel state.',
   null,
   'Do not silently choose weekly Sabbath, festival rest day, or later traditional reckoning.',
   'Focused Hebrew/LXX/canon-witness audit of Leviticus 23:11,15 and surrounding usage.','{}'::jsonb),
  ('weekly_sabbath_civil_continuity','Weekly Sabbath Civil-Calendar Continuity','missing_socket','calendar',330,'missing',
   'The canonical seven-day recurrence is clear; its uninterrupted mapping into a named modern civil weekday is a separate historical question not resolved by the recurrence rule alone.',
   null,
   'Do not infer civil-week continuity from annual feast coordinates.',
   'Historical/witness continuity audit if a civil weekday answer is required.','{}'::jsonb),
  ('general_day_boundary','Universal Day-Boundary Rule','missing_socket','calendar',340,'missing',
   'Explicit evening boundaries exist in particular feast instructions, but Noel does not currently treat those passages alone as proof of a universal day-boundary rule for every calendrical context.',
   null,
   'Do not generalize feast-specific evening language beyond its warrant.',
   'Separate audit of day-boundary language across creation, Torah, narrative, and appointed-time texts.','{}'::jsonb),
  ('long_cycle_projection','Long-Cycle Historical / Civil Projection','missing_socket','calendar',350,'missing',
   'The seventh-year and Jubilee structures are canonically countable, but Noel does not currently possess an adjudicated continuous historical synchronization into modern civil years.',
   null,
   'Do not assign present-day sabbatical or Jubilee years as canonically certain without an explicit chronology basis.',
   'Chronicle/canon witness audit for continuity and reset claims.','{}'::jsonb)
)
insert into draft.noel_context_lens_elements (
  lens_id, element_key, element_name, element_kind, sequence_group, sequence_ordinal,
  clarity_state, statement, functional_role, does_not_establish, evidence_needed, metadata
)
select l.lens_id, s.element_key, s.element_name, s.element_kind, s.sequence_group, s.sequence_ordinal,
       s.clarity_state, s.statement, s.functional_role, s.does_not_establish, s.evidence_needed, s.metadata
from l cross join seed s
on conflict (lens_id, element_key) do update set
  element_name = excluded.element_name,
  element_kind = excluded.element_kind,
  sequence_group = excluded.sequence_group,
  sequence_ordinal = excluded.sequence_ordinal,
  clarity_state = excluded.clarity_state,
  statement = excluded.statement,
  functional_role = excluded.functional_role,
  does_not_establish = excluded.does_not_establish,
  evidence_needed = excluded.evidence_needed,
  metadata = excluded.metadata,
  status = 'active',
  updated_at = now();

create or replace view intelligence.v_noel_active_context_packet as
select
  l.lens_key,
  l.lens_name,
  l.lens_kind,
  l.scope,
  l.authority_level,
  l.inheritance_mode,
  l.summary,
  l.application_rule,
  l.non_forcing_boundary,
  l.priority,
  l.source_basis,
  jsonb_build_object(
    'clear', coalesce(jsonb_agg(jsonb_build_object(
      'element_key', e.element_key,
      'element_name', e.element_name,
      'element_kind', e.element_kind,
      'sequence_group', e.sequence_group,
      'sequence_ordinal', e.sequence_ordinal,
      'statement', e.statement,
      'functional_role', e.functional_role,
      'does_not_establish', e.does_not_establish,
      'evidence_needed', e.evidence_needed,
      'metadata', e.metadata
    ) order by e.sequence_ordinal, e.element_key) filter (where e.clarity_state='clear' and e.status='active'), '[]'::jsonb),
    'fuzzy', coalesce(jsonb_agg(jsonb_build_object(
      'element_key', e.element_key,
      'element_name', e.element_name,
      'element_kind', e.element_kind,
      'sequence_group', e.sequence_group,
      'sequence_ordinal', e.sequence_ordinal,
      'statement', e.statement,
      'functional_role', e.functional_role,
      'does_not_establish', e.does_not_establish,
      'evidence_needed', e.evidence_needed,
      'metadata', e.metadata
    ) order by e.sequence_ordinal, e.element_key) filter (where e.clarity_state='fuzzy' and e.status='active'), '[]'::jsonb),
    'missing', coalesce(jsonb_agg(jsonb_build_object(
      'element_key', e.element_key,
      'element_name', e.element_name,
      'element_kind', e.element_kind,
      'sequence_group', e.sequence_group,
      'sequence_ordinal', e.sequence_ordinal,
      'statement', e.statement,
      'functional_role', e.functional_role,
      'does_not_establish', e.does_not_establish,
      'evidence_needed', e.evidence_needed,
      'metadata', e.metadata
    ) order by e.sequence_ordinal, e.element_key) filter (where e.clarity_state='missing' and e.status='active'), '[]'::jsonb)
  ) as context_packet,
  l.updated_at
from draft.noel_context_lenses l
left join draft.noel_context_lens_elements e on e.lens_id=l.lens_id
where l.status='active'
group by l.lens_id, l.lens_key, l.lens_name, l.lens_kind, l.scope, l.authority_level,
         l.inheritance_mode, l.summary, l.application_rule, l.non_forcing_boundary,
         l.priority, l.source_basis, l.updated_at;

create or replace view intelligence.v_noel_research_object_index_v6 as
select * from intelligence.v_noel_research_object_index_v5
union all
select
  'context_lens'::text as object_type,
  l.lens_key as object_id,
  'noel_context_lens'::text as object_family,
  l.lens_name as display_name,
  l.summary,
  l.status,
  l.authority_level as clarity_state,
  concat_ws(' ', l.lens_key, l.lens_name, l.lens_kind, l.scope, l.authority_level, l.inheritance_mode,
            l.summary, l.application_rule, l.non_forcing_boundary, l.notes, l.source_basis::text) as search_text,
  l.updated_at,
  jsonb_build_object(
    'lens_kind', l.lens_kind,
    'scope', l.scope,
    'authority_level', l.authority_level,
    'inheritance_mode', l.inheritance_mode,
    'application_rule', l.application_rule,
    'non_forcing_boundary', l.non_forcing_boundary,
    'priority', l.priority,
    'source_basis', l.source_basis,
    'notes', l.notes
  ) as metadata
from draft.noel_context_lenses l
where l.status <> 'retired'
union all
select
  'context_lens_element'::text as object_type,
  l.lens_key || ':' || e.element_key as object_id,
  'noel_context_lens'::text as object_family,
  e.element_name as display_name,
  e.statement as summary,
  e.status,
  e.clarity_state,
  concat_ws(' ', l.lens_key, l.lens_name, e.element_key, e.element_name, e.element_kind,
            e.sequence_group, e.clarity_state, e.statement, e.functional_role,
            e.does_not_establish, e.evidence_needed, e.metadata::text) as search_text,
  e.updated_at,
  jsonb_build_object(
    'lens_key', l.lens_key,
    'element_kind', e.element_kind,
    'sequence_group', e.sequence_group,
    'sequence_ordinal', e.sequence_ordinal,
    'functional_role', e.functional_role,
    'does_not_establish', e.does_not_establish,
    'evidence_needed', e.evidence_needed,
    'metadata', e.metadata
  ) as metadata
from draft.noel_context_lens_elements e
join draft.noel_context_lenses l on l.lens_id=e.lens_id
where l.status <> 'retired' and e.status <> 'retired';

create or replace function intelligence.search_noel_research_objects_v1(p_query text, p_limit integer default 12)
returns table(object_type text, object_id text, object_family text, display_name text, summary text, status text, clarity_state text, score numeric)
language sql
stable
set search_path to 'pg_catalog', 'intelligence', 'draft'
as $function$
  with q as (
    select lower(btrim(p_query)) as needle
  ), scored as (
    select
      i.object_type,
      i.object_id,
      i.object_family,
      i.display_name,
      i.summary,
      i.status,
      i.clarity_state,
      (
        case when lower(i.display_name) = q.needle then 100 else 0 end
        + case when lower(i.object_id) = q.needle then 95 else 0 end
        + case when lower(i.display_name) like q.needle || '%' then 55 else 0 end
        + case when lower(i.display_name) like '%' || q.needle || '%' then 35 else 0 end
        + case when lower(i.search_text) like '%' || q.needle || '%' then 20 else 0 end
        + (ts_rank(to_tsvector('simple', coalesce(i.search_text,'')), plainto_tsquery('simple', q.needle)) * 25)::numeric
      )::numeric as score
    from intelligence.v_noel_research_object_index_v6 i
    cross join q
    where q.needle <> ''
      and (
        lower(i.display_name) like '%' || q.needle || '%'
        or lower(i.object_id) like '%' || q.needle || '%'
        or lower(i.search_text) like '%' || q.needle || '%'
        or to_tsvector('simple', coalesce(i.search_text,'')) @@ plainto_tsquery('simple', q.needle)
      )
  )
  select * from scored
  order by score desc, display_name
  limit least(greatest(coalesce(p_limit,12),1),50);
$function$;

insert into draft.noel_operator_rules (
  rule_key, rule_name, rule_category, rule_level, rule_text, use_when,
  failure_if_ignored, status, priority, notes
)
values (
  'sacred_time_state_transition_inheritance_contract_v1',
  'Sacred Time / State Transition Inheritance Contract',
  'canon_context',
  'constitutional',
  'When Noel handles appointed time, calendar, Sabbath, feast, celestial time markers, readiness, time-gated access, release, Jubilee, or other canonically timed operations, inherit the active Sacred Time / State Transition context packet. Apply clear elements as constraints; keep fuzzy elements labeled working; keep missing elements open. Do not force a feast-specific symbolic meaning, physical month-head marker, day-boundary rule, counting convention, civil calendar, or historical synchronization merely to produce a neat answer. The canonically governed state, operation, custody, sequence, and relation outrank later calendar convenience.',
  'Use before calendar arithmetic and before any interpretation that treats a time marker as autonomous source, diagnosis, or complete meaning.',
  'Without this lens Noel can fragment the feast cycle into isolated dates, let astronomy or a modern calendar silently become authority, overstate arithmetic certainty, or erase the operational state transitions that sacred time actually governs.',
  'active',
  2500,
  'Backed by intelligence.v_noel_active_context_packet and indexed through intelligence.v_noel_research_object_index_v6.'
)
on conflict (rule_key) do update set
  rule_name=excluded.rule_name,
  rule_category=excluded.rule_category,
  rule_level=excluded.rule_level,
  rule_text=excluded.rule_text,
  use_when=excluded.use_when,
  failure_if_ignored=excluded.failure_if_ignored,
  status=excluded.status,
  priority=excluded.priority,
  notes=excluded.notes,
  updated_at=now();

update draft.research_claims
set
  claim_title='Canonical Appointed-Time Calculation — State/Rule First, Projection Second',
  short_claim='To calculate a biblical appointed time, first establish the canonically governed state, operation, month/day relation, or counted transition. Only after that may Noel project the result into a Gregorian or other civil date through an explicitly named calendar basis. A civil date is an output of a selected model, not the identity or source of the appointed state.',
  revision_note='2026-09-11: revised under Sacred Time / State Transition lens so coordinate arithmetic does not outrank state, operation, or unresolved calendar mechanics.',
  what_it_says_yes_to='Canonical states, operations, month/day relations, sequence, and counted intervals may be stated directly; model-specific civil projections may be calculated when assumptions and unresolved inputs are named.',
  what_it_says_no_to='Noel may not silently equate biblical appointed time with a modern fixed calendar, conjunction, crescent rule, local sighting system, Gregorian date, or arithmetic convention.',
  updated_at=now()
where claim_key='canon_appointed_time_calculation_architecture_v1';

update draft.research_claims
set
  short_claim='Passover is fixed textually to the fourteenth day of the first month at evening. A separate second-month Passover exists only for the stated delayed-participation conditions. Civil-date conversion depends on the chosen first-month and day-boundary model; Noel should preserve the canonical coordinate rather than converting it to an elapsed-day offset as though that offset were itself the rule.',
  revision_note='2026-09-11: removed the unnecessary “13 elapsed days after Day 1” arithmetic because the canonical rule is M1D14 at evening and civil offsets depend on the projection model.',
  what_it_says_yes_to='Primary Passover = Month 1 Day 14 at evening; conditional Second Passover = Month 2 Day 14 at evening for the stated cases.',
  what_it_says_no_to='Second Passover is not a general alternative date, and an elapsed-day or civil-date offset must not be presented as the canonical rule.',
  notes='Calculation relation only; execution/eligibility rules remain separate inputs. Revised to preserve Sacred Time / State Transition architecture.',
  updated_at=now()
where claim_key='canon_passover_calculation_v1';

update draft.research_claims
set
  short_claim='The Feast of Unleavened Bread occupies seven days beginning on the fifteenth day of the first month. Exodus states its eating boundary from the fourteenth day at evening until the twenty-first day at evening; Leviticus names Month 1 Day 15 as the feast start and preserves first- and seventh-day convocations. Noel should preserve those textual relations rather than replace them with a model-dependent elapsed-day offset.',
  revision_note='2026-09-11: removed model-dependent “14 days after Day 1 begins” arithmetic from the note-level calculation framing.',
  notes='The feast relation is M1D15-21 with explicit evening language in Exodus. Civil offsets belong to a named projection model, not the canonical identity.',
  updated_at=now()
where claim_key='canon_unleavened_bread_calculation_v1';

update draft.research_claims
set
  claim_title='Feast of Weeks — Canonical Count With Inherited Anchor Uncertainty',
  short_claim='Feast of Weeks is generated by a canonical count rather than an independent fixed month/day coordinate: Leviticus counts from the morrow after the sabbath associated with the wave sheaf through seven complete sabbaths/weeks to the morrow after the seventh; Deuteronomy begins seven weeks when the sickle is put to the standing grain. Noel must preserve the textual count and report separately any assumptions required to convert it into modern elapsed-day arithmetic.',
  revision_note='2026-09-11: removed the overconfident statement that the wave-sheaf day must be treated as arithmetic Day 1 yielding exactly 49 elapsed civil days later. The text-level count remains authoritative; modern arithmetic expression depends on the resolved anchor and counting/boundary convention.',
  evidence_needed='Resolve the inherited Firstfruits/Sabbath anchor and audit the count language before promoting a single civil-date arithmetic convention. Keep Leviticus 23 and Deuteronomy 16 in view together.',
  what_it_says_yes_to='Preserve the canonical count: seven complete sabbaths/weeks and the fiftieth-day endpoint in relation to the wave-sheaf/sickle-start anchor.',
  what_it_says_no_to='Do not assign a fixed modern month/day, a universal inclusive-count formula, or a civil elapsed-day offset independently of the unresolved anchor and counting/boundary assumptions.',
  confidence='high_working',
  notes='Weeks inherits the Firstfruits anchor. Textual count, anchor identity, and civil-date arithmetic must be reported as separate layers.',
  updated_at=now()
where claim_key='canon_feast_of_weeks_calculation_v1';

update draft.noel_operator_rules
set
  rule_text='When Noel answers how to calculate a biblical feast or appointed time, inherit the active Sacred Time / State Transition context first. Present the canonically governed state, operation, sequence, coordinate, or counted relation before any modern civil-date projection. State required anchors such as first-month/Abib state, relevant month head, harvest/wave-sheaf relation, or counted interval. A Gregorian or other civil date may be calculated only from an explicitly named projection basis. Because the physical marker for rosh chodesh remains unresolved (claim 162), Noel must not silently choose conjunction, predicted crescent, observed crescent, a modern fixed Jewish calendar, or another authority. Firstfruits must preserve the unresolved “morrow after the sabbath” anchor. Weeks inherits that unresolved anchor and must preserve the canonical count language; any modern elapsed-day conversion must name its counting and day-boundary assumptions rather than being treated as the text itself. Preserve explicit evening boundaries where the canon states them, but do not universalize a day-boundary rule beyond the evidence. Distinguish Passover, Unleavened Bread, Wave Sheaf/Firstfruits, Weeks, Month-7 Day-1 blasting memorial, Atonement, Booths, the Eighth Day, weekly Sabbath, and the conditional Second Passover.',
  failure_if_ignored='Noel can fragment sacred time into isolated dates, give a false appearance of biblical certainty by importing an unstated calendar or counting model, hide the Abib/harvest/custody inputs, or produce a Feast of Weeks civil date from an unacknowledged anchor or arithmetic convention.',
  notes='Revised 2026-09-11 to inherit Sacred Time / State Transition context and remove overconfident elapsed-day arithmetic.',
  updated_at=now()
where rule_key='appointed_time_calculation_output_contract_v1';

commit;
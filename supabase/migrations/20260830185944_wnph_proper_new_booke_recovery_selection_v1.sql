-- WNPH A Proper New Booke of Cookery recovery selection v1.
-- Establishes the qualified 1575 recovery Expression identity, binds it into the qualifying plan,
-- designates the governed 1575 scan as preferred historical source, creates a canonical
-- manifestation-agnostic Publication Source Package, and explicitly selects the recovery.
-- No text is admitted by this migration.

do $$
declare
  v_case uuid;
  v_work uuid;
  v_expression uuid;
  v_decision uuid;
  v_expression_target uuid;
  v_surrogate uuid;
  v_preferred_target uuid;
  v_package uuid;
  v_event uuid;
begin
  select id,work_id into strict v_case,v_work
  from wnph.recovery_cases
  where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1';

  select d.id into strict v_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and d.decision_outcome='qualify'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id);

  insert into wnph.expressions(
    canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary
  ) values(
    'proper-new-booke-of-cookery:wnph-1575-reading-e1',
    v_work,
    'verified_witness_reading_expression',
    'en',
    'established',
    'high',
    'WNPH recovery Expression identity for the governed 1575 witness. Establishment here fixes the recovery scope and witness identity; it does not assert that any reading text has yet been admitted. Text must enter through source-linked verification against the 1575 page images, and other sixteenth-century edition states may not be silently blended into this Expression.'
  ) returning id into v_expression;

  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,expression_id,rationale
  ) values(
    v_case,'candidate',v_expression,
    'Expression target created by the qualifying Recovery Decision: exact 1575 witness reading Expression, not a cross-edition composite.'
  ) returning id into v_expression_target;

  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_target_id
  ) values(v_decision,'source_target',v_expression_target);

  select s.id into strict v_surrogate
  from wnph.surrogates s
  where s.canonical_key='proper-new-booke-of-cookery:commons-ia-1575';

  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,surrogate_id,rationale
  ) values(
    v_case,'preferred_source',v_surrogate,
    'Preferred historical recovery source for the qualified 1575 Expression. This designation selects the governed Commons/Internet Archive page-image surrogate as the source against which reading text must be verified; Wikisource remains comparison material only.'
  ) returning id into v_preferred_target;

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,
    package_role,source_model,model_version,package_status,render_contract,notes
  ) values(
    'proper-new-booke-of-cookery:1575-canonical-publication-source:v1',
    v_case,
    v_expression,
    v_decision,
    'canonical_master',
    'semantic_single_source',
    '1',
    'planned',
    jsonb_build_object(
      'single_source_publishing',true,
      'manifestation_agnostic',true,
      'canonical_layers',jsonb_build_array('witness_structure','verified_text','metadata','provenance'),
      'supported_by_design',jsonb_build_array('responsive_web','reflowable_epub','fixed_layout_epub','print_pdf','paperback','hardcover','future_output_families'),
      'output_family_vocab_open',true,
      'renderer_rule','Downstream renderers may transform presentation and packaging but may not fork, modernize, normalize, or silently alter the canonical 1575 witness reading Expression. Functional recipe semantics must remain a separately governed derived layer.'
    ),
    'Canonical source package for the qualified 1575 witness recovery. The package begins empty of admitted reading text; selection authorizes recovery work, not automatic promotion of Wikisource/OCR or any other derivative into canonical text.'
  ) returning id into v_package;

  select e.id into strict v_event
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);

  if (select to_state from wnph.recovery_case_events where id=v_event) <> 'QUALIFIED' then
    raise exception 'Proper New Booke selection expected QUALIFIED leaf';
  end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_event,'QUALIFIED','SELECTED_FOR_RECOVERY','selection',
    'Explicitly select the exact 1575 witness reading recovery. The preferred historical source is the governed Commons/Internet Archive 1575 scan and the canonical manifestation-agnostic Publication Source Package is established. Selection does not admit any text; reconstruction must still pass source-image verification and canonical-text custody.',
    'wnph:proper-new-booke-selection-v1',true
  );
end $$;
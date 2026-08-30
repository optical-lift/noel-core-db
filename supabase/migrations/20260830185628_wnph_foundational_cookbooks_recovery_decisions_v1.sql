-- WNPH foundational cookbook Recovery Decisions v1.
-- Converts completed factual condition assessments into distinct publishing-recovery judgments.
-- No case is selected for production here. Qualification is not publication selection.

do $$
declare
  v_case uuid;
  v_event uuid;
  v_next uuid;
  v_decision uuid;
  v_obs uuid;
  v_ssa uuid;
  v_rights uuid;
  v_audit uuid;
  v_old_brief uuid;
  v_new_brief uuid;
  v_mode uuid;
  v_new_mode uuid;
  v_target uuid;
begin
  -- THE FORME OF CURY: more evidence is needed before deciding what historical text WNPH would actually recover.
  select id into strict v_case from wnph.recovery_cases where canonical_key='forme-of-cury:foundational-cookbook-recovery-1';
  select e.id into strict v_event from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_event) <> 'CONDITION_ASSESSED' then
    raise exception 'Forme of Cury decision expected CONDITION_ASSESSED leaf';
  end if;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition','Review whether WNPH should recover Pegge''s 1780 editorial witness, a medieval manuscript witness, or a separately governed critical reading expression.','wnph:foundational-cookbooks-decisions-v1') returning id into v_event;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,'more_evidence_needed',
    'Decide whether the current recovery case is for Samuel Pegge''s 1780 editorial manifestation or for a source-governed medieval-text Expression of The Forme of Cury. Do not collapse those into one recovery object.',
    'Modern recovery is not absent: a competent multi-manuscript critical edition exists and Pegge''s 1780 text is available in facsimile, reprint, and reflowable transcription. The unresolved issue is the historical text WNPH would claim to recover. The current governed primary source is Pegge''s 1780 editorial witness, not a medieval manuscript surrogate. Before qualifying a medieval-text recovery, WNPH needs direct manuscript-level source custody or another rights-cleared historical witness basis sufficient to identify the intended Expression. Pegge''s 1780 edition may later be evaluated as its own explicitly editorial-witness recovery.'
  ) returning id into v_decision;

  select a.id into strict v_ssa from wnph.source_sufficiency_assessments a where a.recovery_case_id=v_case and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note)
  values(v_decision,'supports',v_ssa,'The current source set is sufficient for Pegge''s 1780 witness but is deliberately bounded against manuscript-level claims.');
  select a.id into strict v_audit from wnph.existing_recovery_audits a where a.recovery_case_id=v_case and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note)
  values(v_decision,'context',v_audit,'The complete bounded audit establishes competent scholarly recovery and existing Pegge-lineage access, so absence alone cannot justify a new edition.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='text_integrity' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
  values(v_decision,'limits',v_obs,'Textual basis remains conflicted among Pegge''s editorial transcription, later reflow derivatives, and modern multi-manuscript critical recovery.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='edition_relationship_clarity' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
  values(v_decision,'limits',v_obs,'The 1780 editorial manifestation cannot stand silently for the entire medieval textual tradition.');

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'DECISION_REVIEW','MORE_EVIDENCE_NEEDED','decision','Do not qualify a medieval-text recovery until the intended historical Expression has a source basis that does not collapse Pegge''s 1780 editorial witness into the medieval manuscript tradition.','wnph:foundational-cookbooks-decisions-v1');

  -- A PROPER NEW BOOKE OF COOKERY: qualify the exact 1575 witness recovery, not a mixed early-modern composite.
  select id into strict v_case from wnph.recovery_cases where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1';
  select e.id into strict v_event from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_event) <> 'CONDITION_ASSESSED' then
    raise exception 'Proper New Booke decision expected CONDITION_ASSESSED leaf';
  end if;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition','Review the bounded exact-1575-witness recovery condition exposed by the completed audit.','wnph:foundational-cookbooks-decisions-v1') returning id into v_event;

  select b.id into strict v_old_brief from wnph.recovery_case_briefs b where b.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_briefs n where n.supersedes_brief_id=b.id);
  insert into wnph.recovery_case_briefs(recovery_case_id,scope_note,why_recover,proposed_expression_type,priority,supersedes_brief_id)
  values(
    v_case,
    'Recover the governed 1575 witness as its own verified reading Expression: preserve original language and witness structure, produce a source-linked transcription verified against the page images, and keep recipe normalization or functional translation in a separate downstream semantic layer.',
    'The 1575 facsimile survives and a public transcription exists, but the bounded audit did not establish a fully validated, source-linked, accessible reading edition of this exact witness. A recovery can therefore add distinct value without pretending the Work itself is lost.',
    'verified_1575_witness_reading_expression','high',v_old_brief
  ) returning id into v_new_brief;

  select m.id into strict v_mode from wnph.recovery_case_modes m where m.recovery_case_id=v_case and m.recovery_mode='text' and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);
  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id)
  values(v_case,'text','committed','Recover a verified reading text of the exact governed 1575 witness without silently importing readings from other early editions.',v_mode) returning id into v_new_mode;
  v_mode := v_new_mode;
  select m.id into strict v_mode from wnph.recovery_case_modes m where m.recovery_case_id=v_case and m.recovery_mode='transcription' and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);
  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id)
  values(v_case,'transcription','committed','Verify the reading text directly against the 1575 page-image surrogate with source locators and explicit uncertainty where the image does not support a secure reading.',v_mode) returning id into v_new_mode;
  v_mode := v_new_mode;
  select m.id into strict v_mode from wnph.recovery_case_modes m where m.recovery_case_id=v_case and m.recovery_mode='witness' and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);
  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id)
  values(v_case,'witness','committed','Preserve the 1575 witness as a distinct historical state; edition conflation is outside the qualified scope.',v_mode) returning id into v_new_mode;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,'qualify',
    'Qualify a source-linked verified reading Expression of the governed 1575 witness only. Preserve its witness identity, original language, ordering, and historical structure. Do not normalize recipes, modernize instructions, or merge other sixteenth-century states into this Expression.',
    'The exact 1575 witness has adequate facsimile survival and cleared rights, but its available public transcription remains incompletely validated and no bounded evidence established a polished exact-witness reading edition. That is a real, narrow recovery condition. WNPH therefore qualifies recovery of the 1575 witness as a verified text/transcription/witness Expression. Functional recipe translation, ingredient normalization, and cross-edition collation remain separate downstream work, and no publication Manifestation is selected by this decision.'
  ) returning id into v_decision;

  select a.id into strict v_ssa from wnph.source_sufficiency_assessments a where a.recovery_case_id=v_case and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note)
  values(v_decision,'supports',v_ssa,'The governed 1575 page-image surrogate is sufficient to support exact-witness recovery while keeping page-level verification requirements explicit.');
  select d.id into strict v_rights from wnph.rights_determinations d where d.recovery_case_id=v_case and d.jurisdiction='US' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,rights_determination_id,basis_note)
  values(v_decision,'supports',v_rights,'Current U.S. rights are cleared for the historical work and governed mechanical-scan source images.');
  select a.id into strict v_audit from wnph.existing_recovery_audits a where a.recovery_case_id=v_case and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note)
  values(v_decision,'supports',v_audit,'The completed bounded audit identifies a facsimile, partial public transcription, and earlier scholarly recovery without establishing a fully validated exact-1575 reading edition.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='text_integrity' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
  values(v_decision,'supports',v_obs,'Unverified exact-witness text integrity is the content-level condition this recovery will resolve.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='edition_relationship_clarity' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
  values(v_decision,'limits',v_obs,'The qualified Expression must remain 1575-specific and may not silently blend other sixteenth-century states.');

  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_brief_id)
  values(v_decision,'scope',v_new_brief);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_mode_id)
  select v_decision,'mode',m.id from wnph.recovery_case_modes m where m.recovery_case_id=v_case and m.intent_status='committed' and m.recovery_mode in ('text','transcription','witness') and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);
  select t.id into strict v_target from wnph.recovery_case_targets t where t.recovery_case_id=v_case and t.target_role='primary_source' and t.surrogate_id is not null and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_target_id)
  values(v_decision,'source_target',v_target);

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'DECISION_REVIEW','QUALIFIED','decision','Qualify exact-1575 verified text/transcription/witness recovery. This is an Expression-level recovery decision only; no preferred production source package or output Manifestation is selected here.','wnph:foundational-cookbooks-decisions-v1');

  -- MARIA RUNDELL: defer the generic text-recovery case because ordinary modern reading recovery is already adequate.
  select id into strict v_case from wnph.recovery_cases where canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1';
  select e.id into strict v_event from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_event) <> 'CONDITION_ASSESSED' then
    raise exception 'Rundell decision expected CONDITION_ASSESSED leaf';
  end if;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition','Review whether a generic source-faithful text recovery adds material value beyond the competent existing 1807 reflowable reading edition.','wnph:foundational-cookbooks-decisions-v1') returning id into v_event;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,'defer',
    'Decide only the current proposal for a generic source-faithful text/transcription recovery of the 1807 Boston witness. Preserve the Work and source custody for later semantic, provenance, or functional-translation research.',
    'Project Gutenberg already supplies a competent freely reflowable 1807 reading edition derived from the governed Internet Archive source, and the source facsimile itself is richly available. WNPH therefore does not currently need another ordinary text/ebook recovery. The case is deferred rather than declined because a materially different scope may later justify recovery: page-image-verified diplomatic provenance, cross-edition transmission work, or a functional historical translation that converts period household instructions into governed modern operational meaning while retaining the historical source layer.'
  ) returning id into v_decision;
  select a.id into strict v_ssa from wnph.source_sufficiency_assessments a where a.recovery_case_id=v_case and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note) values(v_decision,'context',v_ssa,'Recovery is technically possible; source weakness is not the reason for deferral.');
  select a.id into strict v_audit from wnph.existing_recovery_audits a where a.recovery_case_id=v_case and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note) values(v_decision,'limits',v_audit,'The complete audit establishes competent existing reflowable reading access to the exact 1807 edition.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='modern_recovery_adequacy' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note) values(v_decision,'limits',v_obs,'Ordinary modern reading and ebook recovery is already adequate.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='text_integrity' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note) values(v_decision,'context',v_obs,'Exact diplomatic provenance remains more limited than general reading quality and could support a future narrower case.');
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'DECISION_REVIEW','DEFERRED_RECOVERY','decision','Defer generic text recovery because modern 1807 reading access is already competent. Reopen only for a materially distinct source-verification, transmission, or functional-translation scope.','wnph:foundational-cookbooks-decisions-v1');

  -- THE VIRGINIA HOUSE-WIFE: decline the generic recovery case because strong current scholarly/open-access recovery already exists.
  select id into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:foundational-cookbook-recovery-1';
  select e.id into strict v_event from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_event) <> 'CONDITION_ASSESSED' then
    raise exception 'Virginia House-Wife decision expected CONDITION_ASSESSED leaf';
  end if;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition','Review whether WNPH should duplicate a Work that already has strong current scholarly, facsimile, commercial ebook, and open-access recovery.','wnph:foundational-cookbooks-decisions-v1') returning id into v_event;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,'decline',
    'Decide the current generic source-faithful recovery proposal for The Virginia House-Wife. This decision does not remove the 1824 source from WNPH research custody and does not prohibit a future separately scoped exact-witness or functional-semantic project.',
    'A generic WNPH reading-edition recovery would duplicate strong existing work. The 1824 first-edition facsimile is available at LOC, Andrews McMeel provides modern facsimile/ebook access, and the 2025 University of South Carolina Press edition supplies an authoritative collated text of the early editions, historical commentary, a complete facsimile, and open-access ebook availability. WNPH therefore declines this recovery case as currently scoped. The governed 1824 witness remains valuable as a historical source for corpus comparison or a future functional-semantic layer, but that would be a distinct project rather than a justification for republishing another general reading edition.'
  ) returning id into v_decision;
  select a.id into strict v_audit from wnph.existing_recovery_audits a where a.recovery_case_id=v_case and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note) values(v_decision,'contradicts',v_audit,'The complete audit contradicts the premise of a broad modern-recovery deficiency.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='modern_recovery_adequacy' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note) values(v_decision,'contradicts',v_obs,'Modern scholarly, print, ebook, and open-access recovery is already adequate.');
  select o.id into strict v_obs from wnph.recovery_condition_observations o join wnph.recovery_condition_assessments a on a.id=o.assessment_id join wnph.recovery_condition_types t on t.id=o.condition_type_id where a.recovery_case_id=v_case and t.canonical_key='modern_reading_edition' and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note) values(v_decision,'contradicts',v_obs,'A strong current scholarly reading edition already exists.');
  select d.id into strict v_rights from wnph.rights_determinations d where d.recovery_case_id=v_case and d.jurisdiction='US' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id);
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,rights_determination_id,basis_note) values(v_decision,'context',v_rights,'Rights permit recovery, but permission alone is not a reason to duplicate competent existing recovery.');
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_event,'DECISION_REVIEW','DECLINED_RECOVERY','decision','Decline the generic recovery proposal because competent current scholarly and open-access recovery already exists. Preserve source custody for research and any future distinctly scoped project.','wnph:foundational-cookbooks-decisions-v1');
end $$;
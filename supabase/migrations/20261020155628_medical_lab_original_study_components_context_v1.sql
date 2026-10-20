do $patch$ declare v_ddl text; begin
v_ddl := pg_get_functiondef('intelligence.get_noel_medical_lab_context_v1(text)'::regprocedure);
if position($needle$    'scientific_evidence',$needle$ in v_ddl)=0 then raise exception 'Expected context function anchor missing'; end if;
v_ddl := replace(v_ddl,$needle$    'scientific_evidence',$needle$,$insert$    'study_observation_total',(select count(*) from draft.research_observations where trail_id=23 and observation_type like 'original_study_%'),
    'original_study_components',(select coalesce(jsonb_agg(jsonb_build_object('observation_id',s.observation_id,'kind',s.observation_type,'title',s.observation_title,'measured_or_reported',s.observation_text,'investigator_mechanism_or_unknown',s.mechanism_claim,'interpretive_limit',s.interpretation_note,'source',s.source_reference,'status',s.status) order by s.observation_id),'[]'::jsonb)
      from (select * from draft.research_observations where trail_id=23 and observation_type like 'original_study_%' order by observation_id desc limit 40) s),
    'scientific_evidence',$insert$);
execute v_ddl;
end $patch$;
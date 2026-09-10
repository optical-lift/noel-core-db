begin;

-- Correct the live Gate 3 vertical-slice task by stable Company Work identity.
-- The organization record currently carrying Elm work is not named "Elm Farm",
-- so the prior name-qualified update intentionally matched nothing.
update atlas.work_items
set result_contract_key='ordinary_company_work_worker_attestation_v1',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'completionAuthority','delegated_worker_attestation',
      'secondManagerClickRequired',false
    ),
    updated_at=now()
where stable_key='elm_pot_shasta_2026_09_09'
  and work_state='open';

commit;

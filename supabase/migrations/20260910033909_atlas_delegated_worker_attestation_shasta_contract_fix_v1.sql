begin;
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
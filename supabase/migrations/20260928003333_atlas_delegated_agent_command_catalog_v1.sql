create or replace function atlas.delegated_agent_command_catalog_service_v1(p_token_hash text)
returns table(
  command_key text,
  command_version integer,
  label text,
  execution_class text,
  confirmation_required boolean,
  input_contract jsonb,
  target_contract jsonb
)
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select d.command_key,
         d.command_version,
         d.label,
         d.execution_class,
         (
           d.confirmation_requirement = 'principal_explicit'
           or (
             coalesce((a.confirmation_policy->>'forceAllCommits')::boolean,false)
             and d.execution_class = 'commit'
           )
           or (
             a.confirmation_policy ? 'forceConfirmationCommandKeys'
             and (a.confirmation_policy->'forceConfirmationCommandKeys') ? d.command_key
           )
         ) as confirmation_required,
         d.input_contract,
         d.target_contract
  from atlas.delegated_agent_credentials c
  join atlas.delegated_agent_authorizations a on a.id=c.authorization_id
  join atlas.agent_command_definitions d
    on d.command_key=any(a.allowed_command_keys)
   and d.status='active'
  where c.token_hash=lower(p_token_hash)
    and c.credential_state='active'
    and now()>=c.begins_at
    and (c.expires_at is null or now()<c.expires_at)
    and a.authorization_state='active'
    and now()>=a.begins_at
    and (a.ends_at is null or now()<a.ends_at)
    and not (d.command_key=any(a.denied_command_keys))
    and atlas.execution_class_rank_v1(d.execution_class)<=atlas.execution_class_rank_v1(a.max_execution_class)
  order by d.command_key,d.command_version;
$$;

revoke all on function atlas.delegated_agent_command_catalog_service_v1(text) from public,anon,authenticated;
grant execute on function atlas.delegated_agent_command_catalog_service_v1(text) to service_role;
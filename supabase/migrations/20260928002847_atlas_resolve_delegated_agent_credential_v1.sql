create or replace function atlas.resolve_delegated_agent_credential_service_v1(p_token_hash text)
returns jsonb
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select jsonb_build_object(
    'credentialId', c.id,
    'authorizationId', a.id,
    'carrierId', a.carrier_id,
    'principalId', a.principal_id,
    'ledgerId', a.ledger_id,
    'delegatingSeatId', a.delegating_seat_id,
    'credentialState', c.credential_state,
    'authorizationState', a.authorization_state,
    'credentialExpiresAt', c.expires_at,
    'authorizationEndsAt', a.ends_at
  )
  from atlas.delegated_agent_credentials c
  join atlas.delegated_agent_authorizations a on a.id = c.authorization_id
  where c.token_hash = lower(p_token_hash)
    and c.credential_state = 'active'
    and now() >= c.begins_at
    and (c.expires_at is null or now() < c.expires_at)
    and a.authorization_state = 'active'
    and now() >= a.begins_at
    and (a.ends_at is null or now() < a.ends_at)
  limit 1;
$$;
-- Materialize the verified implementation setup sponsor as the temporary setup actor
-- for the organization created during practitioner implementation.
--
-- This does not create membership, ownership, or Principal identity. It gives the person
-- who was explicitly verified as the setup sponsor the existing temporary organization
-- onboarding carrier needed to authorize organization-owned source connections.

create or replace function atlas.materialize_implementation_setup_actor_from_binding_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_human_user_id uuid;
begin
  if new.organization_id is null or new.implementation_case_id is null or new.ended_at is not null then
    return new;
  end if;

  select participant.human_user_id
    into v_human_user_id
  from atlas.implementation_case_participants participant
  where participant.implementation_case_id = new.implementation_case_id
    and participant.relationship_kind = 'setup_sponsor'
    and participant.active
    and participant.human_user_id is not null
  order by participant.started_at desc, participant.id
  limit 1;

  if v_human_user_id is null then
    return new;
  end if;

  insert into atlas.organization_onboarding_actors (
    organization_id,
    human_user_id,
    actor_kind,
    active,
    started_at,
    ended_at,
    metadata
  ) values (
    new.organization_id,
    v_human_user_id,
    'setup_actor',
    true,
    now(),
    null,
    jsonb_build_object(
      'source','implementation_setup_sponsor_scope_binding',
      'implementationCaseId',new.implementation_case_id,
      'ledgerEntitlementBindingId',new.id,
      'relationship','setup_sponsor'
    )
  )
  on conflict (organization_id, human_user_id) do update
  set active = true,
      ended_at = null,
      metadata = atlas.organization_onboarding_actors.metadata || excluded.metadata;

  return new;
end;
$function$;

comment on function atlas.materialize_implementation_setup_actor_from_binding_v1() is
'Internal consequence of implementation organization-scope binding: the verified active setup sponsor becomes that organization''s temporary setup_actor without receiving membership or ownership.';

revoke all on function atlas.materialize_implementation_setup_actor_from_binding_v1() from public, anon, authenticated, service_role;

drop trigger if exists materialize_implementation_setup_actor_from_binding_v1
  on atlas.ledger_entitlement_bindings;

create trigger materialize_implementation_setup_actor_from_binding_v1
after insert or update of organization_id, ended_at
on atlas.ledger_entitlement_bindings
for each row
when (new.organization_id is not null and new.implementation_case_id is not null and new.ended_at is null)
execute function atlas.materialize_implementation_setup_actor_from_binding_v1();

-- Reconcile any already-bound implementation whose verified setup sponsor predates this consequence.
insert into atlas.organization_onboarding_actors (
  organization_id,
  human_user_id,
  actor_kind,
  active,
  started_at,
  ended_at,
  metadata
)
select
  binding.organization_id,
  sponsor.human_user_id,
  'setup_actor',
  true,
  now(),
  null,
  jsonb_build_object(
    'source','implementation_setup_sponsor_scope_binding_backfill',
    'implementationCaseId',binding.implementation_case_id,
    'ledgerEntitlementBindingId',binding.id,
    'relationship','setup_sponsor'
  )
from atlas.ledger_entitlement_bindings binding
join lateral (
  select participant.human_user_id
  from atlas.implementation_case_participants participant
  where participant.implementation_case_id = binding.implementation_case_id
    and participant.relationship_kind = 'setup_sponsor'
    and participant.active
    and participant.human_user_id is not null
  order by participant.started_at desc, participant.id
  limit 1
) sponsor on true
where binding.organization_id is not null
  and binding.ended_at is null
on conflict (organization_id, human_user_id) do update
set active = true,
    ended_at = null,
    metadata = atlas.organization_onboarding_actors.metadata || excluded.metadata;

alter table ledger.onboarding_cases
  add column case_kind text not null default 'practitioner_onboarding'
  check (case_kind in ('practitioner_onboarding','legacy_adjudicated_migration'));

create or replace function ledger.guard_onboarding_case_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_claimed uuid;
  v_claim_state text;
begin
  if new.requested_by_person_entity_id is not null then
    perform reality.assert_person_entity_v1(new.requested_by_person_entity_id);
  end if;

  if new.practitioner_person_entity_id is not null then
    perform reality.assert_person_entity_v1(new.practitioner_person_entity_id);
  end if;

  if new.verified_claim_id is not null then
    select claimed_entity_id,claim_state
    into v_claimed,v_claim_state
    from reality.entity_claims
    where id=new.verified_claim_id;

    if v_claimed is null
       or v_claimed<>new.subject_entity_id
       or v_claim_state<>'verified' then
      raise exception 'Onboarding claim must be verified and identify the Ledger subject Entity.'
        using errcode='23514';
    end if;
  end if;

  if new.case_kind='practitioner_onboarding'
     and new.onboarding_state in ('practitioner_assigned','in_progress','ready_to_activate','completed')
     and new.practitioner_person_entity_id is null then
    raise exception 'Practitioner is required once practitioner Ledger onboarding is assigned.'
      using errcode='23514';
  end if;

  if new.case_kind='legacy_adjudicated_migration' then
    if nullif(new.onboarding_basis->>'legacyLedgerId','') is null
       or coalesce((new.onboarding_basis->>'migrationAdjudicated')::boolean,false) is not true then
      raise exception 'Legacy Ledger migration requires an adjudicated legacy Ledger basis.'
        using errcode='23514';
    end if;
  end if;

  if new.onboarding_state='ready_to_activate' and new.ready_at is null then
    new.ready_at:=now();
  end if;

  return new;
end
$function$;

create or replace function ledger.guard_ledger_activation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_case ledger.onboarding_cases%rowtype;
begin
  select * into v_case
  from ledger.onboarding_cases
  where id=new.onboarding_case_id
  for update;

  if v_case.id is null then
    raise exception 'Ledger onboarding case required.' using errcode='23514';
  end if;

  if v_case.subject_entity_id<>new.subject_entity_id then
    raise exception 'Ledger subject must match onboarding subject.' using errcode='23514';
  end if;

  if v_case.onboarding_state<>'ready_to_activate' then
    raise exception 'Ledger may only activate from a ready onboarding case.'
      using errcode='23514';
  end if;

  if v_case.case_kind='practitioner_onboarding'
     and v_case.practitioner_person_entity_id is null then
    raise exception 'New Ledger activation requires practitioner onboarding.'
      using errcode='23514';
  end if;

  if v_case.case_kind='legacy_adjudicated_migration'
     and (
       nullif(v_case.onboarding_basis->>'legacyLedgerId','') is null
       or coalesce((v_case.onboarding_basis->>'migrationAdjudicated')::boolean,false) is not true
     ) then
    raise exception 'Legacy Ledger migration is not adjudicated.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

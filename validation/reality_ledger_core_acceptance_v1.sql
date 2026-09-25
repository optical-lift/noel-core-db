-- Atlas Reality / Ledger constitutional acceptance proof v1.
-- Rollback-safe. Creates only synthetic rows inside a transaction.

begin;

create temporary table _proof(
  personal_atlas_created boolean,
  direct_ledger_blocked boolean,
  claim_route_guarded boolean,
  seat_person_guarded boolean,
  exposure_chain_ok boolean,
  legacy_fk_count integer
) on commit drop;

do $proof$
declare
  v_person uuid:=gen_random_uuid();
  v_business uuid:=gen_random_uuid();
  v_other uuid:=gen_random_uuid();
  v_guild uuid:=gen_random_uuid();
  v_route uuid; v_wrong_route uuid; v_claim uuid;
  v_case uuid; v_guild_case uuid;
  v_ledger uuid; v_guild_ledger uuid; v_seat uuid; v_summary uuid; v_conn uuid;
  v_auth uuid;
  a boolean:=false; b boolean:=false; c boolean:=false; d boolean:=false; e boolean:=false;
  bad integer;
begin
  select id into v_auth from auth.users where deleted_at is null order by created_at limit 1;
  if v_auth is null then raise exception 'Acceptance proof requires one existing Auth user.'; end if;

  insert into reality.entities(id,stable_key,entity_kind,display_name) values
    (v_person,'proof-person-'||replace(v_person::text,'-',''),'person','Proof Person'),
    (v_business,'proof-business-'||replace(v_business::text,'-',''),'business','Proof Business'),
    (v_other,'proof-other-'||replace(v_other::text,'-',''),'business','Wrong Route Business'),
    (v_guild,'proof-guild-'||replace(v_guild::text,'-',''),'institution','Proof Guild');

  insert into reality.auth_person_bindings(auth_user_id,person_entity_id)
  values(v_auth,v_person);

  select exists(
    select 1 from personal.atlases
    where person_entity_id=v_person and native and atlas_state='active'
  ) into a;

  insert into reality.contact_routes(entity_id,route_kind,route_value,normalized_value)
  values(v_business,'email','proof@example.invalid','proof@example.invalid')
  returning id into v_route;

  insert into reality.contact_routes(entity_id,route_kind,route_value,normalized_value)
  values(v_other,'email','wrong@example.invalid','wrong@example.invalid')
  returning id into v_wrong_route;

  insert into reality.entity_claims(claimant_person_entity_id,claimed_entity_id,claim_state)
  values(v_person,v_business,'challenge_pending')
  returning id into v_claim;

  begin
    insert into reality.entity_claim_challenges(
      claim_id,contact_route_id,delivery_channel,delivery_target_snapshot
    ) values(v_claim,v_wrong_route,'email','wrong@example.invalid');
  exception when sqlstate '23514' then
    c:=true;
  end;

  insert into reality.entity_claim_challenges(
    claim_id,contact_route_id,delivery_channel,challenge_state,delivery_target_snapshot,verified_at
  ) values(v_claim,v_route,'email','verified','proof@example.invalid',now());

  update reality.entity_claims
  set claim_state='verified',verified_at=now()
  where id=v_claim;

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,verified_claim_id,
    practitioner_person_entity_id,desired_ledger_name,onboarding_state
  ) values(v_business,v_person,v_claim,v_person,'Proof Ledger','in_progress')
  returning id into v_case;

  begin
    insert into ledger.ledgers(subject_entity_id,onboarding_case_id,stable_key,name)
    values(v_business,v_case,'blocked-'||replace(v_case::text,'-',''),'Blocked');
  exception when sqlstate '23514' then
    b:=true;
  end;

  update ledger.onboarding_cases
  set onboarding_state='ready_to_activate'
  where id=v_case;

  insert into ledger.ledgers(subject_entity_id,onboarding_case_id,stable_key,name)
  values(v_business,v_case,'proof-ledger-'||replace(v_case::text,'-',''),'Proof Ledger')
  returning id into v_ledger;

  insert into ledger.seats(ledger_id,person_entity_id)
  values(v_ledger,v_person)
  returning id into v_seat;

  begin
    insert into ledger.seats(ledger_id,person_entity_id)
    values(v_ledger,v_other);
  exception when sqlstate '23514' then
    d:=true;
  end;

  insert into ledger.summaries(
    ledger_id,summary_kind,production_mode,produced_by_seat_id,payload
  ) values(
    v_ledger,'overview','seat_published',v_seat,'{"summary":"bird eye"}'::jsonb
  ) returning id into v_summary;

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
    desired_ledger_name,onboarding_state
  ) values(v_guild,v_person,v_person,'Guild Ledger','ready_to_activate')
  returning id into v_guild_case;

  insert into ledger.ledgers(subject_entity_id,onboarding_case_id,stable_key,name)
  values(
    v_guild,v_guild_case,
    'proof-guild-ledger-'||replace(v_guild_case::text,'-',''),
    'Guild Ledger'
  ) returning id into v_guild_ledger;

  insert into ledger.connections(source_ledger_id,observer_ledger_id)
  values(v_ledger,v_guild_ledger)
  returning id into v_conn;

  insert into ledger.exposures(connection_id,summary_id)
  values(v_conn,v_summary);

  select exists(
    select 1
    from ledger.exposures x
    join ledger.connections lc on lc.id=x.connection_id
    join ledger.summaries s on s.id=x.summary_id
    where lc.source_ledger_id=v_ledger
      and lc.observer_ledger_id=v_guild_ledger
      and s.ledger_id=v_ledger
  ) into e;

  select count(*) into bad
  from pg_constraint co
  join pg_class src on src.oid=co.conrelid
  join pg_namespace sn on sn.oid=src.relnamespace
  join pg_class dst on dst.oid=co.confrelid
  join pg_namespace dn on dn.oid=dst.relnamespace
  where co.contype='f'
    and sn.nspname in ('reality','personal','ledger','compatibility')
    and dn.nspname in ('atlas','local_intel');

  insert into _proof values(a,b,c,d,e,bad);
end
$proof$;

select * from _proof;

rollback;

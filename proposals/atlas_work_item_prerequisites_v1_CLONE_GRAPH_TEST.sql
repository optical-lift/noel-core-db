-- EXECUTE ONLY AFTER CANDIDATE DDL ON A DISPOSABLE CLONE.
-- Schema-only production clone contains no user records; this inserts 100%
-- synthetic fixtures. The entire test transaction ROLLS BACK unconditionally.
-- Do not execute against production or another user's staging database.
begin;
do $$
declare
  v_org uuid;
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_link_ab uuid;
  v_link_bc uuid;
  v_event uuid;
  v_kind text;
  v_msg text;
  v_rejected boolean;
begin
  insert into atlas.organizations(stable_key,name)
    values('clone-prereq-'||gen_random_uuid()::text,
           'Disposable prerequisite clone fixture')
    returning id into v_org;

  insert into atlas.work_items(organization_id,title,work_state)
    values(v_org,'Clone Work A','open') returning id into v_a;
  insert into atlas.work_items(organization_id,title,work_state)
    values(v_org,'Clone Work B','open') returning id into v_b;
  insert into atlas.work_items(organization_id,title,work_state)
    values(v_org,'Clone Work C','open') returning id into v_c;

  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
  values(v_org,v_a,v_b,'depends_on',true) returning id into v_link_ab;
  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
  values(v_org,v_b,v_c,'depends_on',true) returning id into v_link_bc;

  -- Existing semantics: unrelated edge vocabulary must not be changed by
  -- installing a guard for the single "depends_on" relation kind.
  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
  values(v_org,v_c,v_a,'blocks',true);
  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
  values(v_org,v_a,v_c,'completion_bundle_member',true);

  -- A->B->C exists; C->A is a cycle and must be rejected by OUR trigger.
  v_rejected:=false;
  begin
    insert into atlas.work_item_relations(
      organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
    values(v_org,v_c,v_a,'depends_on',true);
  exception when check_violation then
    get stacked diagnostics v_msg=message_text;
    if v_msg not like 'Prerequisite cycle%' then raise; end if;
    v_rejected:=true;
  end;
  if not v_rejected then
    raise exception 'REJECT: C->A should not have been admitted with A->B->C active.';
  end if;

  -- Deactivation leaves original source relation ID intact.
  update atlas.work_item_relations set active=false,updated_at=now()
  where id=v_link_bc;
  if not exists(
    select 1 from atlas.work_item_relations
    where id=v_link_bc and not active
  ) then raise exception 'Deactivated prerequisite source was lost.'; end if;

  -- After B->C is removed, C->A is no longer cyclic.
  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
  values(v_org,v_c,v_a,'depends_on',true);

  -- Reactivating B->C now reintroduces a cycle. Detect the UPDATE route too.
  v_rejected:=false;
  begin
    update atlas.work_item_relations set active=true,updated_at=now()
    where id=v_link_bc;
  exception when check_violation then
    get stacked diagnostics v_msg=message_text;
    if v_msg not like 'Prerequisite cycle%' then raise; end if;
    v_rejected:=true;
  end;
  if not v_rejected then
    raise exception 'REJECT: reactivation should not bypass cycle guard.';
  end if;
  if not exists(
    select 1 from atlas.work_item_relations
    where id=v_link_bc and not active
  ) then
    raise exception 'Rejected reactivation altered source state.';
  end if;

  -- "depends_on" must still forbid self-reference.
  v_rejected:=false;
  begin
    insert into atlas.work_item_relations(
      organization_id,from_work_item_id,to_work_item_id,relation_kind,active)
    values(v_org,v_a,v_a,'depends_on',true);
  exception when check_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'REJECT: self dependency admitted.'; end if;

  if (select count(*) from atlas.work_item_relations
      where organization_id=v_org and relation_kind='completion_bundle_member')<>1
  then
    raise exception 'Existing completion-bundle relation behavior changed.';
  end if;

  -- Event history has independent, database-enforced append-only custody.
  insert into atlas.work_item_prerequisite_events_v1(
    organization_id,ledger_id,relation_id,downstream_work_item_id,
    prerequisite_work_item_id,actor_person_id,source_action_id,
    request_fingerprint,action_kind,before_active,after_active,reason)
  values(v_org,gen_random_uuid(),v_link_ab,v_a,v_b,gen_random_uuid(),
    'clone-event-action-id','clone-fingerprint','establish',null,true,
    'Verified fixture event')
  returning id into v_event;

  v_rejected:=false;
  begin
    update atlas.work_item_prerequisite_events_v1 set reason='altered history'
    where id=v_event;
  exception when check_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'REJECT: audit history UPDATE admitted.'; end if;

  v_rejected:=false;
  begin
    delete from atlas.work_item_prerequisite_events_v1 where id=v_event;
  exception when check_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'REJECT: audit history DELETE admitted.'; end if;

  if not exists(select 1 from atlas.work_item_prerequisite_events_v1
    where id=v_event and reason='Verified fixture event') then
    raise exception 'Immutable original audit row was lost.';
  end if;

  raise notice 'CLONE PASS: three-source chain; cycle rejected; reactivation rejected; unrelated relation types and immutable audit retained; rollback follows.';
end;
$$;
rollback;

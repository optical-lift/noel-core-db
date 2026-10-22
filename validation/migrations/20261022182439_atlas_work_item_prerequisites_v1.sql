-- Disposable production-schema clone postconditions for Atlas prerequisites.
-- Runs only after exact candidate migration on the clone.
-- POST-CANDIDATE CHECKS: disposable production-schema clone ONLY.
-- Not a production migration; execute after reviewing/applying the candidate
-- to the clone. No tenant rows, source text or private data are read.
do $$
declare
  v_relation_has_org_fks int;
  v_other_rows bigint;
begin
  if not exists(
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='work_item_relations'
      and c.relkind='r'
  ) then raise exception 'Canonical Work relation table missing.'; end if;

  select count(*) into v_relation_has_org_fks
  from pg_catalog.pg_constraint c
  where c.conrelid='atlas.work_item_relations'::regclass
    and c.contype='f'
    and pg_catalog.pg_get_constraintdef(c.oid) like
      '%organization_id%';
  if v_relation_has_org_fks<2 then
    raise exception 'Organization-coherent Work foreign keys missing.';
  end if;

  if not exists(select 1 from pg_catalog.pg_trigger t
    where t.tgrelid='atlas.work_item_relations'::regclass
      and t.tgname='guard_work_item_depends_on_cycle_v1'
      and not t.tgisinternal) then
    raise exception 'Global dependency cycle guard missing.';
  end if;

  if not exists(select 1 from pg_catalog.pg_trigger t
    where t.tgrelid='atlas.work_item_prerequisite_events_v1'::regclass
      and t.tgname='guard_work_item_prerequisite_event_immutable_v1'
      and not t.tgisinternal) then
    raise exception 'Append-only audit event trigger missing.';
  end if;

  if not exists(select 1 from pg_catalog.pg_class c
    where c.oid='atlas.work_item_prerequisite_events_v1'::regclass
      and c.relrowsecurity) then
    raise exception 'Prerequisite event evidence not RLS-protected.';
  end if;

  if pg_catalog.has_table_privilege(
    'authenticated','atlas.work_item_prerequisite_events_v1','SELECT') or
     pg_catalog.has_table_privilege(
    'anon','atlas.work_item_prerequisite_events_v1','SELECT') then
    raise exception 'Direct prerequisite event read permissions leaked.';
  end if;

  if pg_catalog.has_function_privilege(
    'anon','public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)','EXECUTE') or
     pg_catalog.has_function_privilege(
    'anon','public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)','EXECUTE') or
     pg_catalog.has_function_privilege(
    'anon','public.atlas_work_prerequisite_event_self_api_v1(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Anonymous prerequisite RPC exposure.';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated','public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)','EXECUTE') or
     not pg_catalog.has_function_privilege(
    'authenticated','public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)','EXECUTE') or
     not pg_catalog.has_function_privilege(
    'authenticated','public.atlas_work_prerequisite_event_self_api_v1(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Authenticated guarded RPC entrypoints unavailable.';
  end if;

  if not exists(select 1 from pg_catalog.pg_constraint c
    where c.conrelid='atlas.work_item_relations'::regclass
      and c.contype='c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%depends_on%') then
    raise exception 'Existing Work relation vocabulary was damaged.';
  end if;

  -- These postconditions do not prove user authorization. That requires
  -- distinct real authenticated principal and seat-only sessions in clone.
  raise notice 'Schema postconditions passed, but auth/cycle transaction tests remain required.';
end;
$$;

-- Dedicated synthetic graph assertions are transactional and roll back.
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

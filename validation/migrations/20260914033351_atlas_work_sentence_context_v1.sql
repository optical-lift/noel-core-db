-- Atlas Work Sentence Context v1 postcondition.
-- Runs only against the disposable production-schema clone after the candidate migration.
-- This validation is transactional and MUST roll back.

begin;

do $$
declare
  v_org uuid:=gen_random_uuid();
  v_other_org uuid:=gen_random_uuid();
  v_user uuid:=gen_random_uuid();
  v_membership uuid;
  v_farm uuid:=gen_random_uuid();
  v_other_farm uuid:=gen_random_uuid();
  v_zone uuid:=gen_random_uuid();
  v_other_zone uuid:=gen_random_uuid();
  v_person uuid:=gen_random_uuid();
  v_work uuid:=gen_random_uuid();
  v_related uuid:=gen_random_uuid();
  v_key text:='work-sentence-context-fixture-'||gen_random_uuid()::text;
  v_failed boolean:=false;
begin
  insert into auth.users(id) values(v_user);

  insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
  values
    (v_org,v_key||'-org','Sentence Context Fixture','active','{}'::jsonb,'ready'),
    (v_other_org,v_key||'-other-org','Other Sentence Context Fixture','active','{}'::jsonb,'ready');

  insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
  values(v_org,v_user,'owner',true,'{}'::jsonb)
  returning id into v_membership;

  insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
  values
    (v_farm,v_org,v_key||'-farm','Sentence Farm','active','{}'::jsonb),
    (v_other_farm,v_other_org,v_key||'-other-farm','Other Sentence Farm','active','{}'::jsonb);

  insert into atlas.zones(id,farm_id,stable_key,label,zone_type,visible_to_guests,sort_order,metadata)
  values
    (v_zone,v_farm,v_key||'-zone','Bed Seven','growing',false,1,'{}'::jsonb),
    (v_other_zone,v_other_farm,v_key||'-other-zone','Other Bed','growing',false,1,'{}'::jsonb);

  insert into atlas.identity_subjects(id,organization_id,state,created_by_user_id,creation_basis)
  values(v_person,v_org,'active',v_user,jsonb_build_object('fixture',true));

  insert into atlas.identity_subject_projections(
    subject_id,organization_id,subject_kind,display_name,aliases,contact_points,
    unresolved_identity,confidence,projection_basis
  ) values(
    v_person,v_org,'person','Katie Fixture','[]'::jsonb,'[]'::jsonb,false,1,
    jsonb_build_object('fixture',true)
  );

  insert into atlas.work_items(id,organization_id,title,work_state,metadata)
  values
    (v_work,v_org,'Prepare revised florist email','open','{}'::jsonb),
    (v_related,v_org,'Pricing review','open','{}'::jsonb);

  perform atlas.attach_work_item_context_internal_v1(
    v_work,'spatial','zone',v_zone,'located_in',v_membership,
    jsonb_build_object('fixture',true),'{}'::jsonb
  );
  perform atlas.attach_work_item_context_internal_v1(
    v_work,'identity','identity_subject',v_person,'for',v_membership,
    jsonb_build_object('fixture',true),'{}'::jsonb
  );

  if not exists(
    select 1 from atlas.work_item_context_links
    where work_item_id=v_work and subject_domain='spatial' and subject_kind='zone'
      and subject_id=v_zone and relation_kind='located_in'
  ) then
    raise exception 'Zone context was not preserved as typed Company Work context.';
  end if;

  if not exists(
    select 1 from atlas.work_item_context_links
    where work_item_id=v_work and subject_domain='identity' and subject_kind='identity_subject'
      and subject_id=v_person and relation_kind='for'
  ) then
    raise exception 'Person context was not preserved separately from responsibility.';
  end if;

  begin
    perform atlas.attach_work_item_context_internal_v1(
      v_work,'spatial','zone',v_other_zone,'located_in',v_membership,'{}'::jsonb,'{}'::jsonb
    );
  exception when insufficient_privilege then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Cross-organization zone context was accepted.';
  end if;

  insert into atlas.work_item_relations(
    organization_id,from_work_item_id,to_work_item_id,relation_kind,active,metadata
  ) values(v_org,v_work,v_related,'depends_on',true,jsonb_build_object('fixture',true));

  if not exists(
    select 1 from atlas.work_item_relations
    where from_work_item_id=v_work and to_work_item_id=v_related and relation_kind='depends_on' and active
  ) then
    raise exception 'Existing Company Work relation contract did not preserve related work.';
  end if;

  if has_table_privilege('authenticated','atlas.work_item_context_links','select')
     or has_table_privilege('authenticated','atlas.work_item_context_links','insert') then
    raise exception 'Authenticated browser callers received direct work context table authority.';
  end if;

  if has_function_privilege('anon','public.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamp with time zone,text,jsonb,jsonb,text)','execute') then
    raise exception 'Anonymous callers can execute derived-work v2.';
  end if;
  if not has_function_privilege('authenticated','public.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamp with time zone,text,jsonb,jsonb,text)','execute') then
    raise exception 'Authenticated derived-work v2 membrane is unavailable.';
  end if;
  if has_function_privilege('anon','public.communication_work_context_candidates_self_v1(uuid,text)','execute') then
    raise exception 'Anonymous callers can enumerate work-context candidates.';
  end if;
  if not has_function_privilege('authenticated','public.communication_work_context_candidates_self_v1(uuid,text)','execute') then
    raise exception 'Authenticated work-context candidate membrane is unavailable.';
  end if;
  if not has_function_privilege('authenticated','public.institutional_conversation_detail_self_v4(uuid)','execute') then
    raise exception 'Conversation detail v4 membrane is unavailable.';
  end if;
end;
$$;

rollback;

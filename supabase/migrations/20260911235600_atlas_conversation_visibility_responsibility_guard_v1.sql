begin;

-- This guard belongs immediately after atlas_institutional_conversation_visibility_v1.
-- Production-schema validation intentionally applies one candidate migration to
-- today's production schema. If the visibility parent migration is not present
-- yet, this migration must leave no broken compiled objects behind. In governed
-- release order, the parent tables/functions exist and the deferred guards below
-- are installed transactionally.
do $install$
begin
  if to_regclass('atlas.institutional_conversation_visibility_policies') is null
     or to_regclass('atlas.institutional_conversation_view_grants') is null
     or to_regprocedure('atlas.institutional_conversation_membership_can_view_v1(uuid,uuid)') is null then
    return;
  end if;

  execute $ddl$
    create or replace function atlas.guard_conversation_visibility_responsibility_v1()
    returns trigger
    language plpgsql
    security definer
    set search_path=pg_catalog,atlas
    as $function$
    declare
      v_conversation_id uuid;
    begin
      if tg_table_name='institutional_conversation_visibility_policies' then
        v_conversation_id:=case when tg_op='DELETE' then old.institutional_conversation_id else new.institutional_conversation_id end;
      else
        v_conversation_id:=case when tg_op='DELETE' then old.institutional_conversation_id else new.institutional_conversation_id end;
      end if;

      if v_conversation_id is not null and exists (
        select 1
        from atlas.institutional_conversation_response_cases rc
        join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
        join atlas.work_allocations wa on wa.work_item_id=wb.work_item_id
          and wa.allocation_role='responsible' and wa.state='active'
        join atlas.organization_memberships responsible on responsible.id=wa.assignee_membership_id
        where rc.institutional_conversation_id=v_conversation_id
          and responsible.active
          and not atlas.institutional_conversation_membership_can_view_v1(v_conversation_id,responsible.id)
      ) then
        raise exception 'Conversation visibility would hide active responsibility. Handoff/complete responsibility or retain that membership visibility first.' using errcode='23514';
      end if;

      if tg_op='DELETE' then return old; end if;
      return new;
    end;
    $function$;
  $ddl$;

  execute 'drop trigger if exists conversation_visibility_responsibility_guard_policy on atlas.institutional_conversation_visibility_policies';
  execute $ddl$
    create constraint trigger conversation_visibility_responsibility_guard_policy
    after insert or update or delete on atlas.institutional_conversation_visibility_policies
    deferrable initially deferred
    for each row execute function atlas.guard_conversation_visibility_responsibility_v1()
  $ddl$;

  execute 'drop trigger if exists conversation_visibility_responsibility_guard_grant on atlas.institutional_conversation_view_grants';
  execute $ddl$
    create constraint trigger conversation_visibility_responsibility_guard_grant
    after insert or update or delete on atlas.institutional_conversation_view_grants
    deferrable initially deferred
    for each row execute function atlas.guard_conversation_visibility_responsibility_v1()
  $ddl$;

  execute $ddl$
    create or replace function atlas.guard_endpoint_grant_against_hidden_responsibility_v1()
    returns trigger
    language plpgsql
    security definer
    set search_path=pg_catalog,atlas
    as $function$
    begin
      if exists (
        select 1
        from atlas.institutional_conversation_endpoints ce
        join atlas.institutional_conversation_visibility_policies vp
          on vp.institutional_conversation_id=ce.institutional_conversation_id
          and vp.visibility_class='restricted'
        join atlas.institutional_conversation_response_cases rc
          on rc.institutional_conversation_id=ce.institutional_conversation_id
        join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
        join atlas.work_allocations wa on wa.work_item_id=wb.work_item_id
          and wa.assignee_membership_id=old.membership_id
          and wa.allocation_role='responsible' and wa.state='active'
        where ce.communication_endpoint_id=old.communication_endpoint_id
          and not atlas.institutional_conversation_membership_can_view_v1(ce.institutional_conversation_id,old.membership_id)
      ) then
        raise exception 'Endpoint capability change would hide a restricted conversation from an active responsible membership. Handoff/complete responsibility first.' using errcode='23514';
      end if;
      if tg_op='DELETE' then return old; end if;
      return new;
    end;
    $function$;
  $ddl$;

  execute 'drop trigger if exists endpoint_grant_hidden_responsibility_guard_update on atlas.communication_endpoint_member_grants';
  execute $ddl$
    create constraint trigger endpoint_grant_hidden_responsibility_guard_update
    after update on atlas.communication_endpoint_member_grants
    deferrable initially deferred
    for each row execute function atlas.guard_endpoint_grant_against_hidden_responsibility_v1()
  $ddl$;

  execute 'drop trigger if exists endpoint_grant_hidden_responsibility_guard_delete on atlas.communication_endpoint_member_grants';
  execute $ddl$
    create constraint trigger endpoint_grant_hidden_responsibility_guard_delete
    after delete on atlas.communication_endpoint_member_grants
    deferrable initially deferred
    for each row execute function atlas.guard_endpoint_grant_against_hidden_responsibility_v1()
  $ddl$;

  execute $ddl$
    comment on function atlas.guard_conversation_visibility_responsibility_v1() is
      'Deferred final-state invariant: an institutional conversation may not commit with active responsibility assigned to a membership that cannot view it.'
  $ddl$;
  execute $ddl$
    comment on function atlas.guard_endpoint_grant_against_hidden_responsibility_v1() is
      'Deferred final-state invariant: endpoint grant changes may not strand active restricted-conversation responsibility.'
  $ddl$;
end;
$install$;

commit;

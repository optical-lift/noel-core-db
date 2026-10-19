begin;

-- C2: An institution may adopt a previously established canonical requirement
-- into its operating register without rewriting that requirement's source,
-- creating Work, allocating a person, or scheduling a day.
-- Exact currently-active native Ledger evidence is mandatory for adoption.
create or replace function atlas.guard_operating_register_identity_v1()
returns trigger language plpgsql volatile security invoker set search_path to ''
as $fn$
begin
  if not exists (
    select 1
    from atlas.ledger_organization_participations lop
    join atlas.ledgers al on al.id=lop.ledger_id and al.status='active'
    join ledger.ledgers nl on nl.id=al.id
    where lop.ledger_id=new.ledger_id
      and lop.organization_id=new.organization_id
      and lop.status='active' and lop.ended_at is null
      and lop.participation_kind in ('governing','operating')
      and nl.ledger_state='active' and nl.retired_at is null
  ) or not exists (
    select 1 from atlas.work_requirements w
    where w.id=new.requirement_id and w.organization_id=new.organization_id
      and w.state='active'
      and (
        (w.source_object_type='company_work_operating_register'
         and w.source_object_id=new.id)
        or (
          w.source_object_type is distinct from 'company_work_operating_register'
          and w.source_object_type is not null and w.source_object_id is not null
          and exists (
            select 1
            from atlas.work_requirement_links l
            join atlas.work_items i on i.id=l.work_item_id
              and i.organization_id=w.organization_id
              and i.work_state='open'
            join atlas.company_work_native_ledger_relevance n
              on n.work_item_id=i.id and n.organization_id=w.organization_id
              and n.ledger_id=new.ledger_id and n.attribution_state='active'
            where l.organization_id=w.organization_id and l.requirement_id=w.id
              and l.active and l.link_role='resolves'
              and (
                n.evidence_kind='owner_attested'
                or (n.evidence_kind='source_verified' and exists (
                  select 1 from atlas.company_work_native_ledger_exact_source_v1(
                    n.work_item_id,n.ledger_id) s
                  where s.source_schema=n.source_schema
                    and s.source_table=n.source_table
                    and s.source_id=n.source_id))
              )
          )
        )
      )
  ) then
    raise exception 'Exact native Ledger participation and source-backed canonical requirement required'
      using errcode='23514';
  end if;
  return new;
end
$fn$;

revoke all on function atlas.guard_operating_register_identity_v1()
  from public,anon,authenticated;

create or replace function atlas.adopt_existing_operating_requirement_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_requirement_id uuid,
  p_document jsonb, p_reason text, p_accountable_position_id uuid default null
) returns jsonb
language plpgsql volatile security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_requirement atlas.work_requirements%rowtype;
  v_entry_id uuid:=gen_random_uuid();
  v_revision_id uuid;
  v_key text;
  v_work_count integer;
begin
  if auth.uid() is null or p_organization_id is null
    or p_ledger_id is null or p_requirement_id is null then
    raise exception 'Authenticated exact Ledger and requirement required' using errcode='42501';
  end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact Ledger owner required' using errcode='42501';
  end if;
  if not atlas.operating_requirement_document_valid_v1(p_document)
    or length(btrim(coalesce(p_reason,''))) not between 12 and 1200 then
    raise exception 'Complete operating definition and specific owner reason required'
      using errcode='22023';
  end if;
  perform atlas.validate_operating_register_links_owner_v1(
    p_organization_id,p_accountable_position_id,null);
  select * into v_requirement from atlas.work_requirements
  where id=p_requirement_id and organization_id=p_organization_id for update;
  if v_requirement.id is null or v_requirement.state<>'active'
    or v_requirement.organization_unit_id is null
    or v_requirement.source_object_type is null
    or v_requirement.source_object_type='company_work_operating_register'
    or v_requirement.source_object_id is null then
    raise exception 'Eligible active pre-existing sourced requirement required'
      using errcode='23514';
  end if;
  if exists (select 1 from atlas.company_work_operating_register_entries r
             where r.requirement_id=p_requirement_id) then
    raise exception 'This canonical requirement is already in an operating register'
      using errcode='23505';
  end if;

  select count(distinct i.id)::integer into v_work_count
  from atlas.work_requirement_links l
  join atlas.work_items i
    on i.id=l.work_item_id and i.organization_id=p_organization_id and i.work_state='open'
  join atlas.company_work_native_ledger_relevance n
    on n.work_item_id=i.id and n.organization_id=p_organization_id
    and n.ledger_id=p_ledger_id and n.attribution_state='active'
  where l.organization_id=p_organization_id and l.requirement_id=p_requirement_id
    and l.active and l.link_role='resolves'
    and (n.evidence_kind='owner_attested' or
      (n.evidence_kind='source_verified' and exists (
        select 1 from atlas.company_work_native_ledger_exact_source_v1(
          n.work_item_id,n.ledger_id) s
        where s.source_schema=n.source_schema and s.source_table=n.source_table
          and s.source_id=n.source_id)));
  if v_work_count<1 then
    raise exception 'Existing requirement has no current exact native Ledger evidence'
      using errcode='42501';
  end if;
  v_key:='existing_'||replace(p_requirement_id::text,'-','');

  -- The trigger independently rechecks Ledger and source eligibility at INSERT.
  insert into atlas.company_work_operating_register_entries(
    id,organization_id,ledger_id,requirement_id,stable_key,established_by_person_id)
  values (v_entry_id,p_organization_id,p_ledger_id,p_requirement_id,v_key,v_owner);

  insert into atlas.company_work_operating_register_revisions(
    entry_id,revision_no,document,policy_state,accountable_position_id,
    recurrence_rule_id,effective_at,authorized_by_person_id,reason)
  values (v_entry_id,1,p_document,'active',p_accountable_position_id,
          null,now(),v_owner,btrim(p_reason))
  returning id into v_revision_id;

  return jsonb_build_object(
    'ok',true,'contractVersion','existing_operating_requirement_adoption_v1',
    'entryId',v_entry_id,'requirementId',p_requirement_id,
    'revisionId',v_revision_id,'revision',1,
    'nativeLedgerId',p_ledger_id,'existingWorkEvidenceCount',v_work_count,
    'canonicalRequirementReused',true,'sourceIdentityChanged',false,
    'workItemIdsCreated','[]'::jsonb,'instancesGenerated',0,
    'allocationChanged',false,'scheduled',false,'recurrenceRuleExecuted',false);
end
$fn$;

revoke all on function atlas.adopt_existing_operating_requirement_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function atlas.adopt_existing_operating_requirement_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,text,uuid) to authenticated;

create or replace function public.adopt_existing_operating_requirement_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_requirement_id uuid,
  p_document jsonb, p_reason text, p_accountable_position_id uuid default null
) returns jsonb language sql volatile security invoker set search_path to ''
as $fn$
  select atlas.adopt_existing_operating_requirement_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_requirement_id,
    p_document,p_reason,p_accountable_position_id);
$fn$;
revoke all on function public.adopt_existing_operating_requirement_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function public.adopt_existing_operating_requirement_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,text,uuid) to authenticated;

commit;

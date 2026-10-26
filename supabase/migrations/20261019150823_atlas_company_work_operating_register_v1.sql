begin;

-- Build 5 continuation, Slice C1.
-- A register entry annotates ONE canonical atlas.work_requirements identity.
-- It is not another Work item, schedule, or recurrence materializer.
create table atlas.company_work_operating_register_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  requirement_id uuid not null references atlas.work_requirements(id) on delete restrict,
  stable_key text not null check (stable_key ~ '^[a-z][a-z0-9_]{2,79}$'),
  established_by_person_id uuid not null references reality.entities(id) on delete restrict,
  established_at timestamptz not null default now(),
  unique (organization_id,ledger_id,stable_key),
  unique (requirement_id),
  foreign key (organization_id,requirement_id)
    references atlas.work_requirements(organization_id,id) on delete restrict
);
create index company_work_operating_register_ledger_v1
  on atlas.company_work_operating_register_entries(organization_id,ledger_id,id);

create table atlas.company_work_operating_register_revisions (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references atlas.company_work_operating_register_entries(id) on delete restrict,
  revision_no integer not null check (revision_no>0),
  document jsonb not null,
  policy_state text not null check (policy_state in ('active','paused')),
  accountable_position_id uuid references atlas.organization_positions(id) on delete restrict,
  recurrence_rule_id uuid references atlas.organization_recurrence_rules(id) on delete restrict,
  effective_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  authorized_by_person_id uuid not null references reality.entities(id) on delete restrict,
  reason text not null check (length(btrim(reason)) between 1 and 1200),
  unique (entry_id,revision_no),
  check (jsonb_typeof(document)='object'),
  check (octet_length(document::text)<=32768)
);
create index company_work_operating_register_revision_effective_v1
  on atlas.company_work_operating_register_revisions
  (entry_id,effective_at desc,revision_no desc);

comment on table atlas.company_work_operating_register_entries is
  'Exact native-Ledger operating register referencing the ONE canonical requirement. The institution retains this need when its accountable Position is vacant.';
comment on table atlas.company_work_operating_register_revisions is
  'Append-only instructions, prerequisites, position accountability and reference to a canonical recurrence rule. Pausing provisioning policy does not cancel canonical Work. No tasks generated here.';

alter table atlas.company_work_operating_register_entries enable row level security;
alter table atlas.company_work_operating_register_revisions enable row level security;
revoke all on atlas.company_work_operating_register_entries from public,anon,authenticated;
revoke all on atlas.company_work_operating_register_revisions from public,anon,authenticated;

create function atlas.guard_operating_register_identity_v1()
returns trigger language plpgsql volatile security invoker set search_path to ''
as $fn$
begin
  if not exists(
    select 1 from atlas.ledgers l
    where l.id=new.ledger_id and l.organization_id=new.organization_id
      and l.status='active'
  ) or not exists (
    select 1 from atlas.work_requirements w
    where w.id=new.requirement_id and w.organization_id=new.organization_id
      and w.source_object_type='company_work_operating_register'
      and w.source_object_id=new.id and w.state='active'
  ) then
    raise exception 'One exact Ledger and one source-matched canonical requirement required'
      using errcode='23514';
  end if;
  return new;
end
$fn$;
create trigger operating_register_identity_scope_v1
  before insert on atlas.company_work_operating_register_entries
  for each row execute function atlas.guard_operating_register_identity_v1();
revoke all on function atlas.guard_operating_register_identity_v1()
  from public,anon,authenticated;

create function atlas.operating_requirement_document_valid_v1(p_document jsonb)
returns boolean language sql immutable security invoker set search_path to ''
as $fn$
  select coalesce(
    jsonb_typeof(p_document)='object'
    and octet_length(p_document::text)<=32768
    and jsonb_typeof(p_document->'requiredOutcome')='string'
    and length(btrim(p_document->>'requiredOutcome')) between 1 and 4000
    and jsonb_typeof(p_document->'instructions')='string'
    and jsonb_typeof(p_document->'prerequisites')='array'
    and jsonb_typeof(p_document->'resources')='array'
    and jsonb_typeof(p_document->'reporting')='object'
    and jsonb_typeof(p_document->'escalation')='object'
    and not exists (
      select 1 from jsonb_object_keys(p_document) as k(key)
      where k.key not in ('requiredOutcome','instructions','prerequisites',
        'resources','reporting','escalation')
    ),false);
$fn$;
revoke all on function atlas.operating_requirement_document_valid_v1(jsonb)
  from public,anon,authenticated;
alter table atlas.company_work_operating_register_revisions
  add constraint company_work_operating_register_document_v1
  check (atlas.operating_requirement_document_valid_v1(document));

create function atlas.prevent_operating_register_history_mutation_v1()
returns trigger language plpgsql volatile security invoker set search_path to ''
as $fn$
begin
  raise exception 'Operating register identity and authored revisions are immutable'
    using errcode='23514';
end
$fn$;
create trigger operating_register_entry_identity_immutable_v1
  before update or delete on atlas.company_work_operating_register_entries
  for each row execute function atlas.prevent_operating_register_history_mutation_v1();
create trigger operating_register_revision_immutable_v1
  before update or delete on atlas.company_work_operating_register_revisions
  for each row execute function atlas.prevent_operating_register_history_mutation_v1();
revoke all on function atlas.prevent_operating_register_history_mutation_v1()
  from public,anon,authenticated;

create function atlas.validate_operating_register_links_owner_v1(
  p_organization_id uuid,p_position_id uuid,p_recurrence_rule_id uuid)
returns void language plpgsql stable security definer set search_path to ''
as $fn$
begin
  if p_position_id is not null and not exists(
    select 1 from atlas.organization_positions p
    where p.id=p_position_id and p.organization_id=p_organization_id
      and p.status='active'
  ) then
    raise exception 'Active accountable Position in exact organization required'
      using errcode='23514';
  end if;
  if p_recurrence_rule_id is not null and not exists(
    select 1 from atlas.organization_recurrence_rules r
    where r.id=p_recurrence_rule_id and r.organization_id=p_organization_id
      and r.rule_state='active'
  ) then
    raise exception 'Existing active organization recurrence rule required'
      using errcode='23514';
  end if;
end
$fn$;
revoke all on function atlas.validate_operating_register_links_owner_v1(uuid,uuid,uuid)
  from public,anon,authenticated;

-- Establish one new canonical requirement, WITHOUT an occurrence, allocation,
-- recurrence schedule, Clock placement, or worker consent.
create function atlas.establish_operating_requirement_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_organization_unit_id uuid,
  p_stable_key text,p_summary text,p_document jsonb,p_reason text,
  p_accountable_position_id uuid default null,
  p_recurrence_rule_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_entry_id uuid:=gen_random_uuid();
  v_requirement_id uuid;
  v_revision_id uuid;
begin
  if auth.uid() is null or p_organization_id is null or p_ledger_id is null
    or p_organization_unit_id is null then
    raise exception 'Signed-in exact Ledger and institutional unit required'
      using errcode='42501';
  end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Current exact native Ledger owner required'
      using errcode='42501';
  end if;
  if p_stable_key is null or p_stable_key !~ '^[a-z][a-z0-9_]{2,79}$'
    or length(btrim(coalesce(p_summary,''))) not between 1 and 300
    or not atlas.operating_requirement_document_valid_v1(p_document)
    or length(btrim(coalesce(p_reason,''))) not between 1 and 1200 then
    raise exception 'Unique stable key, summary, operating document and reason required'
      using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id and u.organization_id=p_organization_id
      and u.status='active'
  ) then
    raise exception 'Active institutional unit required' using errcode='23514';
  end if;
  perform atlas.validate_operating_register_links_owner_v1(
    p_organization_id,p_accountable_position_id,p_recurrence_rule_id);
  -- The unique canonical requirement stable key prevents retry duplication.
  insert into atlas.work_requirements(
    organization_id,organization_unit_id,requirement_kind,summary,
    source_object_type,source_object_id,state,stable_key,metadata)
  values(
    p_organization_id,p_organization_unit_id,'operational',btrim(p_summary),
    'company_work_operating_register',v_entry_id,'active',
    'company_work_operating:'||p_ledger_id::text||':'||p_stable_key,
    jsonb_build_object('nativeLedgerId',p_ledger_id))
  returning id into v_requirement_id;
  insert into atlas.company_work_operating_register_entries(
    id,organization_id,ledger_id,requirement_id,stable_key,
    established_by_person_id)
  values(v_entry_id,p_organization_id,p_ledger_id,v_requirement_id,
    p_stable_key,v_owner);
  insert into atlas.company_work_operating_register_revisions(
    entry_id,revision_no,document,policy_state,accountable_position_id,
    recurrence_rule_id,effective_at,authorized_by_person_id,reason)
  values(v_entry_id,1,p_document,'active',p_accountable_position_id,
    p_recurrence_rule_id,now(),v_owner,btrim(p_reason))
  returning id into v_revision_id;
  return jsonb_build_object(
    'ok',true,'contractVersion','operating_requirement_establishment_v1',
    'entryId',v_entry_id,'requirementId',v_requirement_id,
    'revisionId',v_revision_id,'revision',1,'nativeLedgerId',p_ledger_id,
    'policyState','active','workItemIds','[]'::jsonb,
    'instancesGenerated',0,'allocationChanged',false,'scheduled',false,
    'recurrenceRuleExecuted',false);
end
$fn$;

-- Safe edits revise operating terms only. A separate dependency-aware
-- retirement command must govern cancellation of canonical requirements.
create function atlas.revise_operating_requirement_owner_self_api_v1(
  p_entry_id uuid,p_ledger_id uuid,p_document jsonb,p_policy_state text,
  p_accountable_position_id uuid,p_recurrence_rule_id uuid,
  p_expected_revision integer,p_reason text,p_effective_at timestamptz default now())
returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
  v_entry atlas.company_work_operating_register_entries%rowtype;
  v_owner uuid;
  v_previous integer;
  v_previous_effective timestamptz;
  v_revision_id uuid;
begin
  if auth.uid() is null or p_entry_id is null or p_ledger_id is null then
    raise exception 'Signed-in exact operating register entry and Ledger required'
      using errcode='42501';
  end if;
  select * into v_entry from atlas.company_work_operating_register_entries
    where id=p_entry_id and ledger_id=p_ledger_id for update;
  if v_entry.id is null then
    raise exception 'Exact Ledger register entry unavailable' using errcode='42501';
  end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_entry.organization_id,v_entry.ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact native Ledger owner required' using errcode='42501';
  end if;
  if p_policy_state not in ('active','paused')
    or p_expected_revision is null or p_expected_revision<1
    or p_effective_at is null or p_effective_at<now()-interval '5 minutes'
    or not atlas.operating_requirement_document_valid_v1(p_document)
    or length(btrim(coalesce(p_reason,''))) not between 1 and 1200 then
    raise exception 'Valid revision, operating terms, policy state and reason required'
      using errcode='22023';
  end if;
  perform atlas.validate_operating_register_links_owner_v1(
    v_entry.organization_id,p_accountable_position_id,p_recurrence_rule_id);
  select revision_no,effective_at into v_previous,v_previous_effective
  from atlas.company_work_operating_register_revisions
  where entry_id=v_entry.id order by revision_no desc limit 1;
  if v_previous is distinct from p_expected_revision then
    raise exception 'Register terms changed; reread before saving' using errcode='40001';
  end if;
  if p_effective_at<v_previous_effective then
    raise exception 'Operating definition history must be monotonic'
      using errcode='22023';
  end if;
  insert into atlas.company_work_operating_register_revisions(
    entry_id,revision_no,document,policy_state,accountable_position_id,
    recurrence_rule_id,effective_at,authorized_by_person_id,reason)
  values(v_entry.id,v_previous+1,p_document,p_policy_state,
    p_accountable_position_id,p_recurrence_rule_id,p_effective_at,
    v_owner,btrim(p_reason))
  returning id into v_revision_id;
  return jsonb_build_object(
    'ok',true,'contractVersion','operating_requirement_revision_v1',
    'entryId',v_entry.id,'requirementId',v_entry.requirement_id,
    'revisionId',v_revision_id,'revision',v_previous+1,
    'policyState',p_policy_state,'workAllocationChanged',false,
    'instancesGenerated',0,'canonicalRequirementStateChanged',false);
end
$fn$;

-- A compact native-Ledger owner projection. Requirement, Position,
-- Work allocation, and recurrence are shown as distinct factual carriers.
create function atlas.operating_requirements_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_entries jsonb;
  v_legacy jsonb;
begin
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact native Ledger owner required' using errcode='42501';
  end if;
  if p_limit is null or p_limit<1 or p_limit>200 then
    raise exception 'Limit must be 1..200' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.established_at,e.entry_id),'[]'::jsonb)
  into v_entries from (
    select r.id as entry_id,r.established_at,r.stable_key,
      w.id as requirement_id,w.summary,w.state as requirement_state,
      w.organization_unit_id,
      latest.revision_no,latest.policy_state,latest.document,
      latest.accountable_position_id,latest.recurrence_rule_id,
      latest.effective_at,
      case when latest.accountable_position_id is null then false
        else exists (
          select 1 from atlas.organization_position_appointments a
          where a.position_id=latest.accountable_position_id
            and a.organization_id=r.organization_id and a.status='active'
            and a.begins_at<=now() and (a.ends_at is null or a.ends_at>now())
        ) end as position_has_current_appointment_window,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'workItemId',i.id,'title',i.title,'state',i.work_state,
          'responsiblyAllocated',exists (
            select 1 from atlas.work_allocations a
            where a.work_item_id=i.id and a.organization_id=r.organization_id
              and a.allocation_role='responsible' and a.state='active'))
          order by i.created_at,i.id)
        from atlas.work_requirement_links l
        join atlas.work_items i on i.id=l.work_item_id
          and i.organization_id=r.organization_id
        where l.requirement_id=w.id and l.organization_id=r.organization_id
          and l.active
      ),'[]'::jsonb) as canonical_work
    from atlas.company_work_operating_register_entries r
    join atlas.work_requirements w on w.id=r.requirement_id
      and w.organization_id=r.organization_id
    left join lateral (
      select v.* from atlas.company_work_operating_register_revisions v
      where v.entry_id=r.id and v.effective_at<=now()
      order by v.effective_at desc,v.revision_no desc limit 1
    ) latest on true
    where r.organization_id=p_organization_id and r.ledger_id=p_ledger_id
    order by r.established_at,r.id limit p_limit
  ) e;
  -- Existing legacy-linked requirements remain visible for reconciliation,
  -- but only with exact current native Ledger relevance evidence.
  select coalesce(jsonb_agg(to_jsonb(x) order by x.requirement_id),'[]'::jsonb)
  into v_legacy from (
    select distinct w.id as requirement_id,w.summary,w.state as requirement_state
    from atlas.work_requirements w
    join atlas.work_requirement_links l on l.requirement_id=w.id
      and l.organization_id=w.organization_id and l.active
    join atlas.company_work_native_ledger_relevance n
      on n.work_item_id=l.work_item_id and n.organization_id=w.organization_id
      and n.ledger_id=p_ledger_id and n.attribution_state='active'
    where w.organization_id=p_organization_id
      and not exists (
        select 1 from atlas.company_work_operating_register_entries e
        where e.requirement_id=w.id
      )
      and (n.evidence_kind='owner_attested'
        or (n.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            n.work_item_id,n.ledger_id) s
          where s.source_schema=n.source_schema and s.source_table=n.source_table
            and s.source_id=n.source_id)))
    order by w.id limit p_limit
  ) x;
  return jsonb_build_object(
    'contractVersion','operating_requirements_owner_v1',
    'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
    'registerEntries',v_entries,'legacyLinkedRequirements',v_legacy,
    'positionDoesNotAllocateWork',true,
    'recurrenceRuleDoesNotMaterializeWorkHere',true,
    'unlinkedLegacyRequirementsAreUnattributed',true);
end
$fn$;

revoke all on function atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
  from public,anon,authenticated;
revoke all on function atlas.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)
  from public,anon,authenticated;
revoke all on function atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)
  from public,anon,authenticated;
grant execute on function atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
  to authenticated;
grant execute on function atlas.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)
  to authenticated;
grant execute on function atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)
  to authenticated;

create function public.establish_operating_requirement_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_organization_unit_id uuid,
  p_stable_key text,p_summary text,p_document jsonb,p_reason text,
  p_accountable_position_id uuid default null,p_recurrence_rule_id uuid default null)
returns jsonb language sql volatile security invoker set search_path to ''
as $fn$ select atlas.establish_operating_requirement_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_organization_unit_id,p_stable_key,
  p_summary,p_document,p_reason,p_accountable_position_id,p_recurrence_rule_id) $fn$;
create function public.revise_operating_requirement_owner_self_api_v1(
  p_entry_id uuid,p_ledger_id uuid,p_document jsonb,p_policy_state text,
  p_accountable_position_id uuid,p_recurrence_rule_id uuid,
  p_expected_revision integer,p_reason text,p_effective_at timestamptz default now())
returns jsonb language sql volatile security invoker set search_path to ''
as $fn$ select atlas.revise_operating_requirement_owner_self_api_v1(
  p_entry_id,p_ledger_id,p_document,p_policy_state,p_accountable_position_id,
  p_recurrence_rule_id,p_expected_revision,p_reason,p_effective_at) $fn$;
create function public.operating_requirements_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.operating_requirements_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_limit) $fn$;
revoke all on function public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)
  from public,anon,authenticated;
revoke all on function public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)
  from public,anon,authenticated;
grant execute on function public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
  to authenticated;
grant execute on function public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)
  to authenticated;
grant execute on function public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)
  to authenticated;

commit;

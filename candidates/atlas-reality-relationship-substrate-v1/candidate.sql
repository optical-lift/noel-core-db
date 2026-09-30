-- Atlas Reality Relationship Substrate v1
-- Universal relationship proposition -> evidence -> adjudication -> canonical admission.
-- Internal-only. No domain ontology, browser RPC, research, ranking, or outreach.

create table reality.relationship_kinds (
  relationship_kind text primary key check (btrim(relationship_kind)<>''),
  display_name text not null check (btrim(display_name)<>''),
  description text not null default '',
  inverse_relationship_kind text null,
  symmetric boolean not null default false,
  allowed_subject_kinds text[] null,
  allowed_object_kinds text[] null,
  kind_state text not null default 'active'
    check (kind_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz null,
  check (allowed_subject_kinds is null or cardinality(allowed_subject_kinds)>0),
  check (allowed_object_kinds is null or cardinality(allowed_object_kinds)>0),
  check (not symmetric or inverse_relationship_kind is null)
);

alter table reality.relationship_kinds
  add constraint reality_relationship_kinds_inverse_fkey
  foreign key (inverse_relationship_kind)
  references reality.relationship_kinds(relationship_kind)
  deferrable initially deferred;

create table reality.relationship_propositions (
  id uuid primary key default gen_random_uuid(),
  subject_entity_id uuid not null references reality.entities(id) on delete restrict,
  relationship_kind text not null references reality.relationship_kinds(relationship_kind) on delete restrict,
  object_entity_id uuid not null references reality.entities(id) on delete restrict,
  requested_relationship_state text not null default 'observed'
    check (requested_relationship_state in ('observed','established')),
  valid_from timestamptz null,
  valid_until timestamptz null,
  proposition_state text not null default 'open'
    check (proposition_state in ('open','accepted','rejected','disputed','withdrawn')),
  proposition_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(proposition_basis)='object'),
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  decided_at timestamptz null,
  check (subject_entity_id<>object_entity_id),
  check (valid_until is null or valid_from is null or valid_until>valid_from)
);

create unique index reality_relationship_propositions_idempotency_idx
  on reality.relationship_propositions(idempotency_key)
  where idempotency_key is not null;
create index reality_relationship_propositions_tuple_idx
  on reality.relationship_propositions(subject_entity_id,relationship_kind,object_entity_id,created_at desc);
create index reality_relationship_propositions_open_idx
  on reality.relationship_propositions(proposition_state,created_at)
  where proposition_state='open';

create table reality.relationship_proposition_evidence (
  id uuid primary key default gen_random_uuid(),
  proposition_id uuid not null references reality.relationship_propositions(id) on delete cascade,
  evidence_kind text not null check (btrim(evidence_kind)<>''),
  source_locator jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_locator)='object'),
  evidence_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence_snapshot)='object'),
  note text null,
  observed_at timestamptz null,
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now()
);
create index reality_relationship_proposition_evidence_proposition_idx
  on reality.relationship_proposition_evidence(proposition_id,created_at,id);

create table reality.relationship_proposition_adjudications (
  id uuid primary key default gen_random_uuid(),
  proposition_id uuid not null references reality.relationship_propositions(id) on delete restrict,
  decision text not null check (decision in ('accept','reject','dispute')),
  rationale text not null check (btrim(rationale)<>''),
  authority_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(authority_basis)='object'),
  adjudicated_by_principal_id uuid null references atlas.principals(id) on delete restrict,
  resulting_relationship_id uuid null references reality.entity_relationships(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(proposition_id)
);
create index reality_relationship_proposition_adjudications_result_idx
  on reality.relationship_proposition_adjudications(resulting_relationship_id)
  where resulting_relationship_id is not null;

alter table reality.relationship_kinds enable row level security;
alter table reality.relationship_kinds force row level security;
alter table reality.relationship_propositions enable row level security;
alter table reality.relationship_propositions force row level security;
alter table reality.relationship_proposition_evidence enable row level security;
alter table reality.relationship_proposition_evidence force row level security;
alter table reality.relationship_proposition_adjudications enable row level security;
alter table reality.relationship_proposition_adjudications force row level security;

revoke all on table reality.relationship_kinds from anon,authenticated,service_role;
revoke all on table reality.relationship_propositions from anon,authenticated,service_role;
revoke all on table reality.relationship_proposition_evidence from anon,authenticated,service_role;
revoke all on table reality.relationship_proposition_adjudications from anon,authenticated,service_role;

grant select on table reality.relationship_kinds to service_role;
grant select on table reality.relationship_propositions to service_role;
grant select on table reality.relationship_proposition_evidence to service_role;
grant select on table reality.relationship_proposition_adjudications to service_role;

-- Canonical relationship rows are no longer an application-writable fact table.
revoke insert,update,delete on table reality.entity_relationships from service_role;
grant select on table reality.entity_relationships to service_role;

create or replace function reality.guard_relationship_kind_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_in_use boolean:=false;
begin
  if tg_op='UPDATE' then
    select exists(
      select 1 from reality.relationship_propositions p
      where p.relationship_kind=old.relationship_kind
      union all
      select 1 from reality.entity_relationships r
      where r.relationship_kind=old.relationship_kind
    ) into v_in_use;

    if v_in_use and (
      new.relationship_kind<>old.relationship_kind
      or new.inverse_relationship_kind is distinct from old.inverse_relationship_kind
      or new.symmetric<>old.symmetric
      or new.allowed_subject_kinds is distinct from old.allowed_subject_kinds
      or new.allowed_object_kinds is distinct from old.allowed_object_kinds
    ) then
      raise exception 'Relationship kind semantics are immutable after first use.' using errcode='23514';
    end if;

    if old.kind_state='retired' and new.kind_state<>'retired' then
      raise exception 'Retired relationship kind cannot be reactivated in v1.' using errcode='23514';
    end if;

    if new.kind_state='retired' and old.kind_state<>'retired' and new.retired_at is null then
      new.retired_at:=now();
    end if;
    new.updated_at:=now();
  end if;
  return new;
end
$function$;

create trigger reality_guard_relationship_kind_v1
before update on reality.relationship_kinds
for each row execute function reality.guard_relationship_kind_v1();

create or replace function reality.guard_relationship_proposition_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    if new.subject_entity_id<>old.subject_entity_id
       or new.relationship_kind<>old.relationship_kind
       or new.object_entity_id<>old.object_entity_id
       or new.requested_relationship_state<>old.requested_relationship_state
       or new.valid_from is distinct from old.valid_from
       or new.valid_until is distinct from old.valid_until
       or new.proposition_basis<>old.proposition_basis
       or new.provenance<>old.provenance
       or new.idempotency_key is distinct from old.idempotency_key
       or new.created_at<>old.created_at then
      raise exception 'Relationship proposition semantic content is immutable.' using errcode='23514';
    end if;

    if old.proposition_state<>'open' and new.proposition_state<>old.proposition_state then
      raise exception 'Terminal relationship proposition cannot transition again in v1.' using errcode='23514';
    end if;

    if old.proposition_state='open' and new.proposition_state='open' and new.decided_at is distinct from old.decided_at then
      raise exception 'Open relationship proposition cannot have decided_at.' using errcode='23514';
    end if;

    if new.proposition_state<>'open' and new.decided_at is null then
      new.decided_at:=now();
    end if;
  end if;
  return new;
end
$function$;

create trigger reality_guard_relationship_proposition_v1
before update on reality.relationship_propositions
for each row execute function reality.guard_relationship_proposition_v1();

create or replace function reality.prevent_relationship_evidence_mutation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  raise exception 'Relationship proposition evidence is append-only.' using errcode='23514';
end
$function$;

create trigger reality_prevent_relationship_evidence_mutation_v1
before update or delete on reality.relationship_proposition_evidence
for each row execute function reality.prevent_relationship_evidence_mutation_v1();

create or replace function reality.prevent_relationship_adjudication_mutation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  raise exception 'Relationship proposition adjudications are append-only.' using errcode='23514';
end
$function$;

create trigger reality_prevent_relationship_adjudication_mutation_v1
before update or delete on reality.relationship_proposition_adjudications
for each row execute function reality.prevent_relationship_adjudication_mutation_v1();

create or replace function reality.validate_relationship_proposition_v1(
  p_subject_entity_id uuid,
  p_relationship_kind text,
  p_object_entity_id uuid,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null
)
returns void
language plpgsql
stable
set search_path=''
as $function$
declare
  v_subject reality.entities%rowtype;
  v_object reality.entities%rowtype;
  v_kind reality.relationship_kinds%rowtype;
begin
  if p_subject_entity_id is null or p_object_entity_id is null then
    raise exception 'Relationship subject and object Entities are required.' using errcode='22023';
  end if;
  if p_subject_entity_id=p_object_entity_id then
    raise exception 'Self relationship is not permitted in v1.' using errcode='23514';
  end if;
  if nullif(btrim(p_relationship_kind),'') is null then
    raise exception 'Relationship kind is required.' using errcode='22023';
  end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until<=p_valid_from then
    raise exception 'Relationship valid_until must be greater than valid_from.' using errcode='22023';
  end if;

  select * into v_subject
  from reality.entities
  where id=p_subject_entity_id and identity_state<>'retired';
  if v_subject.id is null then
    raise exception 'Active canonical subject Entity required.' using errcode='P0002';
  end if;

  select * into v_object
  from reality.entities
  where id=p_object_entity_id and identity_state<>'retired';
  if v_object.id is null then
    raise exception 'Active canonical object Entity required.' using errcode='P0002';
  end if;

  select * into v_kind
  from reality.relationship_kinds
  where relationship_kind=btrim(p_relationship_kind)
    and kind_state='active';
  if v_kind.relationship_kind is null then
    raise exception 'Active governed relationship kind required: %',p_relationship_kind using errcode='23514';
  end if;

  if v_kind.allowed_subject_kinds is not null
     and not (v_subject.entity_kind=any(v_kind.allowed_subject_kinds)) then
    raise exception 'Subject Entity kind % is not permitted for relationship kind %.',v_subject.entity_kind,v_kind.relationship_kind using errcode='23514';
  end if;

  if v_kind.allowed_object_kinds is not null
     and not (v_object.entity_kind=any(v_kind.allowed_object_kinds)) then
    raise exception 'Object Entity kind % is not permitted for relationship kind %.',v_object.entity_kind,v_kind.relationship_kind using errcode='23514';
  end if;
end
$function$;

create or replace function reality.register_relationship_kind_service_v1(
  p_relationship_kind text,
  p_display_name text,
  p_description text default '',
  p_inverse_relationship_kind text default null,
  p_symmetric boolean default false,
  p_allowed_subject_kinds text[] default null,
  p_allowed_object_kinds text[] default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_existing reality.relationship_kinds%rowtype;
  v_key text:=nullif(btrim(p_relationship_kind),'');
begin
  if v_key is null or nullif(btrim(p_display_name),'') is null then
    raise exception 'Relationship kind key and display name are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Relationship kind metadata must be a JSON object.' using errcode='22023';
  end if;
  if p_symmetric and p_inverse_relationship_kind is not null then
    raise exception 'Symmetric relationship kind cannot also declare an inverse kind in v1.' using errcode='23514';
  end if;
  if p_allowed_subject_kinds is not null and cardinality(p_allowed_subject_kinds)=0 then
    raise exception 'Allowed subject kinds must be null or non-empty.' using errcode='22023';
  end if;
  if p_allowed_object_kinds is not null and cardinality(p_allowed_object_kinds)=0 then
    raise exception 'Allowed object kinds must be null or non-empty.' using errcode='22023';
  end if;

  select * into v_existing
  from reality.relationship_kinds
  where relationship_kind=v_key;

  if v_existing.relationship_kind is not null then
    if v_existing.kind_state='active'
       and v_existing.display_name=btrim(p_display_name)
       and v_existing.description=coalesce(p_description,'')
       and v_existing.inverse_relationship_kind is not distinct from nullif(btrim(p_inverse_relationship_kind),'')
       and v_existing.symmetric=p_symmetric
       and v_existing.allowed_subject_kinds is not distinct from p_allowed_subject_kinds
       and v_existing.allowed_object_kinds is not distinct from p_allowed_object_kinds
       and v_existing.metadata=p_metadata then
      return jsonb_build_object(
        'contractVersion','reality_relationship_kind_registration_v1',
        'relationshipKind',v_key,
        'state','existing'
      );
    end if;
    raise exception 'Relationship kind % already exists with different semantics or state.',v_key using errcode='23505';
  end if;

  insert into reality.relationship_kinds(
    relationship_kind,display_name,description,inverse_relationship_kind,symmetric,
    allowed_subject_kinds,allowed_object_kinds,metadata
  ) values (
    v_key,btrim(p_display_name),coalesce(p_description,''),nullif(btrim(p_inverse_relationship_kind),''),p_symmetric,
    p_allowed_subject_kinds,p_allowed_object_kinds,p_metadata
  );

  return jsonb_build_object(
    'contractVersion','reality_relationship_kind_registration_v1',
    'relationshipKind',v_key,
    'state','registered'
  );
end
$function$;

create or replace function reality.relationship_proposition_receipt_v1(p_proposition_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  select jsonb_build_object(
    'contractVersion','reality_relationship_proposition_receipt_v1',
    'propositionId',p.id,
    'subjectEntityId',p.subject_entity_id,
    'relationshipKind',p.relationship_kind,
    'objectEntityId',p.object_entity_id,
    'requestedRelationshipState',p.requested_relationship_state,
    'propositionState',p.proposition_state,
    'validFrom',p.valid_from,
    'validUntil',p.valid_until,
    'propositionBasis',p.proposition_basis,
    'provenance',p.provenance,
    'evidenceCount',(select count(*) from reality.relationship_proposition_evidence e where e.proposition_id=p.id),
    'adjudication',(
      select jsonb_build_object(
        'id',a.id,
        'decision',a.decision,
        'rationale',a.rationale,
        'authorityBasis',a.authority_basis,
        'adjudicatedByPrincipalId',a.adjudicated_by_principal_id,
        'resultingRelationshipId',a.resulting_relationship_id,
        'createdAt',a.created_at
      )
      from reality.relationship_proposition_adjudications a
      where a.proposition_id=p.id
    ),
    'createdAt',p.created_at,
    'decidedAt',p.decided_at
  )
  from reality.relationship_propositions p
  where p.id=p_proposition_id
$function$;

create or replace function reality.record_relationship_proposition_service_v1(
  p_subject_entity_id uuid,
  p_relationship_kind text,
  p_object_entity_id uuid,
  p_requested_relationship_state text default 'observed',
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null,
  p_proposition_basis jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_id uuid;
  v_key text:=nullif(btrim(p_idempotency_key),'');
begin
  if p_requested_relationship_state not in ('observed','established') then
    raise exception 'Requested relationship state must be observed or established.' using errcode='22023';
  end if;
  if p_proposition_basis is null or jsonb_typeof(p_proposition_basis)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Proposition basis and provenance must be JSON objects.' using errcode='22023';
  end if;

  perform reality.validate_relationship_proposition_v1(
    p_subject_entity_id,btrim(p_relationship_kind),p_object_entity_id,p_valid_from,p_valid_until
  );

  if v_key is not null then
    select id into v_id from reality.relationship_propositions where idempotency_key=v_key;
    if v_id is not null then
      return reality.relationship_proposition_receipt_v1(v_id);
    end if;
  end if;

  insert into reality.relationship_propositions(
    subject_entity_id,relationship_kind,object_entity_id,requested_relationship_state,
    valid_from,valid_until,proposition_basis,provenance,idempotency_key
  ) values (
    p_subject_entity_id,btrim(p_relationship_kind),p_object_entity_id,p_requested_relationship_state,
    p_valid_from,p_valid_until,p_proposition_basis,p_provenance,v_key
  ) returning id into v_id;

  return reality.relationship_proposition_receipt_v1(v_id);
end
$function$;

create or replace function reality.add_relationship_proposition_evidence_service_v1(
  p_proposition_id uuid,
  p_evidence_kind text,
  p_source_locator jsonb default '{}'::jsonb,
  p_evidence_snapshot jsonb default '{}'::jsonb,
  p_note text default null,
  p_observed_at timestamptz default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_proposition reality.relationship_propositions%rowtype;
  v_evidence_id uuid;
begin
  if nullif(btrim(p_evidence_kind),'') is null then
    raise exception 'Evidence kind is required.' using errcode='22023';
  end if;
  if p_source_locator is null or jsonb_typeof(p_source_locator)<>'object'
     or p_evidence_snapshot is null or jsonb_typeof(p_evidence_snapshot)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Evidence locator, snapshot, and provenance must be JSON objects.' using errcode='22023';
  end if;

  select * into v_proposition
  from reality.relationship_propositions
  where id=p_proposition_id
  for update;
  if v_proposition.id is null then
    raise exception 'Relationship proposition not found.' using errcode='P0002';
  end if;
  if v_proposition.proposition_state<>'open' then
    raise exception 'Evidence may be appended only while relationship proposition is open in v1.' using errcode='23514';
  end if;

  insert into reality.relationship_proposition_evidence(
    proposition_id,evidence_kind,source_locator,evidence_snapshot,note,observed_at,provenance
  ) values (
    p_proposition_id,btrim(p_evidence_kind),p_source_locator,p_evidence_snapshot,p_note,p_observed_at,p_provenance
  ) returning id into v_evidence_id;

  return jsonb_build_object(
    'contractVersion','reality_relationship_proposition_evidence_v1',
    'evidenceId',v_evidence_id,
    'proposition',reality.relationship_proposition_receipt_v1(p_proposition_id)
  );
end
$function$;

create or replace function reality.adjudicate_relationship_proposition_service_v1(
  p_proposition_id uuid,
  p_decision text,
  p_rationale text,
  p_authority_basis jsonb default '{}'::jsonb,
  p_adjudicated_by_principal_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_proposition reality.relationship_propositions%rowtype;
  v_relationship_id uuid;
  v_existing_state text;
  v_desired_state text;
  v_adjudication_id uuid;
  v_evidence_ids jsonb;
  v_evidence_count integer;
begin
  if p_decision not in ('accept','reject','dispute') then
    raise exception 'Decision must be accept, reject, or dispute.' using errcode='22023';
  end if;
  if nullif(btrim(p_rationale),'') is null then
    raise exception 'Adjudication rationale is required.' using errcode='22023';
  end if;
  if p_authority_basis is null or jsonb_typeof(p_authority_basis)<>'object' then
    raise exception 'Authority basis must be a JSON object.' using errcode='22023';
  end if;

  if p_adjudicated_by_principal_id is not null and not exists(
    select 1 from atlas.principals pr
    where pr.id=p_adjudicated_by_principal_id and pr.status='active'
  ) then
    raise exception 'Active adjudicating Principal required when supplied.' using errcode='23514';
  end if;

  select * into v_proposition
  from reality.relationship_propositions
  where id=p_proposition_id
  for update;
  if v_proposition.id is null then
    raise exception 'Relationship proposition not found.' using errcode='P0002';
  end if;
  if v_proposition.proposition_state<>'open' then
    return reality.relationship_proposition_receipt_v1(p_proposition_id);
  end if;

  perform reality.validate_relationship_proposition_v1(
    v_proposition.subject_entity_id,v_proposition.relationship_kind,v_proposition.object_entity_id,
    v_proposition.valid_from,v_proposition.valid_until
  );

  select count(*),coalesce(jsonb_agg(e.id order by e.created_at,e.id),'[]'::jsonb)
  into v_evidence_count,v_evidence_ids
  from reality.relationship_proposition_evidence e
  where e.proposition_id=p_proposition_id;

  if p_decision in ('accept','dispute') and v_evidence_count=0 then
    raise exception 'Accepted or disputed relationship proposition requires evidence.' using errcode='23514';
  end if;

  if p_decision='reject' then
    insert into reality.relationship_proposition_adjudications(
      proposition_id,decision,rationale,authority_basis,adjudicated_by_principal_id
    ) values (
      p_proposition_id,p_decision,btrim(p_rationale),p_authority_basis,p_adjudicated_by_principal_id
    ) returning id into v_adjudication_id;

    update reality.relationship_propositions
    set proposition_state='rejected',decided_at=now()
    where id=p_proposition_id;

    return reality.relationship_proposition_receipt_v1(p_proposition_id);
  end if;

  v_desired_state:=case when p_decision='dispute' then 'disputed' else v_proposition.requested_relationship_state end;

  select r.id,r.relationship_state
  into v_relationship_id,v_existing_state
  from reality.entity_relationships r
  where r.subject_entity_id=v_proposition.subject_entity_id
    and r.relationship_kind=v_proposition.relationship_kind
    and r.object_entity_id=v_proposition.object_entity_id
    and r.valid_from is not distinct from v_proposition.valid_from
    and r.valid_until is not distinct from v_proposition.valid_until
    and r.relationship_state<>'retired'
  order by r.created_at,r.id
  limit 1
  for update;

  if v_relationship_id is not null and v_existing_state<>v_desired_state then
    raise exception 'Conflicting active canonical relationship state % exists; v1 requires explicit conflict resolution.',v_existing_state using errcode='23514';
  end if;

  if v_relationship_id is null then
    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,valid_until,evidence,metadata
    ) values (
      v_proposition.subject_entity_id,
      v_proposition.relationship_kind,
      v_proposition.object_entity_id,
      v_desired_state,
      v_proposition.valid_from,
      v_proposition.valid_until,
      jsonb_build_object(
        'admittedFrom','relationship_proposition',
        'propositionId',v_proposition.id,
        'evidenceIds',v_evidence_ids
      ),
      jsonb_build_object(
        'admissionContract','ATLAS_REALITY_RELATIONSHIP_SUBSTRATE_V1'
      )
    ) returning id into v_relationship_id;
  end if;

  insert into reality.relationship_proposition_adjudications(
    proposition_id,decision,rationale,authority_basis,adjudicated_by_principal_id,resulting_relationship_id
  ) values (
    p_proposition_id,p_decision,btrim(p_rationale),p_authority_basis,p_adjudicated_by_principal_id,v_relationship_id
  ) returning id into v_adjudication_id;

  update reality.relationship_propositions
  set proposition_state=case when p_decision='dispute' then 'disputed' else 'accepted' end,
      decided_at=now()
  where id=p_proposition_id;

  return reality.relationship_proposition_receipt_v1(p_proposition_id);
end
$function$;

revoke all on function reality.validate_relationship_proposition_v1(uuid,text,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function reality.register_relationship_kind_service_v1(text,text,text,text,boolean,text[],text[],jsonb) from public,anon,authenticated;
revoke all on function reality.relationship_proposition_receipt_v1(uuid) from public,anon,authenticated;
revoke all on function reality.record_relationship_proposition_service_v1(uuid,text,uuid,text,timestamptz,timestamptz,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function reality.add_relationship_proposition_evidence_service_v1(uuid,text,jsonb,jsonb,text,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function reality.adjudicate_relationship_proposition_service_v1(uuid,text,text,jsonb,uuid) from public,anon,authenticated;

grant execute on function reality.validate_relationship_proposition_v1(uuid,text,uuid,timestamptz,timestamptz) to service_role;
grant execute on function reality.register_relationship_kind_service_v1(text,text,text,text,boolean,text[],text[],jsonb) to service_role;
grant execute on function reality.relationship_proposition_receipt_v1(uuid) to service_role;
grant execute on function reality.record_relationship_proposition_service_v1(uuid,text,uuid,text,timestamptz,timestamptz,jsonb,jsonb,text) to service_role;
grant execute on function reality.add_relationship_proposition_evidence_service_v1(uuid,text,jsonb,jsonb,text,timestamptz,jsonb) to service_role;
grant execute on function reality.adjudicate_relationship_proposition_service_v1(uuid,text,text,jsonb,uuid) to service_role;

comment on table reality.relationship_kinds is
  'Governed universal vocabulary for canonical Reality relationship semantics.';
comment on table reality.relationship_propositions is
  'Pre-canonical relationship propositions. A proposition is not Reality truth until admitted.';
comment on table reality.relationship_proposition_evidence is
  'Append-only evidence attached to a relationship proposition.';
comment on table reality.relationship_proposition_adjudications is
  'Append-only terminal adjudication receipts for relationship propositions.';
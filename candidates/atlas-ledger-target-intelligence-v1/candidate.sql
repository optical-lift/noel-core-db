-- Atlas Ledger Target Intelligence v1
-- Internal-only deterministic Target Definition / Evaluation substrate.
-- No browser RPC, no acquisition, no ranking, no outreach.

create table ledger.target_purposes (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  stable_key text not null check (btrim(stable_key)<>''),
  name text not null check (btrim(name)<>''),
  purpose_statement text not null check (btrim(purpose_statement)<>''),
  purpose_state text not null default 'active'
    check (purpose_state in ('active','retired')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz null,
  unique(ledger_id,stable_key)
);
create index ledger_target_purposes_ledger_idx
  on ledger.target_purposes(ledger_id,purpose_state,created_at desc);

create table ledger.target_definitions (
  id uuid primary key default gen_random_uuid(),
  purpose_id uuid not null references ledger.target_purposes(id) on delete cascade,
  stable_key text not null check (btrim(stable_key)<>''),
  name text not null check (btrim(name)<>''),
  definition_state text not null default 'active'
    check (definition_state in ('active','retired')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz null,
  unique(purpose_id,stable_key)
);
create index ledger_target_definitions_purpose_idx
  on ledger.target_definitions(purpose_id,definition_state,created_at desc);

create table ledger.target_definition_versions (
  id uuid primary key default gen_random_uuid(),
  target_definition_id uuid not null references ledger.target_definitions(id) on delete cascade,
  version_number integer not null check (version_number>0),
  predicate jsonb not null check (jsonb_typeof(predicate)='object'),
  version_state text not null default 'draft'
    check (version_state in ('draft','active','retired')),
  definition_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(definition_basis)='object'),
  created_at timestamptz not null default now(),
  activated_at timestamptz null,
  retired_at timestamptz null,
  unique(target_definition_id,version_number)
);
create unique index ledger_target_definition_versions_one_active_idx
  on ledger.target_definition_versions(target_definition_id)
  where version_state='active';
create index ledger_target_definition_versions_definition_idx
  on ledger.target_definition_versions(target_definition_id,version_number desc);

create table ledger.target_evaluations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  target_definition_version_id uuid not null references ledger.target_definition_versions(id) on delete restrict,
  subject_entity_id uuid not null references reality.entities(id) on delete restrict,
  evaluation_state text not null
    check (evaluation_state in ('qualified','not_qualified','indeterminate')),
  evaluator_key text not null check (btrim(evaluator_key)<>''),
  evaluator_version text not null check (btrim(evaluator_version)<>''),
  predicate_result jsonb not null check (jsonb_typeof(predicate_result)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  evaluated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index ledger_target_evaluations_idempotency_idx
  on ledger.target_evaluations(ledger_id,idempotency_key)
  where idempotency_key is not null;
create index ledger_target_evaluations_subject_idx
  on ledger.target_evaluations(ledger_id,subject_entity_id,evaluated_at desc,id);
create index ledger_target_evaluations_version_idx
  on ledger.target_evaluations(target_definition_version_id,evaluated_at desc,id);

create table ledger.target_evidence_obligations (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null references ledger.target_evaluations(id) on delete cascade,
  predicate_path text not null check (btrim(predicate_path)<>''),
  obligation_kind text not null check (obligation_kind='resolve_relationship_proposition'),
  proposition jsonb not null check (jsonb_typeof(proposition)='object'),
  obligation_state text not null default 'open'
    check (obligation_state in ('open','satisfied','superseded','cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolution_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_basis)='object'),
  unique(evaluation_id,predicate_path,obligation_kind)
);
create index ledger_target_evidence_obligations_open_idx
  on ledger.target_evidence_obligations(evaluation_id,predicate_path)
  where obligation_state='open';

alter table ledger.target_purposes enable row level security;
alter table ledger.target_definitions enable row level security;
alter table ledger.target_definition_versions enable row level security;
alter table ledger.target_evaluations enable row level security;
alter table ledger.target_evidence_obligations enable row level security;

revoke all on table ledger.target_purposes from anon,authenticated;
revoke all on table ledger.target_definitions from anon,authenticated;
revoke all on table ledger.target_definition_versions from anon,authenticated;
revoke all on table ledger.target_evaluations from anon,authenticated;
revoke all on table ledger.target_evidence_obligations from anon,authenticated;

grant select,insert,update,delete on table ledger.target_purposes to service_role;
grant select,insert,update,delete on table ledger.target_definitions to service_role;
grant select,insert,update,delete on table ledger.target_definition_versions to service_role;
grant select,insert,update,delete on table ledger.target_evaluations to service_role;
grant select,insert,update,delete on table ledger.target_evidence_obligations to service_role;

create or replace function ledger.validate_target_predicate_v1(
  p_predicate jsonb,
  p_depth integer default 0
)
returns void
language plpgsql
immutable
set search_path=''
as $function$
declare
  v_op text;
  v_child jsonb;
  v_entity_id uuid;
  v_counterparty_id uuid;
begin
  if p_depth<0 or p_depth>12 then
    raise exception 'Target predicate nesting exceeds v1 limit.' using errcode='22023';
  end if;

  if p_predicate is null or jsonb_typeof(p_predicate)<>'object' then
    raise exception 'Target predicate must be a JSON object.' using errcode='22023';
  end if;

  v_op:=nullif(btrim(p_predicate->>'op'),'');
  if v_op is null then
    raise exception 'Target predicate op is required.' using errcode='22023';
  end if;

  if v_op in ('all','any') then
    if p_predicate - 'op' - 'predicates' <> '{}'::jsonb then
      raise exception 'Target % predicate contains unsupported fields.',v_op using errcode='22023';
    end if;
    if jsonb_typeof(p_predicate->'predicates')<>'array'
       or jsonb_array_length(p_predicate->'predicates')=0 then
      raise exception 'Target % predicate requires a non-empty predicates array.',v_op using errcode='22023';
    end if;
    for v_child in select value from jsonb_array_elements(p_predicate->'predicates') loop
      perform ledger.validate_target_predicate_v1(v_child,p_depth+1);
    end loop;
    return;
  end if;

  if v_op='not' then
    if p_predicate - 'op' - 'predicate' <> '{}'::jsonb then
      raise exception 'Target not predicate contains unsupported fields.' using errcode='22023';
    end if;
    if jsonb_typeof(p_predicate->'predicate')<>'object' then
      raise exception 'Target not predicate requires one nested predicate.' using errcode='22023';
    end if;
    perform ledger.validate_target_predicate_v1(p_predicate->'predicate',p_depth+1);
    return;
  end if;

  if v_op='entity_kind_is' then
    if p_predicate - 'op' - 'entityKind' <> '{}'::jsonb then
      raise exception 'entity_kind_is contains unsupported fields.' using errcode='22023';
    end if;
    if nullif(btrim(p_predicate->>'entityKind'),'') is null then
      raise exception 'entity_kind_is requires entityKind.' using errcode='22023';
    end if;
    return;
  end if;

  if v_op='entity_id_is' then
    if p_predicate - 'op' - 'entityId' <> '{}'::jsonb then
      raise exception 'entity_id_is contains unsupported fields.' using errcode='22023';
    end if;
    if nullif(btrim(p_predicate->>'entityId'),'') is null then
      raise exception 'entity_id_is requires entityId.' using errcode='22023';
    end if;
    begin
      v_entity_id:=(p_predicate->>'entityId')::uuid;
    exception when invalid_text_representation then
      raise exception 'entity_id_is requires a valid UUID.' using errcode='22023';
    end;
    return;
  end if;

  if v_op='relationship_exists' then
    if p_predicate - 'op' - 'relationshipKind' - 'direction' - 'counterpartyEntityId' <> '{}'::jsonb then
      raise exception 'relationship_exists contains unsupported fields.' using errcode='22023';
    end if;
    if nullif(btrim(p_predicate->>'relationshipKind'),'') is null then
      raise exception 'relationship_exists requires relationshipKind.' using errcode='22023';
    end if;
    if coalesce(p_predicate->>'direction','') not in ('outbound','inbound') then
      raise exception 'relationship_exists direction must be outbound or inbound.' using errcode='22023';
    end if;
    if nullif(btrim(p_predicate->>'counterpartyEntityId'),'') is null then
      raise exception 'relationship_exists requires counterpartyEntityId.' using errcode='22023';
    end if;
    begin
      v_counterparty_id:=(p_predicate->>'counterpartyEntityId')::uuid;
    exception when invalid_text_representation then
      raise exception 'relationship_exists requires a valid counterpartyEntityId UUID.' using errcode='22023';
    end;
    return;
  end if;

  raise exception 'Unsupported Target predicate op: %',v_op using errcode='22023';
end
$function$;

create or replace function ledger.guard_target_definition_version_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  perform ledger.validate_target_predicate_v1(new.predicate,0);

  if tg_op='UPDATE' then
    if new.target_definition_id<>old.target_definition_id
       or new.version_number<>old.version_number
       or new.predicate<>old.predicate
       or new.definition_basis<>old.definition_basis
       or new.created_at<>old.created_at then
      raise exception 'Target Definition Version semantic content is immutable.' using errcode='23514';
    end if;

    if old.version_state='retired' and new.version_state<>old.version_state then
      raise exception 'Retired Target Definition Version cannot be reactivated.' using errcode='23514';
    end if;
    if old.version_state='active' and new.version_state='draft' then
      raise exception 'Active Target Definition Version cannot return to draft.' using errcode='23514';
    end if;
  end if;

  if new.version_state='active' and new.activated_at is null then
    new.activated_at:=now();
  end if;
  if new.version_state='retired' and new.retired_at is null then
    new.retired_at:=now();
  end if;
  return new;
end
$function$;

create trigger ledger_target_definition_version_guard_v1
before insert or update on ledger.target_definition_versions
for each row execute function ledger.guard_target_definition_version_v1();

create or replace function ledger.evaluate_target_predicate_v1(
  p_subject_entity_id uuid,
  p_predicate jsonb,
  p_path text default '$',
  p_depth integer default 0
)
returns jsonb
language plpgsql
stable
set search_path=''
as $function$
declare
  v_op text;
  v_subject reality.entities%rowtype;
  v_child jsonb;
  v_child_result jsonb;
  v_children jsonb:='[]'::jsonb;
  v_obligations jsonb:='[]'::jsonb;
  v_state text;
  v_child_state text;
  v_idx bigint;
  v_true_count integer:=0;
  v_false_count integer:=0;
  v_unknown_count integer:=0;
  v_entity_id uuid;
  v_counterparty_id uuid;
  v_counterparty reality.entities%rowtype;
  v_relationship_kind text;
  v_direction text;
  v_subject_side uuid;
  v_object_side uuid;
  v_relationship_ids jsonb:='[]'::jsonb;
  v_disputed boolean:=false;
begin
  perform ledger.validate_target_predicate_v1(p_predicate,p_depth);

  select * into v_subject
  from reality.entities
  where id=p_subject_entity_id
    and identity_state<>'retired';

  if v_subject.id is null then
    raise exception 'Active Reality subject Entity required.' using errcode='P0002';
  end if;

  v_op:=p_predicate->>'op';

  if v_op in ('all','any') then
    for v_child,v_idx in
      select value,ordinality
      from jsonb_array_elements(p_predicate->'predicates') with ordinality
    loop
      v_child_result:=ledger.evaluate_target_predicate_v1(
        p_subject_entity_id,
        v_child,
        p_path||'.predicates['||(v_idx-1)::text||']',
        p_depth+1
      );
      v_children:=v_children||jsonb_build_array(v_child_result);
      v_obligations:=v_obligations||coalesce(v_child_result->'obligations','[]'::jsonb);
      v_child_state:=v_child_result->>'state';
      if v_child_state='true' then v_true_count:=v_true_count+1;
      elsif v_child_state='false' then v_false_count:=v_false_count+1;
      else v_unknown_count:=v_unknown_count+1;
      end if;
    end loop;

    if v_op='all' then
      if v_false_count>0 then v_state:='false';
      elsif v_unknown_count>0 then v_state:='unknown';
      else v_state:='true';
      end if;
    else
      if v_true_count>0 then v_state:='true';
      elsif v_unknown_count>0 then v_state:='unknown';
      else v_state:='false';
      end if;
    end if;

    return jsonb_build_object(
      'path',p_path,
      'op',v_op,
      'state',v_state,
      'children',v_children,
      'obligations',v_obligations
    );
  end if;

  if v_op='not' then
    v_child_result:=ledger.evaluate_target_predicate_v1(
      p_subject_entity_id,
      p_predicate->'predicate',
      p_path||'.predicate',
      p_depth+1
    );
    v_child_state:=v_child_result->>'state';
    v_state:=case v_child_state when 'true' then 'false' when 'false' then 'true' else 'unknown' end;
    return jsonb_build_object(
      'path',p_path,
      'op',v_op,
      'state',v_state,
      'child',v_child_result,
      'obligations',coalesce(v_child_result->'obligations','[]'::jsonb)
    );
  end if;

  if v_op='entity_kind_is' then
    v_state:=case when v_subject.entity_kind=p_predicate->>'entityKind' then 'true' else 'false' end;
    return jsonb_build_object(
      'path',p_path,
      'op',v_op,
      'state',v_state,
      'expectedEntityKind',p_predicate->>'entityKind',
      'actualEntityKind',v_subject.entity_kind,
      'obligations','[]'::jsonb
    );
  end if;

  if v_op='entity_id_is' then
    v_entity_id:=(p_predicate->>'entityId')::uuid;
    v_state:=case when p_subject_entity_id=v_entity_id then 'true' else 'false' end;
    return jsonb_build_object(
      'path',p_path,
      'op',v_op,
      'state',v_state,
      'expectedEntityId',v_entity_id,
      'actualEntityId',p_subject_entity_id,
      'obligations','[]'::jsonb
    );
  end if;

  if v_op='relationship_exists' then
    v_counterparty_id:=(p_predicate->>'counterpartyEntityId')::uuid;
    v_relationship_kind:=p_predicate->>'relationshipKind';
    v_direction:=p_predicate->>'direction';

    select * into v_counterparty
    from reality.entities
    where id=v_counterparty_id
      and identity_state<>'retired';

    if v_counterparty.id is null then
      raise exception 'Target predicate counterparty Reality Entity is absent or retired.' using errcode='23514';
    end if;

    if v_direction='outbound' then
      v_subject_side:=p_subject_entity_id;
      v_object_side:=v_counterparty_id;
    else
      v_subject_side:=v_counterparty_id;
      v_object_side:=p_subject_entity_id;
    end if;

    select coalesce(jsonb_agg(r.id order by r.created_at,r.id),'[]'::jsonb)
    into v_relationship_ids
    from reality.entity_relationships r
    where r.subject_entity_id=v_subject_side
      and r.object_entity_id=v_object_side
      and r.relationship_kind=v_relationship_kind
      and r.relationship_state in ('observed','established')
      and (r.valid_from is null or r.valid_from<=now())
      and (r.valid_until is null or r.valid_until>now());

    if jsonb_array_length(v_relationship_ids)>0 then
      return jsonb_build_object(
        'path',p_path,
        'op',v_op,
        'state','true',
        'relationshipKind',v_relationship_kind,
        'direction',v_direction,
        'counterpartyEntityId',v_counterparty_id,
        'relationshipIds',v_relationship_ids,
        'obligations','[]'::jsonb
      );
    end if;

    select exists(
      select 1
      from reality.entity_relationships r
      where r.subject_entity_id=v_subject_side
        and r.object_entity_id=v_object_side
        and r.relationship_kind=v_relationship_kind
        and r.relationship_state='disputed'
        and (r.valid_from is null or r.valid_from<=now())
        and (r.valid_until is null or r.valid_until>now())
    ) into v_disputed;

    v_obligations:=jsonb_build_array(jsonb_build_object(
      'kind','resolve_relationship_proposition',
      'predicatePath',p_path,
      'proposition',jsonb_build_object(
        'subjectEntityId',p_subject_entity_id,
        'relationshipKind',v_relationship_kind,
        'direction',v_direction,
        'counterpartyEntityId',v_counterparty_id
      ),
      'reason',case when v_disputed then 'relationship_disputed' else 'relationship_not_established' end
    ));

    return jsonb_build_object(
      'path',p_path,
      'op',v_op,
      'state','unknown',
      'relationshipKind',v_relationship_kind,
      'direction',v_direction,
      'counterpartyEntityId',v_counterparty_id,
      'reason',case when v_disputed then 'relationship_disputed' else 'relationship_not_established' end,
      'obligations',v_obligations
    );
  end if;

  raise exception 'Unsupported Target predicate op at evaluation: %',v_op using errcode='22023';
end
$function$;

create or replace function ledger.guard_target_evaluation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_ledger_id uuid;
begin
  select p.ledger_id into v_ledger_id
  from ledger.target_definition_versions v
  join ledger.target_definitions d on d.id=v.target_definition_id
  join ledger.target_purposes p on p.id=d.purpose_id
  where v.id=new.target_definition_version_id;

  if v_ledger_id is null or v_ledger_id<>new.ledger_id then
    raise exception 'Target Evaluation Ledger must match Target Definition Purpose Ledger.' using errcode='23514';
  end if;

  return new;
end
$function$;

create trigger ledger_target_evaluation_guard_v1
before insert or update on ledger.target_evaluations
for each row execute function ledger.guard_target_evaluation_v1();

create or replace function ledger.target_evaluation_receipt_v1(p_evaluation_id uuid)
returns jsonb
language sql
stable
set search_path=''
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','ledger_target_evaluation_receipt_v1',
    'evaluationId',e.id,
    'ledgerId',e.ledger_id,
    'purpose',jsonb_build_object(
      'id',p.id,
      'stableKey',p.stable_key,
      'name',p.name,
      'statement',p.purpose_statement
    ),
    'targetDefinition',jsonb_build_object(
      'id',d.id,
      'stableKey',d.stable_key,
      'name',d.name,
      'versionId',v.id,
      'versionNumber',v.version_number
    ),
    'subjectEntity',jsonb_build_object(
      'id',s.id,
      'entityKind',s.entity_kind,
      'displayName',s.display_name,
      'identityState',s.identity_state
    ),
    'evaluationState',e.evaluation_state,
    'evaluator',jsonb_build_object(
      'key',e.evaluator_key,
      'version',e.evaluator_version
    ),
    'predicateResult',e.predicate_result,
    'evidenceObligations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',o.id,
        'predicatePath',o.predicate_path,
        'kind',o.obligation_kind,
        'state',o.obligation_state,
        'proposition',o.proposition,
        'createdAt',o.created_at,
        'resolvedAt',o.resolved_at,
        'resolutionBasis',o.resolution_basis
      ) order by o.predicate_path,o.id)
      from ledger.target_evidence_obligations o
      where o.evaluation_id=e.id
    ),'[]'::jsonb),
    'evaluatedAt',e.evaluated_at,
    'provenance',e.provenance,
    'truthBoundary',jsonb_build_object(
      'ledgerPrivate',true,
      'doesNotEstablishReality',true,
      'doesNotEstablishLedgerContext',true,
      'doesNotAuthorizeResearch',true,
      'doesNotAuthorizeCommunication',true,
      'doesNotRank',true
    )
  ))
  from ledger.target_evaluations e
  join ledger.target_definition_versions v on v.id=e.target_definition_version_id
  join ledger.target_definitions d on d.id=v.target_definition_id
  join ledger.target_purposes p on p.id=d.purpose_id
  join reality.entities s on s.id=e.subject_entity_id
  where e.id=p_evaluation_id
$function$;

create or replace function ledger.evaluate_target_definition_service_v1(
  p_target_definition_version_id uuid,
  p_subject_entity_id uuid,
  p_evaluator_key text default 'deterministic_target_predicate_v1',
  p_evaluator_version text default '1',
  p_idempotency_key text default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $function$
declare
  v_version ledger.target_definition_versions%rowtype;
  v_definition ledger.target_definitions%rowtype;
  v_purpose ledger.target_purposes%rowtype;
  v_ledger ledger.ledgers%rowtype;
  v_subject reality.entities%rowtype;
  v_result jsonb;
  v_root_state text;
  v_evaluation_state text;
  v_evaluation_id uuid;
  v_obligation jsonb;
  v_existing uuid;
begin
  if nullif(btrim(p_evaluator_key),'') is null
     or nullif(btrim(p_evaluator_version),'') is null then
    raise exception 'Evaluator key and version are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Evaluation provenance must be a JSON object.' using errcode='22023';
  end if;

  select * into v_version
  from ledger.target_definition_versions
  where id=p_target_definition_version_id
    and version_state='active';
  if v_version.id is null then
    raise exception 'Active Target Definition Version required.' using errcode='23514';
  end if;

  select * into v_definition
  from ledger.target_definitions
  where id=v_version.target_definition_id
    and definition_state='active';
  if v_definition.id is null then
    raise exception 'Active Target Definition required.' using errcode='23514';
  end if;

  select * into v_purpose
  from ledger.target_purposes
  where id=v_definition.purpose_id
    and purpose_state='active';
  if v_purpose.id is null then
    raise exception 'Active Target Purpose required.' using errcode='23514';
  end if;

  select * into v_ledger
  from ledger.ledgers
  where id=v_purpose.ledger_id
    and ledger_state='active';
  if v_ledger.id is null then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;

  select * into v_subject
  from reality.entities
  where id=p_subject_entity_id
    and identity_state<>'retired';
  if v_subject.id is null then
    raise exception 'Active Reality subject Entity required.' using errcode='P0002';
  end if;

  if p_idempotency_key is not null then
    select id into v_existing
    from ledger.target_evaluations
    where ledger_id=v_ledger.id
      and idempotency_key=p_idempotency_key;
    if v_existing is not null then
      return ledger.target_evaluation_receipt_v1(v_existing);
    end if;
  end if;

  v_result:=ledger.evaluate_target_predicate_v1(p_subject_entity_id,v_version.predicate,'$',0);
  v_root_state:=v_result->>'state';
  v_evaluation_state:=case v_root_state
    when 'true' then 'qualified'
    when 'false' then 'not_qualified'
    else 'indeterminate'
  end;

  insert into ledger.target_evaluations(
    ledger_id,
    target_definition_version_id,
    subject_entity_id,
    evaluation_state,
    evaluator_key,
    evaluator_version,
    predicate_result,
    provenance,
    idempotency_key
  ) values (
    v_ledger.id,
    v_version.id,
    p_subject_entity_id,
    v_evaluation_state,
    btrim(p_evaluator_key),
    btrim(p_evaluator_version),
    v_result,
    p_provenance,
    p_idempotency_key
  ) returning id into v_evaluation_id;

  for v_obligation in
    select value
    from jsonb_array_elements(coalesce(v_result->'obligations','[]'::jsonb))
  loop
    insert into ledger.target_evidence_obligations(
      evaluation_id,
      predicate_path,
      obligation_kind,
      proposition
    ) values (
      v_evaluation_id,
      v_obligation->>'predicatePath',
      v_obligation->>'kind',
      v_obligation->'proposition'
    )
    on conflict(evaluation_id,predicate_path,obligation_kind) do nothing;
  end loop;

  return ledger.target_evaluation_receipt_v1(v_evaluation_id);
end
$function$;

revoke all on function ledger.validate_target_predicate_v1(jsonb,integer) from public,anon,authenticated;
revoke all on function ledger.evaluate_target_predicate_v1(uuid,jsonb,text,integer) from public,anon,authenticated;
revoke all on function ledger.target_evaluation_receipt_v1(uuid) from public,anon,authenticated;
revoke all on function ledger.evaluate_target_definition_service_v1(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;

grant execute on function ledger.validate_target_predicate_v1(jsonb,integer) to service_role;
grant execute on function ledger.evaluate_target_predicate_v1(uuid,jsonb,text,integer) to service_role;
grant execute on function ledger.target_evaluation_receipt_v1(uuid) to service_role;
grant execute on function ledger.evaluate_target_definition_service_v1(uuid,uuid,text,text,text,jsonb) to service_role;

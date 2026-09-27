-- Atlas Reality Entity Reconciliation v1
--
-- Shared Intelligence and other evidence systems may propose that two already
-- admitted Reality identities are the same real-world entity. Evidence does not
-- merge Reality. This membrane makes that second act explicit, previewable,
-- human-authorized, atomic, and durable.

create table reality.entity_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  survivor_entity_id uuid not null references reality.entities(id) on delete restrict,
  superseded_entity_id uuid not null references reality.entities(id) on delete restrict,
  case_state text not null default 'proposed'
    check (case_state in ('proposed','confirmed','rejected','cancelled')),
  proposal_source_kind text not null
    check (proposal_source_kind in ('human','shared_intelligence','system')),
  source_reference jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_reference)='object'),
  proposal_basis text not null check (btrim(proposal_basis)<>''),
  proposed_by_person_entity_id uuid null references reality.entities(id) on delete restrict,
  proposal_responsibility_relation_id uuid null
    references reality.responsibility_relations(id) on delete restrict,
  impact_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(impact_snapshot)='object'),
  previewed_at timestamptz null,
  confirmed_by_person_entity_id uuid null references reality.entities(id) on delete restrict,
  confirmation_responsibility_relation_id uuid null
    references reality.responsibility_relations(id) on delete restrict,
  confirmation_basis text null,
  execution_receipt jsonb not null default '{}'::jsonb
    check (jsonb_typeof(execution_receipt)='object'),
  proposed_at timestamptz not null default now(),
  confirmed_at timestamptz null,
  rejected_at timestamptz null,
  cancelled_at timestamptz null,
  updated_at timestamptz not null default now(),
  check (survivor_entity_id<>superseded_entity_id),
  check (
    (case_state='proposed'
      and confirmed_at is null and rejected_at is null and cancelled_at is null)
    or
    (case_state='confirmed'
      and confirmed_at is not null
      and confirmed_by_person_entity_id is not null
      and confirmation_responsibility_relation_id is not null
      and confirmation_basis is not null
      and rejected_at is null and cancelled_at is null)
    or
    (case_state='rejected'
      and rejected_at is not null
      and confirmed_at is null and cancelled_at is null)
    or
    (case_state='cancelled'
      and cancelled_at is not null
      and confirmed_at is null and rejected_at is null)
  )
);

create index reality_entity_reconciliation_cases_pair_idx
  on reality.entity_reconciliation_cases(
    survivor_entity_id,superseded_entity_id,case_state,proposed_at desc
  );

create index reality_entity_reconciliation_cases_superseded_idx
  on reality.entity_reconciliation_cases(
    superseded_entity_id,case_state,proposed_at desc
  );

create table reality.entity_supersessions (
  superseded_entity_id uuid primary key references reality.entities(id) on delete restrict,
  survivor_entity_id uuid not null references reality.entities(id) on delete restrict,
  reconciliation_case_id uuid not null unique
    references reality.entity_reconciliation_cases(id) on delete restrict,
  merged_by_person_entity_id uuid not null references reality.entities(id) on delete restrict,
  responsibility_relation_id uuid not null
    references reality.responsibility_relations(id) on delete restrict,
  merge_basis text not null check (btrim(merge_basis)<>''),
  impact_snapshot jsonb not null
    check (jsonb_typeof(impact_snapshot)='object'),
  execution_receipt jsonb not null
    check (jsonb_typeof(execution_receipt)='object'),
  merged_at timestamptz not null default now(),
  check (survivor_entity_id<>superseded_entity_id)
);

create index reality_entity_supersessions_survivor_idx
  on reality.entity_supersessions(survivor_entity_id,merged_at desc);

alter table reality.entity_reconciliation_cases enable row level security;
alter table reality.entity_supersessions enable row level security;

revoke all on table reality.entity_reconciliation_cases
  from public,anon,authenticated,service_role;
revoke all on table reality.entity_supersessions
  from public,anon,authenticated,service_role;


create or replace function reality.resolve_canonical_entity_v1(
  p_entity_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  with recursive chain(entity_id,depth) as (
    select e.id,0
    from reality.entities e
    where e.id=p_entity_id

    union all

    select s.survivor_entity_id,c.depth+1
    from chain c
    join reality.entity_supersessions s
      on s.superseded_entity_id=c.entity_id
    where c.depth<32
  )
  select c.entity_id
  from chain c
  where not exists(
    select 1
    from reality.entity_supersessions s
    where s.superseded_entity_id=c.entity_id
  )
  order by c.depth desc
  limit 1;
$function$;

revoke all on function reality.resolve_canonical_entity_v1(uuid)
  from public,anon,authenticated;
grant execute on function reality.resolve_canonical_entity_v1(uuid)
  to service_role;


create or replace function reality.entity_reconciliation_impact_internal_v1(
  p_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_case reality.entity_reconciliation_cases%rowtype;
  v_survivor reality.entities%rowtype;
  v_superseded reality.entities%rowtype;
  v_fk record;
  v_survivor_count bigint;
  v_superseded_count bigint;
  v_total_superseded_refs bigint:=0;
  v_compatibility_count bigint:=0;
  v_pair_relationship_count bigint:=0;
  v_composite_fk_count bigint:=0;
  v_references jsonb:='[]'::jsonb;
  v_blockers jsonb:='[]'::jsonb;
begin
  select * into v_case
  from reality.entity_reconciliation_cases
  where id=p_case_id;

  if not found then
    raise exception 'Reality reconciliation case not found.' using errcode='22023';
  end if;

  select * into v_survivor
  from reality.entities
  where id=v_case.survivor_entity_id;

  select * into v_superseded
  from reality.entities
  where id=v_case.superseded_entity_id;

  if v_survivor.id is null or v_superseded.id is null then
    raise exception 'Both Reality entities must exist.' using errcode='23514';
  end if;

  for v_fk in
    select
      ns.nspname as schema_name,
      rel.relname as table_name,
      att.attname as column_name,
      con.conname as constraint_name
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_class rel on rel.oid=con.conrelid
    join pg_catalog.pg_namespace ns on ns.oid=rel.relnamespace
    join lateral unnest(con.conkey) with ordinality ck(attnum,ord) on true
    join lateral unnest(con.confkey) with ordinality fk(attnum,ord)
      on fk.ord=ck.ord
    join pg_catalog.pg_attribute att
      on att.attrelid=con.conrelid and att.attnum=ck.attnum
    join pg_catalog.pg_attribute target_att
      on target_att.attrelid=con.confrelid and target_att.attnum=fk.attnum
    where con.contype='f'
      and con.confrelid='reality.entities'::regclass
      and target_att.attname='id'
      and cardinality(con.conkey)=1
      and not (
        ns.nspname='reality'
        and rel.relname in ('entity_reconciliation_cases','entity_supersessions')
      )
    order by ns.nspname,rel.relname,att.attname
  loop
    execute format(
      'select count(*) filter (where %1$I=$1), count(*) filter (where %1$I=$2) from %2$I.%3$I',
      v_fk.column_name,v_fk.schema_name,v_fk.table_name
    )
    into v_survivor_count,v_superseded_count
    using v_case.survivor_entity_id,v_case.superseded_entity_id;

    if v_survivor_count<>0 or v_superseded_count<>0 then
      v_references:=v_references || jsonb_build_array(
        jsonb_build_object(
          'schema',v_fk.schema_name,
          'table',v_fk.table_name,
          'column',v_fk.column_name,
          'constraint',v_fk.constraint_name,
          'survivorReferences',v_survivor_count,
          'supersededReferences',v_superseded_count
        )
      );
      v_total_superseded_refs:=v_total_superseded_refs+v_superseded_count;
    end if;
  end loop;

  select count(*)
  into v_composite_fk_count
  from pg_catalog.pg_constraint con
  where con.contype='f'
    and con.confrelid='reality.entities'::regclass
    and cardinality(con.conkey)<>1;

  select count(*)
  into v_compatibility_count
  from compatibility.legacy_bindings lb
  where lb.new_schema='reality'
    and lb.new_table='entities'
    and lb.new_id=v_case.superseded_entity_id;

  select count(*)
  into v_pair_relationship_count
  from reality.entity_relationships er
  where (er.subject_entity_id=v_case.survivor_entity_id
         and er.object_entity_id=v_case.superseded_entity_id)
     or (er.subject_entity_id=v_case.superseded_entity_id
         and er.object_entity_id=v_case.survivor_entity_id);

  if v_survivor.identity_state<>'canonical' then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object('kind','survivor_not_canonical','entityId',v_survivor.id)
    );
  end if;

  if v_superseded.identity_state<>'canonical' then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object('kind','superseded_not_canonical','entityId',v_superseded.id)
    );
  end if;

  if v_survivor.entity_kind<>v_superseded.entity_kind then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object(
        'kind','entity_kind_mismatch',
        'survivorKind',v_survivor.entity_kind,
        'supersededKind',v_superseded.entity_kind
      )
    );
  end if;

  if exists(
    select 1 from reality.entity_supersessions s
    where s.superseded_entity_id in (
      v_case.survivor_entity_id,v_case.superseded_entity_id
    )
  ) then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object('kind','existing_supersession')
    );
  end if;

  if v_pair_relationship_count<>0 then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object(
        'kind','direct_relationship_between_candidates',
        'count',v_pair_relationship_count,
        'reason','Repointing would create a self-relationship; adjudicate that relationship first.'
      )
    );
  end if;

  if v_composite_fk_count<>0 then
    v_blockers:=v_blockers || jsonb_build_array(
      jsonb_build_object(
        'kind','unsupported_composite_reality_foreign_key',
        'count',v_composite_fk_count,
        'reason','Reconciliation v1 rewrites only direct single-column Reality Entity foreign keys.'
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'survivor',jsonb_build_object(
      'entityId',v_survivor.id,
      'stableKey',v_survivor.stable_key,
      'entityKind',v_survivor.entity_kind,
      'displayName',v_survivor.display_name,
      'identityState',v_survivor.identity_state
    ),
    'superseded',jsonb_build_object(
      'entityId',v_superseded.id,
      'stableKey',v_superseded.stable_key,
      'entityKind',v_superseded.entity_kind,
      'displayName',v_superseded.display_name,
      'identityState',v_superseded.identity_state
    ),
    'directReferences',v_references,
    'supersededDirectReferenceCount',v_total_superseded_refs,
    'compatibilityBindingsToRewrite',v_compatibility_count,
    'knownBlockers',v_blockers,
    'canAttemptConfirmation',jsonb_array_length(v_blockers)=0,
    'constraintBoundary',jsonb_build_object(
      'atomic',true,
      'dependentConstraintFailureAbortsEntireMerge',true,
      'previewCannotPromiseAllDependentUniqueOrCheckConstraintsWillAcceptTheRewrite',true
    )
  );
end
$function$;

revoke all on function reality.entity_reconciliation_impact_internal_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function reality.open_entity_reconciliation_case_internal_v1(
  p_survivor_entity_id uuid,
  p_superseded_entity_id uuid,
  p_proposal_source_kind text,
  p_source_reference jsonb,
  p_proposal_basis text,
  p_proposed_by_person_entity_id uuid,
  p_proposal_responsibility_relation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_case_id uuid;
  v_survivor reality.entities%rowtype;
  v_superseded reality.entities%rowtype;
  v_lock_key text;
  v_impact jsonb;
begin
  if p_survivor_entity_id is null
     or p_superseded_entity_id is null
     or p_survivor_entity_id=p_superseded_entity_id then
    raise exception 'Two distinct Reality entities are required.' using errcode='22023';
  end if;

  if p_proposal_source_kind not in ('human','shared_intelligence','system') then
    raise exception 'Unsupported reconciliation proposal source.' using errcode='22023';
  end if;

  if p_source_reference is null or jsonb_typeof(p_source_reference)<>'object' then
    raise exception 'source_reference must be a JSON object.' using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_proposal_basis,'')),'') is null then
    raise exception 'A proposal basis is required.' using errcode='22023';
  end if;

  if length(p_proposal_basis)>8000 then
    raise exception 'Proposal basis is too long.' using errcode='22023';
  end if;

  v_lock_key:=least(p_survivor_entity_id::text,p_superseded_entity_id::text)
    ||':'
    ||greatest(p_survivor_entity_id::text,p_superseded_entity_id::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_lock_key,0));

  select * into v_survivor
  from reality.entities
  where id=p_survivor_entity_id;

  select * into v_superseded
  from reality.entities
  where id=p_superseded_entity_id;

  if v_survivor.id is null or v_superseded.id is null then
    raise exception 'Both proposed Reality entities must exist.' using errcode='22023';
  end if;

  if v_survivor.identity_state<>'canonical'
     or v_superseded.identity_state<>'canonical' then
    raise exception 'Both proposed Reality entities must currently be canonical.'
      using errcode='23514';
  end if;

  if v_survivor.entity_kind<>v_superseded.entity_kind then
    raise exception 'Reality reconciliation v1 requires matching entity kinds.'
      using errcode='23514';
  end if;

  if p_proposed_by_person_entity_id is not null then
    if not exists(
      select 1 from reality.entities e
      where e.id=p_proposed_by_person_entity_id
        and e.entity_kind='person'
        and e.identity_state='canonical'
    ) then
      raise exception 'Proposal actor must be a canonical Reality Person.'
        using errcode='42501';
    end if;
  end if;

  if exists(
    select 1 from reality.entity_supersessions s
    where s.superseded_entity_id in (
      p_survivor_entity_id,p_superseded_entity_id
    )
  ) then
    raise exception 'A proposed entity is already superseded.' using errcode='23514';
  end if;

  if exists(
    select 1
    from reality.entity_reconciliation_cases c
    where c.case_state='proposed'
      and (
        (c.survivor_entity_id=p_survivor_entity_id
          and c.superseded_entity_id=p_superseded_entity_id)
        or
        (c.survivor_entity_id=p_superseded_entity_id
          and c.superseded_entity_id=p_survivor_entity_id)
      )
  ) then
    raise exception 'An unresolved reconciliation case already exists for this entity pair.'
      using errcode='23505';
  end if;

  insert into reality.entity_reconciliation_cases(
    survivor_entity_id,
    superseded_entity_id,
    proposal_source_kind,
    source_reference,
    proposal_basis,
    proposed_by_person_entity_id,
    proposal_responsibility_relation_id
  ) values (
    p_survivor_entity_id,
    p_superseded_entity_id,
    p_proposal_source_kind,
    p_source_reference,
    p_proposal_basis,
    p_proposed_by_person_entity_id,
    p_proposal_responsibility_relation_id
  )
  returning id into v_case_id;

  v_impact:=reality.entity_reconciliation_impact_internal_v1(v_case_id);

  update reality.entity_reconciliation_cases
  set impact_snapshot=v_impact,
      previewed_at=now(),
      updated_at=now()
  where id=v_case_id;

  return v_case_id;
end
$function$;

revoke all on function reality.open_entity_reconciliation_case_internal_v1(
  uuid,uuid,text,jsonb,text,uuid,uuid
) from public,anon,authenticated,service_role;


create or replace function reality.execute_entity_reconciliation_internal_v1(
  p_case_id uuid,
  p_actor_person_entity_id uuid,
  p_responsibility_relation_id uuid,
  p_confirmation_basis text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_case reality.entity_reconciliation_cases%rowtype;
  v_survivor reality.entities%rowtype;
  v_superseded reality.entities%rowtype;
  v_impact jsonb;
  v_fk record;
  v_changed bigint;
  v_total_changed bigint:=0;
  v_compatibility_changed bigint:=0;
  v_rewrites jsonb:='[]'::jsonb;
  v_receipt jsonb;
begin
  if nullif(btrim(coalesce(p_confirmation_basis,'')),'') is null then
    raise exception 'A confirmation basis is required.' using errcode='22023';
  end if;

  if length(p_confirmation_basis)>8000 then
    raise exception 'Confirmation basis is too long.' using errcode='22023';
  end if;

  if not exists(
    select 1 from reality.entities e
    where e.id=p_actor_person_entity_id
      and e.entity_kind='person'
      and e.identity_state='canonical'
  ) then
    raise exception 'Confirmation actor must be a canonical Reality Person.'
      using errcode='42501';
  end if;

  select * into v_case
  from reality.entity_reconciliation_cases
  where id=p_case_id
  for update;

  if not found or v_case.case_state<>'proposed' then
    raise exception 'A proposed reconciliation case is required.' using errcode='22023';
  end if;

  perform 1
  from reality.entities e
  where e.id in (v_case.survivor_entity_id,v_case.superseded_entity_id)
  order by e.id
  for update;

  select * into v_survivor
  from reality.entities
  where id=v_case.survivor_entity_id;

  select * into v_superseded
  from reality.entities
  where id=v_case.superseded_entity_id;

  if v_survivor.identity_state<>'canonical'
     or v_superseded.identity_state<>'canonical'
     or v_survivor.entity_kind<>v_superseded.entity_kind then
    raise exception 'Reconciliation entities changed after proposal; preview again.'
      using errcode='23514';
  end if;

  v_impact:=reality.entity_reconciliation_impact_internal_v1(p_case_id);

  if not coalesce((v_impact->>'canAttemptConfirmation')::boolean,false) then
    raise exception 'Reality reconciliation is blocked: %',
      coalesce(v_impact->'knownBlockers','[]'::jsonb)::text
      using errcode='23514';
  end if;

  for v_fk in
    select
      ns.nspname as schema_name,
      rel.relname as table_name,
      att.attname as column_name,
      con.conname as constraint_name
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_class rel on rel.oid=con.conrelid
    join pg_catalog.pg_namespace ns on ns.oid=rel.relnamespace
    join lateral unnest(con.conkey) with ordinality ck(attnum,ord) on true
    join lateral unnest(con.confkey) with ordinality fk(attnum,ord)
      on fk.ord=ck.ord
    join pg_catalog.pg_attribute att
      on att.attrelid=con.conrelid and att.attnum=ck.attnum
    join pg_catalog.pg_attribute target_att
      on target_att.attrelid=con.confrelid and target_att.attnum=fk.attnum
    where con.contype='f'
      and con.confrelid='reality.entities'::regclass
      and target_att.attname='id'
      and cardinality(con.conkey)=1
      and not (
        ns.nspname='reality'
        and rel.relname in ('entity_reconciliation_cases','entity_supersessions')
      )
    order by ns.nspname,rel.relname,att.attname
  loop
    begin
      execute format(
        'update %I.%I set %I=$1 where %I=$2',
        v_fk.schema_name,v_fk.table_name,v_fk.column_name,v_fk.column_name
      )
      using v_case.survivor_entity_id,v_case.superseded_entity_id;

      get diagnostics v_changed=row_count;
      if v_changed<>0 then
        v_total_changed:=v_total_changed+v_changed;
        v_rewrites:=v_rewrites || jsonb_build_array(
          jsonb_build_object(
            'schema',v_fk.schema_name,
            'table',v_fk.table_name,
            'column',v_fk.column_name,
            'constraint',v_fk.constraint_name,
            'rewrittenRows',v_changed
          )
        );
      end if;
    exception
      when unique_violation or check_violation or foreign_key_violation then
        raise exception
          'Reality reconciliation blocked while repointing %.%.% via %: %',
          v_fk.schema_name,v_fk.table_name,v_fk.column_name,
          v_fk.constraint_name,sqlerrm
          using errcode='23514';
    end;
  end loop;

  update compatibility.legacy_bindings lb
  set new_id=v_case.survivor_entity_id,
      basis=coalesce(lb.basis,'{}'::jsonb)||jsonb_build_object(
        'reconciledFromRealityEntityId',v_case.superseded_entity_id,
        'reconciliationCaseId',v_case.id,
        'reconciledAt',now()
      )
  where lb.new_schema='reality'
    and lb.new_table='entities'
    and lb.new_id=v_case.superseded_entity_id;

  get diagnostics v_compatibility_changed=row_count;

  v_receipt:=jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'caseId',v_case.id,
    'survivorEntityId',v_case.survivor_entity_id,
    'supersededEntityId',v_case.superseded_entity_id,
    'directForeignKeyRowsRewritten',v_total_changed,
    'compatibilityBindingsRewritten',v_compatibility_changed,
    'rewrites',v_rewrites,
    'atomic',true
  );

  insert into reality.entity_supersessions(
    superseded_entity_id,
    survivor_entity_id,
    reconciliation_case_id,
    merged_by_person_entity_id,
    responsibility_relation_id,
    merge_basis,
    impact_snapshot,
    execution_receipt
  ) values (
    v_case.superseded_entity_id,
    v_case.survivor_entity_id,
    v_case.id,
    p_actor_person_entity_id,
    p_responsibility_relation_id,
    p_confirmation_basis,
    v_impact,
    v_receipt
  );

  update reality.entities
  set identity_state='retired',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'identityDisposition','superseded',
        'supersededByEntityId',v_case.survivor_entity_id,
        'reconciliationCaseId',v_case.id,
        'supersededAt',now()
      ),
      updated_at=now()
  where id=v_case.superseded_entity_id;

  update reality.entity_reconciliation_cases
  set case_state='confirmed',
      impact_snapshot=v_impact,
      previewed_at=now(),
      confirmed_by_person_entity_id=p_actor_person_entity_id,
      confirmation_responsibility_relation_id=p_responsibility_relation_id,
      confirmation_basis=p_confirmation_basis,
      execution_receipt=v_receipt,
      confirmed_at=now(),
      updated_at=now()
  where id=v_case.id;

  return v_receipt || jsonb_build_object(
    'state','confirmed',
    'canonicalEntityId',v_case.survivor_entity_id,
    'supersededIdentityRetained',true
  );
end
$function$;

revoke all on function reality.execute_entity_reconciliation_internal_v1(
  uuid,uuid,uuid,text
) from public,anon,authenticated,service_role;


create or replace function atlas.reality_entity_reconciliation_propose_self_api_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_survivor uuid;
  v_superseded uuid;
  v_basis text;
  v_source_reference jsonb;
  v_case_id uuid;
  v_impact jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Reconciliation proposal must be a JSON object.' using errcode='22023';
  end if;

  begin
    v_survivor:=nullif(btrim(p_input->>'survivorEntityId'),'')::uuid;
    v_superseded:=nullif(btrim(p_input->>'supersededEntityId'),'')::uuid;
  exception when invalid_text_representation then
    raise exception 'Valid survivorEntityId and supersededEntityId are required.'
      using errcode='22023';
  end;

  if v_survivor is null or v_superseded is null then
    raise exception 'Valid survivorEntityId and supersededEntityId are required.'
      using errcode='22023';
  end if;

  v_basis:=nullif(btrim(p_input->>'basis'),'');
  v_source_reference:=coalesce(p_input->'sourceReference','{}'::jsonb);

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_reconciliation',
    'canonical_merge.propose',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  );

  if v_relation_id is null then
    raise exception 'Reality identity reconciliation responsibility required.'
      using errcode='42501';
  end if;

  v_case_id:=reality.open_entity_reconciliation_case_internal_v1(
    v_survivor,
    v_superseded,
    'human',
    v_source_reference,
    v_basis,
    v_person_id,
    v_relation_id
  );

  v_impact:=reality.entity_reconciliation_impact_internal_v1(v_case_id);

  return jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'caseId',v_case_id,
    'state','proposed',
    'proposedByPersonEntityId',v_person_id,
    'responsibilityRelationId',v_relation_id,
    'impact',v_impact,
    'canonicalMergeExecuted',false
  );
end
$function$;

revoke all on function atlas.reality_entity_reconciliation_propose_self_api_v1(jsonb)
  from public,anon,service_role;
grant execute on function atlas.reality_entity_reconciliation_propose_self_api_v1(jsonb)
  to authenticated;


create or replace function atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(
  p_survivor_entity_id uuid,
  p_superseded_entity_id uuid,
  p_evidence jsonb,
  p_basis text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_case_id uuid;
  v_impact jsonb;
begin
  if p_evidence is null or jsonb_typeof(p_evidence)<>'object' then
    raise exception 'Shared Intelligence evidence must be a JSON object.'
      using errcode='22023';
  end if;

  v_case_id:=reality.open_entity_reconciliation_case_internal_v1(
    p_survivor_entity_id,
    p_superseded_entity_id,
    'shared_intelligence',
    p_evidence,
    p_basis,
    null,
    null
  );

  v_impact:=reality.entity_reconciliation_impact_internal_v1(v_case_id);

  return jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'caseId',v_case_id,
    'state','proposed',
    'proposalSourceKind','shared_intelligence',
    'impact',v_impact,
    'canonicalMergeExecuted',false,
    'humanConfirmationRequired',true
  );
end
$function$;

revoke all on function atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(
  uuid,uuid,jsonb,text
) from public,anon,authenticated;
grant execute on function atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(
  uuid,uuid,jsonb,text
) to service_role;


create or replace function atlas.reality_entity_reconciliation_preview_self_api_v1(
  p_case_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_case_state text;
  v_impact jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_reconciliation',
    'canonical_merge.preview',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  );

  if v_relation_id is null then
    raise exception 'Reality identity reconciliation responsibility required.'
      using errcode='42501';
  end if;

  select case_state into v_case_state
  from reality.entity_reconciliation_cases
  where id=p_case_id;

  if v_case_state is null then
    raise exception 'Reality reconciliation case not found.' using errcode='22023';
  end if;

  if v_case_state<>'proposed' then
    raise exception 'Only a proposed reconciliation case can be previewed live.'
      using errcode='22023';
  end if;

  v_impact:=reality.entity_reconciliation_impact_internal_v1(p_case_id);

  update reality.entity_reconciliation_cases
  set impact_snapshot=v_impact,
      previewed_at=now(),
      updated_at=now()
  where id=p_case_id;

  return jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'caseId',p_case_id,
    'state','proposed',
    'previewedByPersonEntityId',v_person_id,
    'responsibilityRelationId',v_relation_id,
    'impact',v_impact,
    'canonicalMergeExecuted',false
  );
end
$function$;

revoke all on function atlas.reality_entity_reconciliation_preview_self_api_v1(uuid)
  from public,anon,service_role;
grant execute on function atlas.reality_entity_reconciliation_preview_self_api_v1(uuid)
  to authenticated;


create or replace function atlas.reality_entity_reconciliation_confirm_self_api_v1(
  p_case_id uuid,
  p_basis text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_reconciliation',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  );

  if v_relation_id is null then
    raise exception 'Canonical Reality merge execution responsibility required.'
      using errcode='42501';
  end if;

  return reality.execute_entity_reconciliation_internal_v1(
    p_case_id,
    v_person_id,
    v_relation_id,
    p_basis
  );
end
$function$;

revoke all on function atlas.reality_entity_reconciliation_confirm_self_api_v1(
  uuid,text
) from public,anon,service_role;
grant execute on function atlas.reality_entity_reconciliation_confirm_self_api_v1(
  uuid,text
) to authenticated;


-- Merge authority is an explicit responsibility distinct from evidence review.
-- The current project operator is established deliberately; this is not inferred
-- from Seat participation, Organization role, Principal state, or the existing
-- identity-review responsibility.
with operator_person as (
  select e.id
  from reality.entities e
  where e.stable_key='lex'
    and e.entity_kind='person'
    and e.identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,
  responsibility_key,
  title,
  relation_state,
  jurisdiction_kind,
  jurisdiction_domain,
  permitted_operations,
  scope,
  establishment_kind,
  establishment_basis
)
select
  op.id,
  'reality_identity_reconciliation',
  'Govern canonical Reality identity reconciliation',
  'active',
  'domain',
  'reality.identity_resolution',
  array[
    'canonical_merge.propose',
    'canonical_merge.preview',
    'canonical_merge.execute'
  ]::text[],
  '{}'::jsonb,
  'architecture_adjudication',
  jsonb_build_object(
    'basis','Explicitly established with the Reality reconciliation membrane; canonical merge authority is not inferred from identity-review approval.',
    'separateFrom',jsonb_build_array(
      'identity_review.adjudicate',
      'Shared Intelligence merge approval',
      'Seat participation',
      'generic role',
      'Principal'
    )
  )
from operator_person op
on conflict do nothing;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.reality_entity_reconciliation_propose_self_api_v1(jsonb)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Open a Reality reconciliation proposal without executing a merge.',
    'authority','reality_identity_reconciliation / canonical_merge.propose'
  ),
  now(),false
),
(
  'atlas.reality_entity_reconciliation_preview_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Preview the live direct-reference impact of a proposed Reality reconciliation.',
    'authority','reality_identity_reconciliation / canonical_merge.preview'
  ),
  now(),false
),
(
  'atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid, text)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Execute one explicit human-confirmed canonical Reality reconciliation atomically.',
    'authority','reality_identity_reconciliation / canonical_merge.execute',
    'sharedIntelligenceCannotExecute',true
  ),
  now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;


comment on table reality.entity_reconciliation_cases is
  'Governed proposals that two already-admitted Reality identities are one real-world entity. Proposal and evidence do not merge Reality.';

comment on table reality.entity_supersessions is
  'Durable non-destructive identity history for confirmed Reality reconciliations. The superseded Entity row is retained and resolves to the surviving canonical Entity.';

comment on function reality.resolve_canonical_entity_v1(uuid) is
  'Resolve a current or superseded Reality Entity ID to the surviving canonical identity through durable supersession history.';

comment on function atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(
  uuid,uuid,jsonb,text
) is
  'Evidence may open a Reality reconciliation proposal; this service function cannot confirm or execute a canonical merge.';

comment on function atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid,text) is
  'Authenticated human confirmation membrane for canonical Reality reconciliation. Requires explicit canonical_merge.execute responsibility and performs an atomic fail-closed reference rewrite.';


do $validation$
declare
  v_operator uuid;
begin
  select id into v_operator
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  if v_operator is null then
    raise exception 'Reality reconciliation operator Person is unavailable.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,
    'reality_identity_reconciliation',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  ) is null then
    raise exception 'Explicit canonical merge responsibility did not resolve.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,
    'reality_identity_adjudication',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  ) is not null then
    raise exception 'Evidence adjudication improperly became canonical merge authority.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'service_role must not execute canonical merge confirmation.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(uuid,uuid,jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'Shared Intelligence evidence proposal service is unavailable.';
  end if;

  if has_table_privilege(
    'service_role',
    'reality.entity_supersessions',
    'INSERT'
  ) then
    raise exception 'service_role has raw canonical supersession mutation authority.';
  end if;
end
$validation$;

-- Atlas Ledger Target Intelligence v1
-- Evidence Obligation relevance correction.
-- Apply after candidate.sql while v1 remains in candidate state.

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
      if v_false_count>0 then
        v_state:='false';
        v_obligations:='[]'::jsonb;
      elsif v_unknown_count>0 then
        v_state:='unknown';
      else
        v_state:='true';
        v_obligations:='[]'::jsonb;
      end if;
    else
      if v_true_count>0 then
        v_state:='true';
        v_obligations:='[]'::jsonb;
      elsif v_unknown_count>0 then
        v_state:='unknown';
      else
        v_state:='false';
        v_obligations:='[]'::jsonb;
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
      'obligations',case when v_state='unknown'
        then coalesce(v_child_result->'obligations','[]'::jsonb)
        else '[]'::jsonb
      end
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
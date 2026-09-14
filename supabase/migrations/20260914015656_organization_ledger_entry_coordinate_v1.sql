-- Organization Ledger entry coordinate v1.
-- Preserve the exact governing Ledger coordinate in the existing owner window read contract.
-- This is staged inertly until a legitimate Supabase migration identity is generated.

begin;

create or replace function atlas.organization_ledger_owner_window_api_v1(
  p_organization_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_after_revision bigint default 0,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_items jsonb;
  v_max_revision bigint;
begin
  if auth.uid() is null or not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Organization owner access is required.' using errcode='42501';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then
    raise exception 'A valid half-open occurrence window is required.' using errcode='22023';
  end if;
  if coalesce(p_after_revision,0)<0 then
    raise exception 'Revision cursor cannot be negative.' using errcode='22023';
  end if;
  if coalesce(p_limit,0)<1 or p_limit>500 then
    raise exception 'Ledger page limit must be between 1 and 500.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(item order by occurred_at,revision,id),'[]'::jsonb),coalesce(max(revision),p_after_revision)
  into v_items,v_max_revision
  from (
    select e.id,e.ledger_id,e.event_key,e.source_domain,e.semantic_type,e.source_event_key,
      e.organization_unit_id,e.occurred_at,e.established_at,e.title,e.detail,
      e.truth_status,e.designation_status,e.payload,e.provenance,e.correlation,e.revision,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'subjectDomain',s.subject_domain,'subjectKind',s.subject_kind,'subjectId',s.subject_id,
          'relationKind',s.relation_kind,'provenance',s.provenance,'metadata',s.metadata
        ) order by s.created_at,s.id)
        from atlas.organization_ledger_subjects s
        where s.ledger_entry_id=e.id
      ),'[]'::jsonb) as subjects,
      jsonb_build_object(
        'entryId',e.id,'ledgerId',e.ledger_id,'eventKey',e.event_key,'sourceDomain',e.source_domain,
        'semanticType',e.semantic_type,'sourceEventKey',e.source_event_key,
        'organizationUnitId',e.organization_unit_id,'occurredAt',e.occurred_at,
        'establishedAt',e.established_at,'title',e.title,'detail',e.detail,
        'truthStatus',e.truth_status,'designationStatus',e.designation_status,
        'payload',e.payload,'provenance',e.provenance,'correlation',e.correlation,
        'revision',e.revision,
        'subjects',coalesce((
          select jsonb_agg(jsonb_build_object(
            'subjectDomain',s2.subject_domain,'subjectKind',s2.subject_kind,'subjectId',s2.subject_id,
            'relationKind',s2.relation_kind,'provenance',s2.provenance,'metadata',s2.metadata
          ) order by s2.created_at,s2.id)
          from atlas.organization_ledger_subjects s2
          where s2.ledger_entry_id=e.id
        ),'[]'::jsonb)
      ) as item
    from atlas.organization_ledger_entries e
    where e.organization_id=p_organization_id
      and e.occurred_at>=p_start_at and e.occurred_at<p_end_at
      and e.revision>coalesce(p_after_revision,0)
    order by e.occurred_at,e.revision,e.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','organization_ledger_owner_window_api_v1',
    'organizationId',p_organization_id,
    'startAt',p_start_at,'endAt',p_end_at,
    'afterRevision',coalesce(p_after_revision,0),
    'maxRevision',v_max_revision,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer) from public,anon;
grant execute on function atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer) to authenticated;

commit;

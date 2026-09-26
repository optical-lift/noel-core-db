-- Atlas Reality / Ledger Temporal Enrichment + Occupancy Adapter v1
-- Read-only Temporal Field adapter over the existing Reality / Ledger scheduling kernel.

create or replace function atlas.ledger_scheduling_temporal_adapter_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas, ledger, reality, local_intel
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_timezone text := nullif(btrim(p_timezone_name),'');
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_ledger ledger.ledgers%rowtype;
  v_subject_name text;
  v_occurrence_total integer := 0;
  v_claim_total integer := 0;
  v_occurrence_admissions jsonb := '[]'::jsonb;
  v_occupancy_contributions jsonb := '[]'::jsonb;
  v_occurrence_returned integer := 0;
  v_claim_returned integer := 0;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid Ledger temporal date window is required.' using errcode='22023';
  end if;

  if p_end_date-p_start_date > 3660 then
    raise exception 'Ledger temporal adapter window may not exceed 3660 days.' using errcode='22023';
  end if;

  if v_timezone is null or not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Valid Ledger temporal adapter timezone is required.' using errcode='22023';
  end if;

  select * into v_ledger
  from ledger.ledgers l
  where l.id=p_ledger_id
    and l.ledger_state='active';

  if v_ledger.id is null then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;

  select e.display_name into v_subject_name
  from reality.entities e
  where e.id=v_ledger.subject_entity_id;

  v_window_start := p_start_date::timestamp at time zone v_timezone;
  v_window_end := (p_end_date+1)::timestamp at time zone v_timezone;

  select count(*)::integer
  into v_occurrence_total
  from (
    select o.id
    from local_intel.occurrences o
    where (
      (
        o.start_at < v_window_end
        and coalesce(o.end_at,o.start_at+interval '1 minute') > v_window_start
        and (
          exists(
            select 1
            from ledger.occurrence_calendar_bindings cb
            where cb.ledger_id=p_ledger_id
              and cb.occurrence_id=o.id
              and cb.binding_state='active'
          )
          or exists(
            select 1
            from ledger.bookings b
            where b.ledger_id=p_ledger_id
              and b.occurrence_id=o.id
              and b.booking_state<>'cancelled'
          )
          or exists(
            select 1
            from ledger.occurrence_resource_claims c
            where c.ledger_id=p_ledger_id
              and c.occurrence_id=o.id
              and c.claim_state in ('tentative','confirmed')
          )
        )
      )
      or exists(
        select 1
        from ledger.occurrence_resource_claims c
        where c.ledger_id=p_ledger_id
          and c.occurrence_id=o.id
          and c.claim_state in ('tentative','confirmed')
          and c.starts_at<v_window_end
          and c.ends_at>v_window_start
      )
    )
  ) q;

  with admitted as (
    select o.*
    from local_intel.occurrences o
    where (
      (
        o.start_at < v_window_end
        and coalesce(o.end_at,o.start_at+interval '1 minute') > v_window_start
        and (
          exists(
            select 1
            from ledger.occurrence_calendar_bindings cb
            where cb.ledger_id=p_ledger_id
              and cb.occurrence_id=o.id
              and cb.binding_state='active'
          )
          or exists(
            select 1
            from ledger.bookings b
            where b.ledger_id=p_ledger_id
              and b.occurrence_id=o.id
              and b.booking_state<>'cancelled'
          )
          or exists(
            select 1
            from ledger.occurrence_resource_claims c
            where c.ledger_id=p_ledger_id
              and c.occurrence_id=o.id
              and c.claim_state in ('tentative','confirmed')
          )
        )
      )
      or exists(
        select 1
        from ledger.occurrence_resource_claims c
        where c.ledger_id=p_ledger_id
          and c.occurrence_id=o.id
          and c.claim_state in ('tentative','confirmed')
          and c.starts_at<v_window_end
          and c.ends_at>v_window_start
      )
    )
    order by o.start_at,o.title,o.id
    limit v_limit
  ), packed as (
    select
      o.start_at,
      o.title,
      o.id,
      jsonb_build_object(
        'occurrenceId',o.id,
        'scheduling',jsonb_strip_nulls(jsonb_build_object(
          'ledgerId',v_ledger.id,
          'ledgerStableKey',v_ledger.stable_key,
          'ledgerName',v_ledger.name,
          'subjectEntityId',v_ledger.subject_entity_id,
          'subjectDisplayName',v_subject_name,
          'calendarBinding',(
            select jsonb_strip_nulls(jsonb_build_object(
              'bindingId',cb.id,
              'bindingState',cb.binding_state,
              'roleKeys',to_jsonb(cb.role_keys),
              'metadata',cb.metadata,
              'provenance',cb.provenance
            ))
            from ledger.occurrence_calendar_bindings cb
            where cb.ledger_id=p_ledger_id
              and cb.occurrence_id=o.id
            order by (cb.binding_state='active') desc,cb.updated_at desc,cb.id
            limit 1
          ),
          'bookings',coalesce((
            select jsonb_agg(
              jsonb_strip_nulls(jsonb_build_object(
                'bookingId',b.id,
                'bookingKind',b.booking_kind,
                'bookingState',b.booking_state,
                'bookingLabel',b.booking_label,
                'businessModelKey',b.business_model_key,
                'customerEntityId',b.customer_entity_id,
                'customerDisplayName',ce.display_name,
                'confirmedAt',b.confirmed_at,
                'cancelledAt',b.cancelled_at,
                'completedAt',b.completed_at,
                'metadata',b.metadata,
                'provenance',b.provenance,
                'references',coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'referenceKind',br.reference_kind,
                      'systemKey',br.system_key,
                      'referenceKey',br.reference_key,
                      'metadata',br.metadata
                    )
                    order by br.reference_kind,br.system_key,br.reference_key
                  )
                  from ledger.booking_references br
                  where br.booking_id=b.id
                ),'[]'::jsonb)
              ))
              order by b.created_at,b.id
            )
            from ledger.bookings b
            left join reality.entities ce on ce.id=b.customer_entity_id
            where b.ledger_id=p_ledger_id
              and b.occurrence_id=o.id
          ),'[]'::jsonb),
          'resourceClaims',coalesce((
            select jsonb_agg(
              jsonb_strip_nulls(jsonb_build_object(
                'claimId',c.id,
                'claimKind',c.claim_kind,
                'claimState',c.claim_state,
                'startsAt',c.starts_at,
                'endsAt',c.ends_at,
                'quantity',c.quantity,
                'quantityUnit',c.quantity_unit,
                'bookingId',c.booking_id,
                'resource',jsonb_strip_nulls(jsonb_build_object(
                  'resourceId',r.id,
                  'stableKey',r.stable_key,
                  'label',r.label,
                  'resourceKind',r.resource_kind,
                  'parentResourceId',r.parent_resource_id,
                  'resourceState',r.resource_state,
                  'reservable',r.reservable,
                  'capacityMode',r.capacity_mode,
                  'capacityQuantity',r.capacity_quantity,
                  'capacityUnit',r.capacity_unit,
                  'timezoneName',r.timezone_name
                )),
                'classificationState',coalesce(c.metadata->>'classificationState','classified'),
                'conflict',not coalesce((a.availability->>'available')::boolean,false),
                'availability',a.availability,
                'metadata',c.metadata,
                'provenance',c.provenance
              ))
              order by c.starts_at,r.label,c.id
            )
            from ledger.occurrence_resource_claims c
            join reality.resources r on r.id=c.resource_id
            cross join lateral (
              select ledger.resource_claim_availability_v1(
                p_ledger_id,
                c.resource_id,
                c.starts_at,
                c.ends_at,
                c.claim_kind,
                c.quantity,
                c.id,
                c.occurrence_id
              ) as availability
            ) a
            where c.ledger_id=p_ledger_id
              and c.occurrence_id=o.id
              and c.claim_state in ('tentative','confirmed')
          ),'[]'::jsonb),
          'occupancyState',case
            when not exists(
              select 1
              from ledger.occurrence_resource_claims c
              where c.ledger_id=p_ledger_id
                and c.occurrence_id=o.id
                and c.claim_state in ('tentative','confirmed')
            ) then 'unclassified'
            when exists(
              select 1
              from ledger.occurrence_resource_claims c
              cross join lateral (
                select ledger.resource_claim_availability_v1(
                  p_ledger_id,
                  c.resource_id,
                  c.starts_at,
                  c.ends_at,
                  c.claim_kind,
                  c.quantity,
                  c.id,
                  c.occurrence_id
                ) as availability
              ) a
              where c.ledger_id=p_ledger_id
                and c.occurrence_id=o.id
                and c.claim_state in ('tentative','confirmed')
                and coalesce((a.availability->>'available')::boolean,false)=false
            ) then 'conflict'
            else 'clear'
          end,
          'occupancyWindow',(
            select case when count(*)=0 then null else jsonb_build_object(
              'startsAt',min(c.starts_at),
              'endsAt',max(c.ends_at)
            ) end
            from ledger.occurrence_resource_claims c
            where c.ledger_id=p_ledger_id
              and c.occurrence_id=o.id
              and c.claim_state in ('tentative','confirmed')
          )
        ))
      ) as admission
    from admitted o
  )
  select coalesce(
    jsonb_agg(admission order by start_at,title,id),
    '[]'::jsonb
  )
  into v_occurrence_admissions
  from packed;

  v_occurrence_returned:=jsonb_array_length(v_occurrence_admissions);

  select count(*)::integer
  into v_claim_total
  from ledger.occurrence_resource_claims c
  where c.ledger_id=p_ledger_id
    and c.claim_state in ('tentative','confirmed')
    and c.starts_at<v_window_end
    and c.ends_at>v_window_start;

  with claim_rows as (
    select
      c.*,
      r.stable_key as resource_stable_key,
      r.label as resource_label,
      r.resource_kind,
      r.parent_resource_id,
      r.resource_state,
      r.reservable,
      r.capacity_mode,
      r.capacity_quantity,
      r.capacity_unit,
      r.timezone_name as resource_timezone_name,
      o.title as occurrence_title,
      o.status as occurrence_status,
      o.start_at as occurrence_start_at,
      o.end_at as occurrence_end_at,
      b.booking_kind,
      b.booking_state,
      b.booking_label,
      b.customer_entity_id,
      ce.display_name as customer_display_name,
      a.availability,
      (c.starts_at at time zone v_timezone)::date as local_date
    from ledger.occurrence_resource_claims c
    join reality.resources r on r.id=c.resource_id
    join local_intel.occurrences o on o.id=c.occurrence_id
    left join ledger.bookings b on b.id=c.booking_id
    left join reality.entities ce on ce.id=b.customer_entity_id
    cross join lateral (
      select ledger.resource_claim_availability_v1(
        p_ledger_id,
        c.resource_id,
        c.starts_at,
        c.ends_at,
        c.claim_kind,
        c.quantity,
        c.id,
        c.occurrence_id
      ) as availability
    ) a
    where c.ledger_id=p_ledger_id
      and c.claim_state in ('tentative','confirmed')
      and c.starts_at<v_window_end
      and c.ends_at>v_window_start
    order by c.starts_at,r.label,c.id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'projectionKey','ledger_resource_claim:'||c.id::text,
        'sourceRef',jsonb_build_object(
          'authority','ledger',
          'kind','occurrence_resource_claim',
          'id',c.id
        ),
        'standing',case
          when coalesce((c.availability->>'available')::boolean,false) then 'scheduled'
          else 'conflict'
        end,
        'coordinate',jsonb_build_object(
          'dateKey',c.local_date,
          'startsAt',c.starts_at,
          'endsAt',c.ends_at,
          'precision','interval',
          'timezoneName',v_timezone
        ),
        'display',jsonb_strip_nulls(jsonb_build_object(
          'title',c.resource_label,
          'secondary',c.occurrence_title
        )),
        'epistemic',jsonb_build_object(
          'state','established',
          'sourceStatus',c.claim_state
        ),
        'encounter',jsonb_build_object(
          'kind','ledger_resource_claim',
          'id',c.id
        ),
        'sourceSnapshot',jsonb_strip_nulls(jsonb_build_object(
          'ledger',jsonb_build_object(
            'ledgerId',v_ledger.id,
            'stableKey',v_ledger.stable_key,
            'name',v_ledger.name,
            'subjectEntityId',v_ledger.subject_entity_id,
            'subjectDisplayName',v_subject_name
          ),
          'claim',jsonb_strip_nulls(jsonb_build_object(
            'claimId',c.id,
            'claimKind',c.claim_kind,
            'claimState',c.claim_state,
            'startsAt',c.starts_at,
            'endsAt',c.ends_at,
            'quantity',c.quantity,
            'quantityUnit',c.quantity_unit,
            'classificationState',coalesce(c.metadata->>'classificationState','classified'),
            'metadata',c.metadata,
            'provenance',c.provenance
          )),
          'resource',jsonb_strip_nulls(jsonb_build_object(
            'resourceId',c.resource_id,
            'stableKey',c.resource_stable_key,
            'label',c.resource_label,
            'resourceKind',c.resource_kind,
            'parentResourceId',c.parent_resource_id,
            'resourceState',c.resource_state,
            'reservable',c.reservable,
            'capacityMode',c.capacity_mode,
            'capacityQuantity',c.capacity_quantity,
            'capacityUnit',c.capacity_unit,
            'timezoneName',c.resource_timezone_name
          )),
          'occurrence',jsonb_strip_nulls(jsonb_build_object(
            'occurrenceId',c.occurrence_id,
            'title',c.occurrence_title,
            'status',c.occurrence_status,
            'startsAt',c.occurrence_start_at,
            'endsAt',c.occurrence_end_at
          )),
          'booking',case when c.booking_id is null then null else jsonb_strip_nulls(jsonb_build_object(
            'bookingId',c.booking_id,
            'bookingKind',c.booking_kind,
            'bookingState',c.booking_state,
            'bookingLabel',c.booking_label,
            'customerEntityId',c.customer_entity_id,
            'customerDisplayName',c.customer_display_name
          )) end,
          'availability',c.availability
        )),
        'contexts','[]'::jsonb
      )
      order by c.starts_at,c.resource_label,c.id
    ),
    '[]'::jsonb
  )
  into v_occupancy_contributions
  from claim_rows c;

  v_claim_returned:=jsonb_array_length(v_occupancy_contributions);

  return jsonb_build_object(
    'contractVersion','ledger_scheduling_temporal_adapter_v1',
    'ledger',jsonb_build_object(
      'ledgerId',v_ledger.id,
      'stableKey',v_ledger.stable_key,
      'name',v_ledger.name,
      'subjectEntityId',v_ledger.subject_entity_id,
      'subjectDisplayName',v_subject_name
    ),
    'window',jsonb_build_object(
      'startDate',p_start_date,
      'endDate',p_end_date,
      'timezoneName',v_timezone,
      'startsAt',v_window_start,
      'endsBefore',v_window_end
    ),
    'occurrenceAdmissions',v_occurrence_admissions,
    'occupancyContributions',v_occupancy_contributions,
    'coverage',jsonb_build_object(
      'partial',(v_occurrence_total>v_limit or v_claim_total>v_limit),
      'occurrenceAdmissionsTotal',v_occurrence_total,
      'occurrenceAdmissionsReturned',v_occurrence_returned,
      'occurrenceAdmissionsTruncated',(v_occurrence_total>v_limit),
      'occupancyContributionsTotal',v_claim_total,
      'occupancyContributionsReturned',v_claim_returned,
      'occupancyContributionsTruncated',(v_claim_total>v_limit)
    )
  );
end
$function$;

create or replace function atlas.ledger_temporal_composer_service_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_timezone text := nullif(btrim(p_timezone_name),'');
  v_scheduling jsonb;
  v_occurrence_ids uuid[] := '{}';
  v_occurrences jsonb;
  v_contributions jsonb := '[]'::jsonb;
  v_source_count integer := 0;
  v_composer_truncated boolean := false;
  v_partial boolean := false;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid Ledger temporal composer date window is required.' using errcode='22023';
  end if;

  if v_timezone is null or not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Valid Ledger temporal composer timezone is required.' using errcode='22023';
  end if;

  v_scheduling:=atlas.ledger_scheduling_temporal_adapter_v1(
    p_ledger_id,
    p_start_date,
    p_end_date,
    v_timezone,
    v_limit
  );

  select coalesce(
    array_agg(distinct nullif(admission->>'occurrenceId','')::uuid),
    '{}'::uuid[]
  )
  into v_occurrence_ids
  from jsonb_array_elements(v_scheduling->'occurrenceAdmissions') as x(admission);

  v_occurrences:=atlas.canonical_occurrence_temporal_adapter_v1(
    v_occurrence_ids,
    p_start_date,
    p_end_date,
    v_timezone,
    v_limit
  );

  v_source_count:=
    jsonb_array_length(coalesce(v_occurrences->'contributions','[]'::jsonb))
    + jsonb_array_length(coalesce(v_scheduling->'occupancyContributions','[]'::jsonb));

  v_composer_truncated:=v_source_count>v_limit;

  with source_contributions as (
    select value as contribution
    from jsonb_array_elements(coalesce(v_occurrences->'contributions','[]'::jsonb))
    union all
    select value as contribution
    from jsonb_array_elements(coalesce(v_scheduling->'occupancyContributions','[]'::jsonb))
  ), enriched as (
    select case
      when s.contribution#>>'{sourceRef,kind}'='occurrence' then
        s.contribution || jsonb_build_object(
          'scheduling',coalesce((
            select jsonb_agg(admission->'scheduling' order by admission#>>'{scheduling,ledgerId}')
            from jsonb_array_elements(v_scheduling->'occurrenceAdmissions') as x(admission)
            where admission->>'occurrenceId'=s.contribution#>>'{sourceRef,id}'
          ),'[]'::jsonb)
        )
      else s.contribution
    end as contribution
    from source_contributions s
  ), ordered as (
    select
      contribution,
      nullif(contribution#>>'{coordinate,dateKey}','')::date as sort_date,
      case contribution->>'standing'
        when 'conflict' then 0
        when 'scheduled' then 1
        else 5
      end as sort_priority,
      nullif(contribution#>>'{coordinate,startsAt}','')::timestamptz as sort_at,
      contribution#>>'{display,title}' as sort_title,
      contribution->>'projectionKey' as sort_key
    from enriched
    order by
      nullif(contribution#>>'{coordinate,dateKey}','')::date,
      case contribution->>'standing'
        when 'conflict' then 0
        when 'scheduled' then 1
        else 5
      end,
      nullif(contribution#>>'{coordinate,startsAt}','')::timestamptz nulls first,
      contribution#>>'{display,title}',
      contribution->>'projectionKey'
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      contribution
      order by sort_date,sort_priority,sort_at nulls first,sort_title,sort_key
    ),
    '[]'::jsonb
  )
  into v_contributions
  from ordered;

  v_partial:=
    coalesce((v_scheduling#>>'{coverage,partial}')::boolean,false)
    or v_composer_truncated;

  return jsonb_build_object(
    'contractVersion','ledger_temporal_composer_v1',
    'scope',jsonb_build_object(
      'kind','ledger',
      'id',p_ledger_id
    ),
    'ledger',v_scheduling->'ledger',
    'timezoneName',v_timezone,
    'window',jsonb_build_object(
      'startDate',p_start_date,
      'endDate',p_end_date
    ),
    'coverage',jsonb_build_object(
      'partial',v_partial,
      'composerSourceContributionCount',v_source_count,
      'composerReturnedContributionCount',jsonb_array_length(v_contributions),
      'composerTruncated',v_composer_truncated,
      'scheduling',v_scheduling->'coverage',
      'adapters',jsonb_build_array(
        'canonical_occurrence_temporal_adapter_v1',
        'ledger_scheduling_temporal_adapter_v1'
      )
    ),
    'contributions',v_contributions
  );
end
$function$;

create or replace function atlas.ledger_temporal_composer_self_api_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas, auth
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  perform atlas.current_active_ledger_seat_v1(p_ledger_id);

  return atlas.ledger_temporal_composer_service_v1(
    p_ledger_id,
    p_start_date,
    p_end_date,
    p_timezone_name,
    p_limit
  );
end
$function$;

revoke all on function atlas.ledger_scheduling_temporal_adapter_v1(uuid,date,date,text,integer) from public,anon,authenticated;
revoke all on function atlas.ledger_temporal_composer_service_v1(uuid,date,date,text,integer) from public,anon,authenticated;
revoke all on function atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer) from public,anon;

grant execute on function atlas.ledger_scheduling_temporal_adapter_v1(uuid,date,date,text,integer) to service_role;
grant execute on function atlas.ledger_temporal_composer_service_v1(uuid,date,date,text,integer) to service_role;
grant execute on function atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer) to authenticated,service_role;

comment on function atlas.ledger_scheduling_temporal_adapter_v1(uuid,date,date,text,integer)
is 'Internal read-only Reality/Ledger scheduling adapter: admits canonical occurrences for Ledger enrichment and emits independent active Resource Claim occupancy Temporal Contributions.';

comment on function atlas.ledger_temporal_composer_service_v1(uuid,date,date,text,integer)
is 'Internal Ledger-scoped Temporal Field composer: canonical Occurrences retain identity, receive Ledger scheduling overlays, and coexist with independent Resource Claim occupancy contributions.';

comment on function atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)
is 'Authenticated Ledger-seat Temporal Field read membrane for canonical occurrence scheduling enrichment plus explicit Resource Claim occupancy.';

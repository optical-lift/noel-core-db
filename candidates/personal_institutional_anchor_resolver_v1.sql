begin;

create or replace function atlas.resolve_personal_institutional_anchor_self_api_v1(
  p_proposal_id uuid,
  p_limit integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit,12),1),25);
  v_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_label text;
  v_norm text;
  v_ledgers jsonb := '{}'::jsonb;
  v_access jsonb := '{}'::jsonb;
  v_ledger_matches jsonb := '[]'::jsonb;
  v_org_matches jsonb := '[]'::jsonb;
  v_case_matches jsonb := '[]'::jsonb;
  v_total integer := 0;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select *
  into v_proposal
  from atlas.personal_reality_effect_proposals p
  where p.id=p_proposal_id
    and p.owner_user_id=v_uid
    and p.effect_kind='institutional_anchor'
    and p.decision_state='confirmed'
    and p.route_state in ('ready','destination_unavailable');

  if v_proposal.id is null then
    raise exception 'Confirmed Institutional Anchor required.'
      using errcode='42501';
  end if;

  select *
  into v_capture
  from atlas.personal_reality_captures c
  where c.id=v_proposal.capture_id
    and c.owner_user_id=v_uid;

  if v_capture.id is null then
    raise exception 'Institutional Anchor capture custody not found.'
      using errcode='P0002';
  end if;

  v_label := nullif(btrim(v_proposal.proposal->>'candidateLabel'),'');
  if v_label is null then
    raise exception 'Institutional Anchor candidate label missing.'
      using errcode='23514';
  end if;

  v_norm := lower(regexp_replace(v_label,'[[:space:]]+',' ','g'));

  v_ledgers := atlas.principal_ledgers_self_api_v1();
  v_access := atlas.organization_access_self_api_v1();

  select coalesce(jsonb_agg(x.item order by x.exact_match desc,x.label,x.ledger_id),'[]'::jsonb)
  into v_ledger_matches
  from (
    select *
    from (
      select
        item->>'ledgerId' as ledger_id,
        coalesce(nullif(item->>'organizationName',''),item->>'ledgerName','') as label,
        (
          lower(regexp_replace(coalesce(nullif(item->>'organizationName',''),item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
          or lower(regexp_replace(coalesce(item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
        ) as exact_match,
        jsonb_build_object(
          'matchKind','principal_ledger',
          'matchStrength',case
            when lower(regexp_replace(coalesce(nullif(item->>'organizationName',''),item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
              or lower(regexp_replace(coalesce(item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
              then 'exact_label'
            else 'contained_label'
          end,
          'ledgerId',item->>'ledgerId',
          'ledgerName',item->>'ledgerName',
          'organizationId',item->>'organizationId',
          'organizationName',item->>'organizationName',
          'authorityKind',item->>'authorityKind',
          'scopeState',item->>'scopeState'
        ) as item
      from jsonb_array_elements(coalesce(v_ledgers->'items','[]'::jsonb)) item
      where
        lower(regexp_replace(coalesce(nullif(item->>'organizationName',''),item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
        or lower(regexp_replace(coalesce(item->>'ledgerName',''),'[[:space:]]+',' ','g'))=v_norm
        or (
          char_length(v_norm)>=3
          and (
            strpos(lower(coalesce(item->>'organizationName','')),v_norm)>0
            or strpos(v_norm,lower(coalesce(item->>'organizationName','')))>0
            or strpos(lower(coalesce(item->>'ledgerName','')),v_norm)>0
            or strpos(v_norm,lower(coalesce(item->>'ledgerName','')))>0
          )
        )
    ) matches
    order by exact_match desc,label,ledger_id
    limit v_limit
  ) x;

  select coalesce(jsonb_agg(x.item order by x.exact_match desc,x.label,x.organization_id),'[]'::jsonb)
  into v_org_matches
  from (
    select *
    from (
      select
        item->>'organizationId' as organization_id,
        coalesce(item->>'organizationName','') as label,
        lower(regexp_replace(coalesce(item->>'organizationName',''),'[[:space:]]+',' ','g'))=v_norm as exact_match,
        jsonb_build_object(
          'matchKind','organization_access',
          'matchStrength',case
            when lower(regexp_replace(coalesce(item->>'organizationName',''),'[[:space:]]+',' ','g'))=v_norm
              then 'exact_label'
            else 'contained_label'
          end,
          'organizationId',item->>'organizationId',
          'organizationName',item->>'organizationName',
          'organizationMembershipId',item->>'organizationMembershipId',
          'custodyDisposition',item->>'custodyDisposition'
        ) as item
      from jsonb_array_elements(coalesce(v_access->'items','[]'::jsonb)) item
      where
        lower(regexp_replace(coalesce(item->>'organizationName',''),'[[:space:]]+',' ','g'))=v_norm
        or (
          char_length(v_norm)>=3
          and (
            strpos(lower(coalesce(item->>'organizationName','')),v_norm)>0
            or strpos(v_norm,lower(coalesce(item->>'organizationName','')))>0
          )
        )
    ) matches
    order by exact_match desc,label,organization_id
    limit v_limit
  ) x;

  select coalesce(jsonb_agg(x.item order by x.exact_match desc,x.label,x.case_id),'[]'::jsonb)
  into v_case_matches
  from (
    select
      c.id::text as case_id,
      p.starting_label as label,
      lower(regexp_replace(p.starting_label,'[[:space:]]+',' ','g'))=v_norm as exact_match,
      jsonb_build_object(
        'matchKind','implementation_case',
        'matchStrength',case
          when lower(regexp_replace(p.starting_label,'[[:space:]]+',' ','g'))=v_norm then 'exact_label'
          else 'contained_label'
        end,
        'implementationCaseId',c.id,
        'startingLabel',p.starting_label,
        'caseState',c.state,
        'relationshipKind',cp.relationship_kind,
        'participantVerifiedAt',cp.verified_at
      ) as item
    from atlas.implementation_case_participants cp
    join atlas.implementation_cases c
      on c.id=cp.implementation_case_id
     and c.state not in ('closed','cancelled')
    join atlas.implementation_purchases p
      on p.id=c.implementation_purchase_id
    where cp.human_user_id=v_uid
      and cp.active
      and cp.ended_at is null
      and cp.verified_at is not null
      and (
        lower(regexp_replace(p.starting_label,'[[:space:]]+',' ','g'))=v_norm
        or (
          char_length(v_norm)>=3
          and (
            strpos(lower(p.starting_label),v_norm)>0
            or strpos(v_norm,lower(p.starting_label))>0
          )
        )
      )
    order by exact_match desc,label,c.id
    limit v_limit
  ) x;

  v_total :=
    jsonb_array_length(v_ledger_matches)
    + jsonb_array_length(v_org_matches)
    + jsonb_array_length(v_case_matches);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_institutional_anchor_resolution_v1',
    'state',case when v_total>0 then 'existing_reality_found' else 'unresolved' end,
    'proposalId',v_proposal.id,
    'captureId',v_capture.id,
    'sourceEvidenceId',v_capture.evidence_id,
    'candidateLabel',v_label,
    'existingLedgers',v_ledger_matches,
    'accessibleOrganizations',v_org_matches,
    'implementationCases',v_case_matches,
    'counts',jsonb_build_object(
      'existingLedgers',jsonb_array_length(v_ledger_matches),
      'accessibleOrganizations',jsonb_array_length(v_org_matches),
      'implementationCases',jsonb_array_length(v_case_matches)
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'labelMatchDoesNotEstablishIdentity',true,
      'noMatchDoesNotAuthorizeOrganizationCreation',true,
      'doesNotCreateCommercialProposal',true,
      'doesNotChooseLedgerPriceClass',true,
      'requiresHumanDestinationAdjudication',true
    )
  );
end;
$function$;

revoke all on function atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)
  to authenticated;

create or replace function public.resolve_personal_institutional_anchor_self_api_v1(
  p_proposal_id uuid,
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.resolve_personal_institutional_anchor_self_api_v1(
    p_proposal_id,
    p_limit
  );
$function$;

revoke all on function public.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)
  from public,anon,service_role;
grant execute on function public.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.resolve_personal_institutional_anchor_self_api_v1(uuid,integer)',
  'app_endpoint','verified','active',
  true,true,false,1,1,
  jsonb_build_object(
    'source','personal_institutional_anchor_resolution_v1',
    'purpose','Resolve a human-confirmed Institutional Anchor only against institutional reality already visible to the signed-in human.',
    'truthBoundary','Read-only label-compatible retrieval. It does not establish canonical institutional identity, create new scope, or create commercial reality.',
    'classificationRuleVersion',3
  ),
  false
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
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;

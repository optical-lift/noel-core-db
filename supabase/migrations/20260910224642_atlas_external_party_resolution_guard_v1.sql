begin;

create unique index if not exists external_relationships_org_subject_uq
  on atlas.external_relationships(organization_id,subject_id)
  where organization_unit_id is null;
create unique index if not exists external_relationships_unit_subject_uq
  on atlas.external_relationships(organization_id,organization_unit_id,subject_id)
  where organization_unit_id is not null;

create or replace function atlas.normalize_external_party_identifier_v1(p_identifier_type text,p_value text)
returns text
language sql
immutable
set search_path=pg_catalog
as $function$
  select case lower(btrim(coalesce(p_identifier_type,'')))
    when 'email' then lower(btrim(coalesce(p_value,'')))
    when 'phone' then regexp_replace(coalesce(p_value,''),'[^0-9]','','g')
    when 'display_name' then regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g')
    when 'name' then regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g')
    when 'domain' then regexp_replace(lower(btrim(coalesce(p_value,''))),'^www\.','','')
    when 'website' then regexp_replace(regexp_replace(lower(btrim(coalesce(p_value,''))),'^https?://','',''),'/$','','')
    else btrim(coalesce(p_value,''))
  end;
$function$;

comment on function atlas.normalize_external_party_identifier_v1(text,text) is
  'Narrow normalization helper for external-party resolution. Known contact/name types receive canonical normalization; unknown/provider IDs preserve case unless the adapter supplies normalized explicitly.';

insert into atlas.identity_source_records(
  organization_id,source_system_key,source_record_kind,source_record_key,source_observed_at,source_authority,custody_ref,metadata
)
select distinct
  f.organization_id,'local_intel','entity',b.entity_id::text,b.source_date::timestamptz,'enrichment',
  jsonb_build_object('localIntelEntityId',b.entity_id),
  jsonb_build_object('bridge','legacy_buyer_relationship_external_mapping','buyerRelationshipId',b.id,'farmId',b.farm_id)
from atlas.buyer_relationship_reconstruction b
join atlas.farms f on f.id=b.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.id
where b.entity_id is not null
on conflict (organization_id,source_system_key,source_record_kind,source_record_key) do nothing;

insert into atlas.identity_source_subject_assertions(
  organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key
)
select sr.organization_id,sr.id,m.identity_subject_id,'supports',1,
  'Existing buyer relationship was explicitly linked to this Local Intel entity.',
  'local-intel-buyer-bridge:'||b.id::text
from atlas.buyer_relationship_reconstruction b
join atlas.farms f on f.id=b.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.id
join atlas.identity_source_records sr on sr.organization_id=f.organization_id and sr.source_system_key='local_intel' and sr.source_record_kind='entity' and sr.source_record_key=b.entity_id::text
where b.entity_id is not null
on conflict (organization_id,idempotency_key) where idempotency_key is not null do nothing;

insert into atlas.identity_subject_external_identifiers(
  organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata
)
select f.organization_id,m.identity_subject_id,'local_intel','entity_id',b.entity_id::text,b.entity_id::text,true,9,
  jsonb_build_object('source','legacy_buyer_local_intel_bridge','buyerRelationshipId',b.id,'farmId',b.farm_id)
from atlas.buyer_relationship_reconstruction b
join atlas.farms f on f.id=b.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.id
where b.entity_id is not null
on conflict do nothing;

create or replace function atlas.resolve_external_relationship_service_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid default null,
  p_role_key text default 'customer',
  p_display_name text default null,
  p_subject_kind text default 'unknown',
  p_identifiers jsonb default '[]'::jsonb,
  p_source_system_key text default 'atlas',
  p_source_record_kind text default 'external_party_candidate',
  p_source_record_key text default null,
  p_source_observed_at timestamptz default null,
  p_source_authority text default 'evidence_only',
  p_custody_ref jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_allow_create boolean default false,
  p_new_relationship_state text default 'prospective'
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_role_key text:=lower(btrim(coalesce(p_role_key,'')));
  v_subject_kind text:=lower(btrim(coalesce(p_subject_kind,'unknown')));
  v_source_system_key text:=btrim(coalesce(p_source_system_key,''));
  v_source_record_kind text:=btrim(coalesce(p_source_record_kind,''));
  v_source_record_key text:=nullif(btrim(coalesce(p_source_record_key,'')),'');
  v_source_authority text:=lower(btrim(coalesce(p_source_authority,'evidence_only')));
  v_new_relationship_state text:=lower(btrim(coalesce(p_new_relationship_state,'prospective')));
  v_identifiers jsonb:=coalesce(p_identifiers,'[]'::jsonb);
  v_source_record_id uuid;
  v_bound_subjects uuid[];
  v_candidate_subjects uuid[];
  v_candidates jsonb:='[]'::jsonb;
  v_candidate_count integer:=0;
  v_candidate_has_strong integer:=0;
  v_subject_id uuid;
  v_relationship atlas.external_relationships%rowtype;
  v_role atlas.external_relationship_roles%rowtype;
  v_review_id uuid;
  v_match_state text;
  v_identifier jsonb;
  v_provider_key text;
  v_type text;
  v_value text;
  v_normalized text;
  v_identity_scoped boolean;
  v_claim_value jsonb;
  v_claim_id uuid;
  v_conflicting_subjects uuid[];
  v_identifier_conflicts jsonb:='[]'::jsonb;
  v_stable_key text;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id) then raise exception 'Organization not found.' using errcode='P0002'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units ou where ou.organization_id=p_organization_id and ou.id=p_organization_unit_id) then raise exception 'Organization unit is outside organization.' using errcode='23514'; end if;
  if v_role_key='' or v_role_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then raise exception 'A valid relationship role key is required.' using errcode='22023'; end if;
  if v_subject_kind not in ('unknown','person','organization','place') then raise exception 'Unsupported subject kind.' using errcode='22023'; end if;
  if v_source_system_key='' or v_source_record_kind='' then raise exception 'Source system and source record kind are required.' using errcode='22023'; end if;
  if v_source_authority not in ('evidence_only','enrichment','action_result','authoritative_source') then raise exception 'Unsupported source authority.' using errcode='22023'; end if;
  if v_new_relationship_state not in ('prospective','active','unknown') then raise exception 'New external relationships may begin prospective, active, or unknown.' using errcode='22023'; end if;
  if jsonb_typeof(v_identifiers)<>'array' then raise exception 'Identifiers must be a JSON array.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' or jsonb_typeof(coalesce(p_custody_ref,'{}'::jsonb))<>'object' then raise exception 'Basis and custody_ref must be JSON objects.' using errcode='22023'; end if;

  if nullif(btrim(coalesce(p_display_name,'')),'') is not null then
    v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object('type','display_name','value',btrim(p_display_name),'normalized',atlas.normalize_external_party_identifier_v1('display_name',p_display_name),'identityScoped',true,'matchStrength','weak'));
  end if;

  if v_source_record_key is null then
    v_source_record_key:='sha256:'||encode(extensions.digest(convert_to(jsonb_build_object('organizationUnitId',p_organization_unit_id,'roleKey',v_role_key,'displayName',p_display_name,'subjectKind',v_subject_kind,'identifiers',v_identifiers,'basis',coalesce(p_basis,'{}'::jsonb))::text,'UTF8'),'sha256'),'hex');
  end if;

  insert into atlas.identity_source_records(organization_id,source_system_key,source_record_kind,source_record_key,source_observed_at,source_authority,custody_ref,metadata)
  values(p_organization_id,v_source_system_key,v_source_record_kind,v_source_record_key,p_source_observed_at,v_source_authority,coalesce(p_custody_ref,'{}'::jsonb),
    jsonb_build_object('resolver','resolve_external_relationship_service_v1','organizationUnitId',p_organization_unit_id,'roleKey',v_role_key,'displayName',p_display_name,'subjectKind',v_subject_kind,'identifiers',v_identifiers)||coalesce(p_basis,'{}'::jsonb))
  on conflict (organization_id,source_system_key,source_record_kind,source_record_key) do nothing;
  select id into v_source_record_id from atlas.identity_source_records where organization_id=p_organization_id and source_system_key=v_source_system_key and source_record_kind=v_source_record_kind and source_record_key=v_source_record_key;

  with latest as (
    select distinct on (a.subject_id) a.subject_id,a.assertion_kind
    from atlas.identity_source_subject_assertions a
    where a.organization_id=p_organization_id and a.source_record_id=v_source_record_id
    order by a.subject_id,a.created_at desc,a.id desc
  ) select array_agg(subject_id order by subject_id) into v_bound_subjects from latest where assertion_kind='supports';

  if coalesce(array_length(v_bound_subjects,1),0)>1 then
    raise exception 'Identity source record is bound to multiple subjects and requires integrity repair.' using errcode='23505';
  elsif coalesce(array_length(v_bound_subjects,1),0)=1 then
    v_subject_id:=v_bound_subjects[1]; v_match_state:='matched_existing_source_binding';
  end if;

  if v_subject_id is null then
    with input_ids as (
      select nullif(btrim(x->>'providerKey'),'') as provider_key,
             lower(nullif(btrim(x->>'type'),'')) as identifier_type,
             nullif(btrim(x->>'value'),'') as identifier_value,
             coalesce(nullif(btrim(x->>'normalized'),''),atlas.normalize_external_party_identifier_v1(x->>'type',x->>'value')) as identifier_normalized,
             case when lower(coalesce(x->>'identityScoped','true')) in ('false','0','no') then false else true end as identity_scoped
      from jsonb_array_elements(v_identifiers) x
    ), valid_ids as (
      select * from input_ids where identity_scoped and identifier_type is not null and identifier_value is not null and btrim(identifier_normalized)<>''
        and identifier_type not in ('checkout_session_id','payment_intent_id','invoice_id','order_id','transaction_id','message_id','thread_id')
    ), latest_source_assertions as (
      select distinct on (a.subject_id) a.subject_id,a.assertion_kind from atlas.identity_source_subject_assertions a
      where a.organization_id=p_organization_id and a.source_record_id=v_source_record_id order by a.subject_id,a.created_at desc,a.id desc
    ), hits as (
      select i.subject_id,count(*)::int as hit_count,
             bool_or(v.provider_key is not null or v.identifier_type in ('email','phone','entity_id','customer_id','vendor_id','account_id','contact_id','legacy_relationship_key')) as strong_exact
      from valid_ids v
      join atlas.identity_subject_external_identifiers i on i.organization_id=p_organization_id and i.is_current and i.identifier_type=v.identifier_type and i.identifier_normalized=v.identifier_normalized and coalesce(i.provider_key,'')=coalesce(v.provider_key,'')
      left join latest_source_assertions la on la.subject_id=i.subject_id
      where coalesce(la.assertion_kind,'')<>'non_match'
      group by i.subject_id
    ), candidate_rows as (
      select h.subject_id,h.hit_count,h.strong_exact,p.display_name,p.subject_kind,
        coalesce((select jsonb_agg(r.id order by r.created_at,r.id) from atlas.external_relationships r where r.organization_id=p_organization_id and r.subject_id=h.subject_id and r.organization_unit_id is not distinct from p_organization_unit_id),'[]'::jsonb) as relationship_ids
      from hits h left join atlas.identity_subject_projections p on p.subject_id=h.subject_id
    )
    select count(*)::int,
      coalesce(array_agg(subject_id order by strong_exact desc,hit_count desc,subject_id),'{}'::uuid[]),
      coalesce(jsonb_agg(jsonb_build_object('subjectId',subject_id,'displayName',display_name,'subjectKind',subject_kind,'identifierHitCount',hit_count,'strongExactIdentifier',strong_exact,'relationshipIds',relationship_ids) order by strong_exact desc,hit_count desc,subject_id),'[]'::jsonb),
      coalesce(max(case when strong_exact then 1 else 0 end),0)
    into v_candidate_count,v_candidate_subjects,v_candidates,v_candidate_has_strong from candidate_rows;

    if v_candidate_count=1 and v_candidate_has_strong=1 then
      v_subject_id:=v_candidate_subjects[1]; v_match_state:='matched_exact_identifier';
    elsif v_candidate_count>0 then
      select r.id into v_review_id from atlas.identity_reconciliation_reviews r where r.organization_id=p_organization_id and r.source_record_id=v_source_record_id and r.review_kind='source_binding' and r.status='open' order by r.created_at,r.id limit 1;
      if v_review_id is null then
        insert into atlas.identity_reconciliation_reviews(organization_id,review_kind,source_record_id,left_subject_id,status,priority,candidate_data,opened_by)
        values(p_organization_id,'source_binding',v_source_record_id,v_candidate_subjects[1],'open','normal',
          jsonb_build_object('reason',case when v_candidate_count>1 then 'multiple_known_party_candidates' else 'weak_identity_evidence_only' end,'organizationUnitId',p_organization_unit_id,'roleKey',v_role_key,'displayName',p_display_name,'identifiers',v_identifiers,'candidates',v_candidates),
          'external_relationship_resolver') returning id into v_review_id;
      end if;
      return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','identity_review_required','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'reviewId',v_review_id,'candidateCount',v_candidate_count,'candidates',v_candidates,'subjectId',null,'externalRelationshipId',null,'createdSubject',false,'createdRelationship',false);
    elsif not p_allow_create then
      return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','no_match','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'candidateCount',0,'candidates','[]'::jsonb,'subjectId',null,'externalRelationshipId',null,'createdSubject',false,'createdRelationship',false);
    else
      insert into atlas.identity_subjects(organization_id,state,creation_basis)
      values(p_organization_id,'active',jsonb_build_object('sourceSystemKey',v_source_system_key,'sourceRecordKind',v_source_record_kind,'sourceRecordKey',v_source_record_key,'sourceRecordId',v_source_record_id,'resolver','resolve_external_relationship_service_v1')) returning id into v_subject_id;
      insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis)
      values(v_subject_id,p_organization_id,v_subject_kind,nullif(btrim(p_display_name),''),'[]'::jsonb,'[]'::jsonb,nullif(btrim(coalesce(p_display_name,'')),'') is null,case when nullif(btrim(coalesce(p_display_name,'')),'') is null then null else 0.8 end,jsonb_build_object('sourceRecordId',v_source_record_id,'resolver','resolve_external_relationship_service_v1'));
      v_match_state:='created_new_subject';
    end if;
  end if;

  if not exists(select 1 from (select a.assertion_kind from atlas.identity_source_subject_assertions a where a.organization_id=p_organization_id and a.source_record_id=v_source_record_id and a.subject_id=v_subject_id order by a.created_at desc,a.id desc limit 1) q where q.assertion_kind='supports') then
    insert into atlas.identity_source_subject_assertions(organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key)
    values(p_organization_id,v_source_record_id,v_subject_id,'supports',1,
      case when v_match_state='matched_exact_identifier' then 'Deterministic exact identity identifier match.' when v_match_state='created_new_subject' then 'No known-party candidate remained; new identity subject created from source evidence.' else 'Previously established source binding.' end,
      'external-party-resolver:'||v_source_record_id::text||':'||v_subject_id::text||':supports')
    on conflict (organization_id,idempotency_key) where idempotency_key is not null do nothing;
  end if;

  select * into v_relationship from atlas.external_relationships r where r.organization_id=p_organization_id and r.subject_id=v_subject_id and r.organization_unit_id is not distinct from p_organization_unit_id order by r.created_at,r.id limit 1;
  if v_relationship.id is null then
    if not p_allow_create then return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','matched_subject_no_relationship','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'subjectId',v_subject_id,'externalRelationshipId',null,'matchState',v_match_state,'createdSubject',v_match_state='created_new_subject','createdRelationship',false); end if;
    v_stable_key:='subject:'||v_subject_id::text;
    insert into atlas.external_relationships(organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata)
    values(p_organization_id,p_organization_unit_id,v_subject_id,v_stable_key,v_new_relationship_state,jsonb_build_object('sourceRecordId',v_source_record_id,'resolver','resolve_external_relationship_service_v1')||coalesce(p_basis,'{}'::jsonb)) returning * into v_relationship;
  elsif v_relationship.relationship_state in ('inactive','ended') then
    return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','relationship_inactive','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'subjectId',v_subject_id,'externalRelationshipId',v_relationship.id,'relationshipState',v_relationship.relationship_state,'matchState',v_match_state,'createdSubject',v_match_state='created_new_subject','createdRelationship',false);
  end if;

  select * into v_role from atlas.external_relationship_roles rr where rr.external_relationship_id=v_relationship.id and rr.role_key=v_role_key;
  if v_role.external_relationship_id is null then
    if not p_allow_create then return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','matched_relationship_without_role','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'subjectId',v_subject_id,'externalRelationshipId',v_relationship.id,'roleKey',v_role_key,'matchState',v_match_state,'createdSubject',v_match_state='created_new_subject','createdRelationship',false); end if;
    insert into atlas.external_relationship_roles(external_relationship_id,role_key,role_state,basis)
    values(v_relationship.id,v_role_key,'active',jsonb_build_object('sourceRecordId',v_source_record_id,'resolver','resolve_external_relationship_service_v1')) returning * into v_role;
  elsif v_role.role_state<>'active' then
    return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state','relationship_role_inactive','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'subjectId',v_subject_id,'externalRelationshipId',v_relationship.id,'roleKey',v_role_key,'roleState',v_role.role_state,'matchState',v_match_state);
  end if;

  for v_identifier in select value from jsonb_array_elements(v_identifiers) loop
    v_provider_key:=nullif(btrim(v_identifier->>'providerKey'),''); v_type:=lower(nullif(btrim(v_identifier->>'type'),'')); v_value:=nullif(btrim(v_identifier->>'value'),'');
    v_normalized:=coalesce(nullif(btrim(v_identifier->>'normalized'),''),atlas.normalize_external_party_identifier_v1(v_type,v_value));
    v_identity_scoped:=case when lower(coalesce(v_identifier->>'identityScoped','true')) in ('false','0','no') then false else true end;
    if v_type is null or v_value is null or v_normalized is null or btrim(v_normalized)='' then continue; end if;
    v_claim_value:=jsonb_build_object('providerKey',v_provider_key,'type',v_type,'value',v_value,'normalized',v_normalized,'identityScoped',v_identity_scoped);
    select c.id into v_claim_id from atlas.identity_claims c where c.organization_id=p_organization_id and c.subject_id=v_subject_id and c.source_record_id=v_source_record_id and c.claim_kind='external_identifier' and c.claim_value=v_claim_value order by c.created_at,c.id limit 1;
    if v_claim_id is null then
      insert into atlas.identity_claims(organization_id,subject_id,source_record_id,claim_kind,claim_value,confidence,basis,metadata)
      values(p_organization_id,v_subject_id,v_source_record_id,'external_identifier',v_claim_value,1,'Source-supplied external party identifier.',jsonb_build_object('resolver','resolve_external_relationship_service_v1')) returning id into v_claim_id;
    end if;
    if not v_identity_scoped or v_type in ('checkout_session_id','payment_intent_id','invoice_id','order_id','transaction_id','message_id','thread_id') then continue; end if;
    select array_agg(distinct i.subject_id) into v_conflicting_subjects from atlas.identity_subject_external_identifiers i where i.organization_id=p_organization_id and i.is_current and i.subject_id<>v_subject_id and i.identifier_type=v_type and i.identifier_normalized=v_normalized and coalesce(i.provider_key,'')=coalesce(v_provider_key,'');
    if coalesce(array_length(v_conflicting_subjects,1),0)>0 then
      v_identifier_conflicts:=v_identifier_conflicts||jsonb_build_array(jsonb_build_object('claimId',v_claim_id,'providerKey',v_provider_key,'type',v_type,'value',v_value,'normalized',v_normalized,'conflictingSubjectIds',to_jsonb(v_conflicting_subjects)));
    else
      insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata)
      values(p_organization_id,v_subject_id,v_provider_key,v_type,v_value,v_normalized,true,case when v_provider_key is not null then 9 when v_type in ('email','phone') then 8 when v_type='display_name' then 4 else 6 end,jsonb_build_object('sourceRecordId',v_source_record_id,'resolver','resolve_external_relationship_service_v1')) on conflict do nothing;
    end if;
  end loop;

  if nullif(btrim(coalesce(p_display_name,'')),'') is not null then
    update atlas.identity_subject_projections p set display_name=coalesce(p.display_name,btrim(p_display_name)),unresolved_identity=case when p.display_name is null then false else p.unresolved_identity end,confidence=coalesce(p.confidence,case when v_match_state='matched_exact_identifier' then 1 else 0.8 end),projection_basis=p.projection_basis||jsonb_build_object('lastResolverSourceRecordId',v_source_record_id) where p.subject_id=v_subject_id;
  end if;

  return jsonb_build_object('contractVersion','resolve_external_relationship_service_v1','state',case when jsonb_array_length(v_identifier_conflicts)>0 then 'resolved_with_identifier_conflict' else 'resolved' end,'organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'sourceRecordId',v_source_record_id,'subjectId',v_subject_id,'externalRelationshipId',v_relationship.id,'relationshipState',v_relationship.relationship_state,'roleKey',v_role_key,'matchState',v_match_state,'createdSubject',v_match_state='created_new_subject','createdRelationship',v_relationship.created_at>=transaction_timestamp(),'identifierConflicts',v_identifier_conflicts);
end;
$function$;

comment on function atlas.resolve_external_relationship_service_v1(uuid,uuid,text,text,text,jsonb,text,text,text,timestamptz,text,jsonb,jsonb,boolean,text) is
  'Canonical service resolver for organization external relationships. It searches existing identity evidence before creation, auto-matches only unique strong exact identifiers, opens identity review for ambiguous/weak candidates, respects prior non-match adjudication, and creates a new subject/relationship only when no candidate remains and creation is explicitly allowed.';

revoke all on function atlas.normalize_external_party_identifier_v1(text,text) from public,anon,authenticated;
revoke all on function atlas.resolve_external_relationship_service_v1(uuid,uuid,text,text,text,jsonb,text,text,text,timestamptz,text,jsonb,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function atlas.normalize_external_party_identifier_v1(text,text) to service_role;
grant execute on function atlas.resolve_external_relationship_service_v1(uuid,uuid,text,text,text,jsonb,text,text,text,timestamptz,text,jsonb,jsonb,boolean,text) to service_role;

create or replace function atlas.resolve_connected_source_external_relationship_service_v1(p_connected_source_id uuid,p_organization_unit_id uuid default null,p_display_name text default null,p_subject_kind text default 'unknown',p_identifiers jsonb default '[]'::jsonb,p_basis jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare v_source atlas.connected_sources%rowtype; v_identifiers jsonb:=coalesce(p_identifiers,'[]'::jsonb); v_source_record_key text; v_has_strong_identity boolean:=false; v_result jsonb;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state<>'connected' then raise exception 'A connected organization source is required.' using errcode='55000'; end if;
  if jsonb_typeof(v_identifiers)<>'array' or jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' then raise exception 'Identifiers must be an array and basis must be an object.' using errcode='22023'; end if;
  select exists(select 1 from jsonb_array_elements(v_identifiers) x where case when lower(coalesce(x->>'identityScoped','true')) in ('false','0','no') then false else true end and lower(coalesce(x->>'type','')) not in ('checkout_session_id','payment_intent_id','invoice_id','order_id','transaction_id','message_id','thread_id','display_name','name','website','domain','address') and nullif(btrim(x->>'value'),'') is not null) into v_has_strong_identity;
  v_source_record_key:=coalesce(nullif(btrim(p_basis->>'sourceObservationId'),''),nullif(btrim(p_basis->>'sourceEventRef'),''),nullif(btrim(p_basis->>'providerRecordId'),''),nullif(btrim(p_basis->>'checkoutSessionId'),''),'sha256:'||encode(extensions.digest(convert_to(jsonb_build_object('connectedSourceId',v_source.id,'displayName',p_display_name,'identifiers',v_identifiers,'basis',coalesce(p_basis,'{}'::jsonb))::text,'UTF8'),'sha256'),'hex'));
  v_result:=atlas.resolve_external_relationship_service_v1(p_organization_id=>v_source.custodian_organization_id,p_organization_unit_id=>p_organization_unit_id,p_role_key=>'customer',p_display_name=>p_display_name,p_subject_kind=>p_subject_kind,p_identifiers=>v_identifiers,p_source_system_key=>'connected_source:'||v_source.provider_key,p_source_record_kind=>'external_relationship_candidate',p_source_record_key=>v_source_record_key,p_source_observed_at=>null,p_source_authority=>'evidence_only',p_custody_ref=>jsonb_build_object('connectedSourceId',v_source.id),p_basis=>jsonb_build_object('connectedSourceId',v_source.id,'providerKey',v_source.provider_key)||coalesce(p_basis,'{}'::jsonb),p_allow_create=>v_has_strong_identity,p_new_relationship_state=>'active');
  return v_result||jsonb_build_object('connectedSourceId',v_source.id,'providerKey',v_source.provider_key);
end;
$function$;
revoke all on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) to service_role;

commit;

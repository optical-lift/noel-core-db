BEGIN;

-- Evidence-only, recipient-scoped, read-only family retrieval. Do not
-- modify Person, Household membership, Principal, identity link, or permissions.
CREATE OR REPLACE FUNCTION atlas.household_identity_received_links_self_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT jsonb_build_object('ok',true,'links',coalesce(jsonb_agg(jsonb_build_object(
    'householdMemberId',l.household_member_id,
    'householdOwnerName',p.name,
    'relationshipAsRecorded',nullif(btrim(m.relationship),''),
    'relationshipSource','inviting_household_member_record',
    'relationshipReciprocallyConfirmed',false,
    'householdAccessGranted',false,
    'linkedAt',l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb))
  FROM atlas.household_member_identity_links l
  JOIN atlas.household_members m ON m.id=l.household_member_id AND m.household_id=l.household_id AND m.active
  JOIN atlas.households h ON h.id=l.household_id
  JOIN atlas.principals p ON p.id=h.principal_id
  WHERE l.target_auth_user_id=auth.uid() AND l.link_state='active';
$function$


CREATE OR REPLACE FUNCTION atlas.atlas_notebook_index_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_categories jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;

  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  -- The most recent human orientation (v3 Field/Position/Scale or historical
  -- v4 Index categories) is a retrieval hint, not a separate onboarding gate.
  -- The latest human-selected FIELD remains an intentional notebook section.
  -- Real answers may establish further domains; there is no extra Index form.
  with latest_orientation as (
    select coalesce(e.world_domains,'[]'::jsonb) as domains
    from atlas.reality_discovery_orientation_events e
    where e.principal_id=v_principal_id and e.owner_user_id=v_user_id
      and e.orientation_version in (3,4)
    order by e.occurred_at desc,e.id desc limit 1
  ),
  domain_evidence as (
    select jsonb_array_elements_text(domains) as domain
    from latest_orientation
    union
    select jsonb_array_elements_text(
      case when jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
        then q.metadata->'orientationWorldDomains' else '[]'::jsonb end)
    from atlas.reality_discovery_answer_events a
    join atlas.reality_discovery_questions q on q.question_key=a.question_key
    where a.principal_id=v_principal_id and a.owner_user_id=v_user_id
    union
    -- An accepted identity-only household link is sufficient to make Family
    -- retrievable, but never implies shared Household access or a family-role verdict.
    select 'family'::text
      from atlas.household_member_identity_links l
     where l.target_auth_user_id=v_user_id and l.link_state='active'
  )
  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
    into v_categories
  from (select distinct domain from domain_evidence where domain in
      ('home','family','job','business','property','money','school','projects','community','hobbies')) d;

  with descriptors as (
    select -10 as section_order,0 as item_order,
      jsonb_build_object(
        'addressKind','bookplate','spreadKey','bookplate','templateKey','bookplate',
        'title','Bookplate','section','Notebook',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','person','id',v_principal_id)
      ) as item
    union all
    select 0,0,
      jsonb_build_object('addressKind','today','spreadKey','today','templateKey','today','title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','day','id',current_date::text))
    union all
    select 0,1,
      jsonb_build_object('addressKind','index','spreadKey','index','templateKey','index','title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','notebook','id',v_user_id))
    union all
    select 5,
      case d.category
        when 'home' then 10
        when 'family' then 20
        when 'job' then 30
        when 'business' then 40
        when 'property' then 50
        when 'money' then 60
        when 'school' then 70
        when 'projects' then 80
        when 'community' then 90
        when 'hobbies' then 100
        else 999
      end,
      jsonb_build_object(
        'addressKind','section',
        'spreadKey','section:'||d.category,
        'templateKey','section-root',
        'title',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'section',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('domain',d.category,'kind','section','id',d.category),
        'intentionalSectionRoot',true
      )
    from jsonb_array_elements_text(v_categories) d(category)
    union all
    select 10,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey',s.spread_key,'templateKey','composed',
        'title',s.title,'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'spreadInstanceId',s.id,'spreadState',s.spread_state,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'purposeKey',s.purpose_key,'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb)
  into v_items
  from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,
      'indexDoesNotGrantAccess',true,
      'bookplateIsHumanEditableContactPresentation',true,
      'selectedSectionRootsAreIntentionalOrganizationNotDomainTruth',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,
      'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,
      'closedSpreadsRemainRetrievable',true,
      'dataBearingPagesComeFromDurableSpreadRegistry',true
    )
  );
end;
$function$


COMMIT;

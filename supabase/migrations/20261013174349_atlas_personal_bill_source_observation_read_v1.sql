-- Candidate read-only admission. Review under noel-core-db custody.
create or replace function atlas.personal_bill_notice_source_observations_self_api_v1(p_limit integer default 24)
returns jsonb language sql stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $fn$
with principal as (
 select id from atlas.principals
 where user_id=auth.uid() and status='active' order by id limit 1
), permitted as (
 select id from atlas.connected_sources
 where auth.uid() is not null and custodian_user_id=auth.uid()
 and custodian_organization_id is null
 and custodian_organization_unit_id is null
 and provider_key in ('email','imap_smtp_email','gmail','microsoft_graph_email')
 and authorization_state='connected' and revoked_at is null
 and capabilities @> '{"communicationCapture":true,"personalBillRecognition":true}'::jsonb
 and ( 'communication.capture'=any(granted_scopes)
       or 'mail.read'=any(granted_scopes)
       or 'https://www.googleapis.com/auth/gmail.readonly'=any(granted_scopes) )
 and metadata->'personalBillRecognitionConsent' @> '{"enabled":true}'::jsonb
 and metadata#>>'{personalBillRecognitionConsent,actorUserId}'=auth.uid()::text
 and nullif(metadata#>>'{personalBillRecognitionConsent,sourceActionId}','') is not null
), observations as (
 select jsonb_build_object(
 'scope',jsonb_build_object('kind','principal','id',p.id),
 'source',jsonb_build_object(
 'connectedSourceId',s.id,
 'sourceEventRef',o.source_event_ref,
 'contentSha256',o.source_content_hash,
 'providerOccurredDate',to_char(e.occurred_at at time zone 'UTC','YYYY-MM-DD'),
 'observedDate',to_char(o.observed_at at time zone 'UTC','YYYY-MM-DD'),
 'authorizedForRecognitionAtRead',true,
 'coverage','partial'),
 'notice',jsonb_build_object(
 'kind',o.observed_event#>>'{billNotice,kind}',
 'billerName',o.observed_event#>'{billNotice,billerName}',
 'statementPeriodStart',o.observed_event#>'{billNotice,statementPeriodStart}',
 'accountReference',o.observed_event#>'{billNotice,accountReference}',
 'statedDueDate',o.observed_event#>'{billNotice,statedDueDate}',
 'statedAmountDue',o.observed_event#>'{billNotice,statedAmountDue}'
 )) item
 from atlas.communication_event_source_observations o
 join atlas.communication_events e on e.id=o.event_id
 join permitted s on s.id=o.connected_source_id
 join principal p on p.id=o.principal_id
 where e.principal_id=p.id and e.connected_source_id=s.id
 and o.organization_id is null and o.organization_unit_id is null
 and e.organization_id is null and o.observation_kind='source_state_enrichment'
 and e.occurred_at is not null
 and jsonb_typeof(o.observed_event->'billNotice')='object'
 and o.source_content_hash ~ '^[0-9a-fA-F]{64}$'
 order by o.observed_at desc,o.id desc
 limit least(greatest(coalesce(p_limit,24),1),50)
)
select jsonb_build_object(
 'ok',auth.uid() is not null and exists(select 1 from principal),
 'identityRoot','authorized_personal_source_observation',
 'personalBillRecognitionReady',exists(select 1 from permitted),
 'coverageClaim','per_observation_only',
 'connectionChoices',coalesce((
   select jsonb_agg(jsonb_build_object(
     'sourceId',s.id,
     'displayLabel',left(coalesce(s.display_label,s.provider_key),120),
     'transportReady',(
       s.authorization_state='connected' and s.revoked_at is null
       and s.capabilities @> '{"communicationCapture":true,"personalBillRecognition":true}'::jsonb
       and ('communication.capture'=any(s.granted_scopes)
         or 'mail.read'=any(s.granted_scopes)
         or 'https://www.googleapis.com/auth/gmail.readonly'=any(s.granted_scopes))
     ),
     'consentEnabled',(
       s.metadata->'personalBillRecognitionConsent' @> '{"enabled":true}'::jsonb
       and s.metadata#>>'{personalBillRecognitionConsent,actorUserId}'=auth.uid()::text
     )
   ) order by s.id)
   from atlas.connected_sources s
   where s.custodian_user_id=auth.uid()
     and s.custodian_organization_id is null
     and s.custodian_organization_unit_id is null
     and s.provider_key in ('email','imap_smtp_email','gmail','microsoft_graph_email')
     and exists(select 1 from principal)
 ),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(item) from observations),'[]'::jsonb),
 'domainTruthEstablished',false,'clockAuthority',false)
$fn$;

-- Explicitly close PostgreSQL's default PUBLIC execution grant.
revoke all on function atlas.personal_bill_notice_source_observations_self_api_v1(integer) from public,anon;
grant execute on function atlas.personal_bill_notice_source_observations_self_api_v1(integer) to authenticated;

-- The owner grants/revokes *Atlas interpretation consent*, not the provider's
-- OAuth/API read scope and not a financial obligation.
create or replace function atlas.set_personal_bill_recognition_consent_self_api_v1(
  p_connected_source_id uuid,
  p_enabled boolean,
  p_source_action_id text
) returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','atlas','auth'
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_source atlas.connected_sources%rowtype;
  v_action text:=nullif(trim(p_source_action_id),'');
  v_meta jsonb;
  v_history jsonb;
  v_prior jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  if p_connected_source_id is null or p_enabled is null or v_action is null
    or length(v_action)>160 then
    raise exception 'Valid source, decision and source action required.' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.principals
    where user_id=v_uid and status='active') then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;
  select * into v_source from atlas.connected_sources
    where id=p_connected_source_id and custodian_user_id=v_uid
      and custodian_organization_id is null
      and custodian_organization_unit_id is null
    for update;
  if v_source.id is null then
    raise exception 'An owned personal email source is required.' using errcode='42501';
  end if;
  if v_source.provider_key not in ('email','imap_smtp_email','gmail','microsoft_graph_email') then
    raise exception 'Only an email source supports this consent.' using errcode='22023';
  end if;
  v_meta:=coalesce(v_source.metadata,'{}'::jsonb);
  v_history:=coalesce(v_meta->'billRecognitionConsentHistory','[]'::jsonb);
  if jsonb_typeof(v_history)<>'array' then v_history:='[]'::jsonb; end if;
  select value into v_prior from jsonb_array_elements(v_history)
    where value->>'actionId'=v_action limit 1;
  if v_prior is not null then
    if v_prior->>'enabled' is distinct from p_enabled::text then
      raise exception 'This source action belongs to a different decision.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotentReplay',true,
      'consentEnabled',v_meta->'personalBillRecognitionConsent'->'enabled');
  end if;
  if p_enabled and (
    v_source.authorization_state<>'connected'
    or v_source.revoked_at is not null
    or not (v_source.capabilities @> '{"communicationCapture":true,"personalBillRecognition":true}'::jsonb)
    or not ('communication.capture'=any(v_source.granted_scopes)
     or 'mail.read'=any(v_source.granted_scopes)
     or 'https://www.googleapis.com/auth/gmail.readonly'=any(v_source.granted_scopes))
  ) then
    raise exception 'An active verified email-read source is required.' using errcode='42501';
  end if;
  v_history:=v_history||jsonb_build_array(jsonb_build_object(
    'actionId',v_action,'actorUserId',v_uid,'enabled',p_enabled,'recordedAt',now()));
  if jsonb_array_length(v_history)>32 then
    select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
    into v_history from jsonb_array_elements(v_history)
    with ordinality item(value,ordinality)
    where ordinality>jsonb_array_length(v_history)-32;
  end if;
  v_meta:=v_meta||jsonb_build_object(
    'personalBillRecognitionConsent',jsonb_build_object(
      'enabled',p_enabled,
      'actorUserId',v_uid,
      'sourceActionId',v_action,
      'capturedAt',now()
    ),
    'billRecognitionConsentHistory',v_history
  );
  update atlas.connected_sources set metadata=v_meta,updated_at=now()
    where id=v_source.id;
  return jsonb_build_object('ok',true,'idempotentReplay',false,
    'consentEnabled',p_enabled,
    'providerGrantChanged',false,
    'moneyOrClockEstablished',false);
end
$fn$;

revoke all on function atlas.set_personal_bill_recognition_consent_self_api_v1(uuid,boolean,text) from public,anon;
grant execute on function atlas.set_personal_bill_recognition_consent_self_api_v1(uuid,boolean,text) to authenticated;

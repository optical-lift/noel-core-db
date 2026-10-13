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
 'authorizedAtCapture',true,
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
 'items',coalesce((select jsonb_agg(item) from observations),'[]'::jsonb),
 'domainTruthEstablished',false,'clockAuthority',false)
$fn$;

-- Explicitly close PostgreSQL's default PUBLIC execution grant.
revoke all on function atlas.personal_bill_notice_source_observations_self_api_v1(integer) from public,anon;
grant execute on function atlas.personal_bill_notice_source_observations_self_api_v1(integer) to authenticated;

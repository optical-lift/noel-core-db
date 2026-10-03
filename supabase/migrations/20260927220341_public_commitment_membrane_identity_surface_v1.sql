create or replace function atlas.resolve_public_commitment_person_v1(
  p_name text,
  p_email text,
  p_phone text,
  p_surface_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_name text:=btrim(coalesce(p_name,''));
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_phone text:=nullif(btrim(coalesce(p_phone,'')),'');
  v_ids uuid[];
  v_count integer:=0;
  v_entity_id uuid;
  v_state text;
  v_normalized_phone text;
begin
  if length(v_name)<2 or length(v_name)>160 then
    raise exception 'Name is required.' using errcode='22023';
  end if;
  if length(v_email)<5 or length(v_email)>254 or position('@' in v_email)<2 then
    raise exception 'A valid email address is required.' using errcode='22023';
  end if;
  if v_phone is not null and length(v_phone)>60 then
    raise exception 'Phone number is too long.' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,0));

  select array_agg(distinct e.id order by e.id),count(distinct e.id)
  into v_ids,v_count
  from reality.contact_routes c
  join reality.entities e on e.id=c.entity_id
  where c.route_kind='email'
    and lower(coalesce(c.normalized_value,c.route_value))=v_email
    and c.route_state in ('observed','verified')
    and e.identity_state='canonical'
    and e.entity_kind='person';

  if v_count=1 then
    v_entity_id:=v_ids[1];
    v_state:='matched';
  elsif v_count=0 then
    v_entity_id:=gen_random_uuid();
    insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
    values(
      v_entity_id,
      'public_person_'||replace(v_entity_id::text,'-',''),
      'person',v_name,'canonical',
      jsonb_build_object(
        'admittedFrom','public_commitment_surface',
        'admissionBasis',jsonb_build_object(
          'basis','Direct self-supplied public request identity',
          'surfaceKey',p_surface_key
        ),
        'identityEvidenceState','self_supplied_direct_contact'
      )
    );
    insert into reality.contact_routes(
      entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
    ) values(
      v_entity_id,'email',v_email,v_email,'observed',false,
      jsonb_build_object('sourceSystem','public_commitment_surface','verificationState','self_supplied','visibility','private','surfaceKey',p_surface_key),
      jsonb_build_object('contactScope','direct','context','public commitment request')
    );
    v_state:='created';
  else
    v_entity_id:=null;
    v_state:='ambiguous';
  end if;

  if v_entity_id is not null and v_phone is not null then
    v_normalized_phone:=regexp_replace(v_phone,'[^0-9+]','','g');
    insert into reality.contact_routes(
      entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
    ) values(
      v_entity_id,'phone',v_phone,nullif(v_normalized_phone,''),'observed',false,
      jsonb_build_object('sourceSystem','public_commitment_surface','verificationState','self_supplied','visibility','private','surfaceKey',p_surface_key),
      jsonb_build_object('contactScope','direct','context','public commitment request')
    )
    on conflict(entity_id,route_kind,normalized_value) do nothing;
  end if;

  return jsonb_build_object('entityId',v_entity_id,'resolutionState',v_state,'email',v_email);
end;
$function$;

create or replace function atlas.public_commitment_surface_v1(p_surface_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_resources jsonb:='[]'::jsonb;
  v_prices jsonb:='[]'::jsonb;
  v_commitment jsonb:='{}'::jsonb;
  v_approval_required boolean:=false;
  v_min_minutes numeric:=null;
begin
  select * into v_surface
  from atlas.public_commitment_surfaces s
  where s.surface_key=btrim(p_surface_key) and s.surface_state='active';
  if v_surface.id is null then
    raise exception 'Public commitment surface not found or not active.' using errcode='P0002';
  end if;

  if v_surface.adapter_kind='ledger_booking' then
    select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'key',r.stable_key,'label',r.label,'resourceKind',r.resource_kind,'capacityMode',r.capacity_mode
    ) order by r.label,r.id),'[]'::jsonb)
    into v_resources
    from reality.resources r
    where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
      and r.resource_state='active' and r.reservable
      and r.stable_key in (
        select value from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicResourceKeys','[]'::jsonb))
      );

    select coalesce(jsonb_agg(jsonb_build_object(
      'priceBasis',p.price_basis,'amount',p.unit_price,'currency',p.currency,
      'componentType',p.metadata->>'componentType','scope',p.metadata->>'scope'
    ) order by p.price_basis),'[]'::jsonb)
    into v_prices
    from atlas.commercial_offering_prices p
    where p.offering_id=v_surface.commercial_offering_id
      and p.effective_from<=current_date
      and (p.effective_until is null or p.effective_until>=current_date)
      and p.price_basis in (
        select value from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicPriceBasisKeys','[]'::jsonb))
      );

    select coalesce(p.config,'{}'::jsonb) into v_commitment
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='commitment'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind)
    order by p.priority desc,p.id limit 1;

    select coalesce(bool_or(coalesce((p.config->>'required')::boolean,false)),false)
    into v_approval_required
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='approval'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind);

    select max((p.config->>'minMinutes')::numeric)
    into v_min_minutes
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='duration' and p.config ? 'minMinutes'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind);
  end if;

  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_surface_v1',
    'surfaceKey',v_surface.surface_key,
    'title',v_surface.title,
    'description',v_surface.description,
    'adapterKind',v_surface.adapter_kind,
    'publicConfig',v_surface.public_config,
    'offering',case when v_surface.adapter_kind='ledger_booking' then jsonb_build_object(
      'name',v_booking.name,'bookingKind',v_booking.booking_kind,'occurrenceType',v_booking.occurrence_type,
      'defaultDurationMinutes',v_booking.default_duration_minutes,'minimumDurationMinutes',v_min_minutes
    ) else null end,
    'resourceOptions',v_resources,
    'pricingComponents',v_prices,
    'commitmentRequirements',jsonb_build_object(
      'approvalRequired',v_approval_required,
      'agreementRequired',coalesce((v_commitment->>'agreementRequired')::boolean,false),
      'paymentRequiredBeforeConfirmation',coalesce((v_commitment->>'paymentRequiredBeforeConfirmation')::boolean,false),
      'paymentRule',jsonb_build_object(
        'currency',coalesce(v_commitment->>'currency','USD'),
        'fullPaymentAtOrBelowAmount',case when v_commitment ? 'fullPaymentAtOrBelowAmount' then (v_commitment->>'fullPaymentAtOrBelowAmount')::numeric else null end,
        'fullPaymentPercentAtOrBelowThreshold',case when v_commitment ? 'fullPaymentPercentAtOrBelowThreshold' then (v_commitment->>'fullPaymentPercentAtOrBelowThreshold')::numeric else null end,
        'depositPercentAboveThreshold',case when v_commitment ? 'depositPercentAboveThreshold' then (v_commitment->>'depositPercentAboveThreshold')::numeric else null end,
        'remainingBalanceDueTimingState',v_commitment->>'remainingBalanceDueTimingState'
      )
    ),
    'allowedActions',jsonb_build_array('begin_request','evaluate_selection','submit_request')
  );
end;
$function$;

create or replace function atlas.public_commitment_session_v1(p_access_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_hash text;
  v_session atlas.public_commitment_sessions%rowtype;
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_name text;
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  select * into v_surface from atlas.public_commitment_surfaces s where s.id=v_session.surface_id;
  v_name:=coalesce(v_session.identity_snapshot->>'name',(select e.display_name from reality.entities e where e.id=v_session.requester_entity_id));
  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_session_v1',
    'sessionId',v_session.id,
    'surfaceKey',v_surface.surface_key,
    'title',v_surface.title,
    'sessionState',v_session.session_state,
    'identity',jsonb_build_object('name',v_name,'resolutionState',v_session.identity_resolution_state),
    'currentPayload',v_session.current_payload,
    'domainObjectKind',v_session.domain_object_kind,
    'domainObjectId',v_session.domain_object_id,
    'quoteSnapshotId',v_session.quote_snapshot_id,
    'createdAt',v_session.created_at,
    'materializedAt',v_session.materialized_at,
    'nextActions',case
      when v_session.session_state='draft' and not (v_session.current_payload ? 'selectionEvaluation') then jsonb_build_array('evaluate_selection')
      when v_session.session_state='draft' and coalesce((v_session.current_payload->'selectionEvaluation'->>'submissionAllowed')::boolean,false) then jsonb_build_array('submit_request')
      when v_session.session_state='draft' then jsonb_build_array('revise_selection')
      when v_session.session_state='materialized' then jsonb_build_array('await_commitment_requirements')
      else '[]'::jsonb end
  );
end;
$function$;

create or replace function atlas.begin_public_commitment_session_v1(
  p_surface_key text,
  p_name text,
  p_email text,
  p_phone text default null,
  p_literal_request text default null,
  p_idempotency_key text default null,
  p_client_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_identity jsonb;
  v_entity_id uuid;
  v_resolution text;
  v_token text;
  v_hash text;
  v_session_id uuid;
  v_existing atlas.public_commitment_sessions%rowtype;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_literal text:=nullif(btrim(coalesce(p_literal_request,'')),'');
begin
  select * into v_surface from atlas.public_commitment_surfaces s
  where s.surface_key=btrim(p_surface_key) and s.surface_state='active';
  if v_surface.id is null then raise exception 'Public commitment surface not found or not active.' using errcode='P0002'; end if;

  if v_idem is not null then
    select * into v_existing from atlas.public_commitment_sessions s where s.surface_id=v_surface.id and s.idempotency_key=v_idem;
    if v_existing.id is not null then
      if p_client_token is null or encode(extensions.digest(p_client_token,'sha256'),'hex')<>v_existing.public_token_sha256 then
        raise exception 'Existing public request requires its original client token.' using errcode='42501';
      end if;
      return jsonb_build_object('accessToken',p_client_token,'session',atlas.public_commitment_session_v1(p_client_token),'idempotentReplay',true);
    end if;
  end if;

  v_identity:=atlas.resolve_public_commitment_person_v1(p_name,p_email,p_phone,v_surface.surface_key);
  v_entity_id:=case when v_identity->>'entityId' is null then null else (v_identity->>'entityId')::uuid end;
  v_resolution:=v_identity->>'resolutionState';

  v_token:=coalesce(nullif(p_client_token,''),encode(extensions.gen_random_bytes(32),'hex'));
  if length(v_token)<32 then raise exception 'Client token must contain at least 32 characters.' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');

  insert into atlas.public_commitment_sessions(
    surface_id,public_token_sha256,requester_entity_id,identity_resolution_state,identity_snapshot,
    literal_request,session_state,current_payload,idempotency_key,metadata,provenance
  ) values(
    v_surface.id,v_hash,v_entity_id,v_resolution,
    jsonb_build_object('name',btrim(p_name),'email',lower(btrim(p_email)),'phone',nullif(btrim(coalesce(p_phone,'')),'')),
    v_literal,'draft','{}'::jsonb,v_idem,
    jsonb_build_object('channel','public_web'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key)
  ) returning id into v_session_id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session_id,'session.started',
    jsonb_build_object('identityResolutionState',v_resolution,'literalRequest',v_literal),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),
    case when v_idem is null then null else v_idem||':started' end
  );

  return jsonb_build_object('accessToken',v_token,'session',atlas.public_commitment_session_v1(v_token),'idempotentReplay',false);
end;
$function$;

revoke all on function atlas.resolve_public_commitment_person_v1(text,text,text,text) from public;
revoke all on function atlas.public_commitment_surface_v1(text) from public;
revoke all on function atlas.public_commitment_session_v1(text) from public;
revoke all on function atlas.begin_public_commitment_session_v1(text,text,text,text,text,text,text) from public;
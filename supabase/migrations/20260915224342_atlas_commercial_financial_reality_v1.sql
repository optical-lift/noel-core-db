begin;

-- Atlas Commercial Financial Reality v1.
-- Generated migration identity: Supabase CLI v2.116.0.
--
-- Governing rule:
--   domain commercial truth -> universal commercial order/payment evidence
--   -> derived financial position.
--
-- This tranche deliberately does NOT introduce a parallel money-obligation,
-- receipt, or allocation graph. A future obligation layer remains available
-- if real business cases prove that committed order value and collectible
-- obligation must diverge.

-- ---------------------------------------------------------------------------
-- Source custody
-- ---------------------------------------------------------------------------

create or replace function atlas.commercial_order_effective_custody_v1(
  p_commercial_order_id uuid
)
returns table(
  effective_organization_id uuid,
  effective_ledger_id uuid,
  source_domain text,
  source_kind text,
  source_id text,
  disposition text,
  evidence_basis text,
  from_adjudication boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_order atlas.commercial_orders%rowtype;
  v_flower_sale_id uuid;
  v_registration_id uuid;
  v_farm atlas.farms%rowtype;
  v_physical_ledger_id uuid;
  v_custody record;
begin
  select * into v_order
  from atlas.commercial_orders o
  where o.id = p_commercial_order_id;

  if v_order.id is null then
    return;
  end if;

  select x.flower_sale_order_id, x.farm_id
  into v_flower_sale_id, v_farm.id
  from atlas.flower_commercial_order_extensions x
  where x.commercial_order_id = v_order.id
  limit 1;

  if v_flower_sale_id is not null then
    select * into v_farm from atlas.farms f where f.id = v_farm.id;
    v_physical_ledger_id := atlas.primary_ledger_for_organization_v1(v_farm.organization_id);
    select * into v_custody
    from atlas.effective_institutional_custody_v1(
      'atlas','farms',v_farm.id::text,v_farm.organization_id,v_physical_ledger_id
    );

    return query select
      v_custody.effective_organization_id,
      v_custody.effective_ledger_id,
      'flower'::text,
      'flower_sale_order'::text,
      v_flower_sale_id::text,
      v_custody.disposition,
      v_custody.evidence_basis,
      v_custody.from_adjudication;
    return;
  end if;

  select x.registration_id
  into v_registration_id
  from atlas.community_registration_commercial_order_extensions x
  where x.commercial_order_id = v_order.id
  limit 1;

  if v_registration_id is not null then
    select f.* into v_farm
    from atlas.community_registrations r
    join atlas.community_registration_offerings ro on ro.id = r.offering_id
    join atlas.farms f on f.id = ro.farm_id
    where r.id = v_registration_id;

    v_physical_ledger_id := atlas.primary_ledger_for_organization_v1(v_farm.organization_id);
    select * into v_custody
    from atlas.effective_institutional_custody_v1(
      'atlas','farms',v_farm.id::text,v_farm.organization_id,v_physical_ledger_id
    );

    return query select
      v_custody.effective_organization_id,
      v_custody.effective_ledger_id,
      'community_registration'::text,
      'registration'::text,
      v_registration_id::text,
      v_custody.disposition,
      v_custody.evidence_basis,
      v_custody.from_adjudication;
    return;
  end if;

  v_physical_ledger_id := atlas.primary_ledger_for_organization_v1(v_order.organization_id);
  select * into v_custody
  from atlas.effective_institutional_custody_v1(
    'atlas','organizations',v_order.organization_id::text,
    v_order.organization_id,v_physical_ledger_id
  );

  return query select
    v_custody.effective_organization_id,
    v_custody.effective_ledger_id,
    coalesce(nullif(v_order.metadata->>'sourceDomain',''),'commercial')::text,
    'commercial_order'::text,
    v_order.id::text,
    v_custody.disposition,
    v_custody.evidence_basis,
    v_custody.from_adjudication;
end;
$function$;

revoke all on function atlas.commercial_order_effective_custody_v1(uuid)
  from public, anon, authenticated;
grant execute on function atlas.commercial_order_effective_custody_v1(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Flower -> universal commerce synchronization
-- ---------------------------------------------------------------------------

create or replace function atlas.ensure_flower_sale_commercial_order_v1(
  p_flower_sale_order_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_sale atlas.flower_sale_orders%rowtype;
  v_farm atlas.farms%rowtype;
  v_existing uuid;
  v_order_id uuid;
  v_effective_org uuid;
  v_effective_ledger uuid;
  v_disposition text;
  v_evidence_basis text;
  v_unit_id uuid;
  v_customer_relationship_id uuid;
  v_customer_subject_id uuid;
begin
  select x.commercial_order_id into v_existing
  from atlas.flower_commercial_order_extensions x
  where x.flower_sale_order_id = p_flower_sale_order_id;
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_sale
  from atlas.flower_sale_orders s
  where s.id = p_flower_sale_order_id;
  if v_sale.id is null then
    raise exception 'Flower Sale not found.' using errcode='P0002';
  end if;

  select * into v_farm from atlas.farms f where f.id = v_sale.farm_id;
  if v_farm.id is null then
    raise exception 'Flower Sale farm not found.' using errcode='P0002';
  end if;

  select c.effective_organization_id,c.effective_ledger_id,c.disposition,c.evidence_basis
  into v_effective_org,v_effective_ledger,v_disposition,v_evidence_basis
  from atlas.effective_institutional_custody_v1(
    'atlas','farms',v_farm.id::text,v_farm.organization_id,
    atlas.primary_ledger_for_organization_v1(v_farm.organization_id)
  ) c;

  -- Archived/test/unresolved source reality may remain valid domain evidence but
  -- may not manufacture canonical Financial Reality.
  if v_effective_org is null or v_effective_ledger is null or v_disposition = 'archived' then
    return null;
  end if;

  select ou.id into v_unit_id
  from atlas.organization_units ou
  where ou.id = v_farm.organization_unit_id
    and ou.organization_id = v_effective_org
    and ou.status = 'active'
  limit 1;

  if v_sale.buyer_relationship_id is not null then
    select m.external_relationship_id,m.identity_subject_id
    into v_customer_relationship_id,v_customer_subject_id
    from atlas.legacy_buyer_relationship_external_mappings m
    join atlas.external_relationships er on er.id = m.external_relationship_id
    join atlas.identity_subjects ids on ids.id = m.identity_subject_id
    where m.buyer_relationship_id = v_sale.buyer_relationship_id
      and er.organization_id = v_effective_org
      and ids.organization_id = v_effective_org
    limit 1;
  end if;

  insert into atlas.commercial_orders(
    organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,
    order_kind,order_date,channel,subtotal_amount,tax_amount,tip_amount,total_amount,
    currency,idempotency_key,note,metadata,created_at
  ) values (
    v_effective_org,v_unit_id,v_customer_relationship_id,v_customer_subject_id,
    'sale',v_sale.sale_date,v_sale.sales_channel,v_sale.subtotal_amount,v_sale.tax_amount,
    v_sale.tip_amount,v_sale.total_amount,upper(v_sale.currency),
    'flower_sale:'||v_sale.id::text,v_sale.note,
    jsonb_strip_nulls(jsonb_build_object(
      'sourceDomain','flower',
      'sourceKind','flower_sale_order',
      'sourceId',v_sale.id,
      'farmId',v_farm.id,
      'physicalOrganizationId',v_farm.organization_id,
      'physicalOrganizationUnitId',v_farm.organization_unit_id,
      'effectiveLedgerId',v_effective_ledger,
      'custodyDisposition',v_disposition,
      'custodyEvidenceBasis',v_evidence_basis,
      'customerLabel',v_sale.customer_label,
      'legacyBuyerRelationshipId',v_sale.buyer_relationship_id,
      'financialRealityCoverage','governed_from_order_birth',
      'legacyMetadata',v_sale.metadata
    )),
    v_sale.created_at
  ) returning id into v_order_id;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_order_id,'recorded',v_sale.created_at,'flower_sale_recorded:'||v_sale.id::text,
    jsonb_build_object('sourceDomain','flower','sourceId',v_sale.id)
  );

  insert into atlas.flower_commercial_order_extensions(
    flower_sale_order_id,commercial_order_id,farm_id,metadata
  ) values (
    v_sale.id,v_order_id,v_farm.id,
    jsonb_build_object('source','atlas_commercial_financial_reality_v1','effectiveLedgerId',v_effective_ledger)
  );

  return v_order_id;
end;
$function$;

create or replace function atlas.sync_flower_sale_commercial_order_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  perform atlas.ensure_flower_sale_commercial_order_v1(new.id);
  return new;
end;
$function$;

create or replace function atlas.sync_flower_sale_commercial_line_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_order_id uuid;
  v_existing uuid;
  v_commercial_line_id uuid;
begin
  select x.commercial_order_line_id into v_existing
  from atlas.flower_commercial_order_line_extensions x
  where x.flower_sale_order_line_id = new.id;
  if v_existing is not null then
    return new;
  end if;

  v_order_id := atlas.ensure_flower_sale_commercial_order_v1(new.sale_order_id);
  if v_order_id is null then
    return new;
  end if;

  insert into atlas.commercial_order_lines(
    commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,
    metadata,created_at
  ) values (
    v_order_id,null,coalesce(nullif(new.inventory_kind,''),'Flower item'),new.quantity,
    new.unit,new.unit_price,coalesce(new.line_total,round(new.quantity*new.unit_price,2)),
    jsonb_build_object(
      'sourceDomain','flower',
      'sourceKind','flower_sale_order_line',
      'sourceId',new.id,
      'readyLotId',new.ready_lot_id,
      'legacyMetadata',new.metadata
    ),new.created_at
  ) returning id into v_commercial_line_id;

  insert into atlas.flower_commercial_order_line_extensions(
    flower_sale_order_line_id,commercial_order_line_id,farm_id,ready_lot_id,metadata
  ) values (
    new.id,v_commercial_line_id,new.farm_id,new.ready_lot_id,
    jsonb_build_object('source','atlas_commercial_financial_reality_v1')
  );

  return new;
end;
$function$;

create or replace function atlas.sync_flower_sale_commercial_cancel_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_order_id uuid;
begin
  v_order_id := atlas.ensure_flower_sale_commercial_order_v1(new.sale_order_id);
  if v_order_id is null then
    return new;
  end if;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,reason_kind,note,idempotency_key,metadata
  ) values (
    v_order_id,'cancelled',new.created_at,new.reason_kind,new.note,
    'flower_sale_cancel:'||new.id::text,
    jsonb_build_object('sourceDomain','flower','sourceEventId',new.id,'legacyMetadata',new.metadata)
  ) on conflict (commercial_order_id,idempotency_key)
    where idempotency_key is not null do nothing;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Community Registration -> universal commerce synchronization
-- ---------------------------------------------------------------------------

create or replace function atlas.ensure_registration_commercial_order_v1(
  p_registration_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_registration atlas.community_registrations%rowtype;
  v_offering atlas.community_registration_offerings%rowtype;
  v_farm atlas.farms%rowtype;
  v_existing uuid;
  v_order_id uuid;
  v_line_id uuid;
  v_effective_org uuid;
  v_effective_ledger uuid;
  v_disposition text;
  v_evidence_basis text;
  v_unit_id uuid;
  v_commercial_offering_id uuid;
begin
  select x.commercial_order_id into v_existing
  from atlas.community_registration_commercial_order_extensions x
  where x.registration_id = p_registration_id;
  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_registration
  from atlas.community_registrations r
  where r.id = p_registration_id;
  if v_registration.id is null then
    raise exception 'Community Registration not found.' using errcode='P0002';
  end if;

  select * into v_offering
  from atlas.community_registration_offerings o
  where o.id = v_registration.offering_id;
  select * into v_farm from atlas.farms f where f.id = v_offering.farm_id;

  select c.effective_organization_id,c.effective_ledger_id,c.disposition,c.evidence_basis
  into v_effective_org,v_effective_ledger,v_disposition,v_evidence_basis
  from atlas.effective_institutional_custody_v1(
    'atlas','farms',v_farm.id::text,v_farm.organization_id,
    atlas.primary_ledger_for_organization_v1(v_farm.organization_id)
  ) c;

  if v_effective_org is null or v_effective_ledger is null or v_disposition = 'archived' then
    return null;
  end if;

  select ou.id into v_unit_id
  from atlas.organization_units ou
  where ou.id = v_farm.organization_unit_id
    and ou.organization_id = v_effective_org
    and ou.status = 'active'
  limit 1;

  select x.commercial_offering_id into v_commercial_offering_id
  from atlas.community_registration_commercial_offering_extensions x
  join atlas.commercial_offerings co on co.id = x.commercial_offering_id
  where x.registration_offering_id = v_offering.id
    and co.organization_id = v_effective_org
  limit 1;

  insert into atlas.commercial_orders(
    organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,
    order_kind,order_date,channel,subtotal_amount,tax_amount,tip_amount,total_amount,
    currency,idempotency_key,note,metadata,created_at
  ) values (
    v_effective_org,v_unit_id,null,null,'registration',
    coalesce(v_registration.submitted_at::date,v_registration.created_at::date),
    'registration',v_offering.fee_amount,0,0,v_offering.fee_amount,
    upper(v_offering.fee_currency),'community_registration:'||v_registration.id::text,null,
    jsonb_build_object(
      'sourceDomain','community_registration',
      'sourceKind','registration',
      'sourceId',v_registration.id,
      'registrationNumber',v_registration.registration_number,
      'farmId',v_farm.id,
      'physicalOrganizationId',v_farm.organization_id,
      'effectiveLedgerId',v_effective_ledger,
      'custodyDisposition',v_disposition,
      'custodyEvidenceBasis',v_evidence_basis,
      'financialRealityCoverage','governed_from_order_birth'
    ),v_registration.created_at
  ) returning id into v_order_id;

  insert into atlas.commercial_order_lines(
    commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,
    metadata,created_at
  ) values (
    v_order_id,v_commercial_offering_id,v_offering.title,1,v_offering.fee_basis,
    v_offering.fee_amount,v_offering.fee_amount,
    jsonb_build_object('sourceDomain','community_registration','sourceId',v_registration.id),
    v_registration.created_at
  ) returning id into v_line_id;

  insert into atlas.commercial_order_events(
    commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
  ) values (
    v_order_id,'recorded',coalesce(v_registration.submitted_at,v_registration.created_at),
    'community_registration_recorded:'||v_registration.id::text,
    jsonb_build_object('sourceDomain','community_registration','sourceId',v_registration.id)
  );

  if v_registration.status = 'cancelled' then
    insert into atlas.commercial_order_events(
      commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
    ) values (
      v_order_id,'cancelled',coalesce(v_registration.cancelled_at,v_registration.updated_at),
      'community_registration_cancelled:'||v_registration.id::text,
      jsonb_build_object('sourceDomain','community_registration','sourceId',v_registration.id)
    );
  elsif v_registration.status = 'refunded' then
    insert into atlas.commercial_order_events(
      commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
    ) values (
      v_order_id,'refunded',v_registration.updated_at,
      'community_registration_refunded:'||v_registration.id::text,
      jsonb_build_object('sourceDomain','community_registration','sourceId',v_registration.id)
    );
  end if;

  insert into atlas.community_registration_commercial_order_extensions(
    registration_id,commercial_order_id
  ) values (v_registration.id,v_order_id);

  return v_order_id;
end;
$function$;

create or replace function atlas.sync_registration_commercial_order_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_order_id uuid;
begin
  v_order_id := atlas.ensure_registration_commercial_order_v1(new.id);
  if v_order_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'cancelled' then
      insert into atlas.commercial_order_events(
        commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
      ) values (
        v_order_id,'cancelled',coalesce(new.cancelled_at,new.updated_at),
        'community_registration_cancelled:'||new.id::text,
        jsonb_build_object('sourceDomain','community_registration','sourceId',new.id)
      ) on conflict (commercial_order_id,idempotency_key)
        where idempotency_key is not null do nothing;
    elsif new.status = 'refunded' then
      insert into atlas.commercial_order_events(
        commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
      ) values (
        v_order_id,'refunded',new.updated_at,
        'community_registration_refunded:'||new.id::text,
        jsonb_build_object('sourceDomain','community_registration','sourceId',new.id)
      ) on conflict (commercial_order_id,idempotency_key)
        where idempotency_key is not null do nothing;
    end if;
  end if;

  return new;
end;
$function$;

create or replace function atlas.ensure_registration_commercial_payment_v1(
  p_registration_payment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_payment atlas.community_registration_payments%rowtype;
  v_order_id uuid;
  v_order atlas.commercial_orders%rowtype;
  v_commercial_payment_id uuid;
  v_event_exists boolean;
  v_provider_key text;
  v_provider_payment_key text;
  v_observed_state text;
begin
  select * into v_payment
  from atlas.community_registration_payments p
  where p.id = p_registration_payment_id;
  if v_payment.id is null then
    raise exception 'Community Registration payment not found.' using errcode='P0002';
  end if;

  v_order_id := atlas.ensure_registration_commercial_order_v1(v_payment.registration_id);
  if v_order_id is null then
    return null;
  end if;

  select * into v_order from atlas.commercial_orders o where o.id = v_order_id;

  select x.commercial_payment_id into v_commercial_payment_id
  from atlas.community_registration_commercial_payment_extensions x
  where x.registration_payment_id = v_payment.id;

  if v_commercial_payment_id is null then
    v_provider_key := lower(nullif(btrim(coalesce(v_payment.payment_processor,'')),''));
    v_provider_payment_key := nullif(btrim(coalesce(v_payment.external_payment_id,'')),'');
    v_observed_state := case v_payment.status
      when 'paid' then 'succeeded'
      else v_payment.status
    end;

    insert into atlas.commercial_payments(
      organization_id,organization_unit_id,commercial_order_id,payer_relationship_id,
      payer_subject_id,provider_key,provider_payment_key,amount,currency,observed_state,
      paid_at,metadata,created_at
    ) values (
      v_order.organization_id,v_order.organization_unit_id,v_order.id,null,null,
      v_provider_key,v_provider_payment_key,v_payment.amount,upper(v_payment.currency),
      v_observed_state,v_payment.paid_at,
      jsonb_build_object(
        'sourceDomain','community_registration',
        'sourceKind','registration_payment',
        'sourceId',v_payment.id,
        'registrationId',v_payment.registration_id,
        'legacyMetadata',v_payment.metadata
      ),v_payment.created_at
    ) returning id into v_commercial_payment_id;

    insert into atlas.community_registration_commercial_payment_extensions(
      registration_payment_id,commercial_payment_id
    ) values (v_payment.id,v_commercial_payment_id);
  end if;

  if v_payment.status in ('paid','refunded','partially_refunded') and v_payment.paid_at is not null then
    select exists(
      select 1 from atlas.commercial_payment_events e
      where e.commercial_payment_id = v_commercial_payment_id
        and e.event_kind = 'succeeded'
        and e.amount_delta = v_payment.amount
    ) into v_event_exists;
    if not v_event_exists then
      insert into atlas.commercial_payment_events(
        commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
      ) values (
        v_commercial_payment_id,'succeeded',v_payment.amount,upper(v_payment.currency),
        v_payment.paid_at,'community_registration_paid:'||v_payment.id::text,
        jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id)
      );
    end if;
  elsif v_payment.status in ('paid','refunded','partially_refunded') and v_payment.paid_at is null then
    insert into atlas.commercial_payment_events(
      commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
    ) values (
      v_commercial_payment_id,'payment_status_unresolved',0,upper(v_payment.currency),
      v_payment.updated_at,'community_registration_payment_unresolved:'||v_payment.id::text,
      jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id,'status',v_payment.status)
    ) on conflict (commercial_payment_id,provider_event_key)
      where provider_event_key is not null do nothing;
  end if;

  if v_payment.status = 'refunded' then
    if v_payment.refunded_at is not null then
      select exists(
        select 1 from atlas.commercial_payment_events e
        where e.commercial_payment_id = v_commercial_payment_id
          and e.event_kind in ('refund','chargeback','adjustment')
          and e.amount_delta = -v_payment.amount
      ) into v_event_exists;
      if not v_event_exists then
        insert into atlas.commercial_payment_events(
          commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
        ) values (
          v_commercial_payment_id,'refund',-v_payment.amount,upper(v_payment.currency),
          v_payment.refunded_at,'community_registration_refund:'||v_payment.id::text,
          jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id,'fullRefundInferredFromStatus',true)
        );
      end if;
    else
      insert into atlas.commercial_payment_events(
        commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
      ) values (
        v_commercial_payment_id,'refund_status_unresolved',0,upper(v_payment.currency),
        v_payment.updated_at,'community_registration_refund_unresolved:'||v_payment.id::text,
        jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id)
      ) on conflict (commercial_payment_id,provider_event_key)
        where provider_event_key is not null do nothing;
    end if;
  elsif v_payment.status = 'partially_refunded' then
    insert into atlas.commercial_payment_events(
      commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
    ) values (
      v_commercial_payment_id,'partial_refund_unresolved',0,upper(v_payment.currency),
      coalesce(v_payment.refunded_at,v_payment.updated_at),
      'community_registration_partial_refund_unresolved:'||v_payment.id::text,
      jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id,'reason','legacy_source_has_no_partial_refund_amount')
    ) on conflict (commercial_payment_id,provider_event_key)
      where provider_event_key is not null do nothing;
  elsif v_payment.status = 'failed' then
    insert into atlas.commercial_payment_events(
      commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata
    ) values (
      v_commercial_payment_id,'failed',0,upper(v_payment.currency),v_payment.updated_at,
      'community_registration_failed:'||v_payment.id::text,
      jsonb_build_object('sourceDomain','community_registration','sourceId',v_payment.id)
    ) on conflict (commercial_payment_id,provider_event_key)
      where provider_event_key is not null do nothing;
  end if;

  return v_commercial_payment_id;
end;
$function$;

create or replace function atlas.sync_registration_commercial_payment_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  perform atlas.ensure_registration_commercial_payment_v1(new.id);
  return new;
end;
$function$;

-- Trigger functions are private consequence machinery, not application APIs.
revoke all on function atlas.ensure_flower_sale_commercial_order_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.sync_flower_sale_commercial_order_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.sync_flower_sale_commercial_line_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.sync_flower_sale_commercial_cancel_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.ensure_registration_commercial_order_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.sync_registration_commercial_order_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.ensure_registration_commercial_payment_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.sync_registration_commercial_payment_trigger_v1() from public,anon,authenticated,service_role;

create trigger p20_flower_sale_universal_commerce_sync_v1
after insert on atlas.flower_sale_orders
for each row execute function atlas.sync_flower_sale_commercial_order_trigger_v1();

create trigger p20_flower_sale_line_universal_commerce_sync_v1
after insert on atlas.flower_sale_order_lines
for each row execute function atlas.sync_flower_sale_commercial_line_trigger_v1();

create trigger p20_flower_sale_cancel_universal_commerce_sync_v1
after insert on atlas.flower_sale_order_cancellation_events
for each row execute function atlas.sync_flower_sale_commercial_cancel_trigger_v1();

create trigger p20_registration_universal_commerce_sync_v1
after insert or update of status,cancelled_at on atlas.community_registrations
for each row execute function atlas.sync_registration_commercial_order_trigger_v1();

create trigger p20_registration_payment_universal_commerce_sync_v1
after insert or update of status,payment_processor,external_payment_id,paid_at,refunded_at
on atlas.community_registration_payments
for each row execute function atlas.sync_registration_commercial_payment_trigger_v1();

-- ---------------------------------------------------------------------------
-- Backfill only missing universal links. Existing universal rows are immutable
-- and remain historical evidence exactly as recorded.
-- ---------------------------------------------------------------------------

do $backfill_flower_orders$
declare r record;
begin
  for r in
    select s.id
    from atlas.flower_sale_orders s
    left join atlas.flower_commercial_order_extensions x on x.flower_sale_order_id = s.id
    where x.flower_sale_order_id is null
    order by s.created_at,s.id
  loop
    perform atlas.ensure_flower_sale_commercial_order_v1(r.id);
  end loop;
end;
$backfill_flower_orders$;

do $backfill_flower_lines$
declare r record;
begin
  for r in
    select l.*
    from atlas.flower_sale_order_lines l
    left join atlas.flower_commercial_order_line_extensions x on x.flower_sale_order_line_id = l.id
    where x.flower_sale_order_line_id is null
    order by l.created_at,l.id
  loop
    perform atlas.sync_flower_sale_commercial_line_trigger_v1();
  end loop;
end;
$backfill_flower_lines$;

-- The trigger function above depends on NEW and therefore cannot be invoked by
-- the backfill DO block. Backfill lines explicitly with the same invariant.
do $backfill_flower_lines_explicit$
declare
  r record;
  v_order_id uuid;
  v_commercial_line_id uuid;
begin
  for r in
    select l.*
    from atlas.flower_sale_order_lines l
    left join atlas.flower_commercial_order_line_extensions x on x.flower_sale_order_line_id = l.id
    where x.flower_sale_order_line_id is null
    order by l.created_at,l.id
  loop
    v_order_id := atlas.ensure_flower_sale_commercial_order_v1(r.sale_order_id);
    if v_order_id is null then
      continue;
    end if;
    insert into atlas.commercial_order_lines(
      commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,metadata,created_at
    ) values (
      v_order_id,null,coalesce(nullif(r.inventory_kind,''),'Flower item'),r.quantity,r.unit,r.unit_price,
      coalesce(r.line_total,round(r.quantity*r.unit_price,2)),
      jsonb_build_object('sourceDomain','flower','sourceKind','flower_sale_order_line','sourceId',r.id,'readyLotId',r.ready_lot_id,'legacyMetadata',r.metadata),
      r.created_at
    ) returning id into v_commercial_line_id;
    insert into atlas.flower_commercial_order_line_extensions(
      flower_sale_order_line_id,commercial_order_line_id,farm_id,ready_lot_id,metadata
    ) values (
      r.id,v_commercial_line_id,r.farm_id,r.ready_lot_id,
      jsonb_build_object('source','atlas_commercial_financial_reality_v1')
    );
  end loop;
end;
$backfill_flower_lines_explicit$;

do $backfill_flower_cancellations$
declare
  r record;
  v_order_id uuid;
begin
  for r in select * from atlas.flower_sale_order_cancellation_events order by created_at,id loop
    select x.commercial_order_id into v_order_id
    from atlas.flower_commercial_order_extensions x
    where x.flower_sale_order_id = r.sale_order_id;
    if v_order_id is null then
      continue;
    end if;
    insert into atlas.commercial_order_events(
      commercial_order_id,event_kind,occurred_at,reason_kind,note,idempotency_key,metadata
    ) values (
      v_order_id,'cancelled',r.created_at,r.reason_kind,r.note,'flower_sale_cancel:'||r.id::text,
      jsonb_build_object('sourceDomain','flower','sourceEventId',r.id,'legacyMetadata',r.metadata)
    ) on conflict (commercial_order_id,idempotency_key)
      where idempotency_key is not null do nothing;
  end loop;
end;
$backfill_flower_cancellations$;

do $backfill_registrations$
declare r record;
begin
  for r in
    select cr.id
    from atlas.community_registrations cr
    left join atlas.community_registration_commercial_order_extensions x on x.registration_id = cr.id
    where x.registration_id is null
    order by cr.created_at,cr.id
  loop
    perform atlas.ensure_registration_commercial_order_v1(r.id);
  end loop;

  for r in
    select p.id
    from atlas.community_registration_payments p
    order by p.created_at,p.id
  loop
    perform atlas.ensure_registration_commercial_payment_v1(r.id);
  end loop;
end;
$backfill_registrations$;

-- ---------------------------------------------------------------------------
-- Derived Financial Reality
-- ---------------------------------------------------------------------------

create or replace view atlas.commercial_financial_position_v1
with (security_invoker = true)
as
with payment_evidence as (
  select
    p.commercial_order_id,
    count(distinct p.id)::integer as payment_count,
    coalesce(sum(case when e.event_kind = 'succeeded' and e.amount_delta > 0 then e.amount_delta else 0 end),0)::numeric(14,2) as gross_collected_amount,
    coalesce(abs(sum(case when e.event_kind in ('refund','chargeback','adjustment') and e.amount_delta < 0 then e.amount_delta else 0 end)),0)::numeric(14,2) as returned_amount,
    coalesce(sum(case
      when e.event_kind = 'succeeded' then e.amount_delta
      when e.event_kind in ('refund','chargeback','adjustment') then e.amount_delta
      else 0 end),0)::numeric(14,2) as net_collected_amount,
    coalesce(bool_or(e.event_kind in ('partial_refund_unresolved','refund_status_unresolved','payment_status_unresolved')),false) as has_unresolved_payment_evidence,
    min(e.occurred_at) filter (where e.event_kind='succeeded' and e.amount_delta>0) as first_collection_at,
    max(e.occurred_at) filter (where e.event_kind='succeeded' and e.amount_delta>0) as last_collection_at
  from atlas.commercial_payments p
  left join atlas.commercial_payment_events e on e.commercial_payment_id = p.id
  where p.commercial_order_id is not null
  group by p.commercial_order_id
), order_effects as (
  select
    e.commercial_order_id,
    coalesce(bool_or(e.event_kind in ('cancelled','refunded')),false) as ended_or_refunded,
    max(e.occurred_at) filter (where e.event_kind in ('cancelled','refunded')) as ended_or_refunded_at
  from atlas.commercial_order_events e
  group by e.commercial_order_id
), base as (
  select
    o.*,
    c.effective_organization_id,
    c.effective_ledger_id,
    c.source_domain,
    c.source_kind,
    c.source_id,
    c.disposition as custody_disposition,
    c.evidence_basis as custody_evidence_basis,
    coalesce(pe.payment_count,0) as payment_count,
    coalesce(pe.gross_collected_amount,0)::numeric(14,2) as gross_collected_amount,
    coalesce(pe.returned_amount,0)::numeric(14,2) as returned_amount,
    coalesce(pe.net_collected_amount,0)::numeric(14,2) as net_collected_amount,
    coalesce(pe.has_unresolved_payment_evidence,false) as has_unresolved_payment_evidence,
    pe.first_collection_at,
    pe.last_collection_at,
    coalesce(oe.ended_or_refunded,false) as ended_or_refunded,
    oe.ended_or_refunded_at,
    (
      o.metadata->>'financialRealityCoverage' = 'governed_from_order_birth'
      or coalesce(pe.payment_count,0) > 0
    ) as financial_coverage
  from atlas.commercial_orders o
  cross join lateral atlas.commercial_order_effective_custody_v1(o.id) c
  left join payment_evidence pe on pe.commercial_order_id = o.id
  left join order_effects oe on oe.commercial_order_id = o.id
)
select
  b.id as commercial_order_id,
  b.effective_organization_id,
  b.effective_ledger_id,
  b.source_domain,
  b.source_kind,
  b.source_id,
  b.order_kind,
  b.order_date,
  b.channel,
  b.currency,
  b.total_amount::numeric(14,2) as committed_amount,
  b.gross_collected_amount,
  b.returned_amount,
  b.net_collected_amount,
  case
    when b.total_amount = 0 then 0::numeric(14,2)
    when not b.financial_coverage then null::numeric(14,2)
    when b.ended_or_refunded then 0::numeric(14,2)
    else greatest(b.total_amount-b.net_collected_amount,0)::numeric(14,2)
  end as open_amount,
  greatest(b.net_collected_amount-b.total_amount,0)::numeric(14,2) as overpaid_amount,
  b.payment_count,
  b.first_collection_at,
  b.last_collection_at,
  b.ended_or_refunded_at,
  b.financial_coverage,
  case
    when b.total_amount = 0 then 'not_required'
    when b.has_unresolved_payment_evidence or b.net_collected_amount < 0 then 'invariant_gap'
    when not b.financial_coverage then 'collection_unknown'
    when b.ended_or_refunded and b.net_collected_amount > 0 then 'refund_due'
    when b.ended_or_refunded then 'cancelled'
    when b.net_collected_amount = 0 then 'open'
    when b.net_collected_amount < b.total_amount then 'partially_paid'
    when b.net_collected_amount = b.total_amount then 'paid'
    else 'overpaid'
  end as financial_state,
  case
    when b.total_amount = 0 then 'zero_value_commercial_commitment'
    when b.metadata->>'financialRealityCoverage' = 'governed_from_order_birth' then 'governed_from_order_birth'
    when b.payment_count > 0 then 'payment_evidence_present'
    else 'historical_collection_unknown'
  end as financial_coverage_basis,
  b.custody_disposition,
  b.custody_evidence_basis,
  b.created_at
from base b;

revoke all on atlas.commercial_financial_position_v1 from public,anon,authenticated;
grant select on atlas.commercial_financial_position_v1 to service_role;

create or replace function atlas.commercial_financial_position_self_api_v1(
  p_ledger_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null or not atlas.principal_has_ledger_authority_v1(v_principal_id,p_ledger_id) then
    raise exception 'Ledger authority required.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'ledgerId',p_ledger_id,
    'orders',coalesce(jsonb_agg(jsonb_build_object(
      'commercialOrderId',p.commercial_order_id,
      'sourceDomain',p.source_domain,
      'sourceKind',p.source_kind,
      'sourceId',p.source_id,
      'orderKind',p.order_kind,
      'orderDate',p.order_date,
      'currency',p.currency,
      'committedAmount',p.committed_amount,
      'grossCollectedAmount',p.gross_collected_amount,
      'returnedAmount',p.returned_amount,
      'netCollectedAmount',p.net_collected_amount,
      'openAmount',p.open_amount,
      'overpaidAmount',p.overpaid_amount,
      'financialState',p.financial_state,
      'financialCoverage',p.financial_coverage,
      'financialCoverageBasis',p.financial_coverage_basis,
      'firstCollectionAt',p.first_collection_at,
      'lastCollectionAt',p.last_collection_at,
      'endedOrRefundedAt',p.ended_or_refunded_at,
      'custodyDisposition',p.custody_disposition,
      'custodyEvidenceBasis',p.custody_evidence_basis
    ) order by p.order_date desc,p.created_at desc,p.commercial_order_id),'[]'::jsonb)
  ) into v_result
  from atlas.commercial_financial_position_v1 p
  where p.effective_ledger_id = p_ledger_id;

  return v_result;
end;
$function$;

revoke all on function atlas.commercial_financial_position_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.commercial_financial_position_self_api_v1(uuid)
  to authenticated;

comment on view atlas.commercial_financial_position_v1 is
  'Derived Financial Reality over universal commercial order/payment evidence. Historical orders without governed financial coverage remain collection_unknown rather than being asserted as open receivables.';

comment on function atlas.commercial_financial_position_self_api_v1(uuid) is
  'Ledger-authorized Financial Reality read. Domain commercial truth and payment evidence remain distinct; this function derives current paid/open/unknown position without creating a parallel money-obligation clock.';

commit;

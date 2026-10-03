create or replace function ledger.guard_booking_policy_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare v_subject uuid;
begin
  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=new.ledger_id and l.ledger_state='active';
  if v_subject is null then raise exception 'Booking policy requires an active Ledger.' using errcode='23514'; end if;

  if new.resource_id is not null and not exists(
    select 1 from reality.resources r
    where r.id=new.resource_id and r.owner_entity_id=v_subject and r.resource_state<>'retired'
  ) then
    raise exception 'Booking policy resource must belong to the Ledger subject Entity.' using errcode='23514';
  end if;

  if new.policy_kind='duration' then
    if (new.config ? 'minMinutes' and (new.config->>'minMinutes')::numeric < 0)
       or (new.config ? 'maxMinutes' and (new.config->>'maxMinutes')::numeric <= 0)
       or (new.config ? 'minMinutes' and new.config ? 'maxMinutes' and (new.config->>'maxMinutes')::numeric < (new.config->>'minMinutes')::numeric) then
      raise exception 'Invalid duration policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='booking_window' then
    if (new.config ? 'minNoticeMinutes' and (new.config->>'minNoticeMinutes')::numeric < 0)
       or (new.config ? 'maxAdvanceMinutes' and (new.config->>'maxAdvanceMinutes')::numeric < 0) then
      raise exception 'Invalid booking-window policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='start_increment' then
    if not (new.config ? 'minutes') or (new.config->>'minutes')::integer <= 0 then
      raise exception 'Start-increment policy requires minutes > 0.' using errcode='22023';
    end if;
  elsif new.policy_kind='buffer' then
    if (new.config ? 'setupMinutes' and (new.config->>'setupMinutes')::numeric < 0)
       or (new.config ? 'teardownMinutes' and (new.config->>'teardownMinutes')::numeric < 0) then
      raise exception 'Invalid buffer policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='approval' then
    if new.config ? 'required' and jsonb_typeof(new.config->'required')<>'boolean' then
      raise exception 'Approval required must be boolean.' using errcode='22023';
    end if;
  elsif new.policy_kind='recurrence' then
    if new.config ? 'allowed' and jsonb_typeof(new.config->'allowed')<>'boolean' then
      raise exception 'Recurrence allowed must be boolean.' using errcode='22023';
    end if;
  elsif new.policy_kind='commitment' then
    if new.config ? 'agreementRequired' and jsonb_typeof(new.config->'agreementRequired')<>'boolean' then
      raise exception 'Commitment agreementRequired must be boolean.' using errcode='22023';
    end if;
    if new.config ? 'paymentRequiredBeforeConfirmation' and jsonb_typeof(new.config->'paymentRequiredBeforeConfirmation')<>'boolean' then
      raise exception 'Commitment paymentRequiredBeforeConfirmation must be boolean.' using errcode='22023';
    end if;
    if coalesce((new.config->>'paymentRequiredBeforeConfirmation')::boolean,false) then
      if not (new.config ? 'fullPaymentAtOrBelowAmount')
         or not (new.config ? 'fullPaymentPercentAtOrBelowThreshold')
         or not (new.config ? 'depositPercentAboveThreshold') then
        raise exception 'Payment-required commitment policy needs threshold, full-payment percent, and deposit percent.' using errcode='22023';
      end if;
      if (new.config->>'fullPaymentAtOrBelowAmount')::numeric < 0 then
        raise exception 'Commitment full-payment threshold must be >= 0.' using errcode='22023';
      end if;
      if (new.config->>'fullPaymentPercentAtOrBelowThreshold')::numeric <= 0 or (new.config->>'fullPaymentPercentAtOrBelowThreshold')::numeric > 100 then
        raise exception 'Commitment full-payment percent must be > 0 and <= 100.' using errcode='22023';
      end if;
      if (new.config->>'depositPercentAboveThreshold')::numeric <= 0 or (new.config->>'depositPercentAboveThreshold')::numeric > 100 then
        raise exception 'Commitment deposit percent must be > 0 and <= 100.' using errcode='22023';
      end if;
      if new.config ? 'currency' and (new.config->>'currency') !~ '^[A-Z]{3}$' then
        raise exception 'Commitment currency must be a three-letter code.' using errcode='22023';
      end if;
    end if;
  end if;
  return new;
end;
$function$;
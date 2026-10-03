revoke all on function ledger.create_booking_payment_schedule_service_v1(uuid,numeric,text,numeric,boolean,uuid,uuid,text,jsonb,jsonb) from public;
grant execute on function ledger.create_booking_payment_schedule_service_v1(uuid,numeric,text,numeric,boolean,uuid,uuid,text,jsonb,jsonb) to postgres, service_role;
revoke all on function ledger.create_booking_payment_schedule_from_policy_service_v1(uuid,numeric,text,uuid,uuid,text,jsonb,jsonb) from public;
grant execute on function ledger.create_booking_payment_schedule_from_policy_service_v1(uuid,numeric,text,uuid,uuid,text,jsonb,jsonb) to postgres, service_role;
revoke all on function atlas.create_ledger_booking_payment_schedule_self_api_v1(uuid,uuid,numeric,text,uuid,uuid,text,jsonb,jsonb) from public;
grant execute on function atlas.create_ledger_booking_payment_schedule_self_api_v1(uuid,uuid,numeric,text,uuid,uuid,text,jsonb,jsonb) to authenticated, postgres, service_role;
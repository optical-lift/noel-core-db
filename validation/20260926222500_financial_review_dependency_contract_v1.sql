-- Financial review dependency contract v1.
-- Read-only preflight for the production schema seams this branch extends.

begin;

do $fixture$
begin
  if to_regclass('atlas.connected_sources') is null
     or to_regclass('atlas.connected_source_observations') is null
     or to_regclass('atlas.evidence_records') is null
     or to_regclass('atlas.organization_spend_occurrences') is null
     or to_regclass('atlas.commercial_payment_events') is null
     or to_regclass('atlas.commercial_payments') is null
     or to_regclass('atlas.ledger_organization_participations') is null
     or to_regclass('reality.entities') is null
     or to_regclass('reality.auth_person_bindings') is null
     or to_regclass('reality.responsibility_relations') is null
     or to_regclass('compatibility.legacy_bindings') is null
     or to_regclass('ledger.ledgers') is null
     or to_regclass('ledger.seats') is null then
    raise exception 'Financial review dependency table is missing.';
  end if;

  if to_regprocedure('atlas.current_principal_id_v1()') is null
     or to_regprocedure('atlas.current_person_id_v1()') is null
     or to_regprocedure('atlas.current_active_ledger_seat_v1(uuid)') is null
     or to_regprocedure('atlas.current_organization_membership_v1(uuid)') is null
     or to_regprocedure('atlas.organization_spend_assert_custody_v1(uuid,uuid)') is null
     or to_regprocedure('atlas.record_organization_spend_core_v1(uuid,uuid,uuid,uuid,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('atlas.link_organization_spend_evidence_core_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,jsonb)') is null
     or to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') is null then
    raise exception 'Financial review dependency function is missing.';
  end if;

  if to_regclass('atlas.commercial_financial_position_v1') is null then
    raise exception 'Commercial financial position projection is missing.';
  end if;
end
$fixture$;

rollback;
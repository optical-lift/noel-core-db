BEGIN;

-- Self-contained behavioral proof for Atlas Expense Report Admission v1.
-- This validates the new reporting semantics without requiring candidate
-- production tables to exist. Everything is transaction-local and rolled back.

create temporary table proof_spend (
  spend_id uuid primary key default gen_random_uuid(),
  allocation_id uuid unique not null default gen_random_uuid(),
  occurred_on date not null,
  source_amount numeric not null,
  source_currency text not null,
  operational_purpose text,
  funding_kind text not null
);

create temporary table proof_categories (
  category_key text primary key,
  label text not null
);

create temporary table proof_rates (
  rate_id uuid primary key default gen_random_uuid(),
  source_currency text not null,
  report_currency text not null,
  quote_value numeric not null,
  quote_convention text not null,
  conversion_multiplier numeric not null
);

create temporary table proof_links (
  fact_link_id uuid primary key default gen_random_uuid(),
  allocation_id uuid not null unique,
  inclusion_state text not null default 'unresolved',
  claim_treatment text not null default 'unresolved',
  category_key text references proof_categories(category_key),
  classification_state text not null default 'unclassified',
  report_currency text not null default 'USD'
);

create temporary table proof_exceptions (
  fact_link_id uuid not null,
  exception_code text not null,
  severity text not null,
  unique(fact_link_id,exception_code)
);

create or replace function pg_temp.normalize_rate(q numeric, convention text)
returns numeric language sql immutable as $$
  select case
    when q is null or q<=0 then null
    when convention='source_units_per_one_reporting_unit' then 1/q
    when convention in ('reporting_units_per_one_source_unit','canonical_multiplier') then q
    else null
  end
$$;

insert into proof_categories(category_key,label) values
('facilities','Facilities'),
('program_activity','Program/Activity'),
('hospitality_lodging','Hospitality/Lodging');

insert into proof_spend(occurred_on,source_amount,source_currency,operational_purpose,funding_kind)
values
('2026-10-03',1840,'MXN','Lumber for Los Domos maintenance','organization_member'),
('2026-10-07',920,'MXN','Plumbing supplies for Los Domos','organization_member'),
('2026-10-12',1650,'MXN','Electrical parts for Los Domos','organization_member');

-- Suggested classification is not authoritative.
insert into proof_links(allocation_id,inclusion_state,claim_treatment,category_key,classification_state)
select allocation_id,'included','reimbursement','facilities','suggested'
from proof_spend where source_amount=1840;

insert into proof_exceptions(fact_link_id,exception_code,severity)
select fact_link_id,'expense_category_unresolved','blocking'
from proof_links where classification_state<>'confirmed';

DO $$
declare n int;
begin
  select count(*) into n from proof_exceptions where exception_code='expense_category_unresolved';
  if n<>1 then raise exception 'FAIL: suggested category must remain blocking'; end if;
end$$;

-- Human confirmation clears the category exception.
update proof_links set classification_state='confirmed'
where allocation_id=(select allocation_id from proof_spend where source_amount=1840);
delete from proof_exceptions e using proof_links l
where e.fact_link_id=l.fact_link_id and e.exception_code='expense_category_unresolved'
  and l.classification_state='confirmed';

DO $$
declare n int;
begin
  select count(*) into n from proof_exceptions where exception_code='expense_category_unresolved';
  if n<>0 then raise exception 'FAIL: confirmed category should clear blocking exception'; end if;
end$$;

-- Member-funded unresolved claim treatment blocks.
insert into proof_links(allocation_id,inclusion_state,claim_treatment,category_key,classification_state)
select allocation_id,'included','unresolved','facilities','confirmed'
from proof_spend where source_amount=920;

insert into proof_exceptions(fact_link_id,exception_code,severity)
select l.fact_link_id,'reimbursement_treatment_unresolved','blocking'
from proof_links l join proof_spend s using(allocation_id)
where s.funding_kind='organization_member' and l.claim_treatment='unresolved';

DO $$
declare n int;
begin
  select count(*) into n from proof_exceptions where exception_code='reimbursement_treatment_unresolved';
  if n<>1 then raise exception 'FAIL: member-funded unresolved treatment must block'; end if;
end$$;

-- Missing foreign-currency rate blocks.
insert into proof_links(allocation_id,inclusion_state,claim_treatment,category_key,classification_state)
select allocation_id,'included','reimbursement','facilities','confirmed'
from proof_spend where source_amount=1650;

insert into proof_exceptions(fact_link_id,exception_code,severity)
select l.fact_link_id,'exchange_rate_missing','blocking'
from proof_links l join proof_spend s using(allocation_id)
where s.source_currency<>l.report_currency
  and not exists(select 1 from proof_rates r where r.source_currency=s.source_currency and r.report_currency=l.report_currency);

DO $$
declare n int;
begin
  select count(*) into n from proof_exceptions where exception_code='exchange_rate_missing';
  if n<>3 then raise exception 'FAIL: each included MXN line without a rate must block'; end if;
end$$;

-- CI observed workbook quote: 16.5 MXN per 1 USD.
insert into proof_rates(source_currency,report_currency,quote_value,quote_convention,conversion_multiplier)
values('MXN','USD',16.5,'source_units_per_one_reporting_unit',pg_temp.normalize_rate(16.5,'source_units_per_one_reporting_unit'));

delete from proof_exceptions where exception_code='exchange_rate_missing';

DO $$
declare m numeric; converted numeric;
begin
  select conversion_multiplier into m from proof_rates where source_currency='MXN' and report_currency='USD';
  if abs(m-(1::numeric/16.5::numeric))>0.0000000001 then
    raise exception 'FAIL: rate normalization incorrect: %',m;
  end if;
  select s.source_amount*r.conversion_multiplier into converted
  from proof_spend s cross join proof_rates r where s.source_amount=1650;
  if abs(converted-100)>0.0000001 then
    raise exception 'FAIL: 1650 MXN at 16.5 MXN/USD must equal 100 USD, got %',converted;
  end if;
end$$;

-- Resolve second line's treatment and verify category subtotal from three distinct detail facts.
update proof_links set claim_treatment='reimbursement'
where allocation_id=(select allocation_id from proof_spend where source_amount=920);
delete from proof_exceptions e using proof_links l
where e.fact_link_id=l.fact_link_id and e.exception_code='reimbursement_treatment_unresolved'
  and l.claim_treatment<>'unresolved';

DO $$
declare detail_count int; subtotal numeric; expected numeric;
begin
  select count(*),sum(s.source_amount*r.conversion_multiplier)
  into detail_count,subtotal
  from proof_links l
  join proof_spend s using(allocation_id)
  join proof_rates r on r.source_currency=s.source_currency and r.report_currency=l.report_currency
  where l.inclusion_state='included' and l.classification_state='confirmed' and l.category_key='facilities';

  expected := (1840+920+1650)::numeric/16.5::numeric;
  if detail_count<>3 then raise exception 'FAIL: subtotal must retain three detail lines'; end if;
  if abs(subtotal-expected)>0.0000001 then raise exception 'FAIL: Facilities subtotal does not reconcile'; end if;
end$$;

-- Duplicate admission is structurally impossible in the proof contract.
DO $$
begin
  begin
    insert into proof_links(allocation_id,inclusion_state,claim_treatment,category_key,classification_state)
    select allocation_id,'included','reimbursement','facilities','confirmed'
    from proof_spend where source_amount=1840;
    raise exception 'FAIL: duplicate admission unexpectedly succeeded';
  exception when unique_violation then
    null;
  end;
end$$;

select jsonb_build_object(
  'proof','atlas_expense_report_admission_v1',
  'suggestionRemainedNonAuthoritative',true,
  'humanConfirmationClearedCategoryException',true,
  'memberFundedTreatmentExceptionVerified',true,
  'missingRateExceptionVerified',true,
  'quoteValue',16.5,
  'quoteConvention','source_units_per_one_reporting_unit',
  'canonicalMultiplier',(select conversion_multiplier from proof_rates limit 1),
  '1650MxnUsd',(select 1650*conversion_multiplier from proof_rates limit 1),
  'facilitiesDetailLines',(select count(*) from proof_links where category_key='facilities'),
  'duplicateAdmissionRejected',true,
  'status','passed'
) as validation_result;

ROLLBACK;

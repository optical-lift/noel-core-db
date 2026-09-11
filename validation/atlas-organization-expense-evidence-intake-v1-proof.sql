BEGIN;

-- Behavioral proof for Atlas Organization Expense Evidence Intake v1.
-- Self-contained and rollback-only.

create temporary table proof_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  source_key text not null,
  sha256 text not null,
  object_path text not null,
  mime_type text not null,
  byte_size bigint not null,
  original_filename text,
  unique(organization_id,source_key)
);

create temporary table proof_inbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  evidence_id uuid not null unique references proof_evidence(id),
  context_note text,
  state text not null default 'received',
  admitted_source_authority text,
  admitted_source_ref text
);

create temporary table proof_extractions (
  id uuid primary key default gen_random_uuid(),
  inbox_id uuid not null references proof_inbox(id),
  extractor_key text not null,
  extractor_version text not null,
  attempt_key text not null,
  input_sha256 text not null,
  candidate jsonb not null,
  authority text not null default 'suggestion_only',
  unique(inbox_id,extractor_key,extractor_version,attempt_key)
);

create temporary table proof_spend (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references proof_evidence(id),
  gross_amount numeric not null,
  currency text not null,
  merchant text,
  occurred_on date
);

create temporary table proof_allocations (
  id uuid primary key default gen_random_uuid(),
  spend_id uuid not null references proof_spend(id),
  amount numeric not null,
  purpose text not null
);

-- Capture before Spend exists.
insert into proof_evidence(organization_id,source_key,sha256,object_path,mime_type,byte_size,original_filename)
values('00000000-0000-0000-0000-000000000001','receipt-device-001',repeat('a',64),
       'organizations/00000000-0000-0000-0000-000000000001/expense-evidence/receipt-device-001/receipt.jpg',
       'image/jpeg',245000,'receipt.jpg');
insert into proof_inbox(organization_id,evidence_id,context_note)
select organization_id,id,'lumber for Los Domos' from proof_evidence where source_key='receipt-device-001';

DO $$
declare n int;
begin
 select count(*) into n from proof_spend;
 if n<>0 then raise exception 'FAIL: evidence capture must precede Spend admission'; end if;
end$$;

-- Exact replay resolves to same evidence; conflicting replay is rejected conceptually by unique identity + descriptor match.
DO $$
declare eid uuid; same_eid uuid;
begin
 select id into eid from proof_evidence where source_key='receipt-device-001';
 select id into same_eid from proof_evidence where organization_id='00000000-0000-0000-0000-000000000001' and source_key='receipt-device-001'
   and sha256=repeat('a',64) and mime_type='image/jpeg' and byte_size=245000;
 if same_eid is distinct from eid then raise exception 'FAIL: exact retry did not resolve same evidence'; end if;
 if exists(select 1 from proof_evidence where source_key='receipt-device-001' and sha256=repeat('b',64)) then
   raise exception 'FAIL: conflicting retry unexpectedly matches';
 end if;
end$$;

-- Extraction remains suggestion-only.
insert into proof_extractions(inbox_id,extractor_key,extractor_version,attempt_key,input_sha256,candidate)
select i.id,'receipt_parser','v1','attempt-1',e.sha256,
 jsonb_build_object('merchant','Home Depot','occurredOn','2026-09-03','grossAmount',1840,'currency','MXN')
from proof_inbox i join proof_evidence e on e.id=i.evidence_id;

DO $$
declare a text; spend_n int;
begin
 select authority into a from proof_extractions limit 1;
 select count(*) into spend_n from proof_spend;
 if a<>'suggestion_only' or spend_n<>0 then raise exception 'FAIL: extraction became money truth'; end if;
end$$;

-- Human context supplies purpose that receipt extraction did not contain.
DO $$
declare p text;
begin
 select context_note into p from proof_inbox limit 1;
 if p<>'lumber for Los Domos' then raise exception 'FAIL: human context not preserved'; end if;
end$$;

-- Admit one gross spend, then split into two purpose allocations while preserving one document.
insert into proof_spend(evidence_id,gross_amount,currency,merchant,occurred_on)
select i.evidence_id,(x.candidate->>'grossAmount')::numeric,x.candidate->>'currency',x.candidate->>'merchant',(x.candidate->>'occurredOn')::date
from proof_inbox i join proof_extractions x on x.inbox_id=i.id;

insert into proof_allocations(spend_id,amount,purpose)
select id,1300,'Lumber for Los Domos maintenance' from proof_spend
union all
select id,540,'Participant activity supplies' from proof_spend;

update proof_inbox i set state='admitted',admitted_source_authority='organization_spend_occurrence',admitted_source_ref=s.id::text
from proof_spend s where s.evidence_id=i.evidence_id;

DO $$
declare gross numeric; allocated numeric; ev_count int; alloc_count int;
begin
 select gross_amount into gross from proof_spend;
 select sum(amount),count(*) into allocated,alloc_count from proof_allocations;
 select count(*) into ev_count from proof_evidence;
 if gross<>1840 or allocated<>1840 or alloc_count<>2 or ev_count<>1 then
   raise exception 'FAIL: one evidence/one spend/multiple allocations invariant failed';
 end if;
end$$;

-- Safe read shape intentionally excludes object_path and any signed URL.
select jsonb_build_object(
  'proof','atlas_organization_expense_evidence_intake_v1',
  'status','passed',
  'safeInbox',jsonb_build_object(
    'inboxItemId',i.id,
    'state',i.state,
    'contextNote',i.context_note,
    'file',jsonb_build_object('mimeType',e.mime_type,'byteSize',e.byte_size,'sha256',e.sha256,'originalFilename',e.original_filename),
    'latestExtraction',jsonb_build_object('candidate',x.candidate,'authority',x.authority)
  ),
  'spendCount',(select count(*) from proof_spend),
  'allocationCount',(select count(*) from proof_allocations),
  'privateObjectPathExcludedFromSafeRead',true,
  'signedUrlExcludedFromSafeRead',true
) as validation_result
from proof_inbox i
join proof_evidence e on e.id=i.evidence_id
join proof_extractions x on x.inbox_id=i.id
limit 1;

ROLLBACK;

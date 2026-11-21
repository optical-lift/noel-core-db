import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const sql=readFileSync(new URL(
 "../candidates/atlas_uniops_governor_result_allocation_v1/candidate.sql",
 import.meta.url),"utf8");

test("new owner projection is an additive, exact-current-source guarded read",()=>{
 assert.match(sql,/302be9714957f5bf76d665092c9609b1/);
 assert.match(sql,/pg_get_functiondef\(p\.oid\)/);
 assert.match(sql,/company_work_native_ledger_owner_self_v1\(/);
 assert.match(sql,/p_scope='organization' OR w\.has_exact_ledger_evidence/);
 assert.match(sql,/p_after_work_item_id IS NULL OR wi\.id>p_after_work_item_id/);
 assert.match(sql,/reportedResultCount',reports\.total_count/);
 assert.match(sql,/reported_at DESC,r\.id DESC LIMIT 1/);
 assert.match(sql,/exactOrderWithinTimestampProven',lr\.timestamp_tie_count=1/);
 assert.match(sql,/acceptedResultIsDistinctFromReport',true/);
 assert.match(sql,/reportAllocation',CASE/);
 assert.match(sql,/sourceResultId',lr\.id/);
 assert.match(sql,/historicalNotCurrent',report_allocation\.state<>'active'/);
 assert.match(sql,/recordedReporterMatchesAllocation'/);
 assert.match(sql,/lr\.reported_by_user_id IS NOT NULL/);
 assert.match(sql,/lr\.result_contract_key='continuing_care_actual_v1'/);
 assert.match(sql,/authenticatedReporterPersonId'/);
 assert.match(sql,/report_allocation\.id=lr\.responsible_allocation_id/);
 assert.match(sql,/report_allocation\.organization_id=w\.organization_id/);
 assert.match(sql,/report_allocation\.work_item_id=w\.id/);
 assert.match(sql,/report_allocation\.allocation_role='responsible'/);
 assert.match(sql,/report_allocation\.state IN \('active','completed','released'\)/);
 assert.match(sql,/lr\.reported_at>=report_allocation\.allocated_at/);
 assert.match(sql,/assignee_canonical_person_id IS NOT NULL/);
 assert.doesNotMatch(sql,/\b(?:INSERT INTO|UPDATE atlas\.|DELETE FROM|TRUNCATE|DROP TABLE|GRANT EXECUTE|CREATE TABLE|CREATE POLICY|ALTER TABLE)\b/i);
 assert.equal((sql.match(/CREATE OR REPLACE FUNCTION /g)||[]).length,1);
});

function sourceLinkedReportAllocation(report,allocation){
 if(!report || !allocation || !report.responsibleAllocationId ||
   report.responsibleAllocationId!==allocation.id ||
   report.organizationId!==allocation.organizationId ||
   report.workItemId!==allocation.workItemId ||
   allocation.allocationRole!=="responsible" ||
   !["active","completed","released"].includes(allocation.state) ||
   !allocation.assigneeCanonicalPersonId ||
   !allocation.allocatedAt || report.reportedAt<allocation.allocatedAt)
  return null;
 return {sourceResultId:report.resultId,allocationId:allocation.id,
  assigneeCanonicalPersonId:allocation.assigneeCanonicalPersonId,
  allocationState:allocation.state,
  historicalNotCurrent:allocation.state!=="active",
  sameOriginalAndOrganizationProven:true,
  recordedReporterMatchesAllocation:Boolean(report.reportedByUserId&&
   report.resultContractKey==="continuing_care_actual_v1"&&
   report.metadata?.authenticatedReporterPersonId===allocation.assigneeCanonicalPersonId)};
}

test("synthetic report FK admits only same-original current or historical responsibility",()=>{
 const r={resultId:"r",organizationId:"org",workItemId:"work",
   responsibleAllocationId:"allocation",reportedAt:"2026-11-17T12:00:00Z",
   reportedByUserId:"signed-user",resultContractKey:"continuing_care_actual_v1",
   metadata:{authenticatedReporterPersonId:"person"}};
 const a={id:"allocation",organizationId:"org",workItemId:"work",
   allocationRole:"responsible",state:"completed",
   assigneeCanonicalPersonId:"person",allocatedAt:"2026-11-16T12:00:00Z"};
 for(const state of ["active","completed","released"]){
  const v=sourceLinkedReportAllocation(r,{...a,state});
  assert.equal(v?.sourceResultId,"r");
  assert.equal(v?.allocationId,"allocation");
  assert.equal(v?.historicalNotCurrent,state!=="active");
 }
 for(const bad of [
  {...a,id:"different-allocation"},
  {...a,organizationId:"wrong-org"},
  {...a,workItemId:"wrong-work"},
  {...a,allocationRole:"participant"},
  {...a,state:"offered"},
  {...a,assigneeCanonicalPersonId:null},
  {...a,allocatedAt:"2026-11-18T12:00:00Z"},
 ]){
  assert.equal(sourceLinkedReportAllocation(r,bad),null);
 }
 assert.equal(sourceLinkedReportAllocation({...r,responsibleAllocationId:null},a),null);
 assert.equal(sourceLinkedReportAllocation(r,null),null);
});

test("historical-only unrelated allocation can never be substituted for the result FK",()=>{
 const r={resultId:"r",organizationId:"org",workItemId:"w",
   responsibleAllocationId:"original",reportedAt:"2026-11-17T12:00:00Z"};
 const latestHistorical={id:"later",organizationId:"org",workItemId:"w",
   state:"completed",allocationRole:"responsible",assigneeCanonicalPersonId:"other",
   allocatedAt:"2026-11-15T12:00:00Z"};
 assert.equal(sourceLinkedReportAllocation(r,latestHistorical),null);
});

test("recorded reporter metadata is distinct from the Work allocation FK and cannot prove GoTrue signature alone",()=>{
 const result={resultId:"r",organizationId:"org",workItemId:"work",
  responsibleAllocationId:"alloc",reportedAt:"2026-11-17T12:00:00Z",
  resultContractKey:"continuing_care_actual_v1",
  reportedByUserId:"signed-user",
  metadata:{authenticatedReporterPersonId:"reporter"}};
 const allocation={id:"alloc",organizationId:"org",workItemId:"work",
  allocationRole:"responsible",state:"completed",
  assigneeCanonicalPersonId:"reporter",allocatedAt:"2026-11-16T12:00:00Z"};
 assert.equal(sourceLinkedReportAllocation(result,allocation)?.recordedReporterMatchesAllocation,true);
 for(const invalid of [
  {...result,reportedByUserId:null},
  {...result,resultContractKey:"ordinary_company_work_manager_acceptance_v1"},
  {...result,metadata:{}},
  {...result,metadata:{authenticatedReporterPersonId:"different"}},
 ]){
  const link=sourceLinkedReportAllocation(invalid,allocation);
  assert.equal(link?.recordedReporterMatchesAllocation,false);
 }
});

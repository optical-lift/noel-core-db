#!/usr/bin/env python3
"""Static and pure unit tests for PRE1 signed PostgREST absence contract."""
import ast
import importlib.util
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
HARNESS=(ROOT/"scripts/validate-production-schema-clone.sh").read_text()
WF=(ROOT/".github/workflows/atlas-access03c-pre1-protected-held-pair-clone.yml").read_text()
SCRIPT=ROOT/"scripts/validate-atlas-access03c-pre1-tending-rpc-signed-http.py"
BODY=SCRIPT.read_text()

class Pre1RpcProof(unittest.TestCase):
 def test_strict_missing_function_vs_missing_schema_or_permission(self):
  spec=importlib.util.spec_from_file_location("pre1_rpc_source_test",SCRIPT)
  mod=importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  mod.require_missing_rpc(404,{"code":"PGRST202"},"pure expected")
  for status,code in ((404,"PGRST205"),(404,"42883"),(403,"42501"),
                      (401,"42501"),(200,None),(404,None)):
   with self.assertRaises(AssertionError,msg=str((status,code))):
    mod.require_missing_rpc(status,{"code":code},"pure reject")
 def test_script_uses_real_local_gotrue_v2_positive_and_restricted_cleanup(self):
  ast.parse(BODY)
  for term in ('c1.local_status()', 'c1.sign_in(api,key,name)',
     "from auth.sessions", 'existing.request(api,key,tokens["owner"],V2,"POST",body)',
     'bed.get("taskTitle")==TITLE', 'bed.get("bedKey")==KEY',
     'bed.get("releasedTaskId")==TASK', 'bed.get("cropCycleId")==CYCLE',
     'bed.get("isActionableNow") is False', "'general','skipped','water','farm_shared'",
     "status='skipped' and visibility_scope='farm_shared'",
     "except subprocess.CalledProcessError as exc",
     'existing.private_missing', 'require_missing_rpc(status,packet',
     'error=="PGRST202"', '"PGRST205","42883"', 'time.sleep(0.5)',
     'NOTIFY pgrst', 'select to_regprocedure', 'snapshot(db)==baseline',
     'delete from atlas.task_objects', 'delete from atlas.tasks',
     'delete from atlas.farm_memberships', 'PASS ACCESS03C-PRE1 signed ',
     'class_baseline', 'operation_classes', 'water_nourish',
     "delete from atlas.operation_classes",
     "local operation class is not the exact reviewed production source",
     "object_state", "pre-existing fictional object_state; refuse test-only cleanup",
     "refresh_object_active_task_count_v1", "derived_state_guard",
     "metadata ? 'task_count_synced_at'",
     "synthetic count-only object_state source drift; refuse cleanup",
     '"with deleted as (delete from atlas.object_state where "+',
     'derived_state_guard+" returning object_id) "+',
     '"select count(*) from deleted"', "cleanup_sql",
     "synthetic object_state cleanup affected unexpected row count",
     "synthetic object_state survived scoped cleanup"):
   self.assertIn(term,BODY)
  self.assertNotIn("'general','open','water','farm_shared'",BODY)
  self.assertNotIn('https://',BODY)
  self.assertNotIn('SUPABASE_SERVICE_ROLE_KEY',BODY)
  self.assertIn("refuses nonlocal database",BODY)
 def test_exact_optin_pinned_to_held_source_in_disposable_harness(self):
  for fragment in ('--pre1-rest-proof', 'pre1_rest_proof=false',
      'ac8552f35e4de14f1ae337c29cfc1c2971af1c9b',
      'signed_access03_zone_retirement_probe', 
      'scripts/validate-atlas-access03c-pre1-tending-rpc-signed-http.py',
      '^PASS ACCESS03C-PRE1 signed '):
   self.assertIn(fragment,HARNESS)
  self.assertIn('if [ "$pre1_rest_proof" = true ]; then',HARNESS)
  self.assertLess(HARNESS.index('phase="genuine signed local ACCESS-03A'),
                  HARNESS.index('phase="signed local PRE1 v1 REST RPC absence'))
  for fragment in ('--pre1-rest-proof', 'tests/test_atlas_access03c_pre1_tending_rpc_source.py',
      'signed-access03c-pre1-rpc-summary.txt',
      'PRE1_CLONE_RESULT=PASS_SIGNED_LOCAL_V1_RPC_ABSENCE_V2_POSITIVE'):
   self.assertIn(fragment,WF)
  self.assertIn('environment: production',WF)
  self.assertIn('ref: main',WF)
  self.assertIn('909d95c198671f9c80e28ad4e58d7534ded22675',WF)

if __name__=="__main__":unittest.main()

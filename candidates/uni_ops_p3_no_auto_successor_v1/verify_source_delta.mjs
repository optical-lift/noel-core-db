#!/usr/bin/env node
// Exact-source P3 custody check. NOT an integrated database or signed test.
// The sole allowed change is 6A's Result-triggered no-task branch.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const file='candidates/uni_ops_p3_no_auto_successor_v1/01_result_only_rhythm_evaluator_held.sql';
const s=readFileSync(file,'utf8');
const start=s.indexOf('CREATE OR REPLACE FUNCTION atlas.evaluate_rhythm_binding_v1(');
assert.ok(start>=0,'original deployed function signature must remain');
const fn=s.slice(start).trimEnd()+'\n';
const first=fn.indexOf("if coalesce(p_trigger_kind,'clock') in");
const last=fn.indexOf("      end if;",first);
assert.ok(first>0&&last>first,'one result-only dispatch must exist');
assert.equal(fn.indexOf("if coalesce(p_trigger_kind,'clock') in",first+1),-1);
const block=fn.slice(first,last+"      end if;".length);
assert.match(block,/'workflow_precheck','workflow_result'/);
assert.match(block,/'game_master_precheck','game_master_satisfaction'/);
assert.match(block,/'qualified_evaluation_no_successor'/);
assert.match(block,/v_task_result := atlas\.ensure_rhythm_task_v1\(/);
const restored=fn.replace(block,"v_task_result := atlas.ensure_rhythm_task_v1(v_state.id, v_next_state, v_boundary_at);");
const md5=createHash('md5').update(restored).digest('hex');
assert.equal(md5,'774ad5c6728a615ada5bf4ea823c5498',
  'P3 changed live function outside the single intended expression; STOP');
assert.match(fn,/create/i);
assert.match(fn,/v_state\.lease_started_at/);
assert.match(fn,/atlas\.record_rhythm_transition_v1/);
assert.match(fn,/update atlas\.rhythm_state/);
console.log('P3 exact-live-source one-expression delta verified; NO SQL, signed runtime or release acceptance');

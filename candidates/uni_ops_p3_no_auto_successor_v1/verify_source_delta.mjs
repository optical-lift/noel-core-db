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
assert.match(block,/'activation_prerequisite_completed'/);
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

// Phase split: file 11 checks its exact original MD5 BEFORE replacing the
// signal function; deferred_postconditions.sql runs AFTER that replacement.
// Requiring the original MD5 again afterward would make a successful
// assembled overlay fail by construction. This is source-only, not PG proof.
const signalOverlay=readFileSync(
  'candidates/uni_ops_p3_no_auto_successor_v1/11_governed_rhythm_clock_signal_specific_hold_held.sql','utf8');
const assembledPost=readFileSync(
  'candidates/uni_ops_p3_no_auto_successor_v1/deferred_postconditions.sql','utf8');
assert.match(signalOverlay,/IS DISTINCT FROM '44878fb25c583320a0af033e4266d25b'/,
  'pre-install live-source drift pin must remain');
assert.doesNotMatch(assembledPost,/44878fb25c583320a0af033e4266d25b/,
  'post-install assertions may not demand the replaced live-source fingerprint');
for(const name of [
  'v_signal text;',
  'INTO v_signal;',
  "position('governed_rhythm_clock_signal_held' IN v_signal)",
  "position('automatic_task_release_authorized' IN v_signal)",
  "position('noAutomaticNextTask' IN v_signal)",
  "position('release_eligible_work_v1' IN v_signal)",
  "position('gate_satisfied_at' IN v_signal)",
]){
  assert.ok(assembledPost.includes(name),`missing post-install signal assertion: ${name}`);
}
assert.match(signalOverlay,/release_eligible_work_v1/,
  'unrelated independent signal sources must retain their original release path');
console.log('P3 pre-install source pin / post-install overlay split source-verified; runtime acceptance HELD');

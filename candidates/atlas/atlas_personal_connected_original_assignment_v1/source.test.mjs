import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const s=readFileSync(new URL("./candidate.sql",import.meta.url),"utf8");
test("one original and reciprocal accepted link, not a household or Company task copy",()=>{
 for(const fragment of ["atlas.household_member_identity_links","i.invitation_state='accepted'","i.accepted_by_user_id=l.target_auth_user_id","p.user_id=p_user_id OR l.target_auth_user_id=p_user_id","atlas.personal_task_ready_person_v1(l.target_auth_user_id)","REFERENCES atlas.task_entries(id) ON DELETE RESTRICT","a.connection_evidence->>peer.peer_person_id::text","t.owner_user_id=auth.uid() AND t.principal_id=v_principal FOR UPDATE","'acceptanceRequired',false","'recipientAttested',false","'newTaskCreated',false","FOR SHARE","v_prior.revision<>p_expected_revision+1","v_revision<>p_expected_revision"])assert.ok(s.includes(fragment),fragment);
 assert.doesNotMatch(s,/insert\s+into\s+atlas\.(task_entries|work_items|tasks|household_member_identity_links)\b/i);
 assert.doesNotMatch(s,/grant\s+execute\s+on/i);
 assert.doesNotMatch(s,/create\s+(or\s+replace\s+)?function\s+public\./i);
});

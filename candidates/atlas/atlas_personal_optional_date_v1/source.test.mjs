import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const sql=readFileSync(new URL("./candidate.sql",import.meta.url),"utf8");
test("original task date nullable, exact retry and signed undated reader",()=>{assert.match(sql,/ALTER TABLE atlas\.task_entries ALTER COLUMN due_date DROP NOT NULL/);assert.match(sql,/v_task\.due_date IS DISTINCT FROM p_due_date/);assert.match(sql,/atlas\.personal_task_assigned_actor_v1\(t\.id,auth\.uid\(\),v_principal\)/);assert.match(sql,/t\.due_date IS NOT DISTINCT FROM p_date/);assert.doesNotMatch(sql,/CREATE TABLE|GRANT|INSERT INTO atlas\.work_items/i);});

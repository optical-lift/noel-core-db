-- Atlas flower preparation directive approval lock v1
--
-- Keep the new post-harvest preparation workflow technically dormant until the
-- Owner has explicitly approved its wording, task-card presentation, and runtime
-- behavior. No authenticated Atlas application session may invoke the directive
-- release RPC while this lock is installed.

revoke execute on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) from authenticated;

comment on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) is
  'DORMANT / OWNER-APPROVAL LOCKED. Atomically records Owner requested preparation rows and releases Flower Preparation only after a later governed migration explicitly restores application EXECUTE following Owner approval of wording, task-card styling, and runtime behavior.';
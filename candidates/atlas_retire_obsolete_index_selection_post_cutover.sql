-- POST-CUTOVER RETIREMENT CANDIDATE ONLY.
-- Do not run until:
-- 1. atlas_foundry_notebook_index_v1 has been promoted and validated;
-- 2. Atlas first-use UI and notebook no longer call these APIs;
-- 3. client/version compatibility and pg_depend/function reference scans are clean;
-- 4. the reviewed migration workflow and owner approve irreversible API retirement.
-- v3/v4 recorded orientation EVENTS remain; history is not thrown away.
-- RESTRICT intentionally blocks execution when a dependency survives.
drop function if exists public.set_personal_atlas_index_selection_self_api_v1(jsonb) restrict;
drop function if exists public.personal_atlas_index_selection_self_api_v1() restrict;
drop function if exists atlas.set_personal_atlas_index_selection_self_api_v1(jsonb) restrict;
drop function if exists atlas.personal_atlas_index_selection_self_api_v1() restrict;

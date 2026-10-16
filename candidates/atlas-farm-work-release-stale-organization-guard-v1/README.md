# Farm release integrity candidate

Status: inert, unreleased; clone validation required.

The hourly eligible-work release job has failed repeatedly with a tasks-to-organizations foreign key violation. Read-only inspection found one obsolete organization identifier in many planned-work payloads, although the farms themselves reference established organizations.

The candidate checks each occurrence before inserting a task. When its specified organization is not found, it preserves the occurrence, marks an auditable hold reason on the occurrence, and continues processing other eligible work. It does not substitute another organization, delete history, suppress the foreign key, or assume all planned occurrences are due.

Acceptance in a disposable clone:
1. An unrelated valid occurrence still releases normally.
2. An invalid-source occurrence remains intact and produces no task.
3. Retrying neither duplicates a task nor overwrites the original hold timestamp.
4. Correcting the source payload through an authorized process permits ordinary release.
5. Qualifying work already satisfied by evidence is still closed through its original path.
6. Existing budget, membership, safety, and notification constraints remain unchanged.

Do not migrate this candidate to production before canonical source generation, isolated clone validation and a separate release decision.

## Production-read-only acceptance, 2026-10-15

The diagnostic packet `production-readonly-diagnostics.sql` uses only SELECT over existing source tables and the confirmed STABLE occurrence gate. It does not invoke the release writer, create test tasks, alter a schema, or dispatch notifications.

At inspection time, among Elm occurrences passing the actual active release-policy, date/horizon, parent, and occurrence gates, **60 were candidates for the release loop**: **34** had the absent organization ID, **6** referenced an existing organization, and **20** omitted an organization (which is not, by itself, a referential violation). The active top-level task count was **99** against the existing safety threshold of **5,000**. This is a read-only projection, not proof that all noninvalid occurrences would be released: the existing day budget, window and other gates still apply inside the writer.

The recent production cron has continued to fail hourly. A structural source comparison against `pg_get_functiondef` confirmed that the candidate's original function body is preserved exactly after removing only its added guard, new counter, and counter field. An initial SQL terminator omission in the candidate was fixed before release; the function now terminates before `COMMIT;`.

Production remains unchanged. A full executable candidate test must follow the **existing canonical production-schema clone workflow**, which reads only the production schema and applies migration code to a disposable database without a paid Supabase development branch. Do not call the volatile release function on production merely to test it, because it can create tasks and notification plans with side effects that are not appropriately rolled back by an interactive tool invocation.

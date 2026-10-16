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

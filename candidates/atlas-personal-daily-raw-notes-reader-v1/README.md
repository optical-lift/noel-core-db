# Personal Daily Log – source-backed raw notes

Source candidate only. No new table. Reuses `atlas.personal_reality_captures` from the already-live immutable Person capture command. Returns only the signed-in owner’s captured `sourceSurface=personal_notebook_daily_log`, `entryKind=note` entries on the selected **notebook page date**. Never asserts the note was witnessed at that date or belongs to a Collection.

- Requires signed-in canonical Reality Person with active native Personal Atlas; read-only wrapper is executable by authenticated only, never by anon or public; underlying function internal.
- Source items have original capture IDs / evidence IDs. At most 120 latest notes are returned, with `total` / `truncated` clearly exposed rather than silently pretending a full page.
- Existing task writer remains separate. Capturing testimony does not create or complete a task, join a Ledger, add a household event, or admit Clock work.
- Two synthetic native Persons test write/read, other-day isolation, foreign-Person privacy, and unchanged task rows.

Use the canonical generated migration lane and disposable production-schema clone, then protected production release. Atlas app's Daily Log may read this API only after it is proven released, otherwise show a precise unavailable-source message.

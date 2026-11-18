#!/usr/bin/env python3
"""Exact already-executed historical structural migration custody, never a replay."""
import hashlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent
PATH = ROOT / "supabase/migrations/20261117234613_history_story_parallels_research_only_v1.sql"
EXPECTED_SHA = "54eb7579152cf3326a208d4c5931b5d404898b5f"
TARGETS = [
    "draft.history_accounts",
    "draft.history_scenes",
    "draft.history_scene_functions",
    "draft.history_storylines",
    "draft.history_storyline_scenes",
    "draft.history_parallel_sets",
    "draft.history_parallel_evidence",
    "draft.history_scene_canon_links",
]

class HistoricalHistorySourceCustody(unittest.TestCase):
    def test_exact_live_bytes_and_eight_private_draft_tables(self):
        raw = PATH.read_bytes()
        self.assertEqual(len(raw), 9299)
        actual = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        self.assertEqual(actual, EXPECTED_SHA)
        sql = raw.decode("utf-8")
        tables = [x.lower() for x in re.findall(
            r"create\s+table\s+if\s+not\s+exists\s+([a-z_][a-z0-9_.]*)",
            sql, flags=re.IGNORECASE)]
        self.assertEqual(tables, TARGETS)
        rls = [x.lower() for x in re.findall(
            r"alter\s+table\s+([a-z_][a-z0-9_.]*)\s+enable\s+row\s+level\s+security",
            sql, flags=re.IGNORECASE)]
        self.assertEqual(rls, TARGETS)
        for forbidden in (
            r"\binsert\s+into\b", r"\bdelete\s+from\b",
            r"\bupdate\s+[a-z_][a-z0-9_]*\s+set\b",
            r"\bcopy\s+[a-z_]", r"\btruncate\s+[a-z_]",
            r"\b(?:atlas|titus|wnph)\.", r"\bcreate\s+(?:or\s+replace\s+)?function\b",
        ):
            self.assertIsNone(re.search(forbidden, sql, flags=re.IGNORECASE))
        acl = [line.strip() for line in sql.splitlines()
               if re.match(r"^\s*(grant|revoke)\s+", line, flags=re.IGNORECASE)]
        self.assertEqual(len(acl), 3)
        self.assertTrue(acl[0].startswith("revoke all on table draft.history_accounts"))
        self.assertTrue(acl[0].endswith("from public, anon, authenticated;"))
        self.assertTrue(acl[1].startswith("grant select,insert,update,delete on table draft.history_accounts"))
        self.assertTrue(acl[1].endswith("to service_role;"))
        self.assertEqual(acl[2], "grant usage,select on all sequences in schema draft to service_role;")
        self.assertEqual(len(re.findall(r"(?im)^comment on table ", sql)), 3)

if __name__ == "__main__":
    unittest.main()

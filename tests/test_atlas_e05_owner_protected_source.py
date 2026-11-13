"""Offline protected-E05 workflow source refusal tests only; no secrets or SQL."""
from pathlib import Path
import ast
import unittest

ROOT=Path(__file__).resolve().parents[1]
WORKFLOW=ROOT/".github/workflows/atlas-e05-owner-protected-current-schema-signed.yml"
CONTROLLER=ROOT/"scripts/run-atlas-e05-owner-protected-signed.py"

class E05OwnerWorkflowSourceTests(unittest.TestCase):
    def test_owner_and_protected_environment(self):
        text=WORKFLOW.read_text()
        for token in ("author_association == 'OWNER'","github.actor == github.repository_owner",
                      "github.event.issue.user.login == github.actor",
                      "github.event.issue.state == 'open'","environment: production",
                      "on:\n  pull_request:","  issues:\n    types: [opened, edited, reopened]",
                      "schema_and_roles_only","release_intent","test_only"):
            self.assertIn(token,text,token)

    def test_secret_snapshot_only_and_no_dump_upload(self):
        text=WORKFLOW.read_text()
        self.assertIn("secrets.NOEL_CORE_DATABASE_URL",text)
        self.assertIn("secrets.ATLAS_E05_SOURCE_READ_TOKEN",text)
        self.assertIn("db dump --db-url",text)
        self.assertIn("--role-only",text)
        self.assertNotIn("upload-artifact",text)
        self.assertIn("NO_ARTIFACT_UPLOAD",text)
        self.assertIn("persist-credentials: false",text)

    def test_native_riversong_branch_does_not_require_actions_node(self):
        text=WORKFLOW.read_text()
        protected=text.split("  owner-approved-disposable-signed:",1)[1]
        self.assertIn("runs-on: [self-hosted, macOS, X64, atlas-verifier]",protected)
        self.assertIn("git -C",protected)
        self.assertNotIn("uses: actions/checkout",protected)
        self.assertIn("git hash-object scripts/atlas-riversong-e05-signed-acceptance.py",protected)

    def test_controller_no_remote_database_connection_string(self):
        s=CONTROLLER.read_text()
        ast.parse(s)
        self.assertNotIn("NOEL_CORE_DATABASE_URL",s)
        self.assertIn('runtime.root/"db"',s)
        self.assertIn('"atlas_e05_"+secrets.token_hex',s)
        self.assertIn("run-atlas-e05-isolated-riversong.py",s)
        self.assertIn("ThreadingHTTPServer",s)
        self.assertNotIn("service_role",s)

    def test_pinned_rest_and_auth_source(self):
        s=CONTROLLER.read_text()
        self.assertIn("03a176e71a18065bae73aac805691a99d6d663ab",s)
        self.assertIn("55da4dfa7b376e83151e5091340c4f83d6d5fdfa",s)
        self.assertIn("87401240aa913d57e8bc276af1f221ff5ddc9765",s)

if __name__=="__main__":
    unittest.main()

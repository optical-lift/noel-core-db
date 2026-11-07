#!/usr/bin/env python3
"""HELD reviewer candidate only. Run signed local Titus learner tests on a real-schema clone.

This adapter cannot authenticate against remote endpoints: the underlying validator
requires a localhost Supabase database, API, and independently signed OAuth sessions.
"""
import importlib.util
import sys
from pathlib import Path

probe=Path(__file__).resolve().parents[1]/"candidates/shared-titus-learner-private-notebook-v1/validate_signed_local_http.py"
spec=importlib.util.spec_from_file_location("held_titus_learner_clone_signed",probe)
module=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=module
spec.loader.exec_module(module)
if "--require-canonical-clone" not in sys.argv:
    sys.argv.append("--require-canonical-clone")
if __name__=="__main__":
    module.main()

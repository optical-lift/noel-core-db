#!/usr/bin/env python3
"""Fail-closed negative tests for signed private source Git-tree inclusion."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("private_git_source", ROOT / "scripts/verify-private-source-custody.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
data = json.loads((ROOT / "custody/private-noel-h1847-signed-source-inclusion-v1.json").read_text())
ids = mod.verify_inclusion(data)
assert len(ids) == 2
assert mod.tree_hash(data["gitTrees"][-1]["entries"]) == data["gitTrees"][-1]["sha"]

mutators = {
    "wrong_source_blob": lambda p: p["sources"][0].update(liveGitBlobSha1="0" * 40),
    "missing_verified_leaf": lambda p: p["gitTrees"][-1]["entries"].pop(0),
    "wrong_repo": lambda p: p.update(privateSourceRepository="wrong/private-repo"),
    "wrong_path": lambda p: p["sources"][0].update(privatePath="wrong.sql"),
    "wrong_version": lambda p: p["sources"][0].update(version="20261010299999"),
    "wrong_signed_tree": lambda p: p["signedCommit"].update(treeSha1="0" * 40),
    "missing_nested_directory": lambda p: p["gitTrees"][2]["entries"].clear(),
    "forged_tree_blob": lambda p: p["gitTrees"][-1]["entries"][1].update(sha="0" * 40),
}
for name, mutate in mutators.items():
    wrong = copy.deepcopy(data)
    mutate(wrong)
    try:
        mod.verify_inclusion(wrong)
    except (ValueError, AssertionError, KeyError):
        continue
    raise AssertionError("Private custody inclusion forgery accepted: " + name)

print("Private signed Git-source inclusion negative tests PASS: two exact private blobs, eight forged proofs rejected.")

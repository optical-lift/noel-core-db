#!/usr/bin/env python3
"""Verify exact partition of the previously tested SQL into two atomic migrations."""
from pathlib import Path

base = Path(__file__).resolve().parents[2] / "candidates/shared-listening-delivery-artifact-v1"
completion = (base / "generated_production_completion_candidate.sql").read_text()
original = (base / "manuscript_original_registration_candidate.sql").read_text()
staging = (base / "generated_listening_storage_candidate.sql").read_text()
enum_line = "ALTER TYPE transcript_core.asset_provenance_class ADD VALUE IF NOT EXISTS 'manuscript_source';\n"
assert original.count(enum_line) == 1

def body(source):
    marker = "\nBEGIN;\n"
    assert source.count(marker) == 1
    assert source.endswith("COMMIT;\n")
    return source.replace(marker, "\n", 1)[:-len("COMMIT;\n")]

enum_expected = (
    "-- Reviewed Shared native source type; first migration in a two-stage release.\n"
    "-- This transaction must COMMIT before a later migration uses the enum label.\n"
    "BEGIN;\n" + enum_line + "COMMIT;\n"
)
admission_expected = (
    "-- Reviewed Shared private manuscript, rendering and completion source.\n"
    "-- This is the second governed migration, after the enum migration is released.\n"
    "BEGIN;\n"
    + "\n".join([body(completion), body(original.replace(enum_line, "")), body(staging)])
    + "\nCOMMIT;\n"
)
assert (base / "canonical_native_manuscript_source_provenance_v1.sql").read_text() == enum_expected
assert (base / "canonical_native_private_listening_completion_v1.sql").read_text() == admission_expected
print("PASS exact reviewed SQL partition across two separately atomic release migrations")

#!/usr/bin/env python3
"""Exact SQL transaction partition verifier for existing held source. No network."""
from pathlib import Path
base=Path(__file__).resolve().parents[2]/"candidates/shared-listening-delivery-artifact-v1"
completion=(base/"generated_production_completion_candidate.sql").read_text()
original=(base/"manuscript_original_registration_candidate.sql").read_text()
staging=(base/"generated_listening_storage_candidate.sql").read_text()
enum_line="ALTER TYPE transcript_core.asset_provenance_class ADD VALUE IF NOT EXISTS 'manuscript_source';\\n".replace('\\\\n','\\n')
assert original.count(enum_line)==1

def body(source):
    marker="\\nBEGIN;\\n".replace('\\\\n','\\n')
    assert source.count(marker)==1 and source.endswith("COMMIT;\\n".replace('\\\\n','\\n'))
    return source.replace(marker,"\\n".replace('\\\\n','\\n'),1)[:-len("COMMIT;\\n".replace('\\\\n','\\n'))]

enum_expected="-- Reviewed Shared native source type; first migration in a two-stage release.\\n-- This transaction must COMMIT before a later migration uses the enum label.\\nBEGIN;\\n".replace('\\\\n','\\n')+enum_line+"COMMIT;\\n".replace('\\\\n','\\n')
admission_expected="-- Reviewed Shared private manuscript, rendering and completion source.\\n-- This is the second governed migration, after the enum migration is released.\\nBEGIN;\\n".replace('\\\\n','\\n')+"\\n".replace('\\\\n','\\n').join([body(completion),body(original.replace(enum_line,"")),body(staging)])+"\\nCOMMIT;\\n".replace('\\\\n','\\n')
assert (base/"canonical_native_manuscript_source_provenance_v1.sql").read_text()==enum_expected
assert (base/"canonical_native_private_listening_completion_v1.sql").read_text()==admission_expected
print("PASS exact reviewed SQL partition across two separately atomic release migrations")

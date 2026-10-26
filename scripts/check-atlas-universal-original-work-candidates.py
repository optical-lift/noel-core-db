#!/usr/bin/env python3
"""Static preflight for held universal Atlas Work SQL candidates.

This is deliberately NOT a PostgreSQL compile, signed-user proof or production
migration. Run on exact draft SHA before guarded production-shaped clone.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates" / "atlas"

CANDIDATES = (
    "governed_legacy_farm_reader_disclosure_v1",
    "governed_legacy_farm_reader_disclosure_gate0_extension_v1",
    "governed_legacy_farm_reader_disclosure_gate0_context_v1",
    "governor_effective_subject_disclosure_review_v1",
    "universal_subject_bounded_disclosure_v1",
    "original_subject_choices_for_work_decomposition_v1",
    "universal_original_work_decomposition_v1",
    "universal_household_canonical_work_custody_v1",
    "universal_household_canonical_work_guards_v1",
    "universal_household_rhythm_explicit_decision_v1",
    "household_laundry_original_work_actual_v1",
    "household_laundry_original_work_read_v1",
    "original_subject_work_existing_direct_responsibility_v1",
)

def require(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)

if not BASE.is_dir():
    print("SKIP no Atlas universal Work candidates in this branch")
    raise SystemExit(0)

texts = {}
for name in CANDIDATES:
    p = BASE / name / "candidate.sql"
    require(p.is_file(), f"missing candidate: {p}")
    s = p.read_text()
    texts[name] = s
    require(s.lstrip().startswith("BEGIN;"), f"{name}: missing transaction start")
    require(s.rstrip().endswith("COMMIT;"), f"{name}: missing transaction end")
    require(len(re.findall(r"(?m)^COMMIT;\s*$", s)) == 1,
            f"{name}: extra or absent top-level commit")
    for dollar_label in set(re.findall(r"\$[a-z][a-z0-9_]*\$", s)):
        require(s.count(dollar_label) % 2 == 0,
                f"{name}: unmatched function or DO dollar quote {dollar_label}")
    print(f"PASS transaction boundary {name}")

guard = texts["universal_household_canonical_work_guards_v1"]
actual = texts["household_laundry_original_work_actual_v1"]
read = texts["household_laundry_original_work_read_v1"]
rhythm = texts["universal_household_rhythm_explicit_decision_v1"]
custody = texts["universal_household_canonical_work_custody_v1"]
decomp = texts["universal_original_work_decomposition_v1"]
assignment = texts["original_subject_work_existing_direct_responsibility_v1"]

# An idempotent receipt can expose its original Work, Need, actual result and
# acceptance IDs. Authorization must precede ALL receipt readback paths.
writer = actual.split(
    "CREATE OR REPLACE FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(", 1
)[1].split("\n$function$;", 1)[0]
who = writer.index("v_person:=atlas.household_work_actor_v1")
carrier = writer.index("Physical Work Actual requires authorized original carrier")
replay = writer.index("IF v_result IS NOT NULL THEN")
receipt = writer.index("SELECT id INTO v_result FROM atlas.care_result_events")
require(who < carrier < receipt < replay,
        "Laundry signed governor/exact carrier authority must PRECEDE all replay receipts")
require(writer.count("Physical Work Actual requires authorized original carrier") == 1,
        "exact owner/carrier access guard missing or duplicated")
require("v_work.work_state<>'open' OR v_need.state<>'open'" in writer,
        "new physical Actual must require current original Work/Need")
require("'laundryCompletelyDone',false" in writer,
        "wash-started cannot assert complete whole-Laundry state")
require("household_rhythm_explicit_decisions_v1" in writer
        and "'explicitDecisionId',v_decision.decision_id" in writer,
        "conditional satisfaction must derive from latest immutable Rhythm decision")
require("h.metadata->>'establishedByExplicitDecision'" not in writer,
        "editable metadata cannot authorize Rhythm satisfaction")
print("PASS signed original Laundry physical-Actual replay boundary")

require("AND state='open'" in read
        and "'lastCompletedWorkItemId',v_last_completed_work_id" in read,
        "current Laundry reader must separate open Need from completed original history")
require("household_rhythm_explicit_decisions_v1" in rhythm
        and "BEFORE UPDATE OR DELETE" in rhythm
        and "atlas.require_household_governor_self_v1" in rhythm,
        "Rhythm decisions must be append-only and explicitly governor-authorized")
require("household_rhythm_explicit_decisions_v1" in read,
        "Rhythm read must use original decision, not mutable cadence metadata")
print("PASS separate original Need, Work, Rhythm and physical history")

require("work_items_one_native_custody_v1" in custody
        and "guard_canonical_work_custody_immutability_v1" in custody
        and "work_allocations_exact_assignee_carrier_v1" in custody,
        "shared original Work table must keep immutable exclusive custody")
require("confirmWorkerAttestationAuthority" in decomp
        and "ordinary_company_work_worker_attestation_v1" in decomp,
        "each split Bed Work child must independently govern completion")
require("INSERT INTO atlas.work_items(" not in assignment
        and "INSERT INTO atlas.work_allocations(" in assignment
        and "INSERT INTO atlas.work_execution_plans(" in assignment,
        "assigning existing Bed Work must not create a separate task")
print("PASS single canonical Work and independently governed Bed split")

# All old full-farm routes must be source-guarded, not hidden only in React.
source_names = []
for name in ("governed_legacy_farm_reader_disclosure_v1",
             "governed_legacy_farm_reader_disclosure_gate0_extension_v1",
             "governed_legacy_farm_reader_disclosure_gate0_context_v1"):
    sql = texts[name]
    names = re.findall(r"CREATE OR REPLACE FUNCTION atlas\.([a-z_0-9]+)\(", sql)
    for found in names:
        if found != "require_governed_farm_full_disclosure_self_v1":
            require("PERFORM atlas.require_governed_farm_full_disclosure_self_v1(" in sql,
                    f"{name}: no signed native governor source check")
            source_names.append(found)
require(len(source_names) == 26 and len(set(source_names)) == 26,
        "Gate 0 must enumerate 26 unique guarded historical readers")
review = texts["governor_effective_subject_disclosure_review_v1"]
missing = [name for name in source_names if f"'{name}'" not in review]
require(not missing, f"effective disclosure review missing historical paths: {missing}")
# PostgreSQL has no built-in MAX(uuid). The page cursor must be the exact
# ordered row at p_limit, not a text cast or an unsupported UUID aggregate.
for slug, old, boundary in (
    ("universal_subject_bounded_disclosure_v1",
      "max(q.subject_id)",
      "(array_agg(q.subject_id ORDER BY q.rn) FILTER(WHERE q.rn=p_limit))[1]"),
    ("governor_effective_subject_disclosure_review_v1",
      "max(b.id)",
      "(array_agg(b.id ORDER BY b.rn) FILTER(WHERE b.rn=p_limit))[1]"),
    ("original_subject_choices_for_work_decomposition_v1",
      "max(q.id)",
      "(array_agg(q.id ORDER BY q.rn) FILTER(WHERE q.rn=p_limit))[1]"),
):
    candidate = texts[slug]
    require(old not in candidate and boundary in candidate,
            slug + ": UUID cursor must be the last visible ordered page item")
print("PASS genuine PostgreSQL UUID pagination boundary")

print("PASS 26 source-guarded legacy reader inventory")

# A guessed object ID must not reveal whether a withheld original Bed/Task
# exists. Nonexistence and lack of full disclosure have the same 42501 source
# denial; old P0002 vs 42501 would be an existence oracle.
opaque = texts["governed_legacy_farm_reader_disclosure_gate0_extension_v1"]
for function_name, missing_check in (
    ("bed_components_state_v1", "if v_bed.id is null"),
    ("real_operation_explanation_v1", "if v_transition.id is null"),
    ("weed_card_task_focus_v1", "if v_task.id is null"),
):
    source = opaque.split(
        "CREATE OR REPLACE FUNCTION atlas." + function_name + "(", 1
    )[1].split("$function$;", 1)[0]
    require(missing_check in source,
            function_name + ": missing original-ID existence handling")
    before_gate = source.split(
        "PERFORM atlas.require_governed_farm_full_disclosure_self_v1(", 1
    )[0]
    require("raise exception 'Source unavailable to this Person.'" in before_gate
            and "errcode='42501'" in before_gate
            and "errcode='P0002'" not in before_gate.lower(),
            function_name + ": original-ID existence oracle before governor gate")
print("PASS original Bed/Task opaque ID non-discovery")


print("PASS held SQL source-contract preflight ONLY")

# A real signed acceptance runner is staged for disposable local GoTrue/REST.
# Protect its explicitly non-production harness fixture from DDL, arbitrary
# SQL, accidental recipient identities and drift from its source.
import ast
fixture_source = BASE / "atlas_universal_original_work_integrated_v1" / "fixture.sql"
fixture_clone = ROOT / "validation/fixtures/20261026215011_atlas_universal_original_work_integrated_v1.sql"
require(fixture_source.is_file() and fixture_clone.is_file()
        and fixture_source.read_bytes() == fixture_clone.read_bytes(),
        "Clone-only fixture must be exact original synthetic source")
synthetic = fixture_source.read_text()
clean = re.sub(r"/\*.*?\*/", " ", synthetic, flags=re.S)
clean = re.sub(r"--[^\n]*", " ", clean)
clean = re.sub(r"\s+", " ", clean).strip()
forbidden = re.search(
    r"\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|"
    r"reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|"
    r"listen|notify|security)\b", clean, re.I
)
require(forbidden is None,
        "Clone synthetic fixture has forbidden non-DML token")
require(all(re.match(r"^(insert\s+into|update\s+|delete\s+from|select\s+)",
                     item.strip(), re.I)
            for item in clean.split(";") if item.strip()),
        "Clone synthetic fixture must use bounded DML statements only")
require("Synthetic U-Pick Bed 3" in synthetic and
        "Synthetic withheld Bed 5" in synthetic and
        "clone-household-laundry" in synthetic and
        "insert into auth.users" in synthetic,
        "Required fictional identity, Bed and Laundry fixtures missing")
signed = ROOT / "scripts/validate-atlas-universal-original-work-signed-http.py"
require(signed.is_file(), "Missing signed local universal Work acceptance")
proof = signed.read_text()
ast.parse(proof, filename=str(signed))
require("127[.]0[.]0[.]1" in proof and "c1.sign_in" in proof
        and "production" in proof.lower(),
        "Signed acceptance must require genuine local GoTrue and reject production")
print("PASS synthetic fixture DML-only and signed local acceptance source")

print("PENDING full schema-clone compilation + signed Household/Anna/outsider/Event proof")

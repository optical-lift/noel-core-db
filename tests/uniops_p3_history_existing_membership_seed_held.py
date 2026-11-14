#!/usr/bin/env python3
"""HELD disposable-only C1 historical seed adaptation for EXISTING Person membership.

A signed U2 first-mowing worker is already a canonical member of the test
organization. The independent older historical fixture tried to INSERT a
second membership for the same Person + organization. The current canon
requires unique (organization_id,person_id). This test-only adapter binds the
distinct obsolete Work to the EXISTING member's id, without changing any
historical governor APIs, signed tokens, role grants, P3 SQL or held proof code.

The historical companion remains loaded from its immutable Git blob. ONLY its
one known fictional multi-statement SQL seed can pass this adapter, after a
real read-only local PostgreSQL membership preflight. Never run remotely.
"""
import re
import subprocess
from types import SimpleNamespace

ORG="e5200000-0000-4000-8000-000000000801"
PERSON="e5200000-0000-4000-8000-000000000102"
USER="e5200000-0000-4000-8000-000000000002"
LEGACY="ec410000-0000-4000-8000-000000000201"
WORK="ec410000-0000-4000-8000-000000000901"
ALLOC="ec410000-0000-4000-8000-000000000301"
LEDGER="e5200000-0000-4000-8000-000000000401"
OWNER="e5200000-0000-4000-8000-000000000101"

MEMBER_INSERT=f"""      INSERT INTO atlas.organization_memberships(
       id,organization_id,user_id,role,active,person_id)
      VALUES('{LEGACY}'::uuid,'{ORG}'::uuid,
       '{USER}'::uuid,
       'member',true,'{PERSON}'::uuid);"""
ORIGINAL_ALLOCATION=f"""      INSERT INTO atlas.work_allocations(
       id,organization_id,work_item_id,assignee_membership_id,
       allocation_role,state,establishment_basis_kind,establishment_basis)
      VALUES('{ALLOC}'::uuid,'{ORG}'::uuid,'{WORK}'::uuid,'{LEGACY}'::uuid,
       'responsible','active','self_adoption','{{"historical":true}}'::jsonb);"""
BOUND_ALLOCATION=f"""      INSERT INTO atlas.work_allocations(
       id,organization_id,work_item_id,assignee_membership_id,
       allocation_role,state,establishment_basis_kind,establishment_basis)
      SELECT '{ALLOC}'::uuid,'{ORG}'::uuid,'{WORK}'::uuid,m.id,
       'responsible','active','self_adoption','{{"historical":true}}'::jsonb
      FROM atlas.organization_memberships m
      WHERE m.organization_id='{ORG}'::uuid
        AND m.person_id='{PERSON}'::uuid
        AND m.user_id='{USER}'::uuid
        AND m.active IS TRUE;"""
WORK_INSERT=f"""      INSERT INTO atlas.work_items(
       id,organization_id,title,work_state,source_object_type,
       source_object_id,stable_key)
      VALUES('{WORK}'::uuid,'{ORG}'::uuid,'Fictional obsolete archived duty',
       'open','legacy_task_slice',
       'ec410000-0000-4000-8000-000000000902'::uuid,
       'clone:historical-retirement-proof');"""
RELEVANCE_INSERT=f"""      INSERT INTO atlas.company_work_native_ledger_relevance(
       organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
       attestation_source_ref,attestation_reason,established_by_person_id)
      VALUES('{ORG}'::uuid,'{WORK}'::uuid,'{LEDGER}'::uuid,
       'serves_purpose','owner_attested','clone:obsolete-review',
       'Fictional original Work context for retirement review','{OWNER}'::uuid);"""
ORIGINAL_SEED=(MEMBER_INSERT+"\n"+WORK_INSERT+"\n"+ORIGINAL_ALLOCATION+"\n"+RELEVANCE_INSERT)
MEMBERSHIP_SQL=(
    "select count(*) from atlas.organization_memberships m "
    "where m.organization_id='"+ORG+"'::uuid "
    "and m.person_id='"+PERSON+"'::uuid "
    "and m.user_id='"+USER+"'::uuid and m.active is true")
ALLOCATION_SQL=(
    "select count(*) from atlas.work_allocations a "
    "join atlas.organization_memberships m on m.id=a.assignee_membership_id "
    "where a.id='"+ALLOC+"'::uuid "
    "and a.work_item_id='"+WORK+"'::uuid "
    "and m.organization_id='"+ORG+"'::uuid "
    "and m.person_id='"+PERSON+"'::uuid "
    "and m.user_id='"+USER+"'::uuid and m.active is true")

class HistoricFixtureRefusal(AssertionError):
    """Fixed source-owned refusal, no SQL, UUID, actor or private data text."""

FIXTURE_STAGES=frozenset((
    "membership_preflight","membership_query_failed","membership_absent",
    "membership_not_exactly_one","membership_confirmed",
    "seed_apply_started","seed_apply_failed","seed_applied",
    "allocation_preflight","allocation_query_failed",
    "allocation_not_exactly_one","fixture_verified"
))

def emit_fixture_stage(stage):
    # Only fixed source-owned labels are reported, never SQL or identities.
    if stage not in FIXTURE_STAGES:
        raise HistoricFixtureRefusal("Unrecognized historical diagnostic stage")
    print("UNI_OPS_HISTORY_FIXTURE_STAGE="+stage,flush=True)

def adapt_known_seed(seed):
    if not isinstance(seed,str):
        raise HistoricFixtureRefusal("Historical seed is not text")
    if (seed.strip()!=ORIGINAL_SEED.strip()
            or seed.count("INSERT INTO atlas.")!=4
            or BOUND_ALLOCATION in seed):
        raise HistoricFixtureRefusal("Unreviewed historical seed shape")
    # Retain exact historical Work, ledger-relevance rows, and source-owned
    # governor fixture. Only reuse a Person-root relationship already in DB.
    result=seed.replace(MEMBER_INSERT,"-- existing canonical Person membership reused",1)
    result=result.replace(ORIGINAL_ALLOCATION,BOUND_ALLOCATION,1)
    if (result.count("INSERT INTO atlas.")!=3 or MEMBER_INSERT in result
            or ORIGINAL_ALLOCATION in result or result.count(BOUND_ALLOCATION)!=1):
        raise HistoricFixtureRefusal("Historical Person-root seed adaptation drift")
    return result

class ExistingPersonFixture:
    def __init__(self,original,reader):
        if not callable(getattr(original,"sql",None)) or not callable(reader):
            raise HistoricFixtureRefusal("Exact original local SQL helpers required")
        self._original=original
        self._reader=reader
        self._used=False
    def sql(self,db,seed):
        if (not isinstance(db,str)
                or re.fullmatch(
                    r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
                    db) is None or self._used):
            raise HistoricFixtureRefusal("Historical seed requires unique local invocation")
        adapted=adapt_known_seed(seed)
        self._used=True
        emit_fixture_stage("membership_preflight")
        try:
            membership_count=self._reader(db,MEMBERSHIP_SQL)
        except subprocess.CalledProcessError:
            emit_fixture_stage("membership_query_failed")
            raise
        if membership_count=="0":
            emit_fixture_stage("membership_absent")
            raise HistoricFixtureRefusal("Existing signed canonical Person membership absent")
        if membership_count!="1":
            emit_fixture_stage("membership_not_exactly_one")
            raise HistoricFixtureRefusal("One active signed canonical Person membership required")
        emit_fixture_stage("membership_confirmed")
        print("UNI_OPS_HISTORY_EXISTING_PERSON_MEMBERSHIP=CONFIRMED",flush=True)
        emit_fixture_stage("seed_apply_started")
        try:
            self._original.sql(db,adapted)
        except subprocess.CalledProcessError:
            emit_fixture_stage("seed_apply_failed")
            print("UNI_OPS_HISTORY_FIXTURE_SQL_STAGE=seed_apply_failed",flush=True)
            raise
        emit_fixture_stage("seed_applied")
        emit_fixture_stage("allocation_preflight")
        try:
            allocation_count=self._reader(db,ALLOCATION_SQL)
        except subprocess.CalledProcessError:
            emit_fixture_stage("allocation_query_failed")
            raise
        if allocation_count!="1":
            emit_fixture_stage("allocation_not_exactly_one")
            raise HistoricFixtureRefusal("Obsolete Work failed to bind the existing Person membership")
        emit_fixture_stage("fixture_verified")
        print("UNI_OPS_HISTORY_FIXTURE_SQL_STAGE=seed_applied",flush=True)
        return None

def adapter(original,reader):
    return SimpleNamespace(sql=ExistingPersonFixture(original,reader).sql)

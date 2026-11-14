#!/usr/bin/env python3
"""HELD disposable-only C1 historical seed adaptation for EXISTING Person membership.

U2 establishes the canonical Auth/Person/principal for the signed worker but
does not itself establish a matching organization_memberships row. In a
disposable clone, the frozen historical fixture may use its EXACT original
membership INSERT only when there is no member for that organization+Person,
the signed worker's existing Auth/Person/principal roots match, and no
conflicting/inactive membership exists. When one exact active membership
already exists, the adapter reuses it and drops only the duplicate INSERT.
This never changes governor APIs, tokens, grants, P3 SQL, or held proof code.

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
PERSON_MEMBERSHIP_SQL=(
    "select count(*) from atlas.organization_memberships m "
    "where m.organization_id='"+ORG+"'::uuid "
    "and m.person_id='"+PERSON+"'::uuid")
IDENTITY_SQL=(
    "select case when "
    "(select count(*) from auth.users u "
    "where u.id='"+USER+"'::uuid)=1 and "
    "(select count(*) from reality.auth_person_bindings b "
    "where b.auth_user_id='"+USER+"'::uuid "
    "and b.person_entity_id='"+PERSON+"'::uuid "
    "and b.binding_state='active' and b.retired_at is null)=1 and "
    "(select count(*) from atlas.principals p "
    "where p.user_id='"+USER+"'::uuid "
    "and p.person_id='"+PERSON+"'::uuid "
    "and p.status='active')=1 "
    "then 'aligned' else 'misaligned' end")
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
    "person_identity_preflight","identity_query_failed",
    "person_identity_misaligned","membership_create_authorized",
    "membership_postseed_not_one","membership_created",
    "seed_apply_started","seed_apply_failed","seed_applied",
    "allocation_preflight","allocation_query_failed",
    "allocation_not_exactly_one","fixture_verified"
))

def emit_fixture_stage(stage):
    # Only fixed source-owned labels are reported, never SQL or identities.
    if stage not in FIXTURE_STAGES:
        raise HistoricFixtureRefusal("Unrecognized historical diagnostic stage")
    print("UNI_OPS_HISTORY_FIXTURE_STAGE="+stage,flush=True)

SEED_SQL_KINDS=frozenset((
    "unique_constraint","foreign_key_constraint","check_constraint",
    "not_null_constraint","row_security","permission_denied",
    "missing_column","missing_relation","invalid_enum","data_type",
    "other_postgres_error","unclassified"
))
SEED_PROGRESS=frozenset((
    "not_located","after_one_insert_tag","after_two_insert_tags",
    "after_three_insert_tags"
))

def classify_seed_sql_failure(exc):
    """Diagnostic of captured local psql error, never an authority decision.

    The original frozen seed remains one psql invocation; no SQL retry, split
    operation, altered transaction boundary or private stderr publication.
    """
    stderr=getattr(exc,"stderr",None)
    kind="unclassified"
    if isinstance(stderr,str) and len(stderr)<=100_000:
        errors=[line.split("ERROR:",1)[1].lower()
                for line in stderr.splitlines()
                if line.count("ERROR:")==1]
        if len(errors)==1:
            msg=errors[0]
            if "duplicate key value" in msg or "violates unique constraint" in msg:
                kind="unique_constraint"
            elif "foreign key constraint" in msg:
                kind="foreign_key_constraint"
            elif "check constraint" in msg:
                kind="check_constraint"
            elif "not-null constraint" in msg or "null value in column" in msg:
                kind="not_null_constraint"
            elif "row-level security policy" in msg:
                kind="row_security"
            elif "permission denied" in msg:
                kind="permission_denied"
            elif "column " in msg and "does not exist" in msg:
                kind="missing_column"
            elif "relation " in msg and "does not exist" in msg:
                kind="missing_relation"
            elif "invalid input value for enum" in msg:
                kind="invalid_enum"
            elif "type " in msg and ("does not exist" in msg or
                                      "cannot be cast" in msg):
                kind="data_type"
            else:
                kind="other_postgres_error"
    stdout=getattr(exc,"stdout",None)
    progress="not_located"
    if isinstance(stdout,str) and len(stdout)<=100_000:
        tags=sum(line.strip()=="INSERT 0 1" for line in stdout.splitlines())
        progress={
            1:"after_one_insert_tag",
            2:"after_two_insert_tags",
            3:"after_three_insert_tags"
        }.get(tags,"not_located")
    # These outputs are a safe enum heuristic, not SQLSTATE, and do not claim
    # any INSERT committed; PostgreSQL may roll back the multi-statement call.
    if kind not in SEED_SQL_KINDS or progress not in SEED_PROGRESS:
        raise HistoricFixtureRefusal("Unreviewed seed diagnostic class")
    return kind,progress

def emit_seed_sql_failure(exc):
    kind,progress=classify_seed_sql_failure(exc)
    print("UNI_OPS_HISTORY_SEED_SQL_KIND="+kind,flush=True)
    print("UNI_OPS_HISTORY_SEED_PROGRESS="+progress,flush=True)

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
            person_memberships=self._reader(db,PERSON_MEMBERSHIP_SQL)
        except subprocess.CalledProcessError:
            emit_fixture_stage("membership_query_failed")
            raise
        if membership_count=="1" and person_memberships=="1":
            mode="existing"
            selected=adapted
            emit_fixture_stage("membership_confirmed")
            print("UNI_OPS_HISTORY_EXISTING_PERSON_MEMBERSHIP=CONFIRMED",flush=True)
        elif membership_count=="0" and person_memberships=="0":
            emit_fixture_stage("membership_absent")
            emit_fixture_stage("person_identity_preflight")
            try:
                identity=self._reader(db,IDENTITY_SQL)
            except subprocess.CalledProcessError:
                emit_fixture_stage("identity_query_failed")
                raise
            if identity!="aligned":
                emit_fixture_stage("person_identity_misaligned")
                raise HistoricFixtureRefusal("Signed canonical Person root absent or mismatched")
            # This is the unchanged four-INSERT frozen fictional companion seed.
            # Never manufacture, replace or update an existing Person membership.
            selected=seed
            mode="new"
            emit_fixture_stage("membership_create_authorized")
        else:
            # This includes inactive, rekeyed or duplicate Person memberships.
            # Never switch their identity to force a governor proof.
            emit_fixture_stage("membership_not_exactly_one")
            raise HistoricFixtureRefusal("Conflicting Person-root membership; no fixture writes")
        emit_fixture_stage("seed_apply_started")
        try:
            self._original.sql(db,selected)
        except subprocess.CalledProcessError as exc:
            emit_seed_sql_failure(exc)
            emit_fixture_stage("seed_apply_failed")
            print("UNI_OPS_HISTORY_FIXTURE_SQL_STAGE=seed_apply_failed",flush=True)
            raise
        emit_fixture_stage("seed_applied")
        if mode=="new":
            try:
                now_active=self._reader(db,MEMBERSHIP_SQL)
                now_person=self._reader(db,PERSON_MEMBERSHIP_SQL)
            except subprocess.CalledProcessError:
                emit_fixture_stage("membership_query_failed")
                raise
            if now_active!="1" or now_person!="1":
                emit_fixture_stage("membership_postseed_not_one")
                raise HistoricFixtureRefusal("Frozen member insert failed canonical readback")
            emit_fixture_stage("membership_created")
        emit_fixture_stage("allocation_preflight")
        try:
            allocation_count=self._reader(db,ALLOCATION_SQL)
        except subprocess.CalledProcessError:
            emit_fixture_stage("allocation_query_failed")
            raise
        if allocation_count!="1":
            emit_fixture_stage("allocation_not_exactly_one")
            raise HistoricFixtureRefusal("Obsolete Work allocation not bound to canonical Person")
        emit_fixture_stage("fixture_verified")
        print("UNI_OPS_HISTORY_FIXTURE_SQL_STAGE=seed_applied",flush=True)
        return None

def adapter(original,reader):
    return SimpleNamespace(sql=ExistingPersonFixture(original,reader).sql)

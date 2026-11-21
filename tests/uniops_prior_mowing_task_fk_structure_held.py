#!/usr/bin/env python3
"""HELD SOURCE ONLY: finite structural classification of unknown synthetic Task FK.

No database access is performed without an independent, owner-approved isolated
loopback clone. This helper only describes the *schema relationship* on a failed
Task insert, never a value or a specific name. It does not establish that the
failing Task was the top-level fixture Task rather than trigger-produced work.
"""
import json
import re
import subprocess

LOCAL_DB = r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres"
RECEIPT = "UNI_OPS_PRIOR_MOWING_TASK_FK_STRUCTURE="
# SOURCE COPY: corrected v3 original fictional atlas.tasks INSERT column list.
# Source: tests/uniops_preexisting_mowing_carriers_held.py at pinned #2799,
# corrected in test-only release binding #2803. This is an origin comparison,
# not evidence that a trigger or secondary INSERT provided the same fields.
FIXTURE_TASK_COLUMNS = (
    "id", "organization_id", "farm_id", "title", "task_type", "status",
    "generated_from", "generated_from_id", "origin_kind", "work_lane",
    "visibility_scope", "planned_occurrence_id", "release_policy_id",
    "released_at", "metadata",
)

class StructuralRefusal(AssertionError):
    pass

def _constraint_name(exc):
    if not isinstance(exc,subprocess.CalledProcessError) or not isinstance(exc.stderr,str):
        return None
    names=[]
    for line in exc.stderr.splitlines():
        if not re.search(r"(?i)(?:ERROR|FATAL):",line):
            continue
        m=re.search(r'(?i)\bviolates foreign key constraint\s+"([a-z0-9_]+)"',line)
        if m:
            names.append(m.group(1).lower())
    return names[0] if len(names)==1 else None

def catalog_sql(name):
    if not isinstance(name,str) or not re.fullmatch(r"tasks_[a-z0-9_]{1,100}_fkey",name):
        raise StructuralRefusal("Unknown Task FK token")
    literals=", ".join("'"+n+"'" for n in FIXTURE_TASK_COLUMNS)
    # All metadata is reduced to booleans/counts INSIDE the DB before transport;
    # even private Python never receives column, relation, constraint or trigger
    # names. No rows are selected from any application/user table.
    return f"""SELECT COALESCE((
 SELECT jsonb_build_object(
   'arity', cardinality(c.conkey),
   'fixtureListed', (
      SELECT count(*) FROM unnest(c.conkey) AS k(attnum)
      JOIN pg_catalog.pg_attribute a
        ON a.attrelid=c.conrelid AND a.attnum=k.attnum
      WHERE a.attname IN ({literals})
   ),
   'defaultedOrGenerated', (
      SELECT count(*) FROM unnest(c.conkey) AS k(attnum)
      JOIN pg_catalog.pg_attribute a
        ON a.attrelid=c.conrelid AND a.attnum=k.attnum
      LEFT JOIN pg_catalog.pg_attrdef d
        ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE d.oid IS NOT NULL OR a.attgenerated<>''
   ),
   'beforeRowInsert', EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=c.conrelid
        AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')
        AND (t.tgtype & 7)=7
   ),
   'afterRowInsert', EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=c.conrelid
        AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')
        AND (t.tgtype & 7)=5
   )
 )::text
 FROM pg_catalog.pg_constraint c
 JOIN pg_catalog.pg_class tc ON tc.oid=c.conrelid
 JOIN pg_catalog.pg_namespace nt ON nt.oid=tc.relnamespace
 WHERE current_database()='postgres'
   AND nt.nspname='atlas' AND tc.relname='tasks'
   AND c.contype='f' AND c.conname='{name}'
), 'null')"""

def _is_bool(v):
    return type(v) is bool

def classify_catalog(raw):
    if not isinstance(raw,str) or len(raw)>4096 or raw.count("\n")>1:
        return "catalog_untrusted"
    try:
        result=json.loads(raw.strip())
    except (ValueError,TypeError):
        return "catalog_untrusted"
    if not isinstance(result,dict) or set(result)!={
        'arity','fixtureListed','defaultedOrGenerated','beforeRowInsert','afterRowInsert'
    }:
        return "catalog_untrusted"
    count=result['arity']
    listed=result['fixtureListed']
    defaults=result['defaultedOrGenerated']
    if (type(count) is not int or not 1<=count<=16
        or type(listed) is not int or not 0<=listed<=count
        or type(defaults) is not int or not 0<=defaults<=count
        or not _is_bool(result['beforeRowInsert'])
        or not _is_bool(result['afterRowInsert'])):
        return "catalog_untrusted"
    arity="single" if count==1 else "composite"
    scope="all_listed" if listed==count else "none_listed" if listed==0 else "mixed_listed"
    default="auto_column" if defaults else "no_auto_column"
    before="before_present" if result['beforeRowInsert'] else "before_absent"
    after="after_present" if result['afterRowInsert'] else "after_absent"
    return "_".join((arity,scope,default,before,after))

def classify_exception(exc,db_url,sql,prior_v7):
    # The previous exact report must be unclassified before this query can run.
    if prior_v7!='catalog_unknown_column':
        return "prior_stage_mismatch"
    if not isinstance(db_url,str) or not re.fullmatch(LOCAL_DB,db_url) or not callable(sql):
        return "not_disposable"
    name=_constraint_name(exc)
    if name is None or not re.fullmatch(r"tasks_[a-z0-9_]{1,100}_fkey",name):
        return "invalid_constraint"
    try:
        raw=sql(db_url,catalog_sql(name))
    except Exception:
        return "catalog_unavailable"
    return classify_catalog(raw)

FINITE_RESULTS={
    f'{arity}_{scope}_{auto}_{before}_{after}'
    for arity in ('single','composite')
    for scope in ('all_listed','none_listed','mixed_listed')
    for auto in ('auto_column','no_auto_column')
    for before in ('before_present','before_absent')
    for after in ('after_present','after_absent')
} | {
    'prior_stage_mismatch','not_disposable','invalid_constraint',
    'catalog_unavailable','catalog_untrusted','not_reported','untrusted_report',
    'ambiguous_report'
}

def extract(receipt_text):
    if not isinstance(receipt_text,str):
        return 'untrusted_report'
    vals=[line[len(RECEIPT):] for line in receipt_text.splitlines() if line.startswith(RECEIPT)]
    if len(vals)==0:
        return 'not_reported'
    if len(vals)!=1:
        return 'ambiguous_report'
    return vals[0] if vals[0] in FINITE_RESULTS else 'untrusted_report'

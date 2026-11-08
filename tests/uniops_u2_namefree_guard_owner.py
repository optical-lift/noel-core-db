"""Test-only local PG17/GoTrue-clone classifier for an opaque governor refusal.

No raw PostgREST message, SQL function name/body, Person, token, or UUID is
returned. A matching function body is a *candidate source locus*, not proof
that it was the executing or denying function. Keep source release held.
"""
import base64
import re

_ALLOWED_FAMILIES = frozenset({
    'atlas_source', 'public_transport', 'ledger_source',
    'reality_source', 'auth_source',
})
_NONE = ('unmapped', '0000')


def classify_namefree_source(db_url, message, local_sql):
    """Return (fixed source family, safe ordinal) from a disposable local DB.

    local_sql is the existing clone-only read helper, not a production query.
    No SQL result other than this finite response is accepted.
    """
    if not isinstance(message, str) or not 0 < len(message) <= 512:
        return _NONE
    if any(ord(c) < 32 for c in message):
        return _NONE
    encoded = base64.b64encode(message.encode('utf-8')).decode('ascii')
    # A base64 literal avoids inserting an opaque (possibly quoted) PostgreSQL
    # message directly into SQL. Only the local catalog evaluates it.
    statement = """
WITH indexed AS (
 SELECT n.nspname AS source_schema,
        p.prosrc AS source_body,
        row_number() OVER (
         PARTITION BY n.nspname
         ORDER BY p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)
        ) AS safe_ordinal
 FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE n.nspname IN ('atlas','public','ledger','reality','auth')
   AND p.prokind='f' AND l.lanname IN ('plpgsql','sql')
), source_hits AS (
 SELECT source_schema, safe_ordinal
 FROM indexed
 WHERE pg_catalog.strpos(
         source_body,
         pg_catalog.quote_literal(
           pg_catalog.convert_from(pg_catalog.decode('%s','base64'),'UTF8')
         )
       ) > 0
)
SELECT CASE WHEN count(*)=1 AND max(safe_ordinal) BETWEEN 1 AND 9999
 THEN max(CASE source_schema
   WHEN 'atlas' THEN 'atlas_source'
   WHEN 'public' THEN 'public_transport'
   WHEN 'ledger' THEN 'ledger_source'
   WHEN 'reality' THEN 'reality_source'
   WHEN 'auth' THEN 'auth_source'
 END) || ':' || pg_catalog.lpad(max(safe_ordinal)::text,4,'0')
 WHEN count(*)>1 THEN 'ambiguous:0000'
 ELSE 'unmapped:0000' END
FROM source_hits;
""" % encoded
    try:
        candidate = local_sql(db_url, statement)
    except Exception:
        return ('catalog_error', '0000')
    if not isinstance(candidate, str):
        return ('catalog_error', '0000')
    if candidate in ('unmapped:0000', 'ambiguous:0000'):
        return tuple(candidate.split(':'))
    if not re.fullmatch(r'[a-z_]+:[0-9]{4}', candidate, flags=re.ASCII):
        return ('catalog_error', '0000')
    family, ordinal = candidate.split(':')
    if family not in _ALLOWED_FAMILIES or ordinal == '0000':
        return ('catalog_error', '0000')
    return family, ordinal

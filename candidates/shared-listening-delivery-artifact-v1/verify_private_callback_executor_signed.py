"""HELD signed local private-callback execution proof.

Reuses the CANONICAL existing generated-listening signed GoTrue/Storage
fixture and its genuine bearer/session/byte/replay/revocation matrix. Changes
only the two trusted SQL call sites to a fixed NOLOGIN-role, two-wrapper
transaction. Does not create new fixture users, a validation system, hosted
connection, credential, HTTP host or media publication.
"""
import json
import os
from pathlib import Path
import sys

import verify_generated_listening_storage_signed as native

ROLE = "transcript_core_private_callback_executor_v1"
_REGISTER = "transcript_core_callback_v1.private_register_verified_manuscript_original_v1"
_COMPLETE = "transcript_core_callback_v1.private_complete_verified_listening_production_v1"
_original_registration = native.trusted_signed_local_original_registration
_original_completion = native.trusted_signed_local_completion


def signed_claims(db, api, key, token):
    # Existing /auth/v1/user verifies the *real* local GoTrue bearer.
    actual = json.loads(native.ok(
        native.request(api, key, "/auth/v1/user", token=token),
        "verified private callback bearer"))
    claims = native.payload(token)
    native.check(native.uid(actual["id"]) == native.uid(claims["sub"]) and
                 native.uid(claims["session_id"]) and
                 claims["role"] == "authenticated" and
                 claims.get("is_anonymous") is False and
                 type(claims["exp"]) is int and claims["exp"] > 0,
                 "Private callback requires genuinely signed producer")
    native.check(native.sql(db,
        "select count(*) from auth.sessions where id=" +
        native.literal(claims["session_id"]) +
        " and user_id=" + native.literal(claims["sub"])) == "1",
        "Native session not persisted for private callback")
    return claims


def execute_wrapper(db, claims, function_call, expected_denial=False):
    # One exact local role and two fixed SQL functions. No arbitrary SQL,
    # bearer-derived role/function name, hosted connection, or credentials.
    statement = (
        "BEGIN;\n"
        "SET LOCAL ROLE " + ROLE + ";\n"
        "SELECT set_config('request.jwt.claims'," +
            native.literal(json.dumps(claims, separators=(",", ":"))) +
            ",true) IS NOT NULL;\n"
        "SELECT set_config('request.jwt.claim.sub'," +
            native.literal(claims["sub"]) + ",true) IS NOT NULL;\n"
        "SELECT " + function_call + "::text;\n"
        "COMMIT;\n"
    )
    run = native.subprocess.run(
        ["psql", db, "-XAt", "-v", "ON_ERROR_STOP=1", "-f", "-"],
        input=statement, capture_output=True, text=True)
    if expected_denial:
        native.check(run.returncode != 0,
                     "Invalid private callback unexpectedly succeeded")
        return None
    native.check(run.returncode == 0,
                 "Genuine signed private fixed callback failed")
    values = []
    for line in run.stdout.splitlines():
        if line.startswith('{"contractVersion"') or line.startswith('{"assetId"') or line.startswith('{"binding"'):
            values.append(json.loads(line))
    native.check(len(values) == 1,
                 "Exact one fixed private source receipt required")
    result = values[0]
    native.check(result.get("publication_approved") is False,
                 "Private callback cannot issue publication")
    return result


def trusted_wrapped_original(db, api, key, token,
                             workspace, obj_id, version, content):
    claims = signed_claims(db, api, key, token)
    sha = native.digest(content)
    call = (
        _REGISTER + "(" + native.literal(workspace) + "::uuid," +
        native.literal(obj_id) + "::uuid," + native.literal(version) + "," +
        native.literal(sha) + "," + str(len(content)) + ",'txt')"
    )
    receipt = execute_wrapper(db, claims, call)
    native.check(
        receipt["contractVersion"] == "transcript_core_verified_manuscript_original_v1" and
        receipt["workspaceId"] == workspace and
        receipt["originalSha256"] == sha and
        receipt["objectId"] == obj_id and
        receipt["objectVersion"] == version and
        receipt["sourceFormat"] == "txt",
        "Wrapped signed original receipt changed canonical source")
    asset = native.uid(receipt["assetId"])
    # Existing canonical direct helper must independently prove exact replay,
    # never create another original, and return the same authoritative asset.
    native.check(_original_registration(db, api, key, token, workspace,
                 obj_id, version, content) == asset,
                 "Wrapped original and canonical replay disagree")
    return asset


def trusted_wrapped_completion(db, api, key, token, intent,
                               expected_denial=False):
    claims = signed_claims(db, api, key, token)
    signature = [
        "p_production_id", "p_manuscript_revision_id", "p_master_ordinal",
        "p_delivery_profile_id", "p_profile_rule_version",
        "p_profile_configuration", "p_timeline_manifest", "p_evidence",
    ]
    native.check(set(intent) == set(signature),
                 "Exact canonical completion fields required")
    for name in (signature[0], signature[1], signature[3]):
        native.uid(intent[name])
    native.check(type(intent["p_master_ordinal"]) is int and
                 0 < intent["p_master_ordinal"] < 2147483648,
                 "Exact source production master required")
    call = (
        _COMPLETE + "(" +
        native.literal(intent[signature[0]]) + "::uuid," +
        native.literal(intent[signature[1]]) + "::uuid," +
        str(intent[signature[2]]) + "," +
        native.literal(intent[signature[3]]) + "::uuid," +
        native.literal(intent[signature[4]]) + "," +
        native.literal(json.dumps(intent[signature[5]], sort_keys=True)) + "::jsonb," +
        native.literal(json.dumps(intent[signature[6]], sort_keys=True)) + "::jsonb," +
        native.literal(json.dumps(intent[signature[7]], sort_keys=True)) + "::jsonb)"
    )
    result = execute_wrapper(db, claims, call, expected_denial)
    if expected_denial:
        return None
    native.check(result["contractVersion"] ==
                 "transcript_core_verified_listening_completion_v1" and
                 result["productionId"] == intent["p_production_id"] and
                 result["manuscriptRevisionId"] == intent["p_manuscript_revision_id"] and
                 result["binding"]["publication_approved"] is False,
                 "Wrapped private receipt disagrees with native source")
    # Check the existing canonical owner-only function's exact replay after
    # wrapper completion; the two paths must have identical canonical fruit.
    native.check(_original_completion(db, api, key, token, intent) == result,
                 "Wrapped private completion and canonical replay differ")
    return result


def main():
    # The original canonical main checks loopback db/API, refuses hosted env,
    # creates genuine local GoTrue sessions and actually uploads/readbacks
    # synthetic private Storage objects. This script only interposes fixed
    # NOLOGIN role calls inside its already-existing signed transactions.
    native.check(not any(os.environ.get(k) for k in (
        "NOEL_CORE_DATABASE_URL", "DATABASE_URL", "SUPABASE_DB_URL",
        "SUPABASE_ACCESS_TOKEN", "SUPABASE_SERVICE_ROLE_KEY",
        "SUPABASE_SECRET_KEY")), "No hosted credentials allowed")
    native.trusted_signed_local_original_registration = trusted_wrapped_original
    native.trusted_signed_local_completion = trusted_wrapped_completion
    native.main()
    native.check("--output" in sys.argv, "Existing canonical output required")
    output = Path(sys.argv[sys.argv.index("--output") + 1])
    native.check(output.is_file(), "Missing canonical signed proof")
    prior = output.read_text()
    native.check(prior == "PASS signed local Storage and manuscript-original proof; bounded private native completion, replay and revocation denials; no publication.\n",
                 "Original signed proof summary changed")
    output.write_text(
        "PASS signed local private callback executor: genuine GoTrue and "
        "Storage, private NOLOGIN wrapper, exact original/completion replay, "
        "viewer/outsider/anonymous/service and revoked-session denial; "
        "unpublished, clone only.\n")
    print("PASS verified signed native source through exact NOLOGIN callback wrappers",
          flush=True)


if __name__ == "__main__":
    main()

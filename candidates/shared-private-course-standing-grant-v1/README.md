# Standing private Course authoring — held authority candidate

The existing one-Course working authorization, credential, and Atlas command configuration each expire within 24 hours. This candidate adds a distinct owner-established **standing** authorization with `ends_at = NULL`. The exact Course, owner, private Site carrier, unpublished state, active Titus authoring right, `save_draft` command, and direct-save confirmation policy remain fixed and are rechecked on every call. Revocation through the released signed `shared_private_atlas_carrier_revoke_self_api_v2` remains effective. Nothing here enrolls the owner or issues a credential.

The standing bearer is a separate operator-issued 32-byte secret held only in the existing Site and Atlas server secret stores. Noel stores its hash. The existing issuer and admission path can handle null credential expiry once the working predicate includes the new standing case. A copied or exposed bearer still has only this one Course/command and remains revocable at source, but long-lived secret custody deserves explicit security review and rotation instructions.

The SQL is a candidate based on the released live function bodies. It preserves the old 24-hour branch while adding a standing branch. It updates the source status readback so a null expiration is reported as current when the credential is active. The Atlas adapter must use a separate `standing` mode that has no `COMMAND_UNTIL` environment field and still checks the same bearer digest and source admission on each request.

## Required proof before release

- Disposable production-shaped PG17 clone: old short grant still expires; standing enrollment only from a current signed owner and exact unpublished Course; another Person or Course cannot enroll or read; no second active grant; replay only for the same standing grant.
- Service credential: issuance only after the standing grant; wrong hash, duplicate active credential, revoked/suspended grant, removed Person binding, ended Titus authoring, published Course, and carrier disablement fail closed.
- Actual save: stale Unit revision, changed replay, revocation before and during the write, and independent signed nonowner denial. Confirm the saved original and receipt are the same as the existing canonical writer.
- Atlas: standing mode rejects old expiry configuration, unauthenticated requests, and missing source admission. Preserve proof and 24-hour modes unchanged.
- Site: independently signed nonowner denial and server-only secret verification before activation. No credential value in Git, chat, issue, or logs.

Generate the reviewed `shared_` migration in Noel and release it separately from the Atlas production deployment and the signed owner's actual enrollment. The candidate is not an activation request.

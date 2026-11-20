// Offline candidate-package identity contract. No I/O, shell, credentials, or workflow dispatch.
// The trusted caller must independently verify owner admission and obtain Git observations at pinned commits.
// Never interpret this return value as permission to execute candidate code or deploy.
export function inspectCandidatePackage(manifest, observed) {
  // This is an offline identity check, not authorization or a test/release receipt.
  const fail = message => { throw new Error(message); };
  const keys = (value, expected) => value !== null && typeof value === "object" &&
    !Array.isArray(value) && Object.keys(value).length === expected.length && expected.every(k => Object.hasOwn(value,k));
  const sha = value => typeof value === "string" && /^[0-9a-f]{40}$/.test(value);
  const lanes = ["atlas","titus","wnph","noel","shared"];
  const roles = ["migration","fixture","postconditions","signed_probe","trusted_helper"];
  if (!keys(manifest, ["contract","intent","lane","scope","profile","candidate_sha","controller_sha","assets"])) fail("invalid manifest fields");
  if (manifest.contract !== "noel_candidate_package_v1" || manifest.intent !== "clone_only" ||
      manifest.profile !== "local_signed_auth_rest_v1") fail("unsupported contract, intent or profile");
  if (!lanes.includes(manifest.lane) || typeof manifest.scope !== "string" ||
      !/^[a-z][a-z0-9_]{1,100}_clone_only_v1$/.test(manifest.scope) ||
      !manifest.scope.startsWith(manifest.lane + "_")) fail("invalid lane or scratch scope");
  if (!sha(manifest.candidate_sha) || !sha(manifest.controller_sha)) fail("immutable commits required");
  if (!Array.isArray(manifest.assets) || !Array.isArray(observed) ||
      manifest.assets.length < 4 || manifest.assets.length > 16 ||
      observed.length !== manifest.assets.length) fail("invalid asset cardinality");
  const seen = new Set(), counts = new Map();
  const observations = new Map();
  const fileKey = (origin,path) => origin + ":" + path;
  for (const o of observed) {
    if (!keys(o, ["origin","commit","path","blob","mode"]) ||
        !["candidate","controller"].includes(o.origin) ||
        !sha(o.commit) || !sha(o.blob) ||
        !["100644","100755"].includes(o.mode) ||
        typeof o.path !== "string") fail("invalid observed Git object");
    const k = fileKey(o.origin,o.path);
    if (observations.has(k)) fail("duplicate observation");
    observations.set(k,o);
  }
  for (const a of manifest.assets) {
    if (!keys(a,["role","origin","path","blob"]) || !roles.includes(a.role) ||
        !["candidate","controller"].includes(a.origin) || !sha(a.blob) ||
        typeof a.path !== "string" || a.path.length > 240 ||
        !/^[A-Za-z0-9_-][A-Za-z0-9_.-]*(\/[A-Za-z0-9_-][A-Za-z0-9_.-]*)+$/.test(a.path) ||
        a.path.split("/").some(p=>p === "." || p === "..")) fail("invalid asset");
    const isSql = ["migration","fixture","postconditions"].includes(a.role);
    const prefixOk = a.origin === "candidate" ? a.path.startsWith("candidates/") :
      a.path.startsWith("scripts/") || a.path.startsWith("validation/fixtures/");
    if (!prefixOk || !a.path.endsWith(isSql?".sql":".py")) fail("invalid asset path for role");
    if (a.role === "migration" && a.origin !== "candidate") fail("migration must be held candidate source");
    if (a.role === "trusted_helper" && (a.origin !== "controller" || !a.path.startsWith("scripts/"))) fail("helper must be trusted controller source");
    const k=fileKey(a.origin,a.path);
    if (seen.has(k)) fail("duplicate asset");
    seen.add(k);
    counts.set(a.role,(counts.get(a.role)||0)+1);
    const o=observations.get(k);
    if (!o || o.blob !== a.blob ||
        o.commit !== (a.origin==="candidate"?manifest.candidate_sha:manifest.controller_sha)) fail("immutable source mismatch");
  }
  for (const role of ["migration","postconditions","signed_probe"]) if (counts.get(role)!==1) fail("required unique role: "+role);
  if ((counts.get("fixture")||0)>1 || !(counts.get("trusted_helper")>0)) fail("invalid fixture or helper cardinality");
  return {contract:manifest.contract, scope:manifest.scope, lane:manifest.lane, intent:manifest.intent,
    candidate_sha:manifest.candidate_sha,controller_sha:manifest.controller_sha,
    assets_verified:seen.size, status:"source_identity_matched_only", authorization_verified:false,
    signed_proof_executed:false, release_authorized:false};
}

declare const Deno: any;

type Json = Record<string, unknown>;
type Claim = {
  job_id: string;
  attempt_id: string;
  lease_token: string;
  source_package_key: string;
  target_parent_block_key: string;
  asset_keys: string[] | null;
  proposed_reading_state: "candidate" | "usable";
  allow_usable_auto_admit: boolean;
  proposed_block_key_prefix: string | null;
  start_ordinal: number | null;
  requested_reconstruction_key: string | null;
};

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

async function rpc(name: string, body: Json) {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) throw new Error("Supabase runtime credentials unavailable");

  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${name} ${response.status}: ${text.slice(0, 2000)}`);
  }
  return text ? JSON.parse(text) : null;
}

async function authenticateRunner(req: Request) {
  const token = (req.headers.get("x-wnph-runner-token") ?? "").trim();
  if (!token) return false;
  const valid = await rpc("wnph_validate_reconstruction_runner_token_v1", { p_token: token });
  return valid === true;
}

async function invokeReconstructor(claim: Claim) {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) throw new Error("Supabase runtime credentials unavailable");

  const body: Json = {
    source_package_key: claim.source_package_key,
    target_parent_block_key: claim.target_parent_block_key,
    proposed_reading_state: claim.proposed_reading_state,
    allow_usable_auto_admit: claim.allow_usable_auto_admit,
    dry_run: false,
  };
  if (claim.asset_keys) body.asset_keys = claim.asset_keys;
  if (claim.proposed_block_key_prefix) body.proposed_block_key_prefix = claim.proposed_block_key_prefix;
  if (claim.start_ordinal !== null) body.start_ordinal = claim.start_ordinal;
  if (claim.requested_reconstruction_key) body.reconstruction_key = claim.requested_reconstruction_key;

  const response = await fetch(`${base}/functions/v1/wnph-reading-reconstructor`, {
    method: "POST",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  let parsed: unknown = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = { raw_response: text.slice(0, 8000) };
  }

  return {
    ok: response.ok,
    status: response.status,
    body: parsed,
  };
}

async function finishJob(
  claim: Claim,
  success: boolean,
  retryable: boolean,
  httpStatus: number | null,
  responseBody: unknown,
  errorText: string | null,
) {
  return await rpc("wnph_finish_reconstruction_job_v1", {
    p_job_id: claim.job_id,
    p_attempt_id: claim.attempt_id,
    p_lease_token: claim.lease_token,
    p_success: success,
    p_retryable: retryable,
    p_http_status: httpStatus,
    p_response: responseBody ?? {},
    p_error: errorText,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse(405, { error: "POST required" });

  try {
    if (!(await authenticateRunner(req))) {
      return jsonResponse(403, { error: "Invalid WNPH reconstruction runner credential" });
    }
  } catch (error) {
    return jsonResponse(503, {
      error: "WNPH reconstruction runner authentication unavailable",
      detail: error instanceof Error ? error.message : String(error),
    });
  }

  let requestedMax = 1;
  try {
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const parsed = Number(body.max_jobs ?? 1);
    if (Number.isFinite(parsed)) requestedMax = Math.trunc(parsed);
  } catch {
    requestedMax = 1;
  }
  const maxJobs = Math.max(1, Math.min(5, requestedMax));
  const invocationId = crypto.randomUUID();
  const runnerId = `wnph-reading-reconstruction-runner:v1:${invocationId}`;
  const results: unknown[] = [];

  for (let i = 0; i < maxJobs; i++) {
    let claim: Claim | null = null;
    try {
      claim = await rpc("wnph_claim_reconstruction_job_v1", {
        p_runner_id: runnerId,
        p_lease_seconds: 240,
      }) as Claim | null;
    } catch (error) {
      return jsonResponse(503, {
        ok: false,
        invocation_id: invocationId,
        processed_jobs: results.length,
        results,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    if (!claim?.job_id) break;

    try {
      const worker = await invokeReconstructor(claim);
      if (worker.ok) {
        const finished = await finishJob(claim, true, false, worker.status, worker.body, null);
        results.push({
          job_id: claim.job_id,
          attempt_id: claim.attempt_id,
          outcome: "succeeded",
          worker_status: worker.status,
          database: finished,
        });
      } else {
        const retryable = worker.status >= 500 || worker.status === 429;
        const errorText = `wnph-reading-reconstructor returned HTTP ${worker.status}`;
        const finished = await finishJob(claim, false, retryable, worker.status, worker.body, errorText);
        results.push({
          job_id: claim.job_id,
          attempt_id: claim.attempt_id,
          outcome: retryable ? "retry_or_fail" : "failed",
          worker_status: worker.status,
          database: finished,
        });
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      try {
        const finished = await finishJob(claim, false, true, null, {}, message);
        results.push({
          job_id: claim.job_id,
          attempt_id: claim.attempt_id,
          outcome: "retry_or_fail",
          error: message,
          database: finished,
        });
      } catch (finishError) {
        results.push({
          job_id: claim.job_id,
          attempt_id: claim.attempt_id,
          outcome: "lease_will_recover",
          error: message,
          finish_error: finishError instanceof Error ? finishError.message : String(finishError),
        });
      }
    }
  }

  return jsonResponse(200, {
    ok: true,
    runner: "wnph-reading-reconstruction-runner",
    runner_version: 1,
    invocation_id: invocationId,
    processed_jobs: results.length,
    results,
  });
});

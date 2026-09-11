import "jsr:@supabase/functions-js/edge-runtime.d.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY") ?? "";
const GROQ_API_BASE = "https://api.groq.com/openai/v1";
const PROVIDER_KEY = "groq";
const TRANSCRIPTION_MODEL = "whisper-large-v3-turbo";
const INTERPRETATION_MODEL = "openai/gpt-oss-20b";

const WORK_AREAS = [
  "people","work","time","money","things_places","systems_evidence",
  "access_authority","handoffs_completion","structure_mismatch","other_unresolved",
] as const;

type Json = Record<string, unknown>;
type AccessPacket = {
  ok?: boolean;
  artifactId?: string;
  implementationCaseId?: string;
  implementationThreadId?: string;
};
type BeginTranscript = {
  ok?: boolean;
  shouldTranscribe?: boolean;
  reason?: string;
  artifactId?: string;
  implementationCaseId?: string;
  implementationThreadId?: string;
  transcriptId?: string;
  transcriptText?: string;
  storageBucket?: string;
  storagePath?: string;
  originalFilename?: string | null;
  mimeType?: string | null;
  byteSize?: number;
  durationMs?: number | null;
  startingLabel?: string | null;
};
type BeginInterpretation = {
  ok?: boolean;
  shouldInterpret?: boolean;
  reason?: string;
  interpretationId?: string;
  transcriptText?: string;
};
type Candidate = {
  candidateKind: "finding" | "question";
  workArea: typeof WORK_AREAS[number];
  statement: string;
  evidenceExcerpt: string;
  confidence: number;
};

type Extraction = { summary: string; candidates: Candidate[] };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function rpc<T>(functionName: string, args: Json, authorization: string, apikey: string): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(functionName)}`, {
    method: "POST",
    headers: {
      apikey,
      Authorization: authorization,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${functionName} failed (${response.status}): ${text.slice(0, 1000)}`);
  return (text ? JSON.parse(text) : null) as T;
}

async function serviceRpc<T>(functionName: string, args: Json): Promise<T> {
  return rpc<T>(functionName, args, `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, SUPABASE_SERVICE_ROLE_KEY);
}

async function markFailed(artifactId: string, stage: string, error: unknown, retryable = true) {
  const detail = error instanceof Error ? error.message : String(error ?? "Processing failed.");
  try {
    await serviceRpc("mark_implementation_artifact_processing_failed_service_v1", {
      p_artifact_id: artifactId,
      p_stage: stage,
      p_error_detail: detail.slice(0, 4000),
      p_retryable: retryable,
      p_metadata: {
        processor: "atlas-implementation-artifact-processor",
        provider: PROVIDER_KEY,
        model: stage === "interpretation" ? INTERPRETATION_MODEL : TRANSCRIPTION_MODEL,
        paidFallback: false,
      },
    });
  } catch (markError) {
    console.error("Could not persist implementation artifact failure", markError);
  }
}

function safeFilename(packet: BeginTranscript) {
  const fallback = packet.storagePath?.split("/").pop() || "recording.webm";
  const supplied = packet.originalFilename?.trim();
  const base = supplied && supplied.length <= 180 ? supplied : fallback;
  if (/\.[a-z0-9]{2,5}$/i.test(base)) return base;
  const extension = packet.mimeType === "audio/mp4" || packet.mimeType === "audio/x-m4a" ? ".m4a"
    : packet.mimeType === "audio/mpeg" ? ".mp3"
    : packet.mimeType === "audio/ogg" ? ".ogg"
    : packet.mimeType === "audio/wav" || packet.mimeType === "audio/x-wav" ? ".wav"
    : packet.mimeType === "audio/aac" ? ".aac" : ".webm";
  return `${base}${extension}`;
}

async function downloadArtifact(packet: BeginTranscript) {
  if (!packet.storageBucket || !packet.storagePath) throw new Error("Artifact storage location is missing.");
  const encodedPath = packet.storagePath.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/${encodeURIComponent(packet.storageBucket)}/${encodedPath}`, {
    headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` },
  });
  if (!response.ok) throw new Error(`Artifact download failed (${response.status}): ${(await response.text()).slice(0, 500)}`);
  return await response.blob();
}

async function transcribe(packet: BeginTranscript, audio: Blob) {
  const form = new FormData();
  form.append("model", TRANSCRIPTION_MODEL);
  form.append("response_format", "json");
  form.append("file", new File([audio], safeFilename(packet), { type: packet.mimeType || audio.type || "audio/webm" }));

  const response = await fetch(`${GROQ_API_BASE}/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${GROQ_API_KEY}` },
    body: form,
  });
  const text = await response.text();
  if (!response.ok) {
    const retryAfter = response.headers.get("retry-after");
    throw new Error(`Groq transcription failed (${response.status})${retryAfter ? `; retry after ${retryAfter}s` : ""}: ${text.slice(0, 1000)}`);
  }

  const body = JSON.parse(text) as { text?: string; language?: string; x_groq?: { id?: string } };
  const transcript = body.text?.trim() ?? "";
  if (!transcript) throw new Error("Groq returned an empty transcript.");
  return {
    transcript,
    language: body.language ?? null,
    requestId: response.headers.get("x-request-id") ?? body.x_groq?.id ?? null,
  };
}

const extractionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "candidates"],
  properties: {
    summary: { type: "string" },
    candidates: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["candidateKind", "workArea", "statement", "evidenceExcerpt", "confidence"],
        properties: {
          candidateKind: { type: "string", enum: ["finding", "question"] },
          workArea: { type: "string", enum: WORK_AREAS },
          statement: { type: "string" },
          evidenceExcerpt: { type: "string" },
          confidence: { type: "number" },
        },
      },
    },
  },
};

async function interpret(transcript: string, startingLabel?: string | null) {
  const systemPrompt = [
    "You extract implementation candidates from a human-supplied Atlas onboarding transcript.",
    "The transcript is evidence of what the speaker said, not proof that every proposition is established organizational truth.",
    "Return finding candidates for explicit operational assertions worth review and question candidates only where the transcript exposes a material unresolved fact needed for implementation.",
    "Do not invent names, roles, policies, amounts, schedules, relationships, or facts.",
    "Every evidenceExcerpt must be copied VERBATIM as one contiguous substring from the transcript. Do not normalize punctuation, spelling, capitalization, or filler words inside evidenceExcerpt.",
    "Keep statements concise and faithful. Return no more than 50 candidates.",
    "A practitioner, not the model, decides whether a candidate enters implementation work.",
  ].join(" ");

  const response = await fetch(`${GROQ_API_BASE}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${GROQ_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: INTERPRETATION_MODEL,
      reasoning_effort: "low",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: `Organization/starting label: ${startingLabel || "unknown"}\n\nTRANSCRIPT\n${transcript}` },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "atlas_implementation_intake",
          strict: true,
          schema: extractionSchema,
        },
      },
    }),
  });

  const raw = await response.text();
  if (!response.ok) {
    const retryAfter = response.headers.get("retry-after");
    throw new Error(`Groq interpretation failed (${response.status})${retryAfter ? `; retry after ${retryAfter}s` : ""}: ${raw.slice(0, 1000)}`);
  }

  const body = JSON.parse(raw) as {
    choices?: Array<{ message?: { content?: string | null } }>;
    x_groq?: { id?: string };
  };
  const outputText = body.choices?.[0]?.message?.content?.trim() ?? "";
  if (!outputText) throw new Error("Groq returned no structured interpretation text.");

  const parsed = JSON.parse(outputText) as Extraction;
  const candidates = Array.isArray(parsed.candidates)
    ? parsed.candidates.filter((candidate) =>
      candidate && (candidate.candidateKind === "finding" || candidate.candidateKind === "question") &&
      WORK_AREAS.includes(candidate.workArea) &&
      typeof candidate.statement === "string" && candidate.statement.trim().length > 0 && candidate.statement.length <= 4000 &&
      typeof candidate.evidenceExcerpt === "string" && candidate.evidenceExcerpt.length > 0 && candidate.evidenceExcerpt.length <= 1200 && transcript.includes(candidate.evidenceExcerpt) &&
      typeof candidate.confidence === "number" && candidate.confidence >= 0 && candidate.confidence <= 1
    ).slice(0, 50)
    : [];

  return {
    summary: typeof parsed.summary === "string" ? parsed.summary.slice(0, 2000) : "",
    candidates,
    requestId: response.headers.get("x-request-id") ?? body.x_groq?.id ?? null,
  };
}

async function processArtifact(artifactId: string) {
  let stage: "configuration" | "download" | "transcription" | "interpretation" = "configuration";
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("Supabase processor configuration is unavailable.");
    if (!GROQ_API_KEY) throw new Error("GROQ_API_KEY is not configured for the Atlas implementation artifact processor.");

    const begin = await serviceRpc<BeginTranscript>("begin_implementation_artifact_transcription_service_v1", { p_artifact_id: artifactId });
    if (!begin.ok) throw new Error("Atlas could not begin artifact transcription.");
    if (begin.reason === "already_processing") return;

    let transcript = begin.transcriptText?.trim() ?? "";
    let transcriptId = begin.transcriptId ?? "";

    if (begin.shouldTranscribe) {
      stage = "download";
      const audio = await downloadArtifact(begin);
      stage = "transcription";
      const result = await transcribe(begin, audio);
      transcript = result.transcript;
      if (!transcriptId) throw new Error("Transcript record identity is missing.");
      await serviceRpc("complete_implementation_artifact_transcript_service_v1", {
        p_artifact_id: artifactId,
        p_transcript_id: transcriptId,
        p_transcript_text: transcript,
        p_language_code: result.language,
        p_provider_key: PROVIDER_KEY,
        p_model_key: TRANSCRIPTION_MODEL,
        p_metadata: {
          groqRequestId: result.requestId,
          source: "atlas-implementation-artifact-processor",
          paidFallback: false,
        },
      });
    }

    if (!transcript || !transcriptId) throw new Error("Ready transcript is unavailable for interpretation.");

    stage = "interpretation";
    const interpretation = await serviceRpc<BeginInterpretation>("begin_implementation_artifact_interpretation_service_v1", {
      p_artifact_id: artifactId,
      p_transcript_id: transcriptId,
      p_provider_key: PROVIDER_KEY,
      p_model_key: INTERPRETATION_MODEL,
    });
    if (!interpretation.ok || interpretation.reason === "already_processing" || interpretation.reason === "interpretation_ready") return;
    if (!interpretation.shouldInterpret || !interpretation.interpretationId) return;

    const extracted = await interpret(transcript, begin.startingLabel);
    await serviceRpc("complete_implementation_artifact_interpretation_service_v1", {
      p_interpretation_id: interpretation.interpretationId,
      p_summary: extracted.summary,
      p_candidates: extracted.candidates,
      p_metadata: {
        groqRequestId: extracted.requestId,
        source: "atlas-implementation-artifact-processor",
        exactExcerptFilter: true,
        paidFallback: false,
      },
    });
  } catch (error) {
    console.error("Atlas implementation artifact processing failed", {
      artifactId,
      stage,
      error: error instanceof Error ? error.message : String(error),
    });
    await markFailed(artifactId, stage, error, true);
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Processor configuration is unavailable." }, 503);

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Authentication required." }, 401);

  let artifactId = "";
  try {
    const body = await request.json() as { artifactId?: string };
    artifactId = body.artifactId?.trim() ?? "";
  } catch {
    return json({ error: "Valid JSON body required." }, 400);
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(artifactId)) return json({ error: "Artifact reference is invalid." }, 400);

  try {
    const access = await rpc<AccessPacket>("implementation_artifact_access_self_api_v1", { p_artifact_id: artifactId }, authorization, SUPABASE_ANON_KEY);
    if (!access.ok || access.artifactId !== artifactId) return json({ error: "That artifact is not available to this Atlas account." }, 403);
  } catch (error) {
    console.error("Implementation artifact processor authorization failed", error);
    return json({ error: "That artifact is not available to this Atlas account." }, 403);
  }

  EdgeRuntime.waitUntil(processArtifact(artifactId));
  return json({ ok: true, artifactId, processingQueued: true }, 202);
});

import { PDFDocument } from "npm:pdf-lib@1.17.1";

type Json = Record<string, unknown>;

type NormalizedSurface = {
  asset_key: string;
  storage_uri?: string;
  media_type?: string;
  source_locator: Json;
  metadata?: Json;
  observations?: Json[];
};

const MAX_MANIFEST_BYTES = 8_000_000;
const MAX_PDF_BYTES = 40_000_000;
const MAX_OCR_BYTES = 2_000_000;
const MAX_SURFACES = 5000;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function decodeJwtPayload(token: string): Json | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const normalized = part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=");
    return JSON.parse(atob(normalized));
  } catch {
    return null;
  }
}

async function sha256Hex(input: string | Uint8Array) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

function asArray<T = unknown>(v: unknown): T[] {
  return Array.isArray(v) ? v as T[] : v == null ? [] : [v as T];
}

function labelText(label: unknown): string | null {
  if (typeof label === "string") return label;
  if (!label || typeof label !== "object") return null;
  const o = label as Record<string, unknown>;
  for (const key of ["en", "none", "@value"]) {
    const v = o[key];
    if (typeof v === "string") return v;
    if (Array.isArray(v) && typeof v[0] === "string") return v[0];
  }
  for (const v of Object.values(o)) {
    if (typeof v === "string") return v;
    if (Array.isArray(v) && typeof v[0] === "string") return v[0];
  }
  return null;
}

function serviceId(service: unknown): string | null {
  for (const s of asArray<Record<string, unknown>>(service)) {
    if (!s || typeof s !== "object") continue;
    const id = s.id ?? s["@id"];
    if (typeof id === "string" && id) return id.replace(/\/$/, "");
  }
  return null;
}

function findV3Image(canvas: Record<string, unknown>) {
  for (const page of asArray<Record<string, unknown>>(canvas.items)) {
    for (const ann of asArray<Record<string, unknown>>(page?.items)) {
      for (const body of asArray<Record<string, unknown>>(ann?.body)) {
        if (!body || typeof body !== "object") continue;
        const type = body.type;
        const format = body.format;
        if (type === "Image" || (typeof format === "string" && format.startsWith("image/"))) {
          const id = body.id;
          return {
            image_uri: typeof id === "string" ? id : null,
            media_type: typeof format === "string" ? format : "image/jpeg",
            service_uri: serviceId(body.service),
          };
        }
      }
    }
  }
  return { image_uri: null, media_type: "image/jpeg", service_uri: null };
}

function findV2Image(canvas: Record<string, unknown>) {
  for (const ann of asArray<Record<string, unknown>>(canvas.images)) {
    const body = ann?.resource as Record<string, unknown> | undefined;
    if (!body) continue;
    const id = body["@id"] ?? body.id;
    const format = body.format;
    return {
      image_uri: typeof id === "string" ? id : null,
      media_type: typeof format === "string" ? format : "image/jpeg",
      service_uri: serviceId(body.service),
    };
  }
  return { image_uri: null, media_type: "image/jpeg", service_uri: null };
}

function seeAlsoRefs(resource: Record<string, unknown>): { uri: string; format: string }[] {
  const out: { uri: string; format: string }[] = [];
  for (const ref of asArray<Record<string, unknown>>(resource.seeAlso)) {
    if (!ref || typeof ref !== "object") continue;
    const uri = ref.id ?? ref["@id"];
    const format = ref.format;
    if (typeof uri === "string" && typeof format === "string") out.push({ uri, format });
  }
  return out;
}

function embeddedTextObservationsV3(canvas: Record<string, unknown>, manifestUri: string): Json[] {
  const out: Json[] = [];
  let ordinal = 0;
  for (const annPage of asArray<Record<string, unknown>>(canvas.annotations)) {
    for (const ann of asArray<Record<string, unknown>>(annPage?.items)) {
      const motivation = ann?.motivation;
      for (const body of asArray<Record<string, unknown>>(ann?.body)) {
        if (!body || typeof body !== "object") continue;
        const value = body.value;
        const type = body.type;
        if (type !== "TextualBody" || typeof value !== "string" || !value.trim()) continue;
        ordinal += 1;
        const obs: Json = {
          observation_key: `iiif-text:${String(ordinal).padStart(5, "0")}`,
          observation_kind: "region",
          ordinal,
          text_candidate: value,
          coordinate_unit: "surface",
          derivation_method: "iiif_presentation_textual_annotation_import",
          source_format: "iiif_textual_body",
          processor: { provider: "iiif_manifest", engine: "textual_annotation", version: "presentation_3" },
          external_locator: { manifest_uri: manifestUri, annotation_id: ann?.id ?? null, motivation: motivation ?? null },
          metadata: { canonical_text_asserted: false },
        };
        const target = ann?.target;
        if (typeof target === "string") {
          const m = target.match(/#xywh=(?:pixel:)?([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+)/);
          if (m) Object.assign(obs, { coordinate_unit: "pixel", x: Number(m[1]), y: Number(m[2]), width: Number(m[3]), height: Number(m[4]) });
        }
        out.push(obs);
      }
    }
  }
  return out;
}

function decodeXml(s: string) {
  return s.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}

function textFromAlto(xml: string) {
  const words: string[] = [];
  const re = /<String\b[^>]*\bCONTENT=(?:"([^"]*)"|'([^']*)')[^>]*>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) words.push(decodeXml(m[1] ?? m[2] ?? ""));
  return words.join(" ").replace(/\s+/g, " ").trim();
}

function textFromPageXml(xml: string) {
  const lines: string[] = [];
  const re = /<Unicode>([\s\S]*?)<\/Unicode>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) {
    const t = decodeXml((m[1] ?? "").replace(/<[^>]+>/g, "")).trim();
    if (t) lines.push(t);
  }
  return lines.join("\n");
}

async function fetchTextLimited(uri: string, maxBytes: number) {
  const r = await fetch(uri, { headers: { "user-agent": "WNPH-source-intake/1.0", accept: "application/xml,text/xml,text/plain,*/*" } });
  if (!r.ok) throw new Error(`OCR upstream ${r.status} for ${uri}`);
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.byteLength > maxBytes) throw new Error(`OCR upstream too large (${bytes.byteLength}) for ${uri}`);
  return new TextDecoder("utf-8").decode(bytes);
}

async function attachExternalOcr(surfaces: NormalizedSurface[]) {
  const jobs: { surface: NormalizedSurface; ref: { uri: string; format: string } }[] = [];
  for (const surface of surfaces) {
    const refs = (surface.metadata?.upstream_text_refs ?? []) as unknown;
    for (const ref of asArray<{ uri: string; format: string }>(refs)) {
      if (ref?.uri && ref?.format) jobs.push({ surface, ref });
    }
  }
  if (jobs.length > 1000) throw new Error(`too many external OCR resources (${jobs.length}); max 1000 per intake`);
  let cursor = 0;
  const workers = Array.from({ length: Math.min(8, jobs.length) }, async () => {
    while (cursor < jobs.length) {
      const job = jobs[cursor++];
      const xml = await fetchTextLimited(job.ref.uri, MAX_OCR_BYTES);
      const f = job.ref.format.toLowerCase();
      let text = "";
      let sourceFormat = "xml";
      if (f.includes("alto") || /alto/i.test(job.ref.uri)) {
        text = textFromAlto(xml); sourceFormat = "alto_xml";
      } else if (f.includes("page") || /pagexml|page\.xml/i.test(job.ref.uri)) {
        text = textFromPageXml(xml); sourceFormat = "page_xml";
      } else {
        continue;
      }
      if (!text) throw new Error(`recognized OCR resource produced no text: ${job.ref.uri}`);
      const keyHash = (await sha256Hex(job.ref.uri)).slice(0, 16);
      job.surface.observations ??= [];
      job.surface.observations.push({
        observation_key: `upstream-ocr:${keyHash}`,
        observation_kind: "page_text",
        ordinal: 0,
        text_candidate: text,
        coordinate_unit: "surface",
        derivation_method: "external_ocr_resource_import_without_semantic_normalization",
        source_format: sourceFormat,
        processor: { provider: new URL(job.ref.uri).hostname, engine: "upstream_ocr", version: "unknown" },
        external_locator: { uri: job.ref.uri },
        metadata: { canonical_text_asserted: false },
      });
    }
  });
  await Promise.all(workers);
}

async function normalizeIiif(manifestUri: string, importExternalOcr: boolean): Promise<{ sourceRef: string; surfaces: NormalizedSurface[]; metadata: Json }> {
  const r = await fetch(manifestUri, { headers: { accept: "application/ld+json, application/json", "user-agent": "WNPH-source-intake/1.0" } });
  if (!r.ok) throw new Error(`manifest upstream ${r.status}`);
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.byteLength > MAX_MANIFEST_BYTES) throw new Error(`manifest too large: ${bytes.byteLength}`);
  const manifest = JSON.parse(new TextDecoder("utf-8").decode(bytes)) as Record<string, unknown>;
  const isV3 = manifest.type === "Manifest" && Array.isArray(manifest.items);
  const canvases: Record<string, unknown>[] = isV3
    ? asArray<Record<string, unknown>>(manifest.items)
    : asArray<Record<string, unknown>>(((asArray<Record<string, unknown>>(manifest.sequences)[0] ?? {}).canvases));
  if (!canvases.length) throw new Error("IIIF manifest contains no canvases");
  if (canvases.length > MAX_SURFACES) throw new Error(`manifest has ${canvases.length} canvases; max ${MAX_SURFACES}`);
  const surfaces: NormalizedSurface[] = [];
  for (let i = 0; i < canvases.length; i++) {
    const canvas = canvases[i];
    const canvasId = String(canvas.id ?? canvas["@id"] ?? `${manifestUri}#canvas-${i + 1}`);
    const image = isV3 ? findV3Image(canvas) : findV2Image(canvas);
    if (!image.image_uri && !image.service_uri) throw new Error(`canvas ${i + 1} has no image body/service`);
    const hash = (await sha256Hex(canvasId)).slice(0, 20);
    const refs = [...seeAlsoRefs(manifest), ...seeAlsoRefs(canvas)].filter((ref) => {
      const x = `${ref.format} ${ref.uri}`.toLowerCase();
      return x.includes("alto") || x.includes("page+xml") || x.includes("pagexml") || x.includes("page.xml");
    });
    const locator: Json = {
      iiif_manifest_uri: manifestUri,
      iiif_canvas_uri: canvasId,
      image_uri: image.image_uri,
      iiif_image_service_uri: image.service_uri,
      sequence_index: i + 1,
      pixel_width: typeof canvas.width === "number" ? canvas.width : null,
      pixel_height: typeof canvas.height === "number" ? canvas.height : null,
      label: labelText(canvas.label),
    };
    if (refs.length) locator.upstream_text_uris = refs.map((x) => x.uri);
    const surface: NormalizedSurface = {
      asset_key: `iiif:canvas:${hash}`,
      media_type: image.media_type,
      source_locator: locator,
      metadata: { addressing_standard: `iiif_presentation_${isV3 ? "3" : "2"}`, remote_custody: true, byte_copy_required: false, upstream_text_refs: refs },
      observations: isV3 ? embeddedTextObservationsV3(canvas, manifestUri) : [],
    };
    surfaces.push(surface);
  }
  if (importExternalOcr) await attachExternalOcr(surfaces);
  return {
    sourceRef: manifestUri,
    surfaces,
    metadata: { manifest_sha256: await sha256Hex(bytes), presentation_version: isV3 ? 3 : 2, canvas_count: surfaces.length, external_ocr_imported: importExternalOcr },
  };
}

async function normalizePdf(pdfUri: string): Promise<{ sourceRef: string; surfaces: NormalizedSurface[]; metadata: Json }> {
  const r = await fetch(pdfUri, { headers: { "user-agent": "WNPH-source-intake/1.0", accept: "application/pdf" } });
  if (!r.ok) throw new Error(`PDF upstream ${r.status}`);
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.byteLength > MAX_PDF_BYTES) throw new Error(`PDF too large: ${bytes.byteLength}`);
  const pdf = await PDFDocument.load(bytes, { updateMetadata: false });
  const pages = pdf.getPages();
  if (!pages.length || pages.length > MAX_SURFACES) throw new Error(`PDF page count ${pages.length} outside supported range`);
  const sourceHash = (await sha256Hex(pdfUri)).slice(0, 16);
  const surfaces = pages.map((page, i): NormalizedSurface => ({
    asset_key: `pdf:${sourceHash}:page:${String(i + 1).padStart(5, "0")}`,
    storage_uri: pdfUri,
    media_type: "application/pdf",
    source_locator: { pdf_uri: pdfUri, pdf_page: i + 1, pdf_page_width_points: page.getWidth(), pdf_page_height_points: page.getHeight() },
    metadata: { remote_custody: true, byte_copy_required: false, addressing_standard: "pdf_page_index", needs_raster_or_direct_pdf_ocr: true },
  }));
  return { sourceRef: pdfUri, surfaces, metadata: { pdf_sha256: await sha256Hex(bytes), pdf_bytes: bytes.byteLength, page_count: pages.length } };
}

function normalizeImageList(input: Record<string, unknown>): { sourceRef: string; surfaces: NormalizedSurface[]; metadata: Json } {
  const sourceRef = String(input.source_ref ?? "").trim();
  if (!sourceRef) throw new Error("image/photo list requires source_ref");
  const raw = asArray<Record<string, unknown>>(input.surfaces);
  if (!raw.length || raw.length > MAX_SURFACES) throw new Error(`surface count ${raw.length} outside supported range`);
  const surfaces = raw.map((s, i): NormalizedSurface => {
    const imageUri = typeof s.image_uri === "string" ? s.image_uri : null;
    const storageUri = typeof s.storage_uri === "string" ? s.storage_uri : undefined;
    const serviceUri = typeof s.iiif_image_service_uri === "string" ? s.iiif_image_service_uri : null;
    if (!imageUri && !storageUri && !serviceUri) throw new Error(`surface ${i + 1} lacks image_uri, storage_uri or iiif_image_service_uri`);
    const key = typeof s.asset_key === "string" && s.asset_key.trim() ? s.asset_key.trim() : `image:${String(i + 1).padStart(5, "0")}`;
    return {
      asset_key: key,
      storage_uri: storageUri,
      media_type: typeof s.media_type === "string" ? s.media_type : "image/jpeg",
      source_locator: {
        ...(s.source_locator && typeof s.source_locator === "object" ? s.source_locator as Json : {}),
        image_uri: imageUri,
        iiif_image_service_uri: serviceUri,
        sequence_index: i + 1,
      },
      metadata: s.metadata && typeof s.metadata === "object" ? s.metadata as Json : {},
      observations: Array.isArray(s.observations) ? s.observations as Json[] : [],
    };
  });
  return { sourceRef, surfaces, metadata: { surface_count: surfaces.length } };
}

async function callAtomicRpc(packageKey: string, inputKind: string, sourceRef: string, surfaces: NormalizedSurface[], batchMetadata: Json) {
  const base = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !serviceKey) throw new Error("Supabase runtime credentials unavailable");
  const r = await fetch(`${base}/rest/v1/rpc/wnph_ingest_source_surface_batch_v1`, {
    method: "POST",
    headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ p_source_package_key: packageKey, p_input_kind: inputKind, p_source_ref: sourceRef, p_surfaces: surfaces, p_batch_metadata: batchMetadata }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`atomic intake RPC ${r.status}: ${text.slice(0, 2000)}`);
  return text ? JSON.parse(text) : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "POST required" });
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  const claims = decodeJwtPayload(token);
  if (!claims || claims.role !== "service_role") return json(403, { error: "WNPH source intake currently requires service-role authorization" });

  try {
    const body = await req.json() as Record<string, unknown>;
    const sourcePackageKey = String(body.source_package_key ?? "").trim();
    if (!sourcePackageKey) return json(400, { error: "source_package_key is required" });
    const input = body.input as Record<string, unknown> | undefined;
    if (!input || typeof input !== "object") return json(400, { error: "input object is required" });
    const kind = String(input.kind ?? "");
    let normalized: { sourceRef: string; surfaces: NormalizedSurface[]; metadata: Json };
    let rpcKind: string;
    if (kind === "iiif_manifest") {
      const uri = String(input.url ?? "").trim();
      if (!uri) return json(400, { error: "IIIF input requires url" });
      normalized = await normalizeIiif(uri, input.import_external_ocr === true);
      rpcKind = "iiif_manifest";
    } else if (kind === "pdf") {
      const uri = String(input.url ?? "").trim();
      if (!uri) return json(400, { error: "PDF input requires url" });
      normalized = await normalizePdf(uri);
      rpcKind = "pdf_pages";
    } else if (kind === "image_list" || kind === "photo_batch") {
      normalized = normalizeImageList(input);
      rpcKind = kind;
    } else {
      return json(400, { error: `unsupported input kind ${kind}` });
    }

    const fingerprint = await sha256Hex(JSON.stringify({ source_package_key: sourcePackageKey, input_kind: rpcKind, source_ref: normalized.sourceRef, surfaces: normalized.surfaces }));
    const batchMetadata: Json = { ...normalized.metadata, intake_adapter: "wnph-source-batch-intake", adapter_version: 1, normalized_batch_sha256: fingerprint };
    if (body.dry_run === true) return json(200, { dry_run: true, source_package_key: sourcePackageKey, input_kind: rpcKind, source_ref: normalized.sourceRef, batch_metadata: batchMetadata, surfaces: normalized.surfaces });
    const result = await callAtomicRpc(sourcePackageKey, rpcKind, normalized.sourceRef, normalized.surfaces, batchMetadata);
    return json(200, { ok: true, batch_sha256: fingerprint, normalization: normalized.metadata, database: result });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});

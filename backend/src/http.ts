// Responses, errors, security headers, body reading with limits (docs/CLOUDFLARE_BACKEND.md §2.10, §3.1).

export const MAX_BODY_BYTES = 65_536;
export const MAX_PUSH_BODY_BYTES = 1_048_576;

const SECURITY_HEADERS: Record<string, string> = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-KB-API": "1",
  "Strict-Transport-Security": "max-age=31536000",
};

const HTML_CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/** Per-request context shared by handlers. */
export interface RequestInfo {
  requestId: string;
  /** Error code of the response (for the log line). */
  errorCode?: string;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly description: string,
    readonly extra: Record<string, unknown> = {},
    readonly headers: Record<string, string> = {},
  ) {
    super(`${status} ${code}: ${description}`);
  }
}

export function withSecurityHeaders(headers: Headers, requestId: string): Headers {
  for (const [k, v] of Object.entries(SECURITY_HEADERS)) headers.set(k, v);
  headers.set("X-Request-Id", requestId);
  return headers;
}

export function json(info: RequestInfo, body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(body), { status, headers: withSecurityHeaders(headers, info.requestId) });
}

export function errorResponse(info: RequestInfo, err: ApiError): Response {
  info.errorCode = err.code;
  const headers: Record<string, string> = { ...err.headers };
  if (err.status === 401) headers["WWW-Authenticate"] = `Bearer error="${err.code}"`;
  return json(
    info,
    { error: err.code, error_description: err.description, request_id: info.requestId, ...err.extra },
    err.status,
    headers,
  );
}

export function noContent(info: RequestInfo): Response {
  return new Response(null, { status: 204, headers: withSecurityHeaders(new Headers(), info.requestId) });
}

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"'`]/g, (c) => `&#${c.charCodeAt(0)};`);
}

/** German HTML page (errors, callback fallback). Every interpolated value is escaped here. */
export function htmlPage(
  info: RequestInfo,
  status: number,
  message: string,
  opts: { link?: { href: string; label: string }; location?: string; errorCode?: string } = {},
): Response {
  if (opts.errorCode) info.errorCode = opts.errorCode;
  const link = opts.link ? `<p><a class="btn" href="${escapeHtml(opts.link.href)}">${escapeHtml(opts.link.label)}</a></p>` : "";
  const body =
    `<!doctype html><html lang="de"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><title>KlimaBilanz</title>` +
    `<style>body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:48px 16px;background:#f4f7f5;color:#1c2b22}` +
    `main{max-width:28rem;margin:0 auto;text-align:center}h1{font-size:1.25rem}` +
    `.btn{display:inline-block;padding:12px 20px;border-radius:12px;background:#1f7a4d;color:#fff;text-decoration:none}` +
    `@media (prefers-color-scheme:dark){body{background:#101814;color:#e6efe9}}</style></head>` +
    `<body><main><h1>KlimaBilanz</h1><p>${escapeHtml(message)}</p>${link}</main></body></html>`;
  const headers = new Headers({ "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": HTML_CSP });
  if (opts.location) headers.set("Location", opts.location);
  return new Response(body, { status, headers: withSecurityHeaders(headers, info.requestId) });
}

export function redirect(info: RequestInfo, location: string, status = 302): Response {
  const headers = new Headers({ Location: location });
  return new Response(null, { status, headers: withSecurityHeaders(headers, info.requestId) });
}

// ---------------------------------------------------------------------------------------------------------------
// Request bodies
// ---------------------------------------------------------------------------------------------------------------

export function mediaType(request: Request): string | null {
  const raw = request.headers.get("Content-Type");
  if (raw === null) return null;
  return raw.split(";", 1)[0]!.trim().toLowerCase();
}

function tooLarge(limit: number): ApiError {
  return new ApiError(413, "payload_too_large", `Request body exceeds ${limit} bytes.`);
}

/** Rejects early on Content-Length (before anything else is done with the request). */
export function checkContentLength(request: Request, limit: number): void {
  const declared = request.headers.get("Content-Length");
  if (declared !== null) {
    const n = Number(declared);
    if (Number.isFinite(n) && n > limit) throw tooLarge(limit);
  }
}

/** Reads the body as bytes; checks Content-Length first, then the bytes actually read. */
export async function readBody(request: Request, limit: number): Promise<Uint8Array<ArrayBuffer>> {
  checkContentLength(request, limit);
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel().catch(() => undefined);
      throw tooLarge(limit);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.byteLength;
  }
  return out;
}

const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

export async function readText(request: Request, limit: number): Promise<string> {
  const bytes = await readBody(request, limit);
  try {
    return decoder.decode(bytes);
  } catch {
    throw new ApiError(400, "invalid_request", "Body is not valid UTF-8.");
  }
}

export function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_request", "Body is not valid JSON.");
  }
}

export function isPlainObject(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

/** JSON object body (Content-Type application/json required). An empty body is allowed when `allowEmpty`. */
export async function readJsonObject(request: Request, limit = MAX_BODY_BYTES, allowEmpty = false): Promise<Record<string, unknown>> {
  checkContentLength(request, limit);
  const type = mediaType(request);
  if (type !== "application/json") {
    if (allowEmpty && type === null) {
      const text = await readText(request, limit);
      if (text.trim() === "") return {};
    }
    throw new ApiError(415, "unsupported_media_type", "Content-Type must be application/json.");
  }
  const text = await readText(request, limit);
  if (allowEmpty && text.trim() === "") return {};
  const value = parseJson(text);
  if (!isPlainObject(value)) throw new ApiError(400, "invalid_request", "Body must be a JSON object.");
  return value;
}

/** Form or JSON body as string fields (token / logout endpoints). Non-string JSON values are rejected. */
export async function readFields(request: Request, allowEmpty = false): Promise<Map<string, string>> {
  checkContentLength(request, MAX_BODY_BYTES);
  const type = mediaType(request);
  const fields = new Map<string, string>();
  if (type === "application/x-www-form-urlencoded") {
    const text = await readText(request, MAX_BODY_BYTES);
    for (const [k, v] of new URLSearchParams(text)) {
      // RFC 6749 §3.2: parameters must not be included more than once.
      if (fields.has(k)) throw new ApiError(400, "invalid_request", `Parameter ${k.slice(0, 40)} is repeated.`);
      fields.set(k, v);
    }
    return fields;
  }
  if (type === "application/json") {
    const text = await readText(request, MAX_BODY_BYTES);
    if (allowEmpty && text.trim() === "") return fields;
    const value = parseJson(text);
    if (!isPlainObject(value)) throw new ApiError(400, "invalid_request", "Body must be a JSON object.");
    for (const [k, v] of Object.entries(value)) {
      if (v === null || v === undefined) continue;
      if (typeof v !== "string") throw new ApiError(400, "invalid_request", `Field ${k} must be a string.`);
      fields.set(k, v);
    }
    return fields;
  }
  if (allowEmpty && type === null) {
    const text = await readText(request, MAX_BODY_BYTES);
    if (text.trim() === "") return fields;
  }
  throw new ApiError(415, "unsupported_media_type", "Content-Type must be application/x-www-form-urlencoded or application/json.");
}

// ---------------------------------------------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------------------------------------------

const REQUEST_ID_RE = /^[A-Za-z0-9-]{1,64}$/;

export function requestIdFor(request: Request, randomBytes: (n: number) => Uint8Array): string {
  const ray = request.headers.get("cf-ray");
  if (ray && REQUEST_ID_RE.test(ray)) return ray;
  let hex = "";
  for (const b of randomBytes(8)) hex += b.toString(16).padStart(2, "0");
  return hex;
}

/**
 * Rate-limit subject of the client (§2.8): `CF-Connecting-IP`, where IPv6 addresses are reduced to their /64. A single
 * subscriber or VM gets a whole /64, so per-address buckets would let one client rotate through 2^64 addresses and
 * never hit a limit. IPv4-mapped IPv6 (`::ffff:a.b.c.d`) counts as the IPv4 address.
 */
export function clientIp(request: Request): string {
  const raw = request.headers.get("CF-Connecting-IP");
  if (raw === null || raw.trim() === "") return "unknown";
  return rateLimitSubjectForIp(raw);
}

const HEXTET_RE = /^[0-9a-f]{1,4}$/;
const IPV4_RE = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

function ipv4(s: string): number[] | null {
  const m = IPV4_RE.exec(s);
  if (!m) return null;
  const parts = m.slice(1).map(Number);
  return parts.every((p) => p <= 255) ? parts : null;
}

/** IPv4 unchanged, IPv6 → `"<first four hextets>::/64"`; anything unparsable is used as is (capped). */
export function rateLimitSubjectForIp(ip: string): string {
  const s = ip.trim().toLowerCase();
  if (!s.includes(":")) return s.slice(0, 64);
  let addr = s.replace(/^\[|\]$/g, "").replace(/%.*$/, "");
  // Embedded IPv4 in the last 32 bits (e.g. ::ffff:192.0.2.1) → two hextets.
  const lastColon = addr.lastIndexOf(":");
  const tail = addr.slice(lastColon + 1);
  if (tail.includes(".")) {
    const v4 = ipv4(tail);
    if (!v4) return s.slice(0, 64);
    addr = `${addr.slice(0, lastColon + 1)}${((v4[0]! << 8) | v4[1]!).toString(16)}:${((v4[2]! << 8) | v4[3]!).toString(16)}`;
  }
  const halves = addr.split("::");
  if (halves.length > 2) return s.slice(0, 64);
  const head = halves[0] === "" ? [] : halves[0]!.split(":");
  const rest = halves.length === 2 ? (halves[1] === "" ? [] : halves[1]!.split(":")) : [];
  const missing = 8 - head.length - rest.length;
  if ((halves.length === 2 && missing < 1) || (halves.length === 1 && missing !== 0)) return s.slice(0, 64);
  const hextets = [...head, ...Array<string>(halves.length === 2 ? missing : 0).fill("0"), ...rest];
  if (hextets.length !== 8 || !hextets.every((h) => HEXTET_RE.test(h))) return s.slice(0, 64);
  const groups = hextets.map((h) => h.replace(/^0+(?=.)/, ""));
  if (groups.slice(0, 5).every((g) => g === "0") && groups[5] === "ffff") {
    // ::ffff:c000:201 written in hex: still the IPv4 client.
    const a = parseInt(hextets[6]!, 16);
    const b = parseInt(hextets[7]!, 16);
    return [a >> 8, a & 0xff, b >> 8, b & 0xff].join(".");
  }
  return `${groups.slice(0, 4).join(":")}::/64`;
}

// Control characters (C0, DEL, C1) and lone surrogates.
const CONTROL_RE = /[\u0000-\u001F\u007F-\u009F]/g;
const LONE_SURROGATE_RE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g;

/** Trims, strips control characters and lone surrogates, caps the length; empty → null. */
export function sanitizeText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  let s = value.replace(CONTROL_RE, "").replace(LONE_SURROGATE_RE, "").trim();
  if (s.length > max) {
    s = s.slice(0, max);
    // Do not leave half a surrogate pair at the end.
    if (/[\uD800-\uDBFF]$/.test(s)) s = s.slice(0, -1);
    s = s.trim();
  }
  return s.length > 0 ? s : null;
}

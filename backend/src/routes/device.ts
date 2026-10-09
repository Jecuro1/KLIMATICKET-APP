// Direct install without a computer (docs/DIREKT_INSTALLIEREN.md). Nothing here touches D1 or stores anything.
//
// UDID of an iPhone, the only thing iOS hides from apps and websites, via Apple's "Profile Service" enrollment:
//   GET  /v1/udid           → unsigned .mobileconfig that asks iOS for UDID + PRODUCT (nothing stays installed)
//   POST /v1/udid/callback  ← iOS posts the device-signed plist; we answer 301 → /v1/udid/done?udid=…&product=…
//   GET  /v1/udid/done      → page with the UDID, a copy button and the next step ("Gerät registrieren" on GitHub)
// The values travel only in the redirect URL; Workers Logs strip query strings (wrangler.template.toml) and our own
// log lines carry route names only.
//
// Optional HTTPS host for the ad-hoc build (repository variable OTA_BASE_URL = https://<worker>/v1/ota):
//   GET|HEAD /v1/ota/<tag>/<file>  → streams the asset of this repo's GitHub release, without GitHub's redirect
//   GET|HEAD /v1/ota/latest/manifest.plist
import type { Env } from "../env";
import type { Deps } from "../deps";
import { ApiError, MAX_BODY_BYTES, escapeHtml, readBody, redirect, withSecurityHeaders, type RequestInfo } from "../http";
import { publicBaseUrl } from "./authWeb";

export const DEFAULT_REPO = "Jecuro1/KLIMATICKET-APP";
const REPO_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]{1,100}$/;
// Since 2018 (A12): 8 hex, dash, 16 hex. Older iPhones: 40 hex.
export const UDID_RE = /^(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40})$/;
const PRODUCT_RE = /^[A-Za-z]{1,16}\d{1,3},\d{1,3}$/;
const PAGE_CSP_BASE = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

export const OTA_ROUTE_RE =
  /^\/v1\/ota\/(latest|v\d{1,4}(?:\.\d{1,4}){1,2})\/(manifest\.plist|KlimaBilanz-\d{1,4}(?:\.\d{1,4}){0,2}-adhoc\.ipa|AppIcon-(?:57|512)\.png)$/;

export function githubRepo(env: Env): string {
  const configured = (env.OTA_GITHUB_REPO ?? "").trim();
  return REPO_RE.test(configured) ? configured : DEFAULT_REPO;
}

function xml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// ---------------------------------------------------------------------------------------------------------------
// GET /v1/udid
// ---------------------------------------------------------------------------------------------------------------

export function udidProfile(request: Request, env: Env, deps: Deps, info: RequestInfo): Response {
  const callback = `${publicBaseUrl(env, request)}/v1/udid/callback`;
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <dict>
    <key>URL</key>
    <string>${xml(callback)}</string>
    <key>DeviceAttributes</key>
    <array>
      <string>UDID</string>
      <string>PRODUCT</string>
    </array>
  </dict>
  <key>PayloadOrganization</key>
  <string>KlimaBilanz</string>
  <key>PayloadDisplayName</key>
  <string>KlimaBilanz – Geräte-ID anzeigen</string>
  <key>PayloadDescription</key>
  <string>Zeigt dir die UDID dieses iPhones, damit du es für „Direkt installieren“ registrieren kannst. Es bleibt kein Profil installiert, und KlimaBilanz speichert nichts.</string>
  <key>PayloadIdentifier</key>
  <string>com.knitelarlberg.klimabilanz.udid</string>
  <key>PayloadUUID</key>
  <string>${deps.randomUUID().toUpperCase()}</string>
  <key>PayloadType</key>
  <string>Profile Service</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
`;
  const headers = new Headers({
    "Content-Type": "application/x-apple-aspen-config",
    "Content-Disposition": 'attachment; filename="KlimaBilanz-UDID.mobileconfig"',
  });
  return new Response(body, { status: 200, headers: withSecurityHeaders(headers, info.requestId) });
}

// ---------------------------------------------------------------------------------------------------------------
// POST /v1/udid/callback
// ---------------------------------------------------------------------------------------------------------------

function indexOf(haystack: Uint8Array, needle: string, from = 0): number {
  const n = Array.from(needle, (c) => c.charCodeAt(0));
  outer: for (let i = from; i <= haystack.length - n.length; i++) {
    for (let j = 0; j < n.length; j++) if (haystack[i + j] !== n[j]) continue outer;
    return i;
  }
  return -1;
}

function lastIndexOf(haystack: Uint8Array, needle: string): number {
  const n = Array.from(needle, (c) => c.charCodeAt(0));
  outer: for (let i = haystack.length - n.length; i >= 0; i--) {
    for (let j = 0; j < n.length; j++) if (haystack[i + j] !== n[j]) continue outer;
    return i;
  }
  return -1;
}

/** The plist inside the CMS envelope iOS posts (signed by the device, the content itself is not encrypted). */
export function extractDeviceAttributes(body: Uint8Array): { udid: string; product: string | null } | null {
  let start = indexOf(body, "<?xml");
  if (start < 0) start = indexOf(body, "<plist");
  const end = lastIndexOf(body, "</plist>");
  if (start < 0 || end < start) return null;
  const text = new TextDecoder("utf-8", { fatal: false, ignoreBOM: false }).decode(body.subarray(start, end + "</plist>".length));
  const value = (key: string): string | null => {
    const m = new RegExp(`<key>\\s*${key}\\s*</key>\\s*<string>\\s*([^<]{1,80}?)\\s*</string>`).exec(text);
    return m ? m[1]! : null;
  };
  const udid = value("UDID");
  if (udid === null || !UDID_RE.test(udid)) return null;
  const product = value("PRODUCT");
  return { udid: udid.toUpperCase(), product: product !== null && PRODUCT_RE.test(product) ? product : null };
}

export async function udidCallback(request: Request, env: Env, _deps: Deps, info: RequestInfo): Promise<Response> {
  const body = await readBody(request, MAX_BODY_BYTES);
  const attributes = extractDeviceAttributes(body);
  if (!attributes) {
    info.errorCode = "invalid_request";
    // iOS shows its own "Profilinstallation fehlgeschlagen" for anything but a redirect.
    throw new ApiError(400, "invalid_request", "No device attributes found.");
  }
  const query = new URLSearchParams({ udid: attributes.udid });
  if (attributes.product) query.set("product", attributes.product);
  // 301 is what iOS expects here: it then opens the target in Safari.
  return redirect(info, `${publicBaseUrl(env, request)}/v1/udid/done?${query.toString()}`, 301);
}

// ---------------------------------------------------------------------------------------------------------------
// GET /v1/udid/done
// ---------------------------------------------------------------------------------------------------------------

function page(info: RequestInfo, status: number, title: string, main: string, script = ""): Response {
  const nonce = script ? crypto.randomUUID().replace(/-/g, "") : "";
  const html =
    `<!doctype html><html lang="de"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">` +
    `<meta name="color-scheme" content="light dark"><title>${escapeHtml(title)}</title><style>` +
    `:root{--bg:#f4f7f5;--fg:#1c2b22;--muted:#5b6b62;--card:#fff;--line:#d8e2dc;--accent:#1f7a4d;--on:#fff}` +
    `@media (prefers-color-scheme:dark){:root{--bg:#101814;--fg:#e6efe9;--muted:#9fb1a6;--card:#18231d;--line:#2a3a31;--accent:#3fae78;--on:#06140c}}` +
    `*{box-sizing:border-box}` +
    `body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:32px 16px 48px;background:var(--bg);color:var(--fg);line-height:1.45}` +
    `main{max-width:30rem;margin:0 auto}h1{font-size:1.4rem;margin:0 0 .5rem}p,li{color:var(--muted)}` +
    `.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin:16px 0}` +
    `code{display:block;font:600 1.05rem ui-monospace,Menlo,monospace;word-break:break-all;user-select:all;-webkit-user-select:all;color:var(--fg)}` +
    `.btn{display:block;text-align:center;padding:14px 18px;border-radius:14px;background:var(--accent);color:var(--on);` +
    `font-weight:600;text-decoration:none;border:0;font-size:1rem;width:100%;margin-top:12px}` +
    `.btn.secondary{background:transparent;color:var(--accent);border:1px solid var(--line)}ol{padding-left:1.2rem}` +
    `</style></head><body><main>${main}</main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`;
  const csp = script ? `${PAGE_CSP_BASE}; script-src 'nonce-${nonce}'` : PAGE_CSP_BASE;
  const headers = new Headers({ "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp });
  return new Response(html, { status, headers: withSecurityHeaders(headers, info.requestId) });
}

const COPY_SCRIPT =
  `(function(){var b=document.getElementById("copy"),u=document.getElementById("udid");` +
  `function done(){b.textContent="Kopiert \\u2713";setTimeout(function(){b.textContent="UDID kopieren"},2500)}` +
  `function fallback(){var r=document.createRange();r.selectNodeContents(u);var s=window.getSelection();` +
  `s.removeAllRanges();s.addRange(r);try{document.execCommand("copy");done()}catch(e){}}` +
  `b.addEventListener("click",function(){if(navigator.clipboard&&navigator.clipboard.writeText){` +
  `navigator.clipboard.writeText(u.textContent).then(done,fallback)}else{fallback()}})})();`;

export function udidDone(request: Request, env: Env, _deps: Deps, info: RequestInfo): Response {
  const q = new URL(request.url).searchParams;
  const udid = q.get("udid") ?? "";
  const product = q.get("product");
  if (!UDID_RE.test(udid)) {
    info.errorCode = "invalid_request";
    return page(info, 400, "KlimaBilanz – Geräte-ID", `<h1>Keine Geräte-ID</h1><p>Öffne die Seite zum Anzeigen der UDID ` +
      `noch einmal und installiere das Profil unter Einstellungen › Allgemein › VPN &amp; Geräteverwaltung.</p>` +
      `<a class="btn" href="/v1/udid">Noch einmal versuchen</a>`);
  }
  const repo = githubRepo(env);
  const register = `https://github.com/${repo}/actions/workflows/register-device.yml`;
  const guide = `https://github.com/${repo}/blob/main/docs/DIREKT_INSTALLIEREN.md`;
  const model = product && PRODUCT_RE.test(product) ? `<p>Modell: ${escapeHtml(product)}</p>` : "";
  const main =
    `<h1>Deine Geräte-ID (UDID)</h1>` +
    `<p>Damit registrierst du dieses iPhone für „Direkt installieren“. Es ist kein Profil installiert geblieben, ` +
    `und KlimaBilanz hat nichts gespeichert.</p>` +
    `<div class="card"><code id="udid">${escapeHtml(udid.toUpperCase())}</code>${model}` +
    `<button class="btn" id="copy" type="button">UDID kopieren</button></div>` +
    `<h2 style="font-size:1.1rem">So geht's weiter</h2><ol>` +
    `<li>Tippe auf „UDID kopieren“.</li>` +
    `<li>Öffne „Gerät registrieren“ auf GitHub, tippe auf <b>Run workflow</b>, füge die UDID ein, gib dem iPhone einen ` +
    `Namen und tippe auf den grünen <b>Run workflow</b>-Knopf.</li>` +
    `<li>Ab dem nächsten Release installierst du KlimaBilanz direkt aus der App bzw. von der Installationsseite.</li></ol>` +
    `<a class="btn" href="${escapeHtml(register)}">„Gerät registrieren“ öffnen</a>` +
    `<a class="btn secondary" href="${escapeHtml(guide)}">Anleitung</a>`;
  return page(info, 200, "KlimaBilanz – Geräte-ID", main, COPY_SCRIPT);
}

// ---------------------------------------------------------------------------------------------------------------
// GET|HEAD /v1/ota/<tag>/<file>
// ---------------------------------------------------------------------------------------------------------------

const OTA_TYPES: Record<string, string> = {
  plist: "application/xml",
  ipa: "application/octet-stream",
  png: "image/png",
};
const OTA_TIMEOUT_MS = 30_000;

export async function otaAsset(request: Request, env: Env, deps: Deps, info: RequestInfo, tag: string, file: string): Promise<Response> {
  if (tag === "latest" && file !== "manifest.plist") throw new ApiError(404, "not_found", "Not found.");
  const repo = githubRepo(env);
  const upstream =
    tag === "latest"
      ? `https://github.com/${repo}/releases/latest/download/${file}`
      : `https://github.com/${repo}/releases/download/${tag}/${file}`;
  let res: Response;
  try {
    res = await deps.fetch(upstream, {
      method: request.method === "HEAD" ? "HEAD" : "GET",
      redirect: "follow",
      signal: AbortSignal.timeout(OTA_TIMEOUT_MS),
    });
  } catch (err) {
    deps.log({ event: "ota_upstream_failed", request_id: info.requestId, error: err instanceof Error ? err.name : "unknown" });
    throw new ApiError(502, "upstream_unavailable", "GitHub is not reachable.");
  }
  if (res.status === 404) throw new ApiError(404, "not_found", "Not found.");
  if (!res.ok) throw new ApiError(502, "upstream_unavailable", "GitHub answered with an error.");
  const headers = new Headers({ "Content-Type": OTA_TYPES[file.slice(file.lastIndexOf(".") + 1)]! });
  const length = res.headers.get("Content-Length");
  if (length !== null && /^\d{1,12}$/.test(length)) headers.set("Content-Length", length);
  withSecurityHeaders(headers, info.requestId);
  // Tagged assets never change; "latest" moves with every release.
  headers.set("Cache-Control", tag === "latest" ? "no-store" : "public, max-age=3600");
  return new Response(request.method === "HEAD" ? null : res.body, { status: 200, headers });
}

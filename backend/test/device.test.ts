// Direct install without a computer (src/routes/device.ts): UDID via the iOS profile service, release asset proxy.
// Nothing may be stored: every test here also runs with a D1 binding that throws on use.
import { describe, expect, it } from "vitest";
import { BASE, bodyText, call, expectError, get, makeDeps, type Handler } from "./helpers";
import { extractDeviceAttributes } from "../src/routes/device";

const UDID = "00008110-001A2B3C4D5E801E";
const OLD_UDID = "0123456789abcdef0123456789abcdef01234567";
const RELEASES = "https://github.com/Jecuro1/KLIMATICKET-APP/releases";

/** D1 that fails on any use – proves the device routes never touch the database. */
const NO_DB = {
  prepare: () => {
    throw new Error("D1 must not be used");
  },
  batch: () => {
    throw new Error("D1 must not be used");
  },
} as unknown as D1Database;

/** What iOS posts: a CMS SignedData envelope (binary) around the plain XML plist with the requested attributes. */
function devicePost(attributes: Record<string, string>, extra: Record<string, string> = {}): Request {
  const entries = Object.entries(attributes)
    .map(([k, v]) => `\t<key>${k}</key>\n\t<string>${v}</string>`)
    .join("\n");
  const plist =
    `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ` +
    `"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n${entries}\n</dict>\n</plist>\n`;
  const head = new Uint8Array([0x30, 0x80, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02, 0xa0, 0x80]);
  const tail = new Uint8Array([0x00, 0x00, 0xa0, 0x82, 0x0b, 0xff, 0x30, 0x82, 0x03, 0x00, 0xde, 0xad, 0xbe, 0xef]);
  const xml = new TextEncoder().encode(plist);
  const body = new Uint8Array(head.length + xml.length + tail.length);
  body.set(head, 0);
  body.set(xml, head.length);
  body.set(tail, head.length + xml.length);
  return new Request(`${BASE}/v1/udid/callback`, {
    method: "POST",
    headers: { "Content-Type": "application/pkcs7-signature", ...extra },
    body,
  });
}

describe("GET /v1/udid", () => {
  it("serves an unsigned profile-service payload that asks for UDID and PRODUCT only", async () => {
    const res = await call(makeDeps(), get("/v1/udid"), { DB: NO_DB });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/x-apple-aspen-config");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("content-disposition")).toContain(".mobileconfig");
    const body = await bodyText(res);
    expect(body).toContain("<string>Profile Service</string>");
    expect(body).toContain(`<string>${BASE}/v1/udid/callback</string>`);
    const attributes = /<key>DeviceAttributes<\/key>\s*<array>([\s\S]*?)<\/array>/.exec(body)![1]!;
    expect(attributes.match(/<string>([^<]+)<\/string>/g)).toEqual(["<string>UDID</string>", "<string>PRODUCT</string>"]);
    expect(body).toMatch(/<key>PayloadUUID<\/key>\s*<string>[0-9A-F-]{36}<\/string>/);
  });

  it("uses PUBLIC_BASE_URL for the callback and escapes it", async () => {
    const res = await call(makeDeps(), get("/v1/udid"), { DB: NO_DB, PUBLIC_BASE_URL: "https://api.example.at/" });
    expect(await bodyText(res)).toContain("<string>https://api.example.at/v1/udid/callback</string>");
    const odd = await call(makeDeps(), get("/v1/udid"), { DB: NO_DB, PUBLIC_BASE_URL: "https://a.example/<x>&" });
    const body = await bodyText(odd);
    expect(body).toContain("https://a.example/&lt;x&gt;&amp;/v1/udid/callback");
    expect(body).not.toContain("<x>");
  });

  it("is a plain navigation: Origin does not matter, other methods are refused", async () => {
    const res = await call(makeDeps(), get("/v1/udid", { Origin: "https://example.com" }), { DB: NO_DB });
    expect(res.status).toBe(200);
    const post = await call(makeDeps(), new Request(`${BASE}/v1/udid`, { method: "POST", body: "x" }), { DB: NO_DB });
    expect(post.headers.get("allow")).toBe("GET");
    await expectError(post, 405, "method_not_allowed");
  });
});

describe("POST /v1/udid/callback", () => {
  it("redirects (301) to the page with UDID and model, nothing logged but the route", async () => {
    const deps = makeDeps();
    const res = await call(deps, devicePost({ PRODUCT: "iPhone17,1", UDID: UDID.toLowerCase(), VERSION: "23A341" }), {
      DB: NO_DB,
    });
    expect(res.status).toBe(301);
    expect(res.headers.get("location")).toBe(`${BASE}/v1/udid/done?udid=${UDID}&product=iPhone17%2C1`);
    expect(res.headers.get("cache-control")).toBe("no-store");
    const logged = JSON.stringify(deps.logs);
    expect(logged).toContain('"route":"udid_callback"');
    expect(logged.toUpperCase()).not.toContain(UDID);
  });

  it("accepts the 40-digit UDID of older iPhones and ignores an odd PRODUCT", async () => {
    const res = await call(makeDeps(), devicePost({ UDID: OLD_UDID, PRODUCT: "<script>" }), { DB: NO_DB });
    expect(res.status).toBe(301);
    expect(res.headers.get("location")).toBe(`${BASE}/v1/udid/done?udid=${OLD_UDID.toUpperCase()}`);
  });

  it("works when iOS sends an Origin header and with PUBLIC_BASE_URL", async () => {
    const res = await call(makeDeps(), devicePost({ UDID }, { Origin: "null" }), {
      DB: NO_DB,
      PUBLIC_BASE_URL: "https://api.example.at",
    });
    expect(res.status).toBe(301);
    expect(res.headers.get("location")).toBe(`https://api.example.at/v1/udid/done?udid=${UDID}`);
  });

  it("refuses bodies without a valid UDID and oversized bodies", async () => {
    const deps = makeDeps();
    await expectError(await call(deps, devicePost({ PRODUCT: "iPhone17,1" }), { DB: NO_DB }), 400, "invalid_request");
    await expectError(await call(deps, devicePost({ UDID: "00008110-001A2B3C4D5E801" }), { DB: NO_DB }), 400, "invalid_request");
    await expectError(await call(deps, devicePost({ UDID: `${UDID}"><x` }), { DB: NO_DB }), 400, "invalid_request");
    const plain = new Request(`${BASE}/v1/udid/callback`, { method: "POST", body: "hello" });
    await expectError(await call(deps, plain), 400, "invalid_request");
    const big = new Request(`${BASE}/v1/udid/callback`, { method: "POST", body: new Uint8Array(70_000) });
    await expectError(await call(deps, big, { DB: NO_DB }), 413, "payload_too_large");
    const getRes = await call(deps, get("/v1/udid/callback"));
    expect(getRes.headers.get("allow")).toBe("POST");
  });

  it("extractDeviceAttributes reads only the plist inside the envelope", () => {
    const text = (s: string) => new TextEncoder().encode(s);
    expect(extractDeviceAttributes(text(`junk<plist><dict><key>UDID</key><string> ${UDID} </string></dict></plist>junk`))).toEqual({
      udid: UDID,
      product: null,
    });
    expect(extractDeviceAttributes(text(`<key>UDID</key><string>${UDID}</string>`))).toBeNull();
    expect(extractDeviceAttributes(text(""))).toBeNull();
    expect(extractDeviceAttributes(text(`</plist><plist><key>UDID</key><string>${UDID}</string>`))).toBeNull();
  });
});

describe("GET /v1/udid/done", () => {
  it("shows the UDID with a copy button, the register link and a nonce-only CSP", async () => {
    const res = await call(makeDeps(), get(`/v1/udid/done?udid=${UDID.toLowerCase()}&product=iPhone17%2C1`), { DB: NO_DB });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(res.headers.get("cache-control")).toBe("no-store");
    const html = await res.text();
    expect(html).toContain(`<code id="udid">${UDID}</code>`);
    expect(html).toContain("Modell: iPhone17,1");
    expect(html).toContain(`href="https://github.com/Jecuro1/KLIMATICKET-APP/actions/workflows/register-device.yml"`);
    expect(html).toContain("docs/DIREKT_INSTALLIEREN.md");
    const csp = res.headers.get("content-security-policy")!;
    const nonce = /script-src 'nonce-([0-9a-f]{32})'/.exec(csp)![1];
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(csp).toContain("default-src 'none'");
    expect(csp).not.toContain("unsafe-eval");
    expect(html).not.toMatch(/<script(?! nonce)/);
    expect(html).not.toMatch(/https?:\/\/(?!github\.com\/)/); // no third-party resources, no tracking
  });

  it("uses OTA_GITHUB_REPO for the links, ignores an invalid one", async () => {
    let html = await (await call(makeDeps(), get(`/v1/udid/done?udid=${UDID}`), { DB: NO_DB, OTA_GITHUB_REPO: "someone/fork" })).text();
    expect(html).toContain("https://github.com/someone/fork/actions/workflows/register-device.yml");
    expect(html).not.toContain("Modell:");
    html = await (await call(makeDeps(), get(`/v1/udid/done?udid=${UDID}`), { DB: NO_DB, OTA_GITHUB_REPO: "x/../../evil" })).text();
    expect(html).toContain("https://github.com/Jecuro1/KLIMATICKET-APP/actions/workflows/register-device.yml");
  });

  it("never reflects anything that is not a UDID", async () => {
    const res = await call(makeDeps(), get(`/v1/udid/done?udid=%3Cscript%3Ealert(1)%3C/script%3E&product=%3Cb%3E`), { DB: NO_DB });
    expect(res.status).toBe(400);
    const html = await res.text();
    expect(html).not.toContain("alert(1)");
    expect(html).not.toContain("<b>");
    expect(html).toContain("Keine Geräte-ID");
    expect(res.headers.get("content-security-policy")).not.toContain("script-src");
    const product = await call(makeDeps(), get(`/v1/udid/done?udid=${UDID}&product=%3Cimg%20src%3Dx%3E`), { DB: NO_DB });
    expect(await product.text()).not.toContain("<img");
  });
});

describe("/v1/ota/<tag>/<file>", () => {
  function upstream(deps: ReturnType<typeof makeDeps>, path: string, response: Handler): void {
    deps.net.on(`${RELEASES}/${path}`, response);
  }

  it("streams tagged release assets with the right type, without a redirect", async () => {
    const deps = makeDeps();
    const manifest = '<?xml version="1.0"?><plist version="1.0"><dict/></plist>';
    upstream(deps, "download/v1.2.3/manifest.plist", () => new Response(manifest, { headers: { "Content-Length": `${manifest.length}` } }));
    upstream(deps, "download/v1.2.3/KlimaBilanz-1.2.3-adhoc.ipa", () => new Response(new Uint8Array([0x50, 0x4b, 3, 4])));
    upstream(deps, "download/v1.2.3/AppIcon-57.png", () => new Response(new Uint8Array([0x89, 0x50])));
    let res = await call(deps, get("/v1/ota/v1.2.3/manifest.plist"), { DB: NO_DB });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/xml");
    expect(res.headers.get("content-length")).toBe(`${manifest.length}`);
    expect(res.headers.get("location")).toBeNull();
    expect(res.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(await res.text()).toBe(manifest);
    res = await call(deps, get("/v1/ota/v1.2.3/KlimaBilanz-1.2.3-adhoc.ipa"), { DB: NO_DB });
    expect(res.headers.get("content-type")).toBe("application/octet-stream");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(new Uint8Array([0x50, 0x4b, 3, 4]));
    res = await call(deps, get("/v1/ota/v1.2.3/AppIcon-57.png"), { DB: NO_DB });
    expect(res.headers.get("content-type")).toBe("image/png");
    expect(deps.net.calls.map((c) => c.method)).toEqual(["GET", "GET", "GET"]);
  });

  it("HEAD asks GitHub with HEAD and returns no body", async () => {
    const deps = makeDeps();
    upstream(deps, "download/v1.2.3/manifest.plist", (req) => new Response(req.method === "HEAD" ? null : "x", { headers: { "Content-Length": "42" } }));
    const res = await call(deps, new Request(`${BASE}/v1/ota/v1.2.3/manifest.plist`, { method: "HEAD" }), { DB: NO_DB });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-length")).toBe("42");
    expect(await bodyText(res)).toBe("");
    expect(deps.net.calls[0]!.method).toBe("HEAD");
  });

  it("latest: only the manifest, never cached", async () => {
    const deps = makeDeps();
    upstream(deps, "latest/download/manifest.plist", () => new Response("m"));
    const res = await call(deps, get("/v1/ota/latest/manifest.plist"), { DB: NO_DB });
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    await expectError(await call(deps, get("/v1/ota/latest/KlimaBilanz-1.2.3-adhoc.ipa"), { DB: NO_DB }), 404, "not_found");
  });

  it("serves nothing but our three kinds of files from tags", async () => {
    const deps = makeDeps();
    for (const path of [
      "/v1/ota/v1.2.3/update.json",
      "/v1/ota/v1.2.3/KlimaBilanz-1.2.3.ipa",
      "/v1/ota/v1.2.3/../../x/manifest.plist",
      "/v1/ota/main/manifest.plist",
      "/v1/ota/v1.2.3/AppIcon-1024.png",
      "/v1/ota/v1.2.3/manifest.plist/",
      "/v1/ota/v1/manifest.plist",
    ]) {
      await expectError(await call(deps, get(path), { DB: NO_DB }), 404, "not_found");
    }
    expect(deps.net.calls).toEqual([]);
    const post = await call(deps, new Request(`${BASE}/v1/ota/v1.2.3/manifest.plist`, { method: "POST" }), { DB: NO_DB });
    expect(post.headers.get("allow")).toBe("GET, HEAD");
  });

  it("maps upstream failures", async () => {
    const deps = makeDeps();
    upstream(deps, "download/v9.9.9/manifest.plist", () => new Response("nope", { status: 404 }));
    upstream(deps, "download/v1.2.4/manifest.plist", () => new Response("down", { status: 503 }));
    upstream(deps, "download/v1.2.5/manifest.plist", () => {
      throw new TypeError("network");
    });
    await expectError(await call(deps, get("/v1/ota/v9.9.9/manifest.plist"), { DB: NO_DB }), 404, "not_found");
    await expectError(await call(deps, get("/v1/ota/v1.2.4/manifest.plist"), { DB: NO_DB }), 502, "upstream_unavailable");
    await expectError(await call(deps, get("/v1/ota/v1.2.5/manifest.plist"), { DB: NO_DB }), 502, "upstream_unavailable");
  });

  it("follows OTA_GITHUB_REPO", async () => {
    const deps = makeDeps();
    deps.net.on("https://github.com/someone/fork/releases/download/v2.0/manifest.plist", () => new Response("fork"));
    const res = await call(deps, get("/v1/ota/v2.0/manifest.plist"), { DB: NO_DB, OTA_GITHUB_REPO: "someone/fork" });
    expect(await res.text()).toBe("fork");
  });
});

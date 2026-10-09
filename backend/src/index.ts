// KlimaBilanz API – Cloudflare Worker entry point.
// SKELETON (architect): only GET /v1/health is implemented. WP-S implements docs/CLOUDFLARE_BACKEND.md §3.
import type { Env } from "./env";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "X-KB-API": "1",
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/health") {
      const row = await env.DB.prepare("SELECT server_rev FROM sync_state WHERE id = 1").first<{ server_rev: number }>();
      return json({ ok: row !== null });
    }
    return json({ error: "not_implemented", error_description: "Not implemented yet." }, 501);
  },
} satisfies ExportedHandler<Env>;

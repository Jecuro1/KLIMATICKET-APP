// KlimaBilanz API – Cloudflare Worker entry point. Contract: docs/CLOUDFLARE_BACKEND.md.
import type { Env } from "./env";
import { handle } from "./app";
import { runCleanup } from "./cron";
import { defaultDeps } from "./deps";

const deps = defaultDeps();

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx, deps);
  },
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      runCleanup(env, deps).then(
        () => undefined,
        (err: unknown) => deps.log({ event: "cron_failed", error: err instanceof Error ? err.name : "unknown" }),
      ),
    );
  },
} satisfies ExportedHandler<Env>;

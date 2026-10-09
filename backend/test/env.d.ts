import type { D1Migration } from "cloudflare:test";
import type { Env as WorkerEnv } from "../src/env";

// Types for `env` / `exports` from "cloudflare:test" and "cloudflare:workers" inside tests.
declare global {
  namespace Cloudflare {
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
    interface GlobalProps {
      mainModule: typeof import("../src/index");
    }
  }
}

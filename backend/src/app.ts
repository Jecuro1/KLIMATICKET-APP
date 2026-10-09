// Router, origin policy and error/log middleware (docs/CLOUDFLARE_BACKEND.md §2.10, §3.1, §3.2).
import type { Env } from "./env";
import type { Ctx, Deps } from "./deps";
import { ApiError, errorResponse, requestIdFor, type RequestInfo } from "./http";
import { isProviderName, SPECS, type ProviderName } from "./providers";
import { deleteAccount, getMe, patchMe } from "./routes/account";
import { appleNativeEndpoint } from "./routes/appleNative";
import { callbackFlow, startFlow } from "./routes/authWeb";
import { config, health } from "./routes/meta";
import { pullEndpoint, pushEndpoint } from "./routes/sync";
import { logoutEndpoint, tokenEndpoint } from "./routes/token";

type RouteName =
  | "health"
  | "config"
  | "auth_start"
  | "auth_callback"
  | "auth_token"
  | "auth_native"
  | "auth_logout"
  | "me"
  | "account_delete"
  | "sync_push"
  | "sync_pull";

interface Route {
  name: RouteName;
  methods: string[];
  provider?: ProviderName;
}

const STATIC_ROUTES: Record<string, Route> = {
  "/v1/health": { name: "health", methods: ["GET"] },
  "/v1/config": { name: "config", methods: ["GET"] },
  "/v1/auth/token": { name: "auth_token", methods: ["POST"] },
  "/v1/auth/logout": { name: "auth_logout", methods: ["POST"] },
  "/v1/auth/apple/native": { name: "auth_native", methods: ["POST"] },
  "/v1/me": { name: "me", methods: ["GET", "PATCH"] },
  "/v1/account/delete": { name: "account_delete", methods: ["POST"] },
  "/v1/sync/push": { name: "sync_push", methods: ["POST"] },
  "/v1/sync/pull": { name: "sync_pull", methods: ["GET"] },
};

const PROVIDER_ROUTE_RE = /^\/v1\/auth\/([a-z]{1,20})\/(start|callback)$/;

function matchRoute(pathname: string): Route | null {
  if (Object.hasOwn(STATIC_ROUTES, pathname)) return STATIC_ROUTES[pathname]!;
  const m = PROVIDER_ROUTE_RE.exec(pathname);
  if (!m || !isProviderName(m[1]!)) return null;
  const provider = m[1];
  if (m[2] === "start") return { name: "auth_start", methods: ["GET"], provider };
  return { name: "auth_callback", methods: [SPECS[provider].callbackMethod], provider };
}

async function dispatch(route: Route, request: Request, env: Env, ctx: Ctx, deps: Deps, info: RequestInfo): Promise<Response> {
  switch (route.name) {
    case "health":
      return health(env, deps, info);
    case "config":
      return config(env, deps, info);
    case "auth_start":
      return startFlow(request, env, deps, info, route.provider!);
    case "auth_callback":
      return callbackFlow(request, env, ctx, deps, info, route.provider!);
    case "auth_token":
      return tokenEndpoint(request, env, deps, info);
    case "auth_native":
      return appleNativeEndpoint(request, env, ctx, deps, info);
    case "auth_logout":
      return logoutEndpoint(request, env, deps, info);
    case "me":
      return request.method === "PATCH" ? patchMe(request, env, deps, info) : getMe(request, env, deps, info);
    case "account_delete":
      return deleteAccount(request, env, ctx, deps, info);
    case "sync_push":
      return pushEndpoint(request, env, deps, info);
    case "sync_pull":
      return pullEndpoint(request, env, deps, info);
  }
}

function route(request: Request): Route {
  if (request.method === "OPTIONS") {
    // No CORS, ever.
    throw new ApiError(403, "origin_not_allowed", "Browser origins are not allowed.");
  }
  const url = new URL(request.url);
  const r = matchRoute(url.pathname);
  if (!r) throw new ApiError(404, "not_found", "Not found.");
  // Native URLSession sends no Origin; start/callback are browser navigations (Apple's form_post is checked there).
  if (r.name !== "auth_start" && r.name !== "auth_callback" && request.headers.has("Origin")) {
    throw new ApiError(403, "origin_not_allowed", "Browser origins are not allowed.");
  }
  if (!r.methods.includes(request.method)) {
    throw new ApiError(405, "method_not_allowed", "Method not allowed.", {}, { Allow: r.methods.join(", ") });
  }
  return r;
}

/** The Worker's request handler with injected dependencies (tests pass their own Deps). */
export async function handle(request: Request, env: Env, ctx: Ctx, deps: Deps): Promise<Response> {
  const started = Date.now();
  const info: RequestInfo = { requestId: requestIdFor(request, deps.randomBytes) };
  let routeName = "unmatched";
  let response: Response;
  try {
    const r = route(request);
    routeName = r.provider ? `${r.name}:${r.provider}` : r.name;
    response = await dispatch(r, request, env, ctx, deps, info);
  } catch (err) {
    if (err instanceof ApiError) {
      response = errorResponse(info, err);
    } else {
      // Error names only: messages may carry request data.
      deps.log({ event: "unhandled_error", request_id: info.requestId, route: routeName, error: err instanceof Error ? err.name : "unknown" });
      response = errorResponse(info, new ApiError(500, "server_error", "Internal server error."));
    }
  }
  deps.log({
    request_id: info.requestId,
    method: request.method,
    route: routeName,
    status: response.status,
    ms: Date.now() - started,
    ...(info.errorCode ? { error: info.errorCode } : {}),
  });
  return response;
}

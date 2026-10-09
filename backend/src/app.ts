// Router, origin policy and error/log middleware (docs/CLOUDFLARE_BACKEND.md §2.10, §3.1, §3.2).
import type { Env } from "./env";
import type { Ctx, Deps } from "./deps";
import { ApiError, errorResponse, requestIdFor, type RequestInfo } from "./http";
import { isProviderName, SPECS, type ProviderName } from "./providers";
import { deleteAccount, getMe, patchMe } from "./routes/account";
import { appleNativeEndpoint } from "./routes/appleNative";
import { callbackFlow, startFlow } from "./routes/authWeb";
import { OTA_ROUTE_RE, otaAsset, udidCallback, udidDone, udidProfile } from "./routes/device";
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
  | "sync_pull"
  | "udid_profile"
  | "udid_callback"
  | "udid_done"
  | "ota_asset";

interface Route {
  name: RouteName;
  methods: string[];
  provider?: ProviderName;
  /** ota_asset: release tag and file name. */
  params?: [string, string];
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
  // Direct install (routes/device.ts): Safari pages and the iOS profile service – no credentials, nothing stored.
  "/v1/udid": { name: "udid_profile", methods: ["GET"] },
  "/v1/udid/callback": { name: "udid_callback", methods: ["POST"] },
  "/v1/udid/done": { name: "udid_done", methods: ["GET"] },
};

/** Requests from Safari navigations and iOS' installer/profile daemons; an Origin header changes nothing there. */
const ORIGIN_EXEMPT: ReadonlySet<RouteName> = new Set(["auth_start", "auth_callback", "udid_profile", "udid_callback", "udid_done", "ota_asset"]);

const PROVIDER_ROUTE_RE = /^\/v1\/auth\/([a-z]{1,20})\/(start|callback)$/;

function matchRoute(pathname: string): Route | null {
  if (Object.hasOwn(STATIC_ROUTES, pathname)) return STATIC_ROUTES[pathname]!;
  const ota = OTA_ROUTE_RE.exec(pathname);
  if (ota) return { name: "ota_asset", methods: ["GET", "HEAD"], params: [ota[1]!, ota[2]!] };
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
    case "udid_profile":
      return udidProfile(request, env, deps, info);
    case "udid_callback":
      return udidCallback(request, env, deps, info);
    case "udid_done":
      return udidDone(request, env, deps, info);
    case "ota_asset":
      return otaAsset(request, env, deps, info, route.params![0], route.params![1]);
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
  // Native URLSession sends no Origin; start/callback are browser navigations (Apple's form_post is checked there),
  // the device routes serve Safari and iOS daemons without any credentials.
  if (!ORIGIN_EXEMPT.has(r.name) && request.headers.has("Origin")) {
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

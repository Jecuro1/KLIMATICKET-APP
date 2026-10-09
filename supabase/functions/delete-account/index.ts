// KlimaBilanz – Edge Function "delete-account" (in-app account deletion, App Store guideline 5.1.1(v)).
//
// Client: POST {SUPABASE_URL}/functions/v1/delete-account
//         Authorization: Bearer <access token of the signed-in user>, apikey: <anon / publishable key>
// Answer: 200 {"deleted":true} · 401 invalid/missing token · 405 wrong method · 500 server error
//
// The user id comes from the verified access token, never from the request body. Deleting the auth user cascades
// (ON DELETE CASCADE, see supabase/migrations) to profiles, tickets, trips, favorite_routes and benefits and removes every
// session (all refresh tokens) of that user. Already issued access tokens stay valid until they expire (≤ 1 h) but
// no longer match any row.
//
// Deploy:  supabase functions deploy delete-account --no-verify-jwt --use-api   (--use-api: bundled by Supabase, no Docker)
//          (the function verifies the token itself via GoTrue, which also works with the new asymmetric JWT keys)
// Secrets: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically. Projects that disabled the
//          legacy service_role key set a secret key instead:  supabase secrets set KB_SECRET_KEY=sb_secret_…
//
// Sign in with Apple: App Store builds should additionally revoke the Apple token (https://appleid.apple.com/auth/revoke)
// – that needs the Services ID / client secret and an authorization code from the app; not done here.
import { createClient } from 'npm:@supabase/supabase-js@2'

type Env = (name: string) => string | undefined
type ClientFactory = typeof createClient

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}

export async function handle(req: Request, env: Env, makeClient: ClientFactory): Promise<Response> {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405)
  }

  const url = env('SUPABASE_URL')
  const secretKey = env('KB_SECRET_KEY') || env('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !secretKey) {
    return json({ error: 'server_not_configured' }, 500)
  }

  const match = /^Bearer\s+(\S+)$/i.exec(req.headers.get('Authorization') ?? '')
  if (!match) {
    return json({ error: 'missing_token' }, 401)
  }
  const accessToken = match[1]

  const admin = makeClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })

  // GoTrue checks signature and expiry and returns the user behind the token.
  const { data, error } = await admin.auth.getUser(accessToken)
  const userId = data?.user?.id
  if (error || !userId) {
    return json({ error: 'invalid_token' }, 401)
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId)
  if (deleteError) {
    console.error('delete-account failed', userId, deleteError.message)
    return json({ error: 'delete_failed' }, 500)
  }
  return json({ deleted: true })
}

Deno.serve((req: Request) => handle(req, (name) => Deno.env.get(name), createClient))

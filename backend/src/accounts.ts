// Accounts and identities (docs/CLOUDFLARE_BACKEND.md §2.6): lookup only by (provider, subject), never by e-mail.
import type { Env } from "./env";
import type { Deps } from "./deps";
import type { ProviderName } from "./providers";

export interface IdentityInput {
  provider: ProviderName;
  subject: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  avatarUrl: string | null;
  /** Sealed Apple refresh token (§2.9), stored when present. */
  sealedRefreshToken?: string | null;
}

/** Returns the internal user id for the identity, creating user + identity + profile on the first login. */
export async function findOrCreateUser(env: Env, deps: Deps, id: IdentityInput): Promise<string> {
  const db = env.DB;
  const now = deps.now();
  const existing = await db
    .prepare("SELECT user_id FROM identities WHERE provider = ?1 AND subject = ?2")
    .bind(id.provider, id.subject)
    .first<{ user_id: string }>();
  if (existing) {
    await updateLogin(db, existing.user_id, id, now);
    return existing.user_id;
  }

  const userId = deps.randomUUID().toLowerCase();
  await db.batch([
    db.prepare("INSERT INTO users (id, created_at, last_login_at) VALUES (?1, ?2, ?2)").bind(userId, now),
    db
      .prepare(
        `INSERT INTO identities (provider, subject, user_id, email, email_verified, provider_refresh_token, created_at, last_login_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7) ON CONFLICT (provider, subject) DO NOTHING`,
      )
      .bind(id.provider, id.subject, userId, id.email, id.emailVerified ? 1 : 0, id.sealedRefreshToken ?? null, now),
    db
      .prepare(
        `INSERT INTO profiles (user_id, display_name, avatar_url, created_at, updated_at)
         SELECT ?1, ?2, ?3, ?4, ?4
         WHERE EXISTS (SELECT 1 FROM identities WHERE provider = ?5 AND subject = ?6 AND user_id = ?1)`,
      )
      .bind(userId, id.name, id.avatarUrl, now, id.provider, id.subject),
  ]);
  const owner = await db
    .prepare("SELECT user_id FROM identities WHERE provider = ?1 AND subject = ?2")
    .bind(id.provider, id.subject)
    .first<{ user_id: string }>();
  if (!owner) throw new Error("identity insert failed");
  if (owner.user_id !== userId) {
    // Lost a race against a concurrent first login: our users row is orphaned (removed by the cron, §3.10).
    await updateLogin(db, owner.user_id, id, now);
  }
  return owner.user_id;
}

async function updateLogin(db: D1Database, userId: string, id: IdentityInput, now: number): Promise<void> {
  await db.batch([
    db
      .prepare(
        `UPDATE identities SET
           email = COALESCE(?3, email),
           email_verified = CASE WHEN ?3 IS NULL THEN email_verified ELSE ?4 END,
           provider_refresh_token = COALESCE(?5, provider_refresh_token),
           last_login_at = ?6
         WHERE provider = ?1 AND subject = ?2`,
      )
      .bind(id.provider, id.subject, id.email, id.emailVerified ? 1 : 0, id.sealedRefreshToken ?? null, now),
    db.prepare("UPDATE users SET last_login_at = ?2 WHERE id = ?1").bind(userId, now),
    // Fill the profile only where it is empty.
    db
      .prepare(
        `INSERT INTO profiles (user_id, display_name, avatar_url, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)
         ON CONFLICT (user_id) DO UPDATE SET
           display_name = COALESCE(profiles.display_name, excluded.display_name),
           avatar_url = COALESCE(profiles.avatar_url, excluded.avatar_url),
           updated_at = excluded.updated_at
         WHERE (profiles.display_name IS NULL AND excluded.display_name IS NOT NULL)
            OR (profiles.avatar_url IS NULL AND excluded.avatar_url IS NOT NULL)`,
      )
      .bind(userId, id.name, id.avatarUrl, now),
  ]);
}

/** Stores a sealed Apple refresh token on an existing identity (native code exchange, best effort). */
export async function storeSealedToken(db: D1Database, subject: string, sealed: string): Promise<void> {
  await db
    .prepare("UPDATE identities SET provider_refresh_token = ?2 WHERE provider = 'apple' AND subject = ?1")
    .bind(subject, sealed)
    .run();
}

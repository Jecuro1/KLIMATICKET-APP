import { applyD1Migrations, env } from "cloudflare:test";

// Every test file starts from a fully migrated, empty database.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

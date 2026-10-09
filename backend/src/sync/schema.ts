// Static schema map of the synced tables (docs/CLOUDFLARE_BACKEND.md §3.5). Table and column names in SQL come
// only from here, never from input. A new sync column goes into §3.5, the fixture, the Swift DTO, a migration and
// this map together.

export type ColumnType = "uuid" | "text" | "real" | "int" | "bool" | "timestamp";

export interface Column {
  name: string;
  type: ColumnType;
  /** text: max UTF-16 code units. */
  max?: number;
  /** R: key must be present and non-null. */
  required: boolean;
  /** Stored as NULL when absent/null (only for optional columns). */
  nullable: boolean;
  /** Default for optional, non-nullable columns (normalized value). */
  default?: string | number;
  /**
   * Absent or null in a push keeps the stored value (a new row gets `default`) instead of resetting it – for columns
   * that older apps do not know, so their edits never wipe what a newer app wrote (e.g. `via`, docs/VIA.md §3).
   */
  keepWhenAbsent?: boolean;
}

export interface TableSchema {
  name: SyncTable;
  columns: Column[];
  /** Columns compared for the echo-skip (every column except user_id, id, created_at, updated_at, server_rev). */
  contentColumns: string[];
  /** Columns overwritten on update (every column except user_id, id, created_at). */
  updateColumns: string[];
  boolColumns: string[];
  columnNames: Set<string>;
  upsertSql: string;
  pullSql: string;
}

export const SYNC_TABLES = ["tickets", "trips", "favorite_routes", "benefits"] as const;
export type SyncTable = (typeof SYNC_TABLES)[number];

const R = (name: string, type: ColumnType, max?: number): Column => ({ name, type, max, required: true, nullable: false });
const O = (name: string, type: ColumnType, def: string | number, max?: number): Column => ({
  name,
  type,
  max,
  required: false,
  nullable: false,
  default: def,
});
const N = (name: string, type: ColumnType, max?: number): Column => ({ name, type, max, required: false, nullable: true });
/** Optional, kept when absent (see `keepWhenAbsent`). */
const K = (name: string, type: ColumnType, def: string | number, max?: number): Column => ({
  ...O(name, type, def, max),
  keepWhenAbsent: true,
});

const ID = R("id", "uuid");
const CREATED = R("created_at", "timestamp");
const UPDATED = R("updated_at", "timestamp");
const DELETED = N("deleted_at", "timestamp");

const DEFINITIONS: Record<SyncTable, Column[]> = {
  tickets: [
    ID,
    R("product_id", "text", 100),
    R("name", "text", 200),
    R("variant", "text", 50),
    R("family", "text", 50),
    R("states", "text", 200),
    R("price", "real"),
    R("start_date", "timestamp"),
    R("end_date", "timestamp"),
    R("holder_name", "text", 200),
    R("ticket_number", "text", 100),
    R("theme", "text", 50),
    R("reminders", "text", 200),
    O("is_monthly_payment", "bool", 0),
    O("auto_renews", "bool", 0),
    O("employer_contribution", "real", 0),
    O("add_on_price", "real", 0),
    O("add_ons", "text", "", 2000),
    CREATED,
    UPDATED,
    DELETED,
  ],
  trips: [
    ID,
    R("date", "timestamp"),
    R("from_name", "text", 200),
    R("to_name", "text", 200),
    N("from_station_id", "text", 100),
    N("to_station_id", "text", 100),
    R("mode", "text", 50),
    R("distance_km", "real"),
    R("fare_eur", "real"),
    R("is_fare_manual", "bool"),
    R("is_round_trip", "bool"),
    R("travel_class", "text", 50),
    R("companions", "int"),
    R("states", "text", 200),
    R("note", "text", 10000),
    O("category", "text", "", 50),
    O("is_induced", "bool", 0),
    K("via", "text", "", 1000),
    CREATED,
    UPDATED,
    DELETED,
  ],
  favorite_routes: [
    ID,
    R("title", "text", 200),
    R("from_name", "text", 200),
    R("to_name", "text", 200),
    N("from_station_id", "text", 100),
    N("to_station_id", "text", 100),
    R("mode", "text", 50),
    R("distance_km", "real"),
    R("fare_eur", "real"),
    R("is_round_trip", "bool"),
    R("states", "text", 200),
    R("sort_index", "int"),
    R("usage_count", "int"),
    O("category", "text", "", 50),
    K("via", "text", "", 1000),
    CREATED,
    UPDATED,
    DELETED,
  ],
  benefits: [
    ID,
    R("date", "timestamp"),
    R("partner_id", "text", 100),
    R("title", "text", 200),
    R("saved_eur", "real"),
    R("note", "text", 10000),
    CREATED,
    UPDATED,
    DELETED,
  ],
};

const IMMUTABLE = new Set(["id", "created_at"]);

/** SQL literal of a schema default (static values from DEFINITIONS, never input). */
function sqlLiteral(value: string | number | undefined): string {
  if (value === undefined) return "NULL";
  return typeof value === "number" ? String(value) : `'${value.replace(/'/g, "''")}'`;
}

/** The pushed value; for `keepWhenAbsent` columns the stored one (then the default) when the push leaves it out. */
function selectExpression(table: SyncTable, col: Column): string {
  const pushed = `j.value ->> '$.${col.name}'`;
  if (!col.keepWhenAbsent) return pushed;
  const stored = `(SELECT k.${col.name} FROM ${table} AS k WHERE k.user_id = ?1 AND k.id = j.value ->> '$.id')`;
  return `COALESCE(${pushed}, ${stored}, ${sqlLiteral(col.default)})`;
}

function build(name: SyncTable): TableSchema {
  const columns = DEFINITIONS[name];
  const names = columns.map((c) => c.name);
  const updateColumns = names.filter((c) => !IMMUTABLE.has(c));
  const contentColumns = updateColumns.filter((c) => c !== "updated_at");
  const selectList = columns.map((c) => selectExpression(name, c)).join(", ");
  // §3.6: the revision reserve (UPDATE sync_state … RETURNING) runs first in the same batch; row i of the
  // normalized array gets revision R - n + i + 1. Last writer wins on updated_at; echoes (no content change) skip.
  const upsertSql =
    `INSERT INTO ${name} (user_id, ${names.join(", ")}, server_rev) ` +
    `SELECT ?1, ${selectList}, (SELECT server_rev FROM sync_state WHERE id = 1) - ?3 + j.key + 1 ` +
    `FROM json_each(?2) AS j WHERE true ` +
    `ON CONFLICT (user_id, id) DO UPDATE SET ` +
    `${updateColumns.map((c) => `${c} = excluded.${c}`).join(", ")}, server_rev = excluded.server_rev ` +
    `WHERE excluded.updated_at >= ${name}.updated_at AND (` +
    `${contentColumns.map((c) => `excluded.${c} IS NOT ${name}.${c}`).join(" OR ")})`;
  const pullSql =
    `SELECT user_id, ${names.join(", ")}, server_rev FROM ${name} ` +
    `WHERE user_id = ?1 AND server_rev > ?2 ORDER BY server_rev ASC LIMIT ?3`;
  return {
    name,
    columns,
    contentColumns,
    updateColumns,
    boolColumns: columns.filter((c) => c.type === "bool").map((c) => c.name),
    columnNames: new Set(names),
    upsertSql,
    pullSql,
  };
}

export const SCHEMAS: Record<SyncTable, TableSchema> = {
  tickets: build("tickets"),
  trips: build("trips"),
  favorite_routes: build("favorite_routes"),
  benefits: build("benefits"),
};

export function isSyncTable(s: unknown): s is SyncTable {
  return typeof s === "string" && (SYNC_TABLES as readonly string[]).includes(s);
}

export const RESERVE_SQL = "UPDATE sync_state SET server_rev = server_rev + ?1 WHERE id = 1 RETURNING server_rev";

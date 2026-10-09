// Push row validation and normalization (docs/CLOUDFLARE_BACKEND.md §3.4–§3.6).
import { ApiError, isPlainObject } from "../http";
import { canonicalTimestamp } from "../timestamps";
import type { Column, TableSchema } from "./schema";

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const LONE_SURROGATE_RE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
const MAX_REAL = 1e9;
const INT_MIN = -2147483648;
const INT_MAX = 2147483647;

export type NormalizedValue = string | number | null;
export type NormalizedRow = Record<string, NormalizedValue>;

function invalid(index: number, field: string, reason: string): ApiError {
  return new ApiError(422, "invalid_row", `Row ${index}: field ${field} is invalid (${reason}).`, {
    details: { index, field, reason },
  });
}

function normalizeValue(col: Column, value: unknown, index: number): NormalizedValue {
  switch (col.type) {
    case "uuid":
      if (typeof value !== "string") throw invalid(index, col.name, "type");
      if (!UUID_RE.test(value)) throw invalid(index, col.name, "format");
      return value.toLowerCase();
    case "text":
      if (typeof value !== "string") throw invalid(index, col.name, "type");
      if (value.length > (col.max ?? 0)) throw invalid(index, col.name, "too_long");
      if (value.includes("\u0000")) throw invalid(index, col.name, "nul_character");
      if (LONE_SURROGATE_RE.test(value)) throw invalid(index, col.name, "invalid_unicode");
      return value;
    case "real":
      if (typeof value !== "number" || !Number.isFinite(value)) throw invalid(index, col.name, "type");
      if (Math.abs(value) > MAX_REAL) throw invalid(index, col.name, "out_of_range");
      return value === 0 ? 0 : value; // -0 → 0
    case "int":
      if (typeof value !== "number" || !Number.isInteger(value)) throw invalid(index, col.name, "type");
      if (value < INT_MIN || value > INT_MAX) throw invalid(index, col.name, "out_of_range");
      return value === 0 ? 0 : value;
    case "bool":
      if (typeof value !== "boolean") throw invalid(index, col.name, "type");
      return value ? 1 : 0;
    case "timestamp": {
      if (typeof value !== "string") throw invalid(index, col.name, "type");
      const canonical = canonicalTimestamp(value);
      if (canonical === null) throw invalid(index, col.name, "format");
      return canonical;
    }
  }
}

/**
 * Validates and normalizes one push row. Unknown keys → 422 unknown_field, a foreign user_id → 422 user_mismatch,
 * everything else → 422 invalid_row with {index, field, reason}.
 */
export function normalizeRow(schema: TableSchema, raw: unknown, index: number, userId: string): NormalizedRow {
  if (!isPlainObject(raw)) throw new ApiError(400, "invalid_request", `Row ${index} is not an object.`);
  for (const key of Object.keys(raw)) {
    if (schema.columnNames.has(key) || key === "server_rev") continue;
    if (key === "user_id") {
      const v = raw.user_id;
      if (v === null) continue;
      if (typeof v !== "string" || v.toLowerCase() !== userId) {
        throw new ApiError(422, "user_mismatch", `Row ${index}: user_id does not match the signed-in user.`, {
          details: { index, field: "user_id" },
        });
      }
      continue;
    }
    throw new ApiError(422, "unknown_field", `Row ${index}: unknown field.`, { details: { index, field: key.slice(0, 100) } });
  }
  const out: NormalizedRow = {};
  for (const col of schema.columns) {
    const value = Object.hasOwn(raw, col.name) ? raw[col.name] : undefined;
    if (value === undefined || value === null) {
      if (col.required) throw invalid(index, col.name, "required");
      // Left out of the JSON: the upsert keeps the stored value, a new row gets the default (schema.ts).
      if (col.keepWhenAbsent) continue;
      out[col.name] = col.nullable ? null : (col.default ?? null);
      continue;
    }
    out[col.name] = normalizeValue(col, value, index);
  }
  return out;
}

export interface PreparedRows {
  rows: NormalizedRow[];
  received: number;
}

/**
 * Normalizes every row (the first failure rejects the whole request), clamps far-future updated_at to now and keeps
 * one row per id (greatest updated_at; on a tie the last occurrence).
 */
export function prepareRows(schema: TableSchema, rawRows: unknown[], userId: string, nowCanonical: string, clampLimit: string): PreparedRows {
  const byId = new Map<string, { row: NormalizedRow; order: number }>();
  rawRows.forEach((raw, index) => {
    const row = normalizeRow(schema, raw, index, userId);
    if ((row.updated_at as string) > clampLimit) row.updated_at = nowCanonical;
    const id = row.id as string;
    const existing = byId.get(id);
    if (!existing) {
      byId.set(id, { row, order: index });
    } else if ((row.updated_at as string) >= (existing.row.updated_at as string)) {
      byId.set(id, { row, order: existing.order });
    }
  });
  const rows = [...byId.values()].sort((a, b) => a.order - b.order).map((e) => e.row);
  return { rows, received: rawRows.length };
}

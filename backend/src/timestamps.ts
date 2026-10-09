// Wire timestamps (docs/CLOUDFLARE_BACKEND.md §3.4): RFC 3339 with an offset in, canonical
// "YYYY-MM-DDTHH:MM:SS.ffffffZ" out. JS Date has only milliseconds, so the fraction is carried separately and the
// microseconds survive.

const TIMESTAMP_RE =
  /^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,12}))?)?(?:([Zz])|([+-])(\d{2})(?::?(\d{2}))?)$/;

const MAX_LENGTH = 40;

function pad(n: number, width: number): string {
  return String(n).padStart(width, "0");
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Canonical UTC form, or null when the value is not an accepted timestamp. */
export function canonicalTimestamp(input: string): string | null {
  if (input.length > MAX_LENGTH) return null;
  const m = TIMESTAMP_RE.exec(input);
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  const hour = Number(m[4]);
  const minute = Number(m[5]);
  const second = m[6] === undefined ? 0 : Number(m[6]);
  const fraction = (m[7] ?? "").padEnd(6, "0").slice(0, 6);
  if (year < 1900 || year > 9999) return null;
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;

  let offsetMinutes = 0;
  if (m[8] === undefined) {
    const offH = Number(m[10]);
    const offM = m[11] === undefined ? 0 : Number(m[11]);
    if (offH > 23 || offM > 59) return null;
    offsetMinutes = (offH * 60 + offM) * (m[9] === "-" ? -1 : 1);
  }
  const ms = Date.UTC(year, month - 1, day, hour, minute, second) - offsetMinutes * 60_000;
  const d = new Date(ms);
  const y = d.getUTCFullYear();
  if (y < 1000 || y > 9999) return null; // keep the fixed width (string order = time order)
  return (
    `${pad(y, 4)}-${pad(d.getUTCMonth() + 1, 2)}-${pad(d.getUTCDate(), 2)}T` +
    `${pad(d.getUTCHours(), 2)}:${pad(d.getUTCMinutes(), 2)}:${pad(d.getUTCSeconds(), 2)}.${fraction}Z`
  );
}

/** Canonical form of a millisecond epoch value (internal timestamps, server time). */
export function canonicalFromMs(ms: number): string {
  // toISOString: "YYYY-MM-DDTHH:MM:SS.mmmZ" for years 0–9999.
  return `${new Date(ms).toISOString().slice(0, 23)}000Z`;
}

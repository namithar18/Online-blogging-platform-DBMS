import "server-only";
import { HttpError } from "@/lib/http";

/** Name 1-100 characters, same rule as the communities table CHECK. */
export function parseCommunityName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (name.length === 0 || name.length > 100) {
    throw new HttpError(400, "Name is required (at most 100 characters)");
  }
  return name;
}

/** Optional description: text up to 2000 characters, or null to clear it. */
export function parseDescription(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== "string" || value.length > 2000) {
    throw new HttpError(400, "description must be text (at most 2000 characters) or null");
  }
  return value.trim() || null;
}

/** Map constraint violations on communities to client errors. */
export function communityWriteError(err: unknown): unknown {
  const code = (err as { code?: string }).code;
  if (code === "23505") return new HttpError(409, "A community with this name already exists"); // UNIQUE (name)
  if (code === "23514") return new HttpError(400, "Invalid community details");               // CHECK, or C5 trigger
  return err;
}

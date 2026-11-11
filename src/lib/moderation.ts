import "server-only";
import { HttpError } from "@/lib/http";

export type ModerationAction = "remove" | "restore";

/** Read { action: "remove" | "restore" } from a moderation request body. */
export function parseAction(body: Record<string, unknown>): ModerationAction {
  if (body.action === "remove" || body.action === "restore") return body.action;
  throw new HttpError(400, 'action must be "remove" or "restore"');
}

/**
 * After a conditional UPDATE matched no row, tell "does not exist" (404)
 * apart from "exists but is already in that state" (409).
 */
export function noRowChanged(exists: boolean, what: string, action: ModerationAction): HttpError {
  if (!exists) return new HttpError(404, `${what} not found`);
  return new HttpError(409, action === "remove" ? `${what} is already removed` : `${what} is not removed`);
}

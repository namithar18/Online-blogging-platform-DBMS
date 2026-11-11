import "server-only";
import { getDbPool } from "@/lib/db";
import { HttpError } from "@/lib/http";
import { readSessionUserId } from "@/lib/session";

export type Role = "USER" | "ADMIN";

export interface CurrentUser {
  // users.user_id is bigint; pg returns bigint as a string because it can
  // exceed JavaScript's safe integer range. Pass it straight back as $1.
  userId: string;
  name: string;
  email: string;
  role: Role;
}

/**
 * The logged-in user, or null. Reads the user from the database on every
 * call, so a deleted account or a changed role takes effect immediately.
 */
export async function getCurrentUser(): Promise<CurrentUser | null> {
  const userId = await readSessionUserId();
  if (!userId) return null;

  const { rows } = await getDbPool().query<CurrentUser>(
    `SELECT user_id AS "userId", name, email, role
     FROM users
     WHERE user_id = $1`,
    [userId],
  );
  return rows[0] ?? null;
}

/**
 * Use at the top of every API route that needs a logged-in user.
 * Throws HttpError 401 when there is no valid session.
 *
 *   const user = await requireUser();
 */
export async function requireUser(): Promise<CurrentUser> {
  const user = await getCurrentUser();
  if (!user) throw new HttpError(401, "Not logged in");
  return user;
}

/**
 * Like requireUser, and also 403 unless the role is ADMIN. Authorisation
 * is checked here in the API, never only by hiding buttons in the UI.
 */
export async function requireAdmin(): Promise<CurrentUser> {
  const user = await requireUser();
  if (user.role !== "ADMIN") throw new HttpError(403, "Admins only");
  return user;
}

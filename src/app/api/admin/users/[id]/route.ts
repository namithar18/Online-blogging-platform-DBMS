import { requireAdmin } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

/**
 * PATCH /api/admin/users/:id  { role: "USER" | "ADMIN" }  (admin only)
 *
 * An admin cannot change their own role, so the last admin can never
 * demote themselves and leave the platform with nobody to moderate it.
 * The new role applies at once: requireUser() reads the role from the
 * database on every request, not from the session cookie.
 * Demoting an admin does not touch communities they already created
 * (C5 is only checked when a community row is written; see triggers.sql).
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    const admin = await requireAdmin();
    const userId = parseId((await context.params).id);
    if (!userId) throw new HttpError(404, "User not found");

    const { role } = await readJson(request);
    if (role !== "USER" && role !== "ADMIN") throw new HttpError(400, "role must be USER or ADMIN");
    if (userId === admin.userId) throw new HttpError(409, "You cannot change your own role");

    // The CHECK (role IN ('USER','ADMIN')) on users is the database-level
    // guard for the same rule (C3).
    const { rows } = await getDbPool().query(
      `UPDATE users SET role = $2
       WHERE user_id = $1
       RETURNING user_id AS "userId", name, email, role`,
      [userId, role],
    );
    if (rows.length === 0) throw new HttpError(404, "User not found");
    return Response.json({ user: rows[0] });
  } catch (err) {
    return errorResponse(err);
  }
}

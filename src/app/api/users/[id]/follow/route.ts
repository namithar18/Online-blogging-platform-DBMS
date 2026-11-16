import { getCurrentUser, requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function targetIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "User not found");
  return id;
}

/**
 * GET /api/users/:id/follow -> 200 { userId, followerCount, followingCount, isFollowing }
 * Public. Counts are correlated subqueries computed per request, never
 * stored. isFollowing is false for anonymous callers (NULL never matches).
 */
export async function GET(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await getCurrentUser();
    const targetId = await targetIdFrom(context);
    const { rows } = await getDbPool().query(
      `SELECT u.user_id AS "userId",
              (SELECT count(*) FROM follows f
                WHERE f.followee_id = u.user_id)::int AS "followerCount",
              (SELECT count(*) FROM follows f
                WHERE f.follower_id = u.user_id)::int AS "followingCount",
              EXISTS (SELECT 1 FROM follows f
                       WHERE f.follower_id = $2::bigint
                         AND f.followee_id = u.user_id) AS "isFollowing"
         FROM users u
        WHERE u.user_id = $1`,
      [targetId, user ? user.userId : null],
    );
    if (!rows.length) throw new HttpError(404, "User not found");
    return Response.json(rows[0]);
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * POST /api/users/:id/follow -> 201 { follow }
 * The follower is always the session user. Nothing is checked first; the
 * database decides, then we translate:
 *   23514 follows_not_self (C1)  -> 400  (checked before the FKs fire)
 *   23505 primary key            -> 409  already following
 *   23503 followee FK            -> 404  no such user
 * A "userId === target" check in JS would only protect this one code path;
 * the CHECK protects every path, including future ones and raw SQL.
 */
export async function POST(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const targetId = await targetIdFrom(context);
    try {
      const { rows } = await getDbPool().query(
        `INSERT INTO follows (follower_id, followee_id)
         VALUES ($1, $2)
         RETURNING followee_id AS "followeeId", followed_at AS "followedAt"`,
        [user.userId, targetId],
      );
      return Response.json({ follow: rows[0] }, { status: 201 });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "23514") throw new HttpError(400, "You cannot follow yourself");
      if (code === "23505") throw new HttpError(409, "You already follow this user");
      if (code === "23503") throw new HttpError(404, "User not found");
      throw err;
    }
  } catch (err) {
    return errorResponse(err);
  }
}

/** DELETE /api/users/:id/follow -> 200 { unfollowed } | 404 if not following. */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const targetId = await targetIdFrom(context);
    const { rowCount } = await getDbPool().query(
      `DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2`,
      [user.userId, targetId],
    );
    if (!rowCount) throw new HttpError(404, "You do not follow this user");
    return Response.json({ unfollowed: targetId });
  } catch (err) {
    return errorResponse(err);
  }
}
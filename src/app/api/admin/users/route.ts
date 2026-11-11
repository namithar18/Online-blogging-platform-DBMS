import { requireAdmin } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";

export const runtime = "nodejs";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

/**
 * GET /api/admin/users?role=&limit=&offset=  (admin only) -> 200 { users }
 * password_hash is never selected, so it can never reach the client.
 *
 * Posts and comments are counted in separate derived tables BEFORE the
 * join, as in the popular_posts view: joining posts and comments directly
 * would multiply the rows (3 posts x 4 comments = 12 rows per user).
 */
export async function GET(request: Request): Promise<Response> {
  try {
    await requireAdmin();
    const params = new URL(request.url).searchParams;
    const role = params.get("role");
    if (role !== null && role !== "USER" && role !== "ADMIN") {
      throw new HttpError(400, "role must be USER or ADMIN");
    }
    const limit = Math.min(Math.max(Number(params.get("limit")) || DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(Number(params.get("offset")) || 0, 0);

    const { rows } = await getDbPool().query(
      `SELECT u.user_id    AS "userId",
              u.name,
              u.email,
              u.role,
              u.created_at AS "createdAt",
              COALESCE(p.post_count, 0)::int    AS "postCount",
              COALESCE(c.comment_count, 0)::int AS "commentCount"
       FROM users u
       LEFT JOIN (SELECT author_id, count(*) AS post_count
                  FROM posts GROUP BY author_id) AS p ON p.author_id = u.user_id
       LEFT JOIN (SELECT author_id, count(*) AS comment_count
                  FROM comments GROUP BY author_id) AS c ON c.author_id = u.user_id
       WHERE ($1::text IS NULL OR u.role = $1)
       ORDER BY u.user_id
       LIMIT $2 OFFSET $3`,
      [role, limit, offset],
    );
    return Response.json({ users: rows }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err);
  }
}

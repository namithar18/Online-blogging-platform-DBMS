import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { errorResponse } from "@/lib/http";

export const runtime = "nodejs";

/**
 * GET /api/activity -> 200 { history } (the caller's own, last 50 posts)
 * GROUP BY collapses repeated views of a post into one row with an
 * aggregate count and the latest time. published_posts is a view, so it
 * has no primary key for PostgreSQL to rely on: every non-aggregated
 * column (post_id, title) must be listed in GROUP BY.
 */
export async function GET(): Promise<Response> {
  try {
    const user = await requireUser();
    const { rows } = await getDbPool().query(
      `SELECT p.post_id AS "postId", p.title,
              count(*)::int AS "views",
              max(a.occurred_at) AS "lastViewedAt"
         FROM reading_activity a
         JOIN published_posts p ON p.post_id = a.post_id
        WHERE a.user_id = $1
        GROUP BY p.post_id, p.title
        ORDER BY max(a.occurred_at) DESC
        LIMIT 50`,
      [user.userId],
    );
    return Response.json({ history: rows });
  } catch (err) {
    return errorResponse(err);
  }
}
import { getCurrentUser, requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { errorResponse } from "@/lib/http";

export const runtime = "nodejs";

/**
 * GET /api/communities            -> 200 { communities }
 * GET /api/communities?mine=true  -> only the caller's communities (401 if logged out)
 *
 * Counts are computed on every request, never stored. Each count is its own
 * correlated subquery: joining community_members and posts to the same
 * community would multiply rows (members x posts) and make both counts wrong.
 * postCount reads published_posts, not posts, so drafts and removed posts
 * are never counted (C7). EXISTS stops at the first matching row.
 */
export async function GET(request: Request): Promise<Response> {
  try {
    const mine = new URL(request.url).searchParams.get("mine") === "true";

    // Anonymous callers may list communities; only ?mine=true needs a session.
    const user = mine ? await requireUser() : await getCurrentUser();
    const userId = user ? user.userId : null;

    const { rows } = await getDbPool().query(
      `SELECT c.community_id AS "communityId",
              c.name,
              c.description,
              c.created_at AS "createdAt",
              (SELECT count(*) FROM community_members m
                WHERE m.community_id = c.community_id)::int AS "memberCount",
              (SELECT count(*) FROM published_posts p
                WHERE p.community_id = c.community_id)::int AS "postCount",
              EXISTS (SELECT 1 FROM community_members m2
                       WHERE m2.community_id = c.community_id
                         AND m2.user_id = $1::bigint) AS "isMember"
         FROM communities c
        WHERE ($2::boolean = false
               OR EXISTS (SELECT 1 FROM community_members m3
                           WHERE m3.community_id = c.community_id
                             AND m3.user_id = $1::bigint))
        ORDER BY c.community_id`,
      [userId, mine],
    );
    return Response.json({ communities: rows });
  } catch (err) {
    return errorResponse(err);
  }
}
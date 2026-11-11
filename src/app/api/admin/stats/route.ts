import { requireAdmin } from "@/lib/auth";
import { errorResponse } from "@/lib/http";
import { withTransaction } from "@/lib/transaction";

export const runtime = "nodejs";

const DEFAULT_DAYS = 30;
const MAX_DAYS = 3650;

/**
 * GET /api/admin/stats?days=  (admin only) -> 200 { ...counts }
 *
 * All queries run in ONE transaction at REPEATABLE READ: every statement
 * sees the same snapshot, taken at the first query. Under the default
 * READ COMMITTED each statement takes a fresh snapshot, so a post created
 * between two queries could be counted in one total and missing from
 * another. READ ONLY tells PostgreSQL nothing will be written.
 */
export async function GET(request: Request): Promise<Response> {
  try {
    await requireAdmin();
    const daysParam = Number(new URL(request.url).searchParams.get("days"));
    const days = Math.min(Math.max(Math.trunc(daysParam) || DEFAULT_DAYS, 1), MAX_DAYS);

    const stats = await withTransaction(async (client) => {
      // Must be the first statement after BEGIN.
      await client.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY");

      const usersByRole = await client.query(
        `SELECT role, count(*)::int AS count FROM users GROUP BY role ORDER BY role`,
      );
      const postsByStatus = await client.query(
        `SELECT status, count(*)::int AS count FROM posts GROUP BY status ORDER BY status`,
      );
      const commentsByStatus = await client.query(
        `SELECT status, count(*)::int AS count FROM comments GROUP BY status ORDER BY status`,
      );

      // LEFT JOIN keeps communities with no published posts (count 0).
      // Published posts only, through the C7 view.
      const topCommunities = await client.query(
        `SELECT c.community_id AS "communityId",
                c.name,
                count(p.post_id)::int AS "publishedPosts",
                (SELECT count(*) FROM community_members m
                 WHERE m.community_id = c.community_id)::int AS members
         FROM communities c
         LEFT JOIN published_posts p ON p.community_id = c.community_id
         GROUP BY c.community_id, c.name
         ORDER BY "publishedPosts" DESC, c.name
         LIMIT 5`,
      );

      // NOT EXISTS subquery: communities with no posts at all, the only
      // ones DELETE /api/admin/communities/:id will accept (RESTRICT).
      const emptyCommunities = await client.query(
        `SELECT c.community_id AS "communityId", c.name
         FROM communities c
         WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.community_id = c.community_id)
         ORDER BY c.name`,
      );

      // HAVING filters GROUPS (after aggregation), WHERE filters rows
      // (before it): only readers with at least 2 views in the window.
      const activeReaders = await client.query(
        `SELECT u.user_id AS "userId",
                u.name,
                count(*)::int                   AS views,
                count(DISTINCT ra.post_id)::int AS "distinctPosts"
         FROM reading_activity ra
         JOIN users u ON u.user_id = ra.user_id
         WHERE ra.occurred_at >= now() - make_interval(days => $1)
         GROUP BY u.user_id, u.name
         HAVING count(*) >= 2
         ORDER BY views DESC, u.name
         LIMIT 10`,
        [days],
      );

      return {
        usersByRole: usersByRole.rows,
        postsByStatus: postsByStatus.rows,
        commentsByStatus: commentsByStatus.rows,
        topCommunities: topCommunities.rows,
        emptyCommunities: emptyCommunities.rows,
        activeReaders: { days, readers: activeReaders.rows },
      };
    });

    return Response.json(stats, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err);
  }
}

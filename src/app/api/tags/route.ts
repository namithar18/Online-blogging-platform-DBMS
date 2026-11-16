import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";

export const runtime = "nodejs";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

/**
 * GET /api/tags?minPosts=&limit=   (public)
 * Tags with the number of PUBLISHED posts that use each, most used first.
 *
 * - LEFT JOIN keeps tags that have no published post, so minPosts=0 can
 *   list them (the count is then 0, not a missing row).
 * - The join goes through published_posts, so tags used only by drafts,
 *   unpublished or removed posts do not leak into public counts (C7).
 * - count(p.post_id) counts only real posts; count(*) would count the
 *   NULL row a LEFT JOIN produces and report 1 for an unused tag.
 * - HAVING filters on the aggregate, which WHERE cannot do. Default
 *   minPosts is 1, so a public tag list shows only tags worth clicking.
 */
export async function GET(request: Request): Promise<Response> {
  try {
    const params = new URL(request.url).searchParams;
    const limit = Math.min(Math.max(Number(params.get("limit")) || DEFAULT_LIMIT, 1), MAX_LIMIT);

    const minRaw = params.get("minPosts");
    const minPosts = minRaw === null ? 1 : Number(minRaw);
    if (!Number.isInteger(minPosts) || minPosts < 0) {
      throw new HttpError(400, "minPosts must be a whole number, 0 or more");
    }

    const { rows } = await getDbPool().query(
      `SELECT t.tag_id            AS "tagId",
              t.tag_name          AS "tagName",
              count(p.post_id)::int AS "postCount"
       FROM tags t
       LEFT JOIN post_tags pt       ON pt.tag_id  = t.tag_id
       LEFT JOIN published_posts p  ON p.post_id  = pt.post_id
       GROUP BY t.tag_id, t.tag_name
       HAVING count(p.post_id) >= $1
       ORDER BY "postCount" DESC, t.tag_name
       LIMIT $2`,
      [minPosts, limit],
    );
    return Response.json({ tags: rows });
  } catch (err) {
    return errorResponse(err);
  }
}
import { getCurrentUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { EMBEDDING_MODEL } from "@/lib/embeddings";
import { HttpError, errorResponse } from "@/lib/http";
import { canView, getPostDetail, parseId } from "@/lib/posts";

export const runtime = "nodejs";

const DEFAULT_LIMIT = 5;
const MAX_LIMIT = 20;

type Context = { params: Promise<{ id: string }> };

/**
 * GET /api/posts/:id/similar?limit=  -> 200 { posts }
 * The published posts closest in meaning to this one: same query as
 * db/advanced/vector_search.sql Part 1. Uses the stored embedding, so no
 * model call is needed.
 */
export async function GET(request: Request, context: Context): Promise<Response> {
  try {
    const postId = parseId((await context.params).id);
    const post = postId ? await getPostDetail(postId) : null;
    // The source post must be visible to the caller (a draft only to its
    // author and admins); the RESULTS are always published posts only.
    if (!postId || !post || !canView(post, await getCurrentUser())) {
      throw new HttpError(404, "Post not found");
    }

    const limitParam = Number(new URL(request.url).searchParams.get("limit"));
    const limit = Math.min(Math.max(limitParam || DEFAULT_LIMIT, 1), MAX_LIMIT);

    const pool = getDbPool();
    const { rowCount } = await pool.query(
      "SELECT 1 FROM post_embeddings WHERE post_id = $1 AND model_name = $2",
      [postId, EMBEDDING_MODEL],
    );
    if (!rowCount) return Response.json({ posts: [] }); // nothing to compare with

    // The source vector comes from a scalar subquery, which PostgreSQL runs
    // once before the main query (an InitPlan): ORDER BY then compares every
    // row with one fixed vector, the shape the HNSW index can serve.
    // similarity = 1 - cosine distance (1 = same meaning, 0 = unrelated).
    const { rows } = await pool.query(
      `SELECT p.post_id      AS "postId",
              p.title,
              left(p.content, 200) AS excerpt,
              p.published_at AS "publishedAt",
              u.name         AS "authorName",
              c.name         AS "communityName",
              round((1 - (e.embedding <=> (SELECT embedding FROM post_embeddings
                                           WHERE post_id = $1 AND model_name = $2)))::numeric, 4)::float8
                             AS similarity
       FROM post_embeddings e
       JOIN published_posts p ON p.post_id = e.post_id          -- C7
       JOIN users u           ON u.user_id = p.author_id
       JOIN communities c     ON c.community_id = p.community_id
       WHERE e.model_name = $2
         AND e.post_id <> $1                                    -- not itself
       ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                                 WHERE post_id = $1 AND model_name = $2)
       LIMIT $3`,
      [postId, EMBEDDING_MODEL, limit],
    );
    return Response.json({ posts: rows });
  } catch (err) {
    return errorResponse(err);
  }
}

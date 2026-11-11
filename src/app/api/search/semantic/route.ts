import { getDbPool } from "@/lib/db";
import { EMBEDDING_MODEL, embed } from "@/lib/embeddings";
import { HttpError, errorResponse } from "@/lib/http";

export const runtime = "nodejs";

const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 20;
const MAX_QUERY_LENGTH = 500;

/**
 * GET /api/search/semantic?q=...&limit=  -> 200 { posts }
 * Search by meaning: the phrase is embedded with the same model as the
 * posts, and the published posts with the closest vectors come first.
 * Unlike full-text search, no word has to match ("how do databases find
 * rows quickly" finds the B-tree post). There is always a "closest"
 * post, so results are ranked by similarity rather than cut off.
 */
export async function GET(request: Request): Promise<Response> {
  try {
    const params = new URL(request.url).searchParams;
    const q = params.get("q")?.trim() ?? "";
    if (q.length === 0 || q.length > MAX_QUERY_LENGTH) {
      throw new HttpError(400, `q is required (at most ${MAX_QUERY_LENGTH} characters)`);
    }
    const limit = Math.min(Math.max(Number(params.get("limit")) || DEFAULT_LIMIT, 1), MAX_LIMIT);

    const vector = await embed(q); // 503 if the model is unavailable

    // $1 is the query vector, sent as one parameter like any other value.
    // ORDER BY embedding <=> constant is the shape the HNSW index serves;
    // published_posts applies C7.
    const { rows } = await getDbPool().query(
      `SELECT p.post_id      AS "postId",
              p.title,
              left(p.content, 200) AS excerpt,
              p.published_at AS "publishedAt",
              u.name         AS "authorName",
              c.name         AS "communityName",
              round((1 - (e.embedding <=> $1::vector))::numeric, 4)::float8 AS similarity
       FROM post_embeddings e
       JOIN published_posts p ON p.post_id = e.post_id
       JOIN users u           ON u.user_id = p.author_id
       JOIN communities c     ON c.community_id = p.community_id
       WHERE e.model_name = $2
       ORDER BY e.embedding <=> $1::vector
       LIMIT $3`,
      [vector, EMBEDDING_MODEL, limit],
    );
    return Response.json({ query: q, posts: rows });
  } catch (err) {
    return errorResponse(err);
  }
}

import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { embed, postText, saveEmbedding } from "@/lib/embeddings";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { getPostDetail, parseId, parsePostInput, postWriteError, saveTags } from "@/lib/posts";
import { withTransaction } from "@/lib/transaction";

export const runtime = "nodejs";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

// Shared column list for both feeds. Tags and counts use correlated
// subqueries: they run only for the (at most 50) rows on this page, using
// the post_id indexes from indexes.sql. Joining popular_posts instead
// would aggregate reactions for EVERY post before LIMIT is applied.
const LIST_COLUMNS = `
  p.post_id      AS "postId",
  p.title,
  left(p.content, 200) AS excerpt,
  p.status,
  p.published_at AS "publishedAt",
  p.updated_at   AS "updatedAt",
  p.author_id    AS "authorId",
  u.name         AS "authorName",
  p.community_id AS "communityId",
  c.name         AS "communityName",
  ARRAY(SELECT t.tag_name FROM post_tags pt JOIN tags t ON t.tag_id = pt.tag_id
        WHERE pt.post_id = p.post_id ORDER BY t.tag_name) AS tags,
  (SELECT count(*) FROM reactions r WHERE r.post_id = p.post_id)::int AS "reactionCount",
  (SELECT count(*) FROM comments cm
   WHERE cm.post_id = p.post_id AND cm.status = 'visible')::int     AS "commentCount"`;

/**
 * GET /api/posts
 *   ?communityId=&authorId=&tag=   optional filters (published posts only, C7)
 *   ?mine=true                     the logged-in author's own posts, any status
 *   ?limit=&offset=                paging (limit at most 50)
 */
export async function GET(request: Request): Promise<Response> {
  try {
    const params = new URL(request.url).searchParams;
    const limit = Math.min(Math.max(Number(params.get("limit")) || DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(Number(params.get("offset")) || 0, 0);

    if (params.get("mine") === "true") {
      // An author's own list reads the posts TABLE: drafts and unpublished
      // posts are theirs to see. Newest change first.
      const user = await requireUser();
      const { rows } = await getDbPool().query(
        `SELECT ${LIST_COLUMNS}
         FROM posts p
         JOIN users u       ON u.user_id      = p.author_id
         JOIN communities c ON c.community_id = p.community_id
         WHERE p.author_id = $1
         ORDER BY p.updated_at DESC, p.post_id DESC
         LIMIT $2 OFFSET $3`,
        [user.userId, limit, offset],
      );
      return Response.json({ posts: rows }, { headers: { "Cache-Control": "no-store" } });
    }

    const communityId = params.has("communityId") ? parseId(params.get("communityId")) : null;
    const authorId = params.has("authorId") ? parseId(params.get("authorId")) : null;
    if ((params.has("communityId") && !communityId) || (params.has("authorId") && !authorId)) {
      throw new HttpError(400, "communityId and authorId must be ids");
    }
    const tag = params.get("tag")?.trim().toLowerCase() || null;

    // "$1 IS NULL OR ..." makes each filter optional while the SQL text
    // stays fixed and fully parameterised, instead of gluing WHERE clauses
    // together as strings.
    const { rows } = await getDbPool().query(
      `SELECT ${LIST_COLUMNS}
       FROM published_posts p
       JOIN users u       ON u.user_id      = p.author_id
       JOIN communities c ON c.community_id = p.community_id
       WHERE ($1::bigint IS NULL OR p.community_id = $1)
         AND ($2::bigint IS NULL OR p.author_id = $2)
         AND ($3::text IS NULL OR EXISTS (
               SELECT 1 FROM post_tags pt JOIN tags t ON t.tag_id = pt.tag_id
               WHERE pt.post_id = p.post_id AND t.tag_name = $3))
       ORDER BY p.published_at DESC, p.post_id DESC
       LIMIT $4 OFFSET $5`,
      [communityId, authorId, tag, limit, offset],
    );
    return Response.json({ posts: rows });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * POST /api/posts  { communityId, title, content, status?, tags? } -> 201 { post }
 * The post row, its tags and its embedding are written in ONE
 * transaction: if any step fails, the post is rolled back too (see
 * db/advanced/transactions.sql).
 */
export async function POST(request: Request): Promise<Response> {
  try {
    const user = await requireUser();
    const input = parsePostInput(await readJson(request), false);

    // Computed BEFORE the transaction starts: running the model takes tens
    // of milliseconds, and no transaction should stay open meanwhile. If
    // the model is unavailable this throws 503 and nothing is saved.
    const vector = await embed(postText(input.title as string, input.content as string));

    let postId: string;
    try {
      postId = await withTransaction(async (client) => {
        // C4: a post created as published gets published_at = now().
        // now() is the transaction start time, the same value created_at
        // gets, so published_at >= created_at holds.
        const { rows } = await client.query<{ postId: string }>(
          `INSERT INTO posts (author_id, community_id, title, content, status, published_at)
           VALUES ($1, $2, $3, $4, $5, CASE WHEN $6 THEN now() END)
           RETURNING post_id AS "postId"`,
          [user.userId, input.communityId, input.title, input.content, input.status,
           input.status === "published"],
        );
        const newId = rows[0].postId;
        await saveTags(client, newId, input.tags ?? []);
        await saveEmbedding(client, newId, vector);
        return newId;
      });
    } catch (err) {
      throw postWriteError(err);
    }

    // Read back after COMMIT, so the response shows what was stored.
    return Response.json({ post: await getPostDetail(postId) }, { status: 201 });
  } catch (err) {
    return errorResponse(err);
  }
}

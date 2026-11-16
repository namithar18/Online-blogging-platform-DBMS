import { getCurrentUser, requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function postIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Post not found");
  return id;
}

/**
 * GET /api/posts/:id/reactions -> 200 { postId, counts, total, myReaction }
 * Counts are computed with GROUP BY on every request, never stored.
 * Only published posts are visible here (C7), so drafts and removed posts
 * give 404 and do not reveal that they exist.
 */
export async function GET(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await getCurrentUser();
    const postId = await postIdFrom(context);
    const pool = getDbPool();

    const exists = await pool.query(`SELECT 1 FROM published_posts WHERE post_id = $1`, [postId]);
    if (!exists.rowCount) throw new HttpError(404, "Post not found");

    const counts = await pool.query(
      `SELECT reaction_type AS "type", count(*)::int AS "count"
         FROM reactions
        WHERE post_id = $1
        GROUP BY reaction_type
        ORDER BY reaction_type`,
      [postId],
    );
    const total = (counts.rows as { count: number }[]).reduce((sum, r) => sum + r.count, 0);

    let myReaction: string | null = null;
    if (user) {
      const mine = await pool.query(
        `SELECT reaction_type AS "type" FROM reactions WHERE post_id = $1 AND user_id = $2`,
        [postId, user.userId],
      );
      myReaction = mine.rows[0]?.type ?? null;
    }
    return Response.json({ postId, counts: counts.rows, total, myReaction });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * PUT /api/posts/:id/reactions  body { "type": "like" | "love" | "insightful" }
 *   -> 201 when the reaction is new, 200 when it replaced an earlier one.
 *
 * The primary key (user_id, post_id) allows ONE reaction per user per post
 * (A4), so "react" and "change my reaction" are the same operation: an upsert.
 * INSERT ... ON CONFLICT DO UPDATE is atomic; SELECT-then-INSERT-or-UPDATE
 * could race. The INSERT ... SELECT FROM published_posts inserts zero rows
 * when the post is not published, which becomes 404 (C7).
 * The allowed types are NOT checked here: the CHECK constraint decides (C3)
 * and 23514 is translated to 400. A value longer than varchar(10) raises
 * 22001 instead, also 400.
 * (xmax = 0) is true only for a freshly inserted row, so we can tell insert
 * from update without a second query.
 */
export async function PUT(request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    const body = await readJson(request);
    const type = body.type === undefined ? "like" : body.type;
    if (typeof type !== "string") throw new HttpError(400, "type must be a string");

    try {
      const { rows } = await getDbPool().query(
        `INSERT INTO reactions (user_id, post_id, reaction_type)
         SELECT $1::bigint, p.post_id, $3::varchar
           FROM published_posts p
          WHERE p.post_id = $2
         ON CONFLICT (user_id, post_id)
         DO UPDATE SET reaction_type = EXCLUDED.reaction_type, reacted_at = now()
         RETURNING post_id AS "postId", reaction_type AS "type",
                   reacted_at AS "reactedAt", (xmax = 0) AS "created"`,
        [user.userId, postId, type],
      );
      if (!rows.length) throw new HttpError(404, "Post not found");
      const { created, ...reaction } = rows[0];
      return Response.json({ reaction }, { status: created ? 201 : 200 });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "23514" || code === "22001") {
        throw new HttpError(400, "type must be one of: like, love, insightful");
      }
      throw err;
    }
  } catch (err) {
    return errorResponse(err);
  }
}

/** DELETE /api/posts/:id/reactions -> 200 { removed } | 404 if you had not reacted. */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    const { rowCount } = await getDbPool().query(
      `DELETE FROM reactions WHERE user_id = $1 AND post_id = $2`,
      [user.userId, postId],
    );
    if (!rowCount) throw new HttpError(404, "You have not reacted to this post");
    return Response.json({ removed: postId });
  } catch (err) {
    return errorResponse(err);
  }
}
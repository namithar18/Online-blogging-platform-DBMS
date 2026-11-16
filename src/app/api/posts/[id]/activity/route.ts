import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

/**
 * POST /api/posts/:id/activity -> 201 { activity }
 * Logs one 'view' of a published post by the session user. Every call adds
 * a NEW row: reading_activity is an entity with its own activity_id, not an
 * M:N table, because repeated views of one post are separate facts (so
 * there is deliberately no unique key and no 409). The type is fixed to
 * 'view', the only value the C3 CHECK allows; the client sends nothing.
 * INSERT ... SELECT FROM published_posts: zero rows -> 404 (C7).
 */
export async function POST(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = parseId((await context.params).id);
    if (!postId) throw new HttpError(404, "Post not found");

    const { rows } = await getDbPool().query(
      `INSERT INTO reading_activity (user_id, post_id, activity_type)
       SELECT $1::bigint, p.post_id, 'view'::varchar
         FROM published_posts p
        WHERE p.post_id = $2
       RETURNING activity_id AS "activityId", post_id AS "postId",
                 activity_type AS "activityType", occurred_at AS "occurredAt"`,
      [user.userId, postId],
    );
    if (!rows.length) throw new HttpError(404, "Post not found");
    return Response.json({ activity: rows[0] }, { status: 201 });
  } catch (err) {
    return errorResponse(err);
  }
}
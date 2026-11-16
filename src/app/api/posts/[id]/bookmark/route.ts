import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function postIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Post not found");
  return id;
}

/**
 * POST /api/posts/:id/bookmark -> 201 { bookmark }
 * One atomic INSERT ... SELECT FROM published_posts: zero rows means the
 * post is missing or not published -> 404 (C7). A second bookmark of the
 * same post breaks the primary key (user_id, post_id): 23505 -> 409.
 * No SELECT-before-INSERT, because two requests could both pass it.
 */
export async function POST(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    try {
      const { rows } = await getDbPool().query(
        `INSERT INTO bookmarks (user_id, post_id)
         SELECT $1::bigint, p.post_id
           FROM published_posts p
          WHERE p.post_id = $2
         RETURNING post_id AS "postId", bookmarked_at AS "bookmarkedAt"`,
        [user.userId, postId],
      );
      if (!rows.length) throw new HttpError(404, "Post not found");
      return Response.json({ bookmark: rows[0] }, { status: 201 });
    } catch (err) {
      if ((err as { code?: string }).code === "23505") {
        throw new HttpError(409, "Post is already bookmarked");
      }
      throw err;
    }
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * DELETE /api/posts/:id/bookmark -> 200 { removed } | 404 if not bookmarked.
 * Works even if the post has since been unpublished, so a user can always
 * clean up their own list.
 */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    const { rowCount } = await getDbPool().query(
      `DELETE FROM bookmarks WHERE user_id = $1 AND post_id = $2`,
      [user.userId, postId],
    );
    if (!rowCount) throw new HttpError(404, "Post is not bookmarked");
    return Response.json({ removed: postId });
  } catch (err) {
    return errorResponse(err);
  }
}
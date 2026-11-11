import type { PoolClient } from "pg";
import { type CurrentUser, getCurrentUser, requireUser } from "@/lib/auth";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { canView, getPostDetail, parseId, parsePostInput, postWriteError, saveTags } from "@/lib/posts";
import { withTransaction } from "@/lib/transaction";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function postIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Post not found");
  return id;
}

/**
 * Lock the post row and check the caller may change it. FOR UPDATE holds
 * a row lock until COMMIT/ROLLBACK: a second edit or delete of the same
 * post waits here instead of both reading the old row and the later
 * write silently overwriting the earlier one (lost update).
 */
async function lockOwnPost(client: PoolClient, postId: string, user: CurrentUser): Promise<void> {
  const { rows } = await client.query<{ authorId: string; status: string }>(
    `SELECT author_id AS "authorId", status
     FROM posts
     WHERE post_id = $1
     FOR UPDATE`,
    [postId],
  );
  const post = rows[0];
  if (!post) throw new HttpError(404, "Post not found");
  if (post.authorId !== user.userId) throw new HttpError(403, "You can only change your own posts");
  // Keep moderation decisions and their evidence intact.
  if (post.status === "removed") throw new HttpError(409, "This post was removed by a moderator");
}

// GET /api/posts/:id -> 200 { post }, or 404 if missing or not visible (C7).
export async function GET(_request: Request, context: Context): Promise<Response> {
  try {
    const postId = await postIdFrom(context);
    const post = await getPostDetail(postId);
    if (!post || !canView(post, await getCurrentUser())) {
      throw new HttpError(404, "Post not found");
    }
    return Response.json({ post }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * PATCH /api/posts/:id  any of { communityId, title, content, status, tags }
 * Author only. Fields not sent keep their value; tags, when sent, replace
 * the whole list. updated_at is set by the posts_set_updated_at trigger.
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    const input = parsePostInput(await readJson(request), true);

    try {
      await withTransaction(async (client) => {
        await lockOwnPost(client, postId, user);

        // COALESCE($n, column): NULL means "not sent", keep the old value.
        // published_at is set only the FIRST time a post is published (C4);
        // unpublishing or re-publishing keeps the original date.
        await client.query(
          `UPDATE posts
           SET community_id = COALESCE($2, community_id),
               title        = COALESCE($3, title),
               content      = COALESCE($4, content),
               status       = COALESCE($5, status),
               published_at = CASE WHEN $6 THEN COALESCE(published_at, now())
                                   ELSE published_at END
           WHERE post_id = $1`,
          [postId, input.communityId ?? null, input.title ?? null, input.content ?? null,
           input.status ?? null, input.status === "published"],
        );
        if (input.tags !== undefined) {
          await saveTags(client, postId, input.tags);
        }
      });
    } catch (err) {
      throw postWriteError(err);
    }

    return Response.json({ post: await getPostDetail(postId) });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * DELETE /api/posts/:id  Author only. A real DELETE: ON DELETE CASCADE in
 * schema.sql removes the post's tags links, comments, reactions,
 * bookmarks, reading activity and embeddings with it. Admin moderation
 * uses status = 'removed' (soft delete) instead.
 */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);

    await withTransaction(async (client) => {
      await lockOwnPost(client, postId, user);
      await client.query("DELETE FROM posts WHERE post_id = $1", [postId]);
    });

    return Response.json({ deleted: postId });
  } catch (err) {
    return errorResponse(err);
  }
}

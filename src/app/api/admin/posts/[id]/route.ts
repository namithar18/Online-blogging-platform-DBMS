import { requireAdmin } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { noRowChanged, parseAction } from "@/lib/moderation";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

/**
 * PATCH /api/admin/posts/:id  { action: "remove" | "restore" }  (admin only)
 *
 * Soft delete: the row stays and only status changes. Comments, reactions
 * and history are kept, and published_posts (C7) hides the post from the
 * feed, full-text and semantic search at once. Authors cannot edit or
 * delete a removed post (409 in /api/posts/:id).
 *
 * Restore sets 'unpublished', not the earlier status: the schema keeps no
 * history, so the author decides whether to publish again. A moderation
 * log table would be needed to restore the exact previous state.
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    await requireAdmin();
    const postId = parseId((await context.params).id);
    if (!postId) throw new HttpError(404, "Post not found");
    const action = parseAction(await readJson(request));

    // The WHERE clause makes the change conditional, in one atomic
    // statement: remove only if not removed yet, restore only if removed.
    const pool = getDbPool();
    const { rows } = await pool.query<{ postId: string; status: string }>(
      action === "remove"
        ? `UPDATE posts SET status = 'removed'
           WHERE post_id = $1 AND status <> 'removed'
           RETURNING post_id AS "postId", status`
        : `UPDATE posts SET status = 'unpublished'
           WHERE post_id = $1 AND status = 'removed'
           RETURNING post_id AS "postId", status`,
      [postId],
    );
    if (rows.length === 0) {
      const { rowCount } = await pool.query("SELECT 1 FROM posts WHERE post_id = $1", [postId]);
      throw noRowChanged(Boolean(rowCount), "Post", action);
    }
    return Response.json({ post: rows[0] });
  } catch (err) {
    return errorResponse(err);
  }
}

import { requireAdmin } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { noRowChanged, parseAction } from "@/lib/moderation";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

/**
 * PATCH /api/admin/comments/:id  { action: "remove" | "restore" }  (admin only)
 *
 * Soft delete instead of DELETE: replies point at their parent through
 * the composite FK (parent_comment_id, post_id) (C2). Deleting a parent
 * with replies is refused by that FK, and CASCADE would destroy other
 * users' replies. Setting status = 'removed' keeps the thread intact; the
 * UI shows "[removed]" in its place and popular_posts stops counting it.
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    await requireAdmin();
    const commentId = parseId((await context.params).id);
    if (!commentId) throw new HttpError(404, "Comment not found");
    const action = parseAction(await readJson(request));

    const pool = getDbPool();
    const { rows } = await pool.query<{ commentId: string; status: string }>(
      `UPDATE comments
       SET status = $2
       WHERE comment_id = $1 AND status <> $2
       RETURNING comment_id AS "commentId", status`,
      [commentId, action === "remove" ? "removed" : "visible"],
    );
    if (rows.length === 0) {
      const { rowCount } = await pool.query("SELECT 1 FROM comments WHERE comment_id = $1", [commentId]);
      throw noRowChanged(Boolean(rowCount), "Comment", action);
    }
    return Response.json({ comment: rows[0] });
  } catch (err) {
    return errorResponse(err);
  }
}

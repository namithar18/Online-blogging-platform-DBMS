import { requireUser } from "@/lib/auth";
import { parseCommentContent, whyCommentNotChanged } from "@/lib/comments";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function commentIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Comment not found");
  return id;
}

/**
 * PATCH /api/comments/:id  { content } -> 200 { comment }   (author only)
 * The ownership and status checks are part of the UPDATE's WHERE clause:
 * one atomic statement, and a stranger's or a removed comment simply
 * matches no row. Only then does whyCommentNotChanged() pick 404, 403 or
 * 409. updated_at is set by the comments_set_updated_at trigger, so it is
 * not written here.
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const commentId = await commentIdFrom(context);
    const content = parseCommentContent((await readJson(request)).content);

    const { rows } = await getDbPool().query(
      `UPDATE comments
       SET content = $2
       WHERE comment_id = $1 AND author_id = $3 AND status = 'visible'
       RETURNING comment_id        AS "commentId",
                 post_id           AS "postId",
                 parent_comment_id AS "parentCommentId",
                 content,
                 created_at        AS "createdAt",
                 updated_at        AS "updatedAt"`,
      [commentId, content, user.userId],
    );
    if (rows.length === 0) throw await whyCommentNotChanged(commentId, user);
    return Response.json({ comment: rows[0] });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * DELETE /api/comments/:id -> 200 { deleted }   (author only)
 * A real DELETE. If the comment has replies, the composite foreign key
 * comments_reply_same_post refuses it (23503) and the API answers 409:
 * deleting would orphan other people's replies, and the FK has no CASCADE
 * on purpose. Moderator removal is the soft delete (status = 'removed')
 * in /api/admin/comments/:id.
 */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const commentId = await commentIdFrom(context);

    let rowCount: number | null;
    try {
      ({ rowCount } = await getDbPool().query(
        `DELETE FROM comments
         WHERE comment_id = $1 AND author_id = $2 AND status = 'visible'`,
        [commentId, user.userId],
      ));
    } catch (err) {
      if ((err as { code?: string }).code === "23503") {
        throw new HttpError(409, "This comment has replies and cannot be deleted");
      }
      throw err;
    }
    if (!rowCount) throw await whyCommentNotChanged(commentId, user);
    return Response.json({ deleted: commentId });
  } catch (err) {
    return errorResponse(err);
  }
}
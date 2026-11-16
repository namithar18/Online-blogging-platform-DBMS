import { getCurrentUser, requireUser } from "@/lib/auth";
import { commentWriteError, parseCommentContent } from "@/lib/comments";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { canView, getPostDetail, parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

// A post with thousands of comments should not return them all at once.
const MAX_COMMENTS = 500;

async function postIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Post not found");
  return id;
}

/**
 * GET /api/posts/:id/comments -> 200 { comments }
 * Visible to whoever may see the post (C7: published posts are public;
 * drafts and removed posts only for the author and admins, others get 404).
 *
 * Comments come back threaded: depth-first, every reply directly under
 * its parent, with "depth" for indentation. A recursive CTE builds this
 * in one query: the first SELECT takes the top-level comments, the
 * second repeatedly adds the replies of the rows found so far. "path" is
 * the list of ancestor ids, so ORDER BY path puts a parent before its
 * replies; sibling order is by id, which is posting order.
 *
 * A moderator-removed comment (status = 'removed') stays in the thread so
 * its replies keep their parent (C2 / soft delete), but the text is
 * replaced in SQL with "[removed]", so the original never leaves the DB.
 */
export async function GET(_request: Request, context: Context): Promise<Response> {
  try {
    const postId = await postIdFrom(context);
    const post = await getPostDetail(postId);
    if (!post || !canView(post, await getCurrentUser())) {
      throw new HttpError(404, "Post not found");
    }

    const { rows } = await getDbPool().query(
      `WITH RECURSIVE thread AS (
         SELECT comment_id, parent_comment_id, author_id, content, status,
                created_at, updated_at,
                0 AS depth,
                ARRAY[comment_id] AS path
         FROM comments
         WHERE post_id = $1 AND parent_comment_id IS NULL
         UNION ALL
         SELECT c.comment_id, c.parent_comment_id, c.author_id, c.content, c.status,
                c.created_at, c.updated_at,
                t.depth + 1,
                t.path || c.comment_id
         FROM comments c
         JOIN thread t ON c.parent_comment_id = t.comment_id
         WHERE c.post_id = $1
       )
       SELECT t.comment_id        AS "commentId",
              t.parent_comment_id AS "parentCommentId",
              t.depth,
              t.author_id         AS "authorId",
              u.name              AS "authorName",
              CASE WHEN t.status = 'removed' THEN '[removed]' ELSE t.content END AS content,
              (t.status = 'removed') AS removed,
              t.created_at        AS "createdAt",
              t.updated_at        AS "updatedAt"
       FROM thread t
       JOIN users u ON u.user_id = t.author_id
       ORDER BY t.path
       LIMIT $2`,
      [postId, MAX_COMMENTS],
    );
    return Response.json({ comments: rows }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * POST /api/posts/:id/comments  { content, parentCommentId? } -> 201 { comment }
 * Omit parentCommentId for a top-level comment; send it to reply.
 *
 * - The author is the logged-in user, never taken from the body.
 * - INSERT ... SELECT FROM published_posts is ONE statement: it inserts
 *   only if the post exists AND is published (C7), so there is no gap
 *   between a check and the insert in which the post could be unpublished.
 *   Zero rows inserted -> 404.
 * - C2 is enforced by the composite foreign key
 *   (parent_comment_id, post_id) -> comments(comment_id, post_id): a parent
 *   that does not exist, or belongs to another post, gives 23503 -> 400.
 *   Replying to a moderator-removed comment is allowed; the thread stays whole.
 */
export async function POST(request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const postId = await postIdFrom(context);
    const body = await readJson(request);
    const content = parseCommentContent(body.content);

    let parentCommentId: string | null = null;
    if (body.parentCommentId !== undefined && body.parentCommentId !== null) {
      parentCommentId = parseId(body.parentCommentId);
      if (!parentCommentId) throw new HttpError(400, "parentCommentId must be a comment id");
    }

    let comment: Record<string, unknown> | undefined;
    try {
      const result = await getDbPool().query(
        `INSERT INTO comments (post_id, author_id, parent_comment_id, content)
         SELECT p.post_id, $2::bigint, $3::bigint, $4::text
         FROM published_posts p
         WHERE p.post_id = $1
         RETURNING comment_id        AS "commentId",
                   post_id           AS "postId",
                   parent_comment_id AS "parentCommentId",
                   author_id         AS "authorId",
                   content,
                   created_at        AS "createdAt"`,
        [postId, user.userId, parentCommentId, content],
      );
      comment = result.rows[0];
    } catch (err) {
      throw commentWriteError(err);
    }
    if (!comment) throw new HttpError(404, "Post not found");

    return Response.json({ comment: { ...comment, authorName: user.name } }, { status: 201 });
  } catch (err) {
    return errorResponse(err);
  }
}
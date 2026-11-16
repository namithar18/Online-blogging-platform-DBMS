import "server-only";
import type { CurrentUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError } from "@/lib/http";

export const MAX_COMMENT_LENGTH = 5_000;

/**
 * Comment text: not blank, at most 5000 characters. The table's
 * CHECK (length(trim(content)) > 0) enforces "not blank" as well; the
 * length limit is an API rule only (the column is plain text).
 */
export function parseCommentContent(value: unknown): string {
  const content = typeof value === "string" ? value.trim() : "";
  if (content.length === 0 || content.length > MAX_COMMENT_LENGTH) {
    throw new HttpError(400, `Comment is required (at most ${MAX_COMMENT_LENGTH} characters)`);
  }
  return content;
}

/** Map constraint violations from creating a comment to client errors. */
export function commentWriteError(err: unknown): unknown {
  const code = (err as { code?: string }).code;
  // comments_reply_same_post (C2): the parent does not exist, or it belongs to another post.
  if (code === "23503") return new HttpError(400, "Parent comment does not exist on this post");
  if (code === "23514") return new HttpError(400, "Invalid comment");
  return err;
}

/**
 * After a conditional UPDATE or DELETE matched no row, work out why:
 * missing (404), somebody else's (403) or already removed by a moderator (409).
 * This runs only AFTER the write failed, to pick the message; the write
 * itself never depends on it, so there is no check-then-act race.
 */
export async function whyCommentNotChanged(commentId: string, user: CurrentUser): Promise<HttpError> {
  const { rows } = await getDbPool().query<{ authorId: string; status: string }>(
    `SELECT author_id AS "authorId", status
     FROM comments
     WHERE comment_id = $1`,
    [commentId],
  );
  const comment = rows[0];
  if (!comment) return new HttpError(404, "Comment not found");
  if (comment.authorId !== user.userId) return new HttpError(403, "You can only change your own comments");
  if (comment.status === "removed") return new HttpError(409, "This comment was removed by a moderator");
  return new HttpError(409, "The comment could not be changed, please try again");
}
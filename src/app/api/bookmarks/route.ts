import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { errorResponse } from "@/lib/http";

export const runtime = "nodejs";

/**
 * GET /api/bookmarks -> 200 { bookmarks } (the caller's own, newest first)
 * Joins published_posts, not posts: if a bookmarked post is later
 * unpublished or removed by a moderator it silently leaves the list (C7),
 * but the bookmarks row stays, so it reappears if the post is republished.
 * An INNER JOIN is right here: a bookmark without a visible post has
 * nothing to show.
 */
export async function GET(): Promise<Response> {
  try {
    const user = await requireUser();
    const { rows } = await getDbPool().query(
      `SELECT p.post_id AS "postId", p.title,
              p.author_id AS "authorId", u.name AS "authorName",
              p.published_at AS "publishedAt",
              b.bookmarked_at AS "bookmarkedAt"
         FROM bookmarks b
         JOIN published_posts p ON p.post_id = b.post_id
         JOIN users u ON u.user_id = p.author_id
        WHERE b.user_id = $1
        ORDER BY b.bookmarked_at DESC`,
      [user.userId],
    );
    return Response.json({ bookmarks: rows });
  } catch (err) {
    return errorResponse(err);
  }
}
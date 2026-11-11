import "server-only";
import type { PoolClient } from "pg";
import type { CurrentUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError } from "@/lib/http";

// Authors may move a post between these. 'removed' is set only by admin
// moderation, so it is not accepted here.
export const AUTHOR_STATUSES = ["draft", "published", "unpublished"] as const;
export type AuthorStatus = (typeof AUTHOR_STATUSES)[number];

const MAX_TAGS = 10;
const MAX_CONTENT_LENGTH = 50_000;

export interface PostInput {
  communityId?: string;
  title?: string;
  content?: string;
  status?: AuthorStatus;
  tags?: string[];
}

/** Ids in URLs and bodies are bigint: digits only, no leading zero. */
export function parseId(value: unknown): string | null {
  const s = typeof value === "number" ? String(value) : value;
  return typeof s === "string" && /^[1-9]\d{0,17}$/.test(s) ? s : null;
}

/**
 * Validate a create (partial = false) or edit (partial = true) body.
 * These checks give clear messages; the table's NOT NULL, CHECK and FK
 * constraints still enforce the same rules in the database.
 */
export function parsePostInput(body: Record<string, unknown>, partial: boolean): PostInput {
  const input: PostInput = {};

  if (body.communityId !== undefined || !partial) {
    const communityId = parseId(body.communityId);
    if (!communityId) throw new HttpError(400, "communityId must be a community id");
    input.communityId = communityId;
  }

  if (body.title !== undefined || !partial) {
    const title = typeof body.title === "string" ? body.title.trim() : "";
    if (title.length === 0 || title.length > 200) {
      throw new HttpError(400, "Title is required (at most 200 characters)");
    }
    input.title = title;
  }

  if (body.content !== undefined || !partial) {
    const content = typeof body.content === "string" ? body.content.trim() : "";
    if (content.length === 0 || content.length > MAX_CONTENT_LENGTH) {
      throw new HttpError(400, `Content is required (at most ${MAX_CONTENT_LENGTH} characters)`);
    }
    input.content = content;
  }

  if (body.status !== undefined) {
    if (!AUTHOR_STATUSES.includes(body.status as AuthorStatus)) {
      throw new HttpError(400, `status must be one of: ${AUTHOR_STATUSES.join(", ")}`);
    }
    input.status = body.status as AuthorStatus;
  } else if (!partial) {
    input.status = "draft";
  }

  if (body.tags !== undefined) {
    if (!Array.isArray(body.tags) || !body.tags.every((t) => typeof t === "string")) {
      throw new HttpError(400, "tags must be a list of strings");
    }
    // Same rules as the tags table: lower case, not blank, at most 50.
    const tags = [...new Set((body.tags as string[]).map((t) => t.trim().toLowerCase()))];
    if (tags.some((t) => t.length === 0 || t.length > 50)) {
      throw new HttpError(400, "Each tag must be 1-50 characters");
    }
    if (tags.length > MAX_TAGS) throw new HttpError(400, `At most ${MAX_TAGS} tags`);
    input.tags = tags;
  } else if (!partial) {
    input.tags = [];
  }

  if (partial && Object.keys(input).length === 0) {
    throw new HttpError(400, "Nothing to update");
  }
  return input;
}

/**
 * Replace a post's tags. Must run inside the caller's transaction, so a
 * failure here also undoes the post insert/update.
 * Each statement takes the whole list as ONE array parameter ($1::text[]),
 * so any number of tags is still a single parameterised query.
 */
export async function saveTags(client: PoolClient, postId: string, tags: string[]): Promise<void> {
  await client.query("DELETE FROM post_tags WHERE post_id = $1", [postId]);
  if (tags.length === 0) return;

  // Find-or-create: existing names are skipped instead of violating UNIQUE.
  await client.query(
    `INSERT INTO tags (tag_name)
     SELECT unnest($1::text[])
     ON CONFLICT (tag_name) DO NOTHING`,
    [tags],
  );
  await client.query(
    `INSERT INTO post_tags (post_id, tag_id)
     SELECT $1, tag_id FROM tags WHERE tag_name = ANY($2::text[])`,
    [postId, tags],
  );
}

/** Turn constraint violations from a post write into 400 responses. */
export function postWriteError(err: unknown): unknown {
  const code = (err as { code?: string }).code;
  if (code === "23503") return new HttpError(400, "Community does not exist"); // foreign_key_violation
  if (code === "23514") return new HttpError(400, "Invalid post details");     // check_violation
  return err;
}

export interface PostDetail {
  postId: string;
  title: string;
  content: string;
  status: string;
  authorId: string;
  authorName: string;
  communityId: string;
  communityName: string;
  createdAt: string;
  updatedAt: string;
  publishedAt: string | null;
  tags: string[];
  reactionCount: number;
  commentCount: number;
}

/**
 * One post with its tags and counts, any status. Counts are computed from
 * reactions and comments on every read, never stored (CLAUDE.md).
 * Callers decide who may see a non-published post (canView).
 */
export async function getPostDetail(postId: string): Promise<PostDetail | null> {
  const { rows } = await getDbPool().query<PostDetail>(
    `SELECT p.post_id      AS "postId",
            p.title,
            p.content,
            p.status,
            p.author_id    AS "authorId",
            u.name         AS "authorName",
            p.community_id AS "communityId",
            c.name         AS "communityName",
            p.created_at   AS "createdAt",
            p.updated_at   AS "updatedAt",
            p.published_at AS "publishedAt",
            ARRAY(SELECT t.tag_name
                  FROM post_tags pt
                  JOIN tags t ON t.tag_id = pt.tag_id
                  WHERE pt.post_id = p.post_id
                  ORDER BY t.tag_name)                              AS tags,
            (SELECT count(*) FROM reactions r
             WHERE r.post_id = p.post_id)::int                      AS "reactionCount",
            (SELECT count(*) FROM comments cm
             WHERE cm.post_id = p.post_id AND cm.status = 'visible')::int AS "commentCount"
     FROM posts p
     JOIN users u       ON u.user_id      = p.author_id
     JOIN communities c ON c.community_id = p.community_id
     WHERE p.post_id = $1`,
    [postId],
  );
  return rows[0] ?? null;
}

/**
 * C7 for single posts: published posts are public; drafts, unpublished
 * and removed posts only for their author and admins. Everyone else gets
 * a 404, so the API does not even reveal that the post exists.
 */
export function canView(post: PostDetail, user: CurrentUser | null): boolean {
  if (post.status === "published") return true;
  return user !== null && (user.userId === post.authorId || user.role === "ADMIN");
}

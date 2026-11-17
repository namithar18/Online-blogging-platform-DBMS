"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";

// One post with everything a reader can do on it. Every piece of data comes
// from the API; the page never decides what is allowed. For example, a draft
// is hidden by the API (C7), and the page just shows its 404.

type Me = { userId: string; name: string; role: string };
type Post = {
  postId: string;
  title: string;
  content: string;
  status: string;
  authorId: string;
  authorName: string;
  communityName: string;
  publishedAt: string | null;
  tags: string[];
};
type Reactions = { counts: { type: string; count: number }[]; total: number; myReaction: string | null };
type Follow = { followerCount: number; isFollowing: boolean };
type Comment = {
  commentId: string;
  parentCommentId: string | null;
  depth: number;
  authorName: string;
  content: string;
  removed: boolean;
  createdAt: string;
};
type Similar = { postId: string; title: string; authorName: string; similarity: number };

const REACTION_TYPES = ["like", "love", "insightful"] as const;
const DOT = "·";

// GET helper: parsed JSON on success, null on any error status.
async function getJson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url, { cache: "no-store" });
    return res.ok ? ((await res.json()) as T) : null;
  } catch {
    return null;
  }
}

// Write helper: returns the API's error message, or null when it worked.
async function send(url: string, method: string, body?: unknown): Promise<string | null> {
  try {
    const res = await fetch(url, {
      method,
      headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.ok) return null;
    const data = await res.json().catch(() => null);
    return data?.error ?? `Request failed (${res.status})`;
  } catch {
    return "Could not reach the server";
  }
}

export default function PostPage() {
  const { id } = useParams<{ id: string }>();

  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const [post, setPost] = useState<Post | null | undefined>(undefined);
  const [reactions, setReactions] = useState<Reactions | null>(null);
  const [bookmarked, setBookmarked] = useState(false);
  const [follow, setFollow] = useState<Follow | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [similar, setSimilar] = useState<Similar[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [newComment, setNewComment] = useState("");
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const [replyText, setReplyText] = useState("");
  const viewLogged = useRef(false);

  const loadReactions = useCallback(async () => {
    setReactions(await getJson<Reactions>(`/api/posts/${id}/reactions`));
  }, [id]);

  const loadComments = useCallback(async () => {
    const data = await getJson<{ comments: Comment[] }>(`/api/posts/${id}/comments`);
    setComments(data?.comments ?? []);
  }, [id]);

  const loadFollow = useCallback(async (authorId: string) => {
    setFollow(await getJson<Follow>(`/api/users/${authorId}/follow`));
  }, []);

  // First load. State is only set after the awaits (in the async function),
  // and "cancelled" ignores results if the page was left in the meantime.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const [meData, postData] = await Promise.all([
        getJson<{ user: Me }>("/api/auth/me"),
        getJson<{ post: Post }>(`/api/posts/${id}`),
      ]);
      if (cancelled) return;
      const user = meData?.user ?? null;
      setMe(user);
      setPost(postData?.post ?? null);
      if (!postData) return;

      const p = postData.post;
      const [similarData, bookmarksData] = await Promise.all([
        getJson<{ posts: Similar[] }>(`/api/posts/${id}/similar?limit=5`),
        user ? getJson<{ bookmarks: { postId: string }[] }>("/api/bookmarks") : Promise.resolve(null),
        loadReactions(),
        loadComments(),
        loadFollow(p.authorId),
      ]);
      if (cancelled) return;
      setSimilar(similarData?.posts ?? []);
      setBookmarked(bookmarksData?.bookmarks.some((b) => b.postId === p.postId) ?? false);

      // One reading_activity row per visit, logged-in readers only (A7).
      // The ref stops React's development double-run from logging it twice.
      if (user && p.status === "published" && !viewLogged.current) {
        viewLogged.current = true;
        void send(`/api/posts/${id}/activity`, "POST");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id, loadReactions, loadComments, loadFollow]);

  // Runs one write, shows its error if any, then reloads what changed.
  async function act(write: () => Promise<string | null>, reload: () => Promise<void>) {
    setBusy(true);
    setMessage(null);
    const error = await write();
    if (error) setMessage(error);
    await reload();
    setBusy(false);
  }

  // Clicking your current reaction removes it; any other one replaces it
  // (the API does an upsert: one reaction per user per post, A4).
  function react(type: string) {
    const remove = reactions?.myReaction === type;
    void act(
      () => send(`/api/posts/${id}/reactions`, remove ? "DELETE" : "PUT", remove ? undefined : { type }),
      loadReactions,
    );
  }

  function toggleBookmark() {
    const wasBookmarked = bookmarked;
    void act(
      () => send(`/api/posts/${id}/bookmark`, wasBookmarked ? "DELETE" : "POST"),
      async () => {
        const data = await getJson<{ bookmarks: { postId: string }[] }>("/api/bookmarks");
        setBookmarked(data?.bookmarks.some((b) => b.postId === id) ?? false);
      },
    );
  }

  function toggleFollow() {
    if (!post || !follow) return;
    const authorId = post.authorId;
    void act(
      () => send(`/api/users/${authorId}/follow`, follow.isFollowing ? "DELETE" : "POST"),
      () => loadFollow(authorId),
    );
  }

  function addComment(e: FormEvent) {
    e.preventDefault();
    const content = newComment;
    void act(async () => {
      const error = await send(`/api/posts/${id}/comments`, "POST", { content });
      if (!error) setNewComment("");
      return error;
    }, loadComments);
  }

  function addReply(e: FormEvent, parentCommentId: string) {
    e.preventDefault();
    const content = replyText;
    void act(async () => {
      const error = await send(`/api/posts/${id}/comments`, "POST", { content, parentCommentId });
      if (!error) {
        setReplyText("");
        setReplyTo(null);
      }
      return error;
    }, loadComments);
  }

  if (post === undefined) {
    return <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>Loading...</main>;
  }
  if (post === null) {
    return (
      <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
        <h1>Post not found</h1>
        <p>It does not exist, or it is not published.</p>
        <Link href="/">Back to the latest posts</Link>
      </main>
    );
  }

  const loggedIn = Boolean(me);
  const isAuthor = me?.userId === post.authorId;
  const countOf = (type: string) => reactions?.counts.find((c) => c.type === type)?.count ?? 0;

  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
      {post.status !== "published" && (
        <p style={{ padding: 8, border: "1px solid #c90", borderRadius: 4 }}>
          This post is <strong>{post.status}</strong>. Only its author and admins can see it.
        </p>
      )}

      <h1 style={{ marginBottom: 4 }}>{post.title}</h1>
      <p style={{ marginTop: 0 }}>
        <small>
          {post.authorName} in {post.communityName}
          {post.publishedAt ? ` ${DOT} ${new Date(post.publishedAt).toLocaleDateString()}` : ""}
          {post.tags.length > 0 ? ` ${DOT} ${post.tags.join(", ")}` : ""}
        </small>
      </p>

      {/* Plain text with line breaks kept; never rendered as HTML. */}
      <div style={{ whiteSpace: "pre-wrap", lineHeight: 1.6 }}>{post.content}</div>

      {message && (
        <p role="alert" style={{ color: "crimson" }}>
          {message}
        </p>
      )}

      {/* Reactions, bookmark and follow */}
      <section style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", margin: "24px 0" }}>
        {REACTION_TYPES.map((type) => (
          <button
            key={type}
            onClick={() => react(type)}
            disabled={!loggedIn || busy}
            style={{ fontWeight: reactions?.myReaction === type ? "bold" : "normal" }}
          >
            {type} ({countOf(type)})
          </button>
        ))}
        {loggedIn && (
          <button onClick={toggleBookmark} disabled={busy}>
            {bookmarked ? "Bookmarked" : "Bookmark"}
          </button>
        )}
        {loggedIn && !isAuthor && follow && (
          <button onClick={toggleFollow} disabled={busy}>
            {follow.isFollowing ? `Following ${post.authorName}` : `Follow ${post.authorName}`}
          </button>
        )}
        {follow && (
          <small>
            {follow.followerCount} follower{follow.followerCount === 1 ? "" : "s"}
          </small>
        )}
        {!loggedIn && (
          <small>
            <Link href="/login">Log in</Link> to react, bookmark, follow or comment.
          </small>
        )}
      </section>

      {/* Similar posts: pgvector cosine similarity on the stored embeddings */}
      {similar.length > 0 && (
        <section style={{ margin: "24px 0" }}>
          <h2>Similar posts</h2>
          <ul>
            {similar.map((s) => (
              <li key={s.postId}>
                <Link href={`/posts/${s.postId}`}>{s.title}</Link>{" "}
                <small>
                  by {s.authorName} {DOT} similarity {Math.round(s.similarity * 100)}%
                </small>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* Comments: the API returns them threaded (recursive CTE) with a depth */}
      <section style={{ margin: "24px 0" }}>
        <h2>Comments ({comments.filter((c) => !c.removed).length})</h2>
        {comments.length === 0 && <p>No comments yet.</p>}
        <ul style={{ listStyle: "none", padding: 0 }}>
          {comments.map((c) => (
            <li key={c.commentId} style={{ marginLeft: c.depth * 24, padding: "8px 0", borderBottom: "1px solid #8883" }}>
              <small>
                {c.removed ? "[removed]" : c.authorName} {DOT} {new Date(c.createdAt).toLocaleString()}
              </small>
              <div style={{ whiteSpace: "pre-wrap", fontStyle: c.removed ? "italic" : "normal" }}>{c.content}</div>
              {loggedIn && post.status === "published" && (
                <button
                  onClick={() => {
                    setReplyTo(replyTo === c.commentId ? null : c.commentId);
                    setReplyText("");
                  }}
                  style={{ fontSize: 12, marginTop: 4 }}
                >
                  {replyTo === c.commentId ? "Cancel" : "Reply"}
                </button>
              )}
              {replyTo === c.commentId && (
                <form onSubmit={(e) => addReply(e, c.commentId)} style={{ display: "flex", gap: 8, marginTop: 8 }}>
                  <input
                    value={replyText}
                    onChange={(e) => setReplyText(e.target.value)}
                    placeholder="Write a reply"
                    aria-label="Reply"
                    maxLength={5000}
                    style={{ flex: 1, padding: 6 }}
                  />
                  <button type="submit" disabled={busy || !replyText.trim()}>
                    Reply
                  </button>
                </form>
              )}
            </li>
          ))}
        </ul>

        {loggedIn && post.status === "published" && (
          <form onSubmit={addComment} style={{ display: "grid", gap: 8, marginTop: 16 }}>
            <textarea
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="Write a comment"
              aria-label="Comment"
              maxLength={5000}
              rows={3}
              style={{ padding: 8 }}
            />
            <button type="submit" disabled={busy || !newComment.trim()} style={{ justifySelf: "start" }}>
              Post comment
            </button>
          </form>
        )}
      </section>
    </main>
  );
}

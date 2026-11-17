"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

// The logged-in author's own posts in every status (draft, published,
// unpublished, removed). This is the only list that shows drafts: the home
// feed and search read the published_posts view (C7). The API filters by
// the session user, so nobody can list someone else's drafts.

type Post = {
  postId: string;
  title: string;
  status: string;
  updatedAt: string;
  communityName: string;
  reactionCount: number;
  commentCount: number;
};

const DOT = "·";

export default function MyPostsPage() {
  // undefined = loading, null = not logged in
  const [posts, setPosts] = useState<Post[] | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const res = await fetch("/api/posts?mine=true&limit=50", { cache: "no-store" });
        if (cancelled) return;
        if (res.status === 401) {
          setPosts(null);
          return;
        }
        const data = await res.json().catch(() => null);
        if (!res.ok) {
          setError(data?.error ?? `Could not load your posts (${res.status})`);
          setPosts([]);
          return;
        }
        setPosts(data.posts as Post[]);
      } catch {
        if (!cancelled) {
          setError("Could not reach the server");
          setPosts([]);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <h1>My posts</h1>
        {posts !== null && <Link href="/write">Write a post</Link>}
      </div>

      {posts === undefined && <p>Loading...</p>}
      {posts === null && (
        <p>
          <Link href="/login">Log in</Link> to see your posts.
        </p>
      )}
      {error && <p role="alert" style={{ color: "crimson" }}>{error}</p>}
      {posts && posts.length === 0 && !error && <p>You have not written any posts yet.</p>}

      {posts && posts.length > 0 && (
        <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 12 }}>
          {posts.map((p) => (
            <li key={p.postId} style={{ borderBottom: "1px solid #8884", paddingBottom: 10 }}>
              <Link href={`/posts/${p.postId}`} style={{ fontSize: 18 }}>
                {p.title}
              </Link>{" "}
              <span
                style={{
                  fontSize: 12,
                  padding: "1px 6px",
                  borderRadius: 4,
                  border: "1px solid #8888",
                  marginLeft: 4,
                }}
              >
                {p.status}
              </span>
              <div>
                <small>
                  {p.communityName} {DOT} updated {new Date(p.updatedAt).toLocaleDateString()} {DOT}{" "}
                  {p.reactionCount} reactions {DOT} {p.commentCount} comments
                </small>
              </div>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}

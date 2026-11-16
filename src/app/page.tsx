"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type Post = {
  postId: string;
  title: string;
  excerpt: string;
  publishedAt: string;
  authorName: string;
  communityName: string;
  tags: string[];
  reactionCount: number;
  commentCount: number;
};

type PageResult = { rows: Post[]; error: string | null };

const PAGE_SIZE = 10;
const DOT = "\u00b7";

// Published posts only: the API reads the published_posts view (C7).
// Asking for one row more than a page tells us whether another page exists.
// This function only fetches and returns data; it never sets state.
async function fetchPage(offset: number): Promise<PageResult> {
  try {
    const res = await fetch(`/api/posts?limit=${PAGE_SIZE + 1}&offset=${offset}`);
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      return { rows: [], error: data?.error ?? `Could not load posts (${res.status})` };
    }
    return { rows: data.posts as Post[], error: null };
  } catch {
    return { rows: [], error: "Could not reach the server" };
  }
}

export default function HomePage() {
  const [posts, setPosts] = useState<Post[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Called only from promise callbacks, never synchronously inside an effect.
  const applyResult = useCallback((result: PageResult, offset: number) => {
    if (result.error) {
      setError(result.error);
    } else {
      setHasMore(result.rows.length > PAGE_SIZE);
      setPosts((prev) => (offset === 0 ? [] : prev).concat(result.rows.slice(0, PAGE_SIZE)));
    }
    setLoading(false);
  }, []);

  // First page. loading starts as true, so nothing is set before the await.
  // "cancelled" ignores the result if the effect was cleaned up (Strict Mode).
  useEffect(() => {
    let cancelled = false;
    void fetchPage(0).then((result) => {
      if (!cancelled) applyResult(result, 0);
    });
    return () => {
      cancelled = true;
    };
  }, [applyResult]);

  // An event handler, so it may set state directly.
  function loadMore() {
    const offset = posts.length;
    setLoading(true);
    setError(null);
    void fetchPage(offset).then((result) => applyResult(result, offset));
  }

  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
      <h1>Latest posts</h1>
      {error && <p role="alert" style={{ color: "crimson" }}>{error}</p>}
      {!loading && !error && posts.length === 0 && <p>No posts yet.</p>}

      <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 16 }}>
        {posts.map((p) => (
          <li key={p.postId} style={{ borderBottom: "1px solid #8884", paddingBottom: 12 }}>
            <h3 style={{ margin: "0 0 4px" }}>
              <Link href={`/posts/${p.postId}`}>{p.title}</Link>
            </h3>
            <p style={{ margin: "0 0 4px" }}>{p.excerpt}</p>
            <small>
              {p.authorName} in {p.communityName} {DOT}{" "}
              {new Date(p.publishedAt).toLocaleDateString()} {DOT} {p.reactionCount} reactions {DOT}{" "}
              {p.commentCount} comments
              {p.tags.length > 0 ? ` ${DOT} ${p.tags.join(", ")}` : ""}
            </small>
          </li>
        ))}
      </ul>

      {loading && <p>Loading...</p>}
      {hasMore && !loading && <button onClick={loadMore}>Load more</button>}
    </main>
  );
}
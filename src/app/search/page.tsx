"use client";

import { useEffect, useState, type FormEvent } from "react";

type Result = {
  postId: string;
  title: string;
  snippet: string;
  publishedAt: string;
  authorName: string;
  communityId: string;
  communityName: string;
  relevance: number;
};
type Community = { communityId: string; name: string };
type Filters = { q: string; community: string; tag: string };

const PAGE_SIZE = 10;

// The API wraps matches in [[[ ]]]. Splitting on the markers gives
// alternating plain / matched parts, rendered as React text nodes, so post
// content is never injected as HTML.
function Highlighted({ text }: { text: string }) {
  const parts = text.split(/\[\[\[|\]\]\]/);
  return (
    <>
      {parts.map((part, i) => (i % 2 === 1 ? <mark key={i}>{part}</mark> : part))}
    </>
  );
}

export default function SearchPage() {
  const [q, setQ] = useState("");
  const [community, setCommunity] = useState("");
  const [tag, setTag] = useState("");
  const [communities, setCommunities] = useState<Community[]>([]);
  const [active, setActive] = useState<Filters | null>(null);
  const [results, setResults] = useState<Result[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Optional: the community list comes from /api/communities. If that route
  // is not available, the dropdown simply stays hidden.
  useEffect(() => {
    fetch("/api/communities")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        if (d && Array.isArray(d.communities)) setCommunities(d.communities);
      })
      .catch(() => {});
  }, []);

  async function run(filters: Filters, newOffset: number) {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({
        q: filters.q,
        limit: String(PAGE_SIZE),
        offset: String(newOffset),
      });
      if (filters.community) params.set("community", filters.community);
      if (filters.tag.trim()) params.set("tag", filters.tag.trim());
      const res = await fetch(`/api/search?${params.toString()}`);
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setResults([]);
        setTotal(0);
        setError(data?.error ?? `Search failed (${res.status})`);
        return;
      }
      setResults(data.posts);
      setTotal(data.total);
      setOffset(newOffset);
    } catch {
      setError("Could not reach the server");
    } finally {
      setLoading(false);
    }
  }

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!q.trim()) return;
    const filters = { q: q.trim(), community, tag };
    setActive(filters);
    void run(filters, 0);
  }

  const from = total === 0 ? 0 : offset + 1;
  const to = offset + results.length;

  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
      <h1>Search posts</h1>
      <form onSubmit={onSubmit} style={{ display: "grid", gap: 8, marginBottom: 16 }}>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder='Keywords, "exact phrase", -excluded'
          aria-label="Search keywords"
          maxLength={500}
          style={{ padding: 8 }}
        />
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {communities.length > 0 && (
            <select
              value={community}
              onChange={(e) => setCommunity(e.target.value)}
              aria-label="Community"
              style={{ padding: 8 }}
            >
              <option value="">All communities</option>
              {communities.map((c) => (
                <option key={c.communityId} value={c.communityId}>
                  {c.name}
                </option>
              ))}
            </select>
          )}
          <input
            value={tag}
            onChange={(e) => setTag(e.target.value)}
            placeholder="Tag (e.g. postgresql)"
            aria-label="Tag"
            style={{ padding: 8 }}
          />
          <button type="submit" disabled={loading || !q.trim()} style={{ padding: "8px 16px" }}>
            {loading ? "Searching..." : "Search"}
          </button>
        </div>
      </form>

      {error && <p role="alert" style={{ color: "crimson" }}>{error}</p>}

      {active && !error && !loading && (
        <p>
          {total === 0
            ? "No posts match your search."
            : `Showing ${from}-${to} of ${total} result${total === 1 ? "" : "s"}`}
        </p>
      )}

      <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 16 }}>
        {results.map((r) => (
          <li key={r.postId} style={{ borderBottom: "1px solid #8884", paddingBottom: 12 }}>
            <h3 style={{ margin: "0 0 4px" }}>{r.title}</h3>
            <p style={{ margin: "0 0 4px" }}>
              <Highlighted text={r.snippet} />
            </p>
            <small>
              {r.authorName} in {r.communityName} · {new Date(r.publishedAt).toLocaleDateString()} ·
              relevance {r.relevance}
            </small>
          </li>
        ))}
      </ul>

      {active && total > PAGE_SIZE && (
        <div style={{ display: "flex", gap: 8 }}>
          <button
            disabled={loading || offset === 0}
            onClick={() => void run(active, Math.max(0, offset - PAGE_SIZE))}
          >
            Previous
          </button>
          <button
            disabled={loading || offset + PAGE_SIZE >= total}
            onClick={() => void run(active, offset + PAGE_SIZE)}
          >
            Next
          </button>
        </div>
      )}
    </main>
  );
}
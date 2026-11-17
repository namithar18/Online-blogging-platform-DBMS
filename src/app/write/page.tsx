"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";

// Create a post. The API saves the post, its tags and its embedding in ONE
// transaction, so a post is never stored without its tags or its vector.
// The author is always the logged-in user; it is never sent from here.

type Community = { communityId: string; name: string };

export default function WritePage() {
  const router = useRouter();
  const [loggedIn, setLoggedIn] = useState<boolean | undefined>(undefined);
  const [communities, setCommunities] = useState<Community[]>([]);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [communityId, setCommunityId] = useState("");
  const [tags, setTags] = useState("");
  const [status, setStatus] = useState<"draft" | "published">("draft");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const [me, list] = await Promise.all([
        fetch("/api/auth/me", { cache: "no-store" }).then((r) => r.ok).catch(() => false),
        fetch("/api/communities")
          .then((r) => (r.ok ? r.json() : null))
          .catch(() => null),
      ]);
      if (cancelled) return;
      setLoggedIn(me);
      const rows: Community[] = list?.communities ?? [];
      setCommunities(rows);
      if (rows.length > 0) setCommunityId(rows[0].communityId);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/posts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title,
          content,
          communityId,
          status,
          tags: tags
            .split(",")
            .map((t) => t.trim())
            .filter((t) => t.length > 0),
        }),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setError(data?.error ?? `Could not save the post (${res.status})`);
        return;
      }
      router.push(`/posts/${data.post.postId}`);
    } catch {
      setError("Could not reach the server");
    } finally {
      setBusy(false);
    }
  }

  if (loggedIn === undefined) {
    return <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>Loading...</main>;
  }
  if (!loggedIn) {
    return (
      <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
        <h1>Write a post</h1>
        <p>
          <Link href="/login">Log in</Link> to write a post.
        </p>
      </main>
    );
  }

  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 24 }}>
      <h1>Write a post</h1>
      <form onSubmit={onSubmit} style={{ display: "grid", gap: 8 }}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Title"
          aria-label="Title"
          maxLength={200}
          required
          style={{ padding: 8, fontSize: 18 }}
        />
        <textarea
          value={content}
          onChange={(e) => setContent(e.target.value)}
          placeholder="Write your post"
          aria-label="Content"
          rows={12}
          required
          style={{ padding: 8 }}
        />
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <select
            value={communityId}
            onChange={(e) => setCommunityId(e.target.value)}
            aria-label="Community"
            required
            style={{ padding: 8 }}
          >
            {communities.map((c) => (
              <option key={c.communityId} value={c.communityId}>
                {c.name}
              </option>
            ))}
          </select>
          <input
            value={tags}
            onChange={(e) => setTags(e.target.value)}
            placeholder="Tags, separated by commas"
            aria-label="Tags"
            style={{ padding: 8, flex: 1 }}
          />
        </div>
        <div style={{ display: "flex", gap: 16 }}>
          <label>
            <input type="radio" name="status" checked={status === "draft"} onChange={() => setStatus("draft")} /> Save
            as draft (only you can see it)
          </label>
          <label>
            <input
              type="radio"
              name="status"
              checked={status === "published"}
              onChange={() => setStatus("published")}
            />{" "}
            Publish now
          </label>
        </div>
        {error && <p role="alert" style={{ color: "crimson", margin: 0 }}>{error}</p>}
        <button type="submit" disabled={busy || !communityId} style={{ justifySelf: "start", padding: "8px 16px" }}>
          {busy ? "Saving..." : status === "draft" ? "Save draft" : "Publish"}
        </button>
      </form>
    </main>
  );
}

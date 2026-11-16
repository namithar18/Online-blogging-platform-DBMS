"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        setError(data?.error ?? `Login failed (${res.status})`);
        return;
      }
      // Client-side navigation: the path changes (/login -> /), which makes
      // the nav bar re-check the session. refresh() reloads server data.
      router.push("/");
      router.refresh();
    } catch {
      setError("Could not reach the server");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main style={{ maxWidth: 360, margin: "0 auto", padding: 24 }}>
      <h1>Log in</h1>
      <form onSubmit={onSubmit} style={{ display: "grid", gap: 8 }}>
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="Email"
          aria-label="Email"
          required
          style={{ padding: 8 }}
        />
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Password"
          aria-label="Password"
          required
          style={{ padding: 8 }}
        />
        {error && <p role="alert" style={{ color: "crimson", margin: 0 }}>{error}</p>}
        <button type="submit" disabled={busy} style={{ padding: 8 }}>
          {busy ? "Logging in..." : "Log in"}
        </button>
      </form>
      <p>
        No account? <Link href="/register">Register</Link>
      </p>
    </main>
  );
}
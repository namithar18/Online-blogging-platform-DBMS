"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

export default function RegisterPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // The role is not sent: the API never accepts it from the client, and the
  // column DEFAULT 'USER' applies, so nobody can register as ADMIN.
  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email, password }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        setError(data?.error ?? `Registration failed (${res.status})`);
        return;
      }
      // Path changes (/register -> /), so the nav bar re-checks the session.
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
      <h1>Register</h1>
      <form onSubmit={onSubmit} style={{ display: "grid", gap: 8 }}>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Name"
          aria-label="Name"
          maxLength={100}
          required
          style={{ padding: 8 }}
        />
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
          {busy ? "Creating account..." : "Create account"}
        </button>
      </form>
      <p>
        Already registered? <Link href="/login">Log in</Link>
      </p>
    </main>
  );
}
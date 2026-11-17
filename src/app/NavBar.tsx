"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

type User = { userId: string; name: string; role: string };

// undefined = still asking the server, null = not logged in.
export default function NavBar() {
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const router = useRouter();
  const pathname = usePathname();

  // The session cookie is httpOnly, so the page cannot read it. It asks the
  // API who is logged in; the server stays the only judge of the session.
  // Re-runs on every route change, so after login/register (/login -> /)
  // the nav bar picks up the new session without a full page reload.
  useEffect(() => {
    let cancelled = false;
    fetch("/api/auth/me")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        if (!cancelled) setUser(d?.user ?? null);
      })
      .catch(() => {
        if (!cancelled) setUser(null);
      });
    return () => {
      cancelled = true;
    };
  }, [pathname]);

  async function logout() {
    await fetch("/api/auth/logout", { method: "POST" }).catch(() => {});
    // Logout happens on "/" and goes to "/", so the pathname does not change
    // and the effect above would not re-run. Clear the state directly.
    setUser(null);
    router.push("/");
    router.refresh();
  }

  return (
    <nav
      style={{
        display: "flex",
        gap: 16,
        alignItems: "center",
        padding: "12px 24px",
        borderBottom: "1px solid #8884",
      }}
    >
      <strong>Blog</strong>
      <Link href="/">Home</Link>
      <Link href="/search">Search</Link>
      {user && (
        <>
          <Link href="/write">Write</Link>
          <Link href="/my-posts">My posts</Link>
        </>
      )}
      <span style={{ marginLeft: "auto", display: "flex", gap: 12, alignItems: "center" }}>
        {user === undefined ? null : user ? (
          <>
            <span>
              {user.name}
              {user.role === "ADMIN" ? " (admin)" : ""}
            </span>
            <button onClick={() => void logout()}>Log out</button>
          </>
        ) : (
          <>
            <Link href="/login">Log in</Link>
            <Link href="/register">Register</Link>
          </>
        )}
      </span>
    </nav>
  );
}
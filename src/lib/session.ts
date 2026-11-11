import "server-only";
import { cookies } from "next/headers";
import { SignJWT, jwtVerify } from "jose";

// A session is a signed token (JWT) in an httpOnly cookie. Nothing is
// stored in the database, so no extra table is needed. Trade-off: a
// token cannot be revoked before it expires, so it lives only 8 hours,
// and requireUser() re-reads the user's role from the database anyway.
const COOKIE_NAME = "session";
const SESSION_SECONDS = 60 * 60 * 8;

function secretKey(): Uint8Array {
  const secret = process.env.SESSION_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("SESSION_SECRET must be set to at least 32 characters");
  }
  return new TextEncoder().encode(secret);
}

/** Sign a token for this user and set it as the session cookie. */
export async function createSession(userId: string): Promise<void> {
  // Only the user id goes in the token ("sub" = subject). The role is
  // looked up on every request, so a demoted admin loses access at once.
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime(`${SESSION_SECONDS}s`)
    .sign(secretKey());

  (await cookies()).set(COOKIE_NAME, token, {
    httpOnly: true,                                // not readable by browser JavaScript
    secure: process.env.NODE_ENV === "production", // HTTPS only in production
    sameSite: "lax",                               // not sent on cross-site POSTs
    path: "/",
    maxAge: SESSION_SECONDS,
  });
}

/** The user id from a valid session cookie, or null if missing, expired or tampered with. */
export async function readSessionUserId(): Promise<string | null> {
  const token = (await cookies()).get(COOKIE_NAME)?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secretKey(), { algorithms: ["HS256"] });
    return payload.sub ?? null;
  } catch {
    return null;
  }
}

export async function deleteSession(): Promise<void> {
  (await cookies()).delete(COOKIE_NAME);
}

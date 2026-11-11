import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { PASSWORD_MAX_BYTES, PASSWORD_MIN_LENGTH, hashPassword } from "@/lib/password";
import { createSession } from "@/lib/session";

export const runtime = "nodejs";

// POST /api/auth/register  { name, email, password }  -> 201 { user }
export async function POST(request: Request): Promise<Response> {
  try {
    const body = await readJson(request);
    const name = typeof body.name === "string" ? body.name.trim() : "";
    // Lower case to satisfy CHECK (email = lower(email)) instead of failing on it.
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";

    // Friendly messages first; the database constraints are the real guard.
    if (name.length === 0 || name.length > 100) {
      throw new HttpError(400, "Name is required (at most 100 characters)");
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 255) {
      throw new HttpError(400, "A valid email is required");
    }
    if (password.length < PASSWORD_MIN_LENGTH || Buffer.byteLength(password) > PASSWORD_MAX_BYTES) {
      throw new HttpError(400, `Password must be ${PASSWORD_MIN_LENGTH}-${PASSWORD_MAX_BYTES} bytes long`);
    }

    const passwordHash = await hashPassword(password);

    // role is never taken from the request: the column DEFAULT 'USER'
    // applies, so nobody can register as ADMIN.
    // No "SELECT ... WHERE email = $1" check first: two requests could
    // both pass it at the same time. The UNIQUE constraint on email is
    // checked atomically by the database, so we rely on it (23505 below).
    const { rows } = await getDbPool().query<{ userId: string; role: string }>(
      `INSERT INTO users (name, email, password_hash)
       VALUES ($1, $2, $3)
       RETURNING user_id AS "userId", role`,
      [name, email, passwordHash],
    );
    const user = rows[0];

    await createSession(user.userId);
    return Response.json({ user: { userId: user.userId, name, email, role: user.role } }, { status: 201 });
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === "23505") {
      // unique_violation on users.email
      return errorResponse(new HttpError(409, "An account with this email already exists"));
    }
    if (code === "23514") {
      // check_violation: input passed our checks but not the table's CHECK
      return errorResponse(new HttpError(400, "Invalid registration details"));
    }
    return errorResponse(err);
  }
}

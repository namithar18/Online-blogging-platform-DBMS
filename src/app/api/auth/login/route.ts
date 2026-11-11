import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { DUMMY_HASH, verifyPassword } from "@/lib/password";
import { createSession } from "@/lib/session";

export const runtime = "nodejs";

// POST /api/auth/login  { email, password }  -> 200 { user }
export async function POST(request: Request): Promise<Response> {
  try {
    const body = await readJson(request);
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";

    // Parameterised: the email is sent separately from the SQL text, so
    // input like  ' OR '1'='1  is just an email that matches nobody.
    const { rows } = await getDbPool().query<{
      userId: string;
      name: string;
      email: string;
      role: string;
      passwordHash: string;
    }>(
      `SELECT user_id AS "userId", name, email, role, password_hash AS "passwordHash"
       FROM users
       WHERE email = $1`,
      [email],
    );
    const user = rows[0];

    // Always run one bcrypt compare, even for an unknown email, so both
    // failures take the same time and return the same message.
    const passwordOk = await verifyPassword(password, user?.passwordHash ?? DUMMY_HASH);
    if (!user || !passwordOk) {
      throw new HttpError(401, "Invalid email or password");
    }

    await createSession(user.userId);
    return Response.json({
      user: { userId: user.userId, name: user.name, email: user.email, role: user.role },
    });
  } catch (err) {
    return errorResponse(err);
  }
}

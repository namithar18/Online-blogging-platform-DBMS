import { requireUser } from "@/lib/auth";
import { errorResponse } from "@/lib/http";

export const runtime = "nodejs";

// GET /api/auth/me  -> 200 { user } or 401 when not logged in.
export async function GET(): Promise<Response> {
  try {
    const user = await requireUser();
    return Response.json({ user }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err);
  }
}

import { errorResponse } from "@/lib/http";
import { deleteSession } from "@/lib/session";

export const runtime = "nodejs";

// POST /api/auth/logout  -> 200. POST, not GET, so a link or image on
// another site cannot log the user out.
export async function POST(): Promise<Response> {
  try {
    await deleteSession();
    return Response.json({ ok: true });
  } catch (err) {
    return errorResponse(err);
  }
}

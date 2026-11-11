import { requireAdmin } from "@/lib/auth";
import { errorResponse } from "@/lib/http";

export const runtime = "nodejs";

// GET /api/admin/check  -> 200 for an ADMIN, 403 for a USER, 401 when
// logged out. Shows the role check working in the API; the
// admin-moderation routes will use requireAdmin() the same way.
export async function GET(): Promise<Response> {
  try {
    const admin = await requireAdmin();
    return Response.json({ ok: true, admin: { userId: admin.userId, name: admin.name } });
  } catch (err) {
    return errorResponse(err);
  }
}

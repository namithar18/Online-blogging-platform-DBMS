import { requireAdmin } from "@/lib/auth";
import { communityWriteError, parseCommunityName, parseDescription } from "@/lib/communities";
import { getDbPool } from "@/lib/db";
import { errorResponse, readJson } from "@/lib/http";

export const runtime = "nodejs";

/**
 * POST /api/admin/communities  { name, description? } -> 201 { community }
 * created_by is the logged-in admin. C5 is checked twice: requireAdmin()
 * here, and the communities_creator_must_be_admin trigger in the database
 * (which also catches an admin demoted between the two checks).
 */
export async function POST(request: Request): Promise<Response> {
  try {
    const admin = await requireAdmin();
    const body = await readJson(request);
    const name = parseCommunityName(body.name);
    const description = body.description === undefined ? null : parseDescription(body.description);

    const { rows } = await getDbPool().query(
      `INSERT INTO communities (name, description, created_by)
       VALUES ($1, $2, $3)
       RETURNING community_id AS "communityId", name, description,
                 created_by AS "createdBy", created_at AS "createdAt"`,
      [name, description, admin.userId],
    );
    return Response.json({ community: rows[0] }, { status: 201 });
  } catch (err) {
    return errorResponse(communityWriteError(err));
  }
}

import { requireUser } from "@/lib/auth";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function communityIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Community not found");
  return id;
}

/**
 * POST /api/communities/:id/join -> 201 { membership }
 * The user comes from the session, never from the request. There is no
 * "SELECT ... is he already a member?" first: two requests could both
 * pass that check. The composite PRIMARY KEY (user_id, community_id) is
 * checked atomically, so a duplicate gives 23505 -> 409, and a community
 * that does not exist breaks the foreign key (23503) -> 404.
 */
export async function POST(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const communityId = await communityIdFrom(context);

    try {
      const { rows } = await getDbPool().query(
        `INSERT INTO community_members (user_id, community_id)
         VALUES ($1, $2)
         RETURNING community_id AS "communityId", joined_at AS "joinedAt"`,
        [user.userId, communityId],
      );
      return Response.json({ membership: rows[0] }, { status: 201 });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "23505") throw new HttpError(409, "You are already a member of this community");
      if (code === "23503") throw new HttpError(404, "Community not found");
      throw err;
    }
  } catch (err) {
    return errorResponse(err);
  }
}

/**
 * DELETE /api/communities/:id/join -> 200 { left }
 * Leaving removes only the membership row. The user's posts in the
 * community stay: authors need not be members (A8).
 */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    const user = await requireUser();
    const communityId = await communityIdFrom(context);

    const { rowCount } = await getDbPool().query(
      `DELETE FROM community_members
       WHERE user_id = $1 AND community_id = $2`,
      [user.userId, communityId],
    );
    if (!rowCount) throw new HttpError(404, "You are not a member of this community");
    return Response.json({ left: communityId });
  } catch (err) {
    return errorResponse(err);
  }
}
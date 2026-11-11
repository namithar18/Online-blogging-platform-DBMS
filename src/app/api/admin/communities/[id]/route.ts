import { requireAdmin } from "@/lib/auth";
import { communityWriteError, parseCommunityName, parseDescription } from "@/lib/communities";
import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse, readJson } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

type Context = { params: Promise<{ id: string }> };

async function communityIdFrom(context: Context): Promise<string> {
  const id = parseId((await context.params).id);
  if (!id) throw new HttpError(404, "Community not found");
  return id;
}

/**
 * PATCH /api/admin/communities/:id  { name?, description? }  (admin only)
 * description: null clears it. A name already in use -> 409 (UNIQUE).
 */
export async function PATCH(request: Request, context: Context): Promise<Response> {
  try {
    await requireAdmin();
    const communityId = await communityIdFrom(context);
    const body = await readJson(request);
    const name = body.name === undefined ? null : parseCommunityName(body.name);
    const descriptionSent = body.description !== undefined;
    const description = descriptionSent ? parseDescription(body.description) : null;
    if (name === null && !descriptionSent) throw new HttpError(400, "Nothing to update");

    // COALESCE cannot tell "not sent" from "set to NULL", so description
    // uses an explicit flag ($4) instead.
    const { rows } = await getDbPool().query(
      `UPDATE communities
       SET name        = COALESCE($2, name),
           description = CASE WHEN $4 THEN $3 ELSE description END
       WHERE community_id = $1
       RETURNING community_id AS "communityId", name, description,
                 created_by AS "createdBy", created_at AS "createdAt"`,
      [communityId, name, description, descriptionSent],
    );
    if (rows.length === 0) throw new HttpError(404, "Community not found");
    return Response.json({ community: rows[0] });
  } catch (err) {
    return errorResponse(communityWriteError(err));
  }
}

/**
 * DELETE /api/admin/communities/:id  (admin only)
 * posts.community_id is ON DELETE RESTRICT: a community that still has
 * posts cannot be deleted, so no content disappears by accident. The
 * database refuses (23503) and the API answers 409. Memberships go with
 * the community (community_members is ON DELETE CASCADE).
 */
export async function DELETE(_request: Request, context: Context): Promise<Response> {
  try {
    await requireAdmin();
    const communityId = await communityIdFrom(context);

    const { rowCount } = await getDbPool().query(
      "DELETE FROM communities WHERE community_id = $1",
      [communityId],
    );
    if (!rowCount) throw new HttpError(404, "Community not found");
    return Response.json({ deleted: communityId });
  } catch (err) {
    if ((err as { code?: string }).code === "23503") {
      return errorResponse(
        new HttpError(409, "This community still has posts; move or delete them first"),
      );
    }
    return errorResponse(err);
  }
}

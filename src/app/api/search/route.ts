import { getDbPool } from "@/lib/db";
import { HttpError, errorResponse } from "@/lib/http";
import { parseId } from "@/lib/posts";

export const runtime = "nodejs";

const MAX_QUERY_LENGTH = 500;

function intParam(
  params: URLSearchParams,
  name: string,
  fallback: number,
  min: number,
  max: number,
): number {
  const raw = params.get(name);
  if (raw === null || raw === "") return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new HttpError(400, `${name} must be an integer from ${min} to ${max}`);
  }
  return n;
}

/**
 * GET /api/search?q=...&community=<id>&tag=<name>&limit=10&offset=0
 *   -> 200 { query, total, limit, offset, posts }
 *
 * Keyword search with PostgreSQL full-text search (the semantic version is
 * /api/search/semantic). Why each choice:
 * - search_vector @@ query is served by the GIN index posts_search_vector_idx;
 *   LIKE '%word%' cannot use a B-tree index and would scan every row.
 * - websearch_to_tsquery accepts raw user input ("quoted phrase", -excluded,
 *   or) and never raises a syntax error, unlike to_tsquery.
 * - The query reads published_posts, never posts, so drafts, unpublished and
 *   removed posts cannot appear (C7).
 * - ts_rank orders by relevance; post_id is the tiebreak so pages are stable.
 * - The tag filter is EXISTS, not a JOIN on post_tags: a join would repeat a
 *   post once for every matching tag row.
 * - count(*) OVER () gives the total number of matches before LIMIT/OFFSET,
 *   so the UI can show "N results" without a second query.
 * - Every value is a bound parameter. The highlight markers [[[ and ]]] are
 *   plain text, so the page can render them as <mark> without ever putting
 *   post content into innerHTML.
 */
export async function GET(request: Request): Promise<Response> {
  try {
    const params = new URL(request.url).searchParams;

    const q = params.get("q")?.trim() ?? "";
    if (q.length === 0 || q.length > MAX_QUERY_LENGTH) {
      throw new HttpError(400, `q is required (at most ${MAX_QUERY_LENGTH} characters)`);
    }

    let community: string | null = null;
    const rawCommunity = params.get("community");
    if (rawCommunity !== null && rawCommunity !== "") {
      community = parseId(rawCommunity);
      if (!community) throw new HttpError(400, "community must be a numeric id");
    }

    // tags are stored in lower case (CHECK tag_name = lower(tag_name)).
    const tag = params.get("tag")?.trim().toLowerCase() || null;

    const limit = intParam(params, "limit", 10, 1, 50);
    const offset = intParam(params, "offset", 0, 0, 10000);

    const { rows } = await getDbPool().query(
      `WITH q AS (SELECT websearch_to_tsquery('english', $1) AS query)
       SELECT p.post_id AS "postId",
              p.title,
              ts_headline('english', p.content, q.query,
                          'StartSel=[[[, StopSel=]]], MaxWords=35, MinWords=15') AS snippet,
              p.published_at AS "publishedAt",
              u.name AS "authorName",
              c.community_id AS "communityId",
              c.name AS "communityName",
              round(ts_rank(p.search_vector, q.query)::numeric, 4)::float8 AS relevance,
              count(*) OVER ()::int AS total
         FROM published_posts p
         CROSS JOIN q
         JOIN users u ON u.user_id = p.author_id
         JOIN communities c ON c.community_id = p.community_id
        WHERE p.search_vector @@ q.query
          AND ($2::bigint IS NULL OR p.community_id = $2::bigint)
          AND ($3::text IS NULL OR EXISTS (
                SELECT 1
                  FROM post_tags pt
                  JOIN tags t ON t.tag_id = pt.tag_id
                 WHERE pt.post_id = p.post_id AND t.tag_name = $3::text))
        ORDER BY ts_rank(p.search_vector, q.query) DESC, p.post_id ASC
        LIMIT $4 OFFSET $5`,
      [q, community, tag, limit, offset],
    );

    const total: number = rows[0]?.total ?? 0;
    const posts = rows.map((row) => {
      const { total: rowTotal, ...post } = row;
      void rowTotal;
      return post;
    });
    return Response.json({ query: q, total, limit, offset, posts });
  } catch (err) {
    return errorResponse(err);
  }
}
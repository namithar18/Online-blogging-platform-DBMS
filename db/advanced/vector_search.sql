-- =====================================================================
-- vector_search.sql — semantic similarity with pgvector (component 9,
-- SQL part).
--
--   Part 1. "Similar posts": nearest neighbours by cosine distance,
--           filtered through published_posts (C7)
--   Part 2. HNSW index: EXPLAIN before/after on 10 000 random vectors,
--           and how the planner handles the C7 filter
--           (inside a transaction, rolled back)
--   Part 3. The permanent HNSW index
--
-- How it works: all-MiniLM-L6-v2 turns "title. content" into 384 numbers
-- (db/seed_embeddings.sql). Texts with similar meaning point in similar
-- directions. Cosine distance (<=>) = 1 - cosine similarity:
--   0 = same direction, 1 = unrelated, 2 = opposite.
-- pgvector also has <-> (Euclidean/L2) and <#> (negative inner product);
-- the index operator class must match the operator used in ORDER BY,
-- otherwise the index is ignored.
--
-- Run order: schema.sql -> seed.sql -> triggers.sql -> views.sql
--            -> indexes.sql -> seed_embeddings.sql -> this file.
--   psql "$DATABASE_URL" -f db/advanced/vector_search.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Drop first, so that on a re-run the "before" plan in Part 2 really
-- runs without the index.
DROP INDEX IF EXISTS post_embeddings_embedding_hnsw_idx;

\echo ''
\echo '=== Embeddings loaded: expect 12 rows of 384 dimensions ==='
SELECT count(*) AS embeddings, min(vector_dims(embedding)) AS dimensions
FROM post_embeddings
WHERE model_name = 'all-MiniLM-L6-v2';


-- =====================================================================
-- Part 1 — similar posts.
-- The source vector comes from a scalar subquery. PostgreSQL runs it once
-- before the main query (an InitPlan), so ORDER BY compares every row
-- with one fixed vector — the shape an index can serve (Part 2).
-- Joining published_posts applies C7: drafts, unpublished and removed
-- posts are never recommended.
-- =====================================================================
\echo ''
\echo '--- 1. Posts most similar to post 1 (B-tree indexes)'
SELECT p.post_id,
       p.title,
       round((e.embedding <=> (SELECT embedding FROM post_embeddings
                               WHERE post_id = 1 AND model_name = 'all-MiniLM-L6-v2'))::numeric, 4)
           AS cosine_distance
FROM post_embeddings e
JOIN published_posts p ON p.post_id = e.post_id
WHERE e.model_name = 'all-MiniLM-L6-v2'
  AND e.post_id <> 1                       -- a post is not "similar" to itself
ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                          WHERE post_id = 1 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 3;

\echo ''
\echo '--- 2. Posts most similar to post 6 (text embeddings)'
SELECT p.post_id,
       p.title,
       round((e.embedding <=> (SELECT embedding FROM post_embeddings
                               WHERE post_id = 6 AND model_name = 'all-MiniLM-L6-v2'))::numeric, 4)
           AS cosine_distance
FROM post_embeddings e
JOIN published_posts p ON p.post_id = e.post_id
WHERE e.model_name = 'all-MiniLM-L6-v2'
  AND e.post_id <> 6
ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                          WHERE post_id = 6 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 3;

\echo ''
\echo '--- 3. C7: neighbours of post 7 from the posts TABLE include draft post 10'
SELECT p.post_id,
       p.title,
       p.status,
       round((e.embedding <=> (SELECT embedding FROM post_embeddings
                               WHERE post_id = 7 AND model_name = 'all-MiniLM-L6-v2'))::numeric, 4)
           AS cosine_distance
FROM post_embeddings e
JOIN posts p ON p.post_id = e.post_id
WHERE e.model_name = 'all-MiniLM-L6-v2'
  AND e.post_id <> 7
ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                          WHERE post_id = 7 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 3;

\echo ''
\echo '--- 4. C7: the same search through published_posts -> post 10 is gone'
SELECT p.post_id,
       p.title,
       p.status,
       round((e.embedding <=> (SELECT embedding FROM post_embeddings
                               WHERE post_id = 7 AND model_name = 'all-MiniLM-L6-v2'))::numeric, 4)
           AS cosine_distance
FROM post_embeddings e
JOIN published_posts p ON p.post_id = e.post_id
WHERE e.model_name = 'all-MiniLM-L6-v2'
  AND e.post_id <> 7
ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                          WHERE post_id = 7 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 3;


-- =====================================================================
-- Part 2 — HNSW on a realistic number of vectors.
--
-- Without an index, nearest-neighbour search is exact but must compute
-- the distance to EVERY vector and sort them. HNSW (Hierarchical
-- Navigable Small World) is a graph: each vector links to its nearest
-- neighbours, and the search walks the graph towards the query, visiting
-- only a small part of the table.
--
-- Trade-off (viva): HNSW is APPROXIMATE. It can miss a true neighbour
-- (recall < 100%) in exchange for speed. A B-tree or GIN index never
-- changes the answer, only the speed; an HNSW index can change the answer.
--
-- 10 000 generated posts with random vectors: random is fine here because
-- we only look at the plan, not at the meaning of the results. 1 in 100
-- is published, the rest are drafts: this matters for test 7.
-- =====================================================================
\echo ''
\echo '=== Part 2. Loading 10 000 generated posts + random vectors (rolled back) ==='
BEGIN;

INSERT INTO posts (author_id, community_id, title, content, status, published_at)
SELECT 3, 1,
       'Generated post ' || n,
       'Generated content ' || n,
       CASE WHEN n % 100 = 0 THEN 'published' ELSE 'draft' END,
       CASE WHEN n % 100 = 0 THEN now() END
FROM generate_series(1, 10000) AS n;

-- ARRAY(SELECT random() ...) builds 384 random numbers. The reference to
-- p.post_id makes the subquery run once PER ROW; without it PostgreSQL
-- would compute one array and give every post the same vector.
INSERT INTO post_embeddings (post_id, model_name, embedding)
SELECT p.post_id,
       'all-MiniLM-L6-v2',
       ARRAY(SELECT random() - 0.5
             FROM generate_series(1, 384)
             WHERE p.post_id IS NOT NULL)::vector(384)
FROM posts p
WHERE p.title LIKE 'Generated post %';

ANALYZE posts;
ANALYZE post_embeddings;

\echo ''
\echo '--- 5 BEFORE: 5 nearest vectors -> expect Seq Scan + Sort over ~10 000 rows'
EXPLAIN ANALYZE
SELECT post_id
FROM post_embeddings
WHERE model_name = 'all-MiniLM-L6-v2'
ORDER BY embedding <=> (SELECT embedding FROM post_embeddings
                        WHERE post_id = 1 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 5;

-- vector_cosine_ops: build the graph for <=>. m = links per node,
-- ef_construction = candidates considered while building. These are the
-- pgvector defaults, written out so they can be discussed: higher values
-- give better recall but a slower build and a bigger index.
CREATE INDEX post_embeddings_embedding_hnsw_idx
    ON post_embeddings USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
ANALYZE post_embeddings;

\echo ''
\echo '--- 6 AFTER: expect Index Scan using post_embeddings_embedding_hnsw_idx, no Sort'
EXPLAIN ANALYZE
SELECT post_id
FROM post_embeddings
WHERE model_name = 'all-MiniLM-L6-v2'
ORDER BY embedding <=> (SELECT embedding FROM post_embeddings
                        WHERE post_id = 1 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 5;

-- -------------------------------------------------------------------
-- Test 7 — HNSW and a WHERE filter (C7).
-- An HNSW scan returns its ef_search (default 40) nearest candidates and
-- the filter runs AFTERWARDS. If only 1% of posts are published, ~40
-- candidates would leave 0 or 1 rows, and LIMIT 10 would not be met.
--
-- PostgreSQL avoids that trap here by itself: the planner estimates that
-- only ~100 posts are published, so it fetches those first (through the
-- partial index posts_published_at_idx from indexes.sql) and computes
-- the EXACT distance for just those 100. No HNSW, no missed neighbours.
-- The planner chooses by estimated cost, as in indexes.sql Part 3.
--
-- When the filter is NOT selective enough for that plan and HNSW is used,
-- pgvector 0.8+ offers SET hnsw.iterative_scan = relaxed_order: the scan
-- keeps walking the graph until enough rows pass the filter.
-- -------------------------------------------------------------------
\echo ''
\echo '--- 7. Similar published posts: expect NO hnsw index, the published posts are'
\echo '       fetched first and sorted exactly (Sort over ~100 rows)'
EXPLAIN ANALYZE
SELECT e.post_id
FROM post_embeddings e
JOIN published_posts p ON p.post_id = e.post_id
WHERE e.model_name = 'all-MiniLM-L6-v2'
ORDER BY e.embedding <=> (SELECT embedding FROM post_embeddings
                          WHERE post_id = 1 AND model_name = 'all-MiniLM-L6-v2')
LIMIT 10;

ROLLBACK;   -- generated posts, vectors and the demo index are all undone

-- ROLLBACK leaves the generated rows behind as dead tuples (MVCC), see
-- indexes.sql. VACUUM reclaims them so later EXPLAINs see the real size.
VACUUM ANALYZE posts;
VACUUM ANALYZE post_embeddings;


-- =====================================================================
-- Part 3 — the permanent index.
-- With 12 rows the planner still prefers an exact Seq Scan + Sort (all
-- rows fit in one page). The index pays off as the platform grows, and
-- the app's queries already have the shape it needs.
-- =====================================================================
\echo ''
\echo '=== Part 3. Creating the permanent HNSW index ==='
CREATE INDEX post_embeddings_embedding_hnsw_idx
    ON post_embeddings USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'post_embeddings'
ORDER BY indexname;

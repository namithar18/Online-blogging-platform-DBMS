--==========================================================================
-- File: fulltext.sql
-- Purpose: Add full-text search support for the `posts` table.
--==========================================================================
--
-- 1. GIN index on the generated `search_vector` column
-- ---------------------------------------------------------------------------
-- A GIN (Generalized Inverted Index) is the standard index type for searching
-- tsvector columns. It stores a mapping from each lexeme (word) to the rows
-- containing that lexeme, enabling fast `@@` (match) queries.
--
-- The column `posts.search_vector` is already defined as a stored generated
-- column (see db/schema.sql). Because it is generated, its value is always up-to-date - we only need an index to make look-ups efficient.
--
-- The index creation is idempotent: it will be created only if it does not
-- already exist.  `CONCURRENTLY` avoids locking the `posts` table for writes
-- during index build, which is safe for production environments.
--
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_search_vector
    ON posts USING gin (search_vector);

--==========================================================================
-- 2. Ranked full-text search query
-- ---------------------------------------------------------------------------
-- The following example demonstrates a searchable query that:
--   * accepts a literal search phrase
--   * uses `websearch_to_tsquery('english', ...)` - parses the phrase similar
--     to a web search engine (handles quotes, AND/OR, etc.)
--   * matches the generated `search_vector` with the `@@` operator
--   * ranks results with `ts_rank`
--   * returns only published posts
--   * orders by relevance (highest first)
--
-- To run the example, paste the block into psql and execute it.
-- Replace the search phrase as needed.
--
-- NOTE: This query is written to be self-contained - it does not rely on any
-- application-specific parameter placeholders.
--
WITH q AS (
    SELECT websearch_to_tsquery('english', 'machine learning') AS query
)
SELECT
    p.post_id,
    p.title,
    p.content,
    p.published_at,
    ts_rank(p.search_vector, q.query) AS relevance
FROM posts p, q
WHERE p.status = 'published'
  AND p.search_vector @@ q.query
ORDER BY relevance DESC;

--==========================================================================
-- 3. EXPLAIN (ANALYZE, BUFFERS) verification
-- ---------------------------------------------------------------------------
-- The block below runs the same query under EXPLAIN to show the execution
-- plan and resource usage.  Look for `Bitmap Index Scan` (or `Index Scan`) on
-- `idx_posts_search_vector` - that indicates the GIN index is being used.
-- If the planner decides a sequential scan is cheaper (e.g., very small
-- tables), it will show `Seq Scan`.  PostgreSQL may choose a sequential scan
-- when the estimated row count is low; this does not mean the index is wrong.
--
-- To force index usage for diagnostic purposes without changing permanent
-- settings you can temporarily raise `enable_seqscan` to `off` for the
-- session, e.g.:
--   SET enable_seqscan = off;
-- Then re-run the EXPLAIN.  Remember to reset it afterwards.
--
EXPLAIN (ANALYZE, BUFFERS)
WITH q AS (
    SELECT websearch_to_tsquery('english', 'machine learning') AS query
)
SELECT
    p.post_id,
    p.title,
    p.content,
    p.published_at,
    ts_rank(p.search_vector, q.query) AS relevance
FROM posts p, q
WHERE p.status = 'published'
  AND p.search_vector @@ q.query
ORDER BY relevance DESC;

--==========================================================================
-- 4. How to run this script
-- ---------------------------------------------------------------------------
--   1. Connect to the project's PostgreSQL database (e.g. via psql or any GUI).
--   2. Execute the file:
--        \i db/advanced/fulltext.sql
--   3. The index will be created (if missing) and the example queries can be
--      copied into the console to test.
--   4. Use the EXPLAIN block to verify that the index is being used.
--==========================================================================

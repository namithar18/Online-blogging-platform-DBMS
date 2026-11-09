\set ON_ERROR_STOP on
--==========================================================================
-- File: fulltext.sql
-- Purpose: Demonstrate full‑text search on the `published_posts` view.
--==========================================================================
-- NOTE: This script assumes that the schema (db/schema.sql), seed data
-- (db/seed.sql) and any view definitions (e.g. `published_posts`) have already
-- been applied.
--
-- 1. Drop any previous index and recreate it using the project's naming
--    convention.  The index is created on the generated `search_vector`
--    column of the `posts` table.
-- ---------------------------------------------------------------------------
\echo 'Creating permanent GIN index on posts.search_vector';
DROP INDEX IF EXISTS idx_posts_search_vector;
DROP INDEX IF EXISTS posts_search_vector_idx;
CREATE INDEX posts_search_vector_idx ON posts USING gin (search_vector);

--==========================================================================
-- 2. Demonstration search term – changed to "index" to match sample data.
\echo 'Running published-post full-text search';
-- ---------------------------------------------------------------------------
-- The view `published_posts` encapsulates the "status = 'published'" filter.
-- The query below shows how to rank results and order deterministically.
--
WITH q AS (
    SELECT websearch_to_tsquery('english', 'index') AS query
)
SELECT
    p.post_id,
    p.title,
    p.content,
    p.published_at,
    ts_rank(p.search_vector, q.query) AS relevance
FROM published_posts p, q
WHERE p.search_vector @@ q.query
ORDER BY relevance DESC, p.post_id ASC;

--==========================================================================
-- 3. Show that a draft post (post_id = 10) contains the term "index" in its
--    underlying `posts` row but is filtered out by the `published_posts` view.
-- ---------------------------------------------------------------------------
\echo 'Demonstrating that draft post 10 is excluded from published_posts';
WITH q AS (
    SELECT websearch_to_tsquery('english', 'index') AS query
)
SELECT
    p.post_id,
    p.title,
    p.content,
    p.status,
    ts_rank(p.search_vector, q.query) AS relevance
FROM posts p, q
WHERE p.post_id = 10
  AND p.search_vector @@ q.query;
-- The draft post should NOT appear in the published_posts view, so this query returns zero rows.
WITH q AS (
    SELECT websearch_to_tsquery('english', 'index') AS query
)
SELECT
    p.post_id,
    p.title
FROM published_posts p, q
WHERE p.post_id = 10
  AND p.search_vector @@ q.query;

--==========================================================================
-- 4. EXPLAIN (ANALYZE, BUFFERS) on a sizable temporary dataset.
-- ---------------------------------------------------------------------------
-- Insert ~100,000 test posts inside a transaction that is rolled back, then
-- run the same query with EXPLAIN.  This demonstrates the planner's choice
-- of the GIN index without leaving any rows behind.
--
--==========================================================================
-- 4. Comparing EXPLAIN plans before and after the GIN index
-- ---------------------------------------------------------------------------
\echo 'Comparing EXPLAIN plans before and after the GIN index';
BEGIN;
-- Generate ~100,000 test posts. About 1 % contain the word "index".
INSERT INTO posts (author_id, community_id, title, content, status, published_at)
SELECT
    1,                                   -- author_id (existing user)
    1,                                   -- community_id (existing community)
    'Test post ' || gs,                  -- title
    CASE
        WHEN gs % 100 = 0 THEN
            'This is a test post about index and other topics. ' || gs
        ELSE
            'This is a generic test post without the keyword. ' || gs
    END,
    'published',
    CURRENT_TIMESTAMP
FROM generate_series(1, 100000) AS gs;
ANALYZE posts;
-- EXPLAIN without the GIN index (index dropped temporarily)
DROP INDEX IF EXISTS posts_search_vector_idx;
EXPLAIN (ANALYZE, BUFFERS)
WITH q AS (
    SELECT websearch_to_tsquery('english', 'index') AS query
)
SELECT
    p.post_id,
    ts_rank(p.search_vector, q.query) AS relevance
FROM published_posts p, q
WHERE p.search_vector @@ q.query
ORDER BY relevance DESC, p.post_id ASC;
-- Re‑create the GIN index and analyze again
CREATE INDEX posts_search_vector_idx ON posts USING gin (search_vector);
ANALYZE posts;
-- EXPLAIN with the GIN index present
EXPLAIN (ANALYZE, BUFFERS)
WITH q AS (
    SELECT websearch_to_tsquery('english', 'index') AS query
)
SELECT
    p.post_id,
    ts_rank(p.search_vector, q.query) AS relevance
FROM published_posts p, q
WHERE p.search_vector @@ q.query
ORDER BY relevance DESC, p.post_id ASC;
\echo 'Rolling back the temporary test data';
ROLLBACK;


--==========================================================================
-- End of script.
--==========================================================================

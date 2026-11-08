-- =====================================================================
-- indexes.sql — B-tree indexes and EXPLAIN (component 4, step 4).
--
--   Part 1. EXPLAIN ANALYZE before/after on 100 000 generated posts
--           (inside a transaction, rolled back)
--   Part 2. The permanent indexes
--   Part 3. Why the planner still ignores them on the 12-row seed data
--
-- PostgreSQL indexes PRIMARY KEY and UNIQUE columns automatically, but
-- NOT foreign key columns. Rule used here: index every FK column that is
-- not already the FIRST column of an existing index. FK columns are what
-- joins filter on, and ON DELETE RESTRICT/CASCADE must search them every
-- time a parent row is deleted.
--
-- Trade-off (viva): each index speeds up reads but slows every INSERT,
-- UPDATE and DELETE on its table (the index must be updated too) and
-- takes disk space. So only columns that are actually searched or joined.
--
-- Not here: GIN on posts.search_vector (component 5, fulltext.sql) and
-- the HNSW vector index (component 9).
--
-- Run order: after schema.sql and seed.sql (any time after those).
--   psql "$DATABASE_URL" -f db/advanced/indexes.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Drop first, so that on a re-run the "before" plans in Part 1 really
-- run without the indexes.
DROP INDEX IF EXISTS posts_author_id_idx;
DROP INDEX IF EXISTS posts_community_id_idx;
DROP INDEX IF EXISTS posts_published_at_idx;
DROP INDEX IF EXISTS communities_created_by_idx;
DROP INDEX IF EXISTS post_tags_tag_id_idx;
DROP INDEX IF EXISTS community_members_community_id_idx;
DROP INDEX IF EXISTS comments_post_id_idx;
DROP INDEX IF EXISTS comments_author_id_idx;
DROP INDEX IF EXISTS comments_parent_comment_id_idx;
DROP INDEX IF EXISTS reactions_post_id_idx;
DROP INDEX IF EXISTS bookmarks_post_id_idx;
DROP INDEX IF EXISTS follows_followee_id_idx;
DROP INDEX IF EXISTS reading_activity_user_time_idx;
DROP INDEX IF EXISTS reading_activity_post_id_idx;


-- =====================================================================
-- Part 1 — before/after on a realistic amount of data.
-- With only 12 posts every query is a sequential scan no matter what
-- (see Part 3), so we add 100 000 posts inside a transaction, compare
-- the plans, and ROLLBACK: the generated rows and the demo indexes
-- disappear again.
-- =====================================================================
\echo ''
\echo '=== Part 1. Loading 100 000 generated posts (rolled back at the end) ==='
BEGIN;

-- Generated authors are users 4-8 only, so author 3 keeps just her few
-- seed posts: a very selective search, which is where an index shines.
-- Every 10th generated post is a draft (published_at NULL, C4).
INSERT INTO posts (author_id, community_id, title, content, status,
                   created_at, updated_at, published_at)
SELECT 4 + n % 5,
       1 + n % 5,
       'Generated post ' || n,
       'Generated content for post number ' || n,
       CASE WHEN n % 10 = 0 THEN 'draft' ELSE 'published' END,
       t.ts, t.ts,
       CASE WHEN n % 10 = 0 THEN NULL ELSE t.ts END
FROM generate_series(1, 100000) AS n
CROSS JOIN LATERAL (SELECT timestamptz '2025-01-01' + n * interval '1 minute' AS ts) AS t;

-- ANALYZE refreshes the table statistics the planner uses to estimate
-- row counts. Without it the planner would still think posts is tiny.
ANALYZE posts;

\echo ''
\echo '--- Q1 BEFORE: posts by author 3 -> expect Seq Scan over ~100 000 rows'
EXPLAIN ANALYZE
SELECT post_id, title FROM posts WHERE author_id = 3;

\echo ''
\echo '--- Q2 BEFORE: 10 newest published posts -> expect Seq Scan + Sort'
EXPLAIN ANALYZE
SELECT post_id, title, published_at
FROM published_posts
ORDER BY published_at DESC
LIMIT 10;

CREATE INDEX posts_author_id_idx ON posts (author_id);
CREATE INDEX posts_published_at_idx ON posts (published_at DESC)
    WHERE status = 'published';
ANALYZE posts;

\echo ''
\echo '--- Q1 AFTER: expect Index Scan (or Bitmap Index Scan) on posts_author_id_idx'
EXPLAIN ANALYZE
SELECT post_id, title FROM posts WHERE author_id = 3;

\echo ''
\echo '--- Q2 AFTER: expect Index Scan on posts_published_at_idx, no Sort'
EXPLAIN ANALYZE
SELECT post_id, title, published_at
FROM published_posts
ORDER BY published_at DESC
LIMIT 10;

ROLLBACK;   -- generated posts and both demo indexes are gone again

-- MVCC (viva): ROLLBACK does not erase the 100 000 rows from disk. They
-- stay in the table's pages as dead tuples, invisible to every query,
-- until VACUUM reclaims the space. Without this the table would still
-- look big to the planner in Part 3. VACUUM cannot run inside a
-- transaction block, so it runs on its own here.
VACUUM ANALYZE posts;


-- =====================================================================
-- Part 2 — the permanent indexes.
-- "Leading column" (viva): a composite index on (a, b) is sorted by a
-- first, like a phone book sorted by surname then first name. It helps
-- searches on a, or on a and b, but NOT on b alone. That is why the PKs
-- below do not cover their second column.
-- =====================================================================
\echo ''
\echo '=== Part 2. Creating the permanent indexes ==='

-- posts: "posts by this author" (profile page) and "posts in this
-- community" (community page); also the RESTRICT checks when deleting a
-- user or community.
CREATE INDEX posts_author_id_idx    ON posts (author_id);
CREATE INDEX posts_community_id_idx ON posts (community_id);

-- Partial index: only rows WHERE status = 'published' are stored, which
-- is the same filter as published_posts (C7). Smaller than a full index,
-- and already sorted newest-first for the feed. The planner uses it only
-- when the query's WHERE implies the index's WHERE.
CREATE INDEX posts_published_at_idx ON posts (published_at DESC)
    WHERE status = 'published';

-- communities.created_by: RESTRICT check when deleting a user.
CREATE INDEX communities_created_by_idx ON communities (created_by);

-- PK (post_id, tag_id) covers "tags of a post", not "posts with a tag".
CREATE INDEX post_tags_tag_id_idx ON post_tags (tag_id);

-- PK (user_id, community_id) covers "my communities", not "members of
-- a community".
CREATE INDEX community_members_community_id_idx ON community_members (community_id);

-- comments: the UNIQUE (comment_id, post_id) index starts with comment_id,
-- so it cannot find "all comments of a post".
CREATE INDEX comments_post_id_idx           ON comments (post_id);
CREATE INDEX comments_author_id_idx         ON comments (author_id);
-- Replies of a comment; also the C2 composite FK check on delete.
CREATE INDEX comments_parent_comment_id_idx ON comments (parent_comment_id);

-- PK (user_id, post_id) starts with user_id; popular_posts groups
-- reactions by post_id.
CREATE INDEX reactions_post_id_idx ON reactions (post_id);
CREATE INDEX bookmarks_post_id_idx ON bookmarks (post_id);

-- PK (follower_id, followee_id) covers "who do I follow", not
-- "who follows me".
CREATE INDEX follows_followee_id_idx ON follows (followee_id);

-- Reading history (queries.sql Q17): one user's views, newest first.
-- user_id is the leading column, so this also serves the FK.
CREATE INDEX reading_activity_user_time_idx ON reading_activity (user_id, occurred_at DESC);
CREATE INDEX reading_activity_post_id_idx   ON reading_activity (post_id);

-- post_embeddings needs none: its PK (post_id, model_name) already starts
-- with the FK column post_id.

\echo ''
\echo '--- All indexes: the *_pkey / *_key ones were created automatically'
SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;


-- =====================================================================
-- Part 3 — on the real 12-row table the planner still picks Seq Scan.
-- All 12 posts fit in one 8 kB page: reading that page is cheaper than
-- reading the index AND the page. The planner chooses by estimated cost,
-- not by whether an index exists.
-- =====================================================================
\echo ''
\echo '=== Part 3. Small table: Seq Scan even though the index exists ==='
EXPLAIN SELECT post_id, title FROM posts WHERE author_id = 3;

\echo ''
\echo '--- Forcing the planner away from Seq Scan shows the index is usable'
-- enable_seqscan = off is only for experiments: it makes Seq Scan look
-- extremely expensive. Never use it in the application.
SET enable_seqscan = off;
EXPLAIN SELECT post_id, title FROM posts WHERE author_id = 3;
RESET enable_seqscan;

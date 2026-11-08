-- =====================================================================
-- views.sql — named, stored queries (component 4, step 2).
--
--   published_posts   enforces C7: only published, non-removed posts
--   popular_posts     reaction and comment counts, computed (not stored)
--
-- A view stores only its SELECT, not data. Every query on it re-runs that
-- SELECT, so it is always up to date with the base tables.
--
-- Run order: schema.sql -> seed.sql -> triggers.sql -> this file.
-- DROP TABLE removes dependent views as well, so re-run this file every
-- time schema.sql is re-run.
--   psql "$DATABASE_URL" -f db/advanced/views.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Dropped in reverse dependency order: popular_posts is built on
-- published_posts. CREATE OR REPLACE VIEW cannot remove or rename
-- columns, so drop-and-create keeps this file re-runnable after edits.
DROP VIEW IF EXISTS popular_posts;
DROP VIEW IF EXISTS published_posts;


-- ---------------------------------------------------------------------
-- 1. published_posts — C7.
--
-- Search (component 5), recommendations and similar posts (component 9)
-- query this view instead of posts, so the C7 filter lives in ONE place
-- and cannot be forgotten in one of many queries.
-- status = 'published' already excludes 'draft', 'unpublished' and
-- 'removed' (moderated), because status holds exactly one value.
--
-- Single table, no joins, no GROUP BY: PostgreSQL makes such a view
-- automatically updatable (INSERT/UPDATE/DELETE pass through to posts).
-- WITH CHECK OPTION then rejects any write through the view that would
-- produce a row the view cannot show, e.g. inserting a draft.
-- ---------------------------------------------------------------------
CREATE VIEW published_posts AS
SELECT post_id,
       author_id,
       community_id,
       title,
       content,
       status,
       created_at,
       updated_at,
       published_at,
       search_vector          -- kept so full-text search can use the view
FROM posts
WHERE status = 'published'
WITH CHECK OPTION;


-- ---------------------------------------------------------------------
-- 2. popular_posts — counts computed by GROUP BY, never stored
-- (CLAUDE.md: counts are computed with queries). Built on published_posts,
-- so it inherits C7.
--
-- Each count is aggregated in its own derived table BEFORE joining.
-- Joining reactions and comments directly would multiply rows: a post
-- with 5 reactions and 4 comments would give 5 x 4 = 20 joined rows and
-- both counts would come out as 20 (see test 3 below).
--
-- Only 'visible' comments are counted: removed ones are soft-deleted.
-- LEFT JOIN + COALESCE: posts with no reactions or comments still appear,
-- with 0 instead of NULL.
--
-- No ORDER BY here: SQL does not guarantee a view's row order to the
-- outer query. Sort when querying the view.
--
-- Alternative (viva): a MATERIALIZED VIEW stores the result and is faster
-- to read, but is stale until REFRESH MATERIALIZED VIEW is run. A plain
-- view is fine at this data size and is never out of date.
-- ---------------------------------------------------------------------
CREATE VIEW popular_posts AS
SELECT p.post_id,
       p.title,
       u.name                               AS author_name,
       c.name                               AS community_name,
       p.published_at,
       COALESCE(r.like_count, 0)            AS like_count,
       COALESCE(r.love_count, 0)            AS love_count,
       COALESCE(r.insightful_count, 0)      AS insightful_count,
       COALESCE(r.reaction_count, 0)        AS reaction_count,
       COALESCE(cm.comment_count, 0)        AS comment_count,
       -- Simple, explainable score: every reaction or comment counts 1.
       COALESCE(r.reaction_count, 0) + COALESCE(cm.comment_count, 0)
                                            AS popularity_score
FROM published_posts p
JOIN users       u ON u.user_id      = p.author_id
JOIN communities c ON c.community_id = p.community_id
LEFT JOIN (
    -- One row per post. FILTER counts only the rows matching the
    -- condition, giving all three per-type counts in a single pass.
    SELECT post_id,
           count(*)                                         AS reaction_count,
           count(*) FILTER (WHERE reaction_type = 'like')       AS like_count,
           count(*) FILTER (WHERE reaction_type = 'love')       AS love_count,
           count(*) FILTER (WHERE reaction_type = 'insightful') AS insightful_count
    FROM reactions
    GROUP BY post_id
) r ON r.post_id = p.post_id
LEFT JOIN (
    SELECT post_id, count(*) AS comment_count
    FROM comments
    WHERE status = 'visible'
    GROUP BY post_id
) cm ON cm.post_id = p.post_id;


\echo ''
\echo '=== Views installed ==='
SELECT table_name AS view_name, is_updatable, check_option
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY view_name;


-- =====================================================================
-- Tests, part 1 — valid queries. Must NOT print ERROR.
-- =====================================================================
\echo ''
\echo '--- 1. C7: published_posts shows 9 of 12 posts (posts 1-9)'
SELECT (SELECT count(*) FROM posts)           AS all_posts,
       (SELECT count(*) FROM published_posts) AS visible_posts;

\echo '--- 2. C7: draft (10), unpublished (11) and removed (12) are hidden -> 0'
SELECT count(*) AS hidden_posts_visible
FROM published_posts
WHERE post_id IN (10, 11, 12);

\echo '--- 3. Why popular_posts aggregates first: a naive join on post 1'
\echo '        (5 reactions, 4 comments) gives 20 for both counts'
SELECT p.post_id,
       count(r.user_id)    AS wrong_reaction_count,
       count(cm.comment_id) AS wrong_comment_count
FROM posts p
LEFT JOIN reactions r  ON r.post_id  = p.post_id
LEFT JOIN comments  cm ON cm.post_id = p.post_id
WHERE p.post_id = 1
GROUP BY p.post_id;

\echo '--- 4. popular_posts: post 1 -> 5 reactions, 4 comments, score 9'
\echo '        post 7 -> 1 comment, not 2: its removed comment is not counted'
SELECT post_id, title, reaction_count, comment_count, popularity_score
FROM popular_posts
ORDER BY popularity_score DESC, published_at DESC;

\echo '--- 5. Views are live: unpublish post 1 and it vanishes from both (rolled back)'
BEGIN;
UPDATE posts SET status = 'unpublished' WHERE post_id = 1;
SELECT (SELECT count(*) FROM published_posts WHERE post_id = 1) AS in_published,
       (SELECT count(*) FROM popular_posts   WHERE post_id = 1) AS in_popular;
ROLLBACK;


-- =====================================================================
-- Tests, part 2 — invalid statements. Every one MUST print ERROR.
-- =====================================================================
\set ON_ERROR_STOP off

\echo ''
\echo '=== Invalid: each one below must print ERROR ==='

\echo '--- 6. CHECK OPTION: insert a draft through published_posts'
INSERT INTO published_posts (author_id, community_id, title, content, status)
VALUES (3, 1, 'Sneaky draft', 'Should not get in.', 'draft');

\echo '--- 7. CHECK OPTION: hide a post by updating it through the view'
UPDATE published_posts SET status = 'removed' WHERE post_id = 1;

\echo '--- 8. popular_posts is not updatable (joins + GROUP BY)'
UPDATE popular_posts SET popularity_score = 1000 WHERE post_id = 1;

\echo ''
\echo '=== After the invalid statements nothing changed ==='
SELECT (SELECT count(*) FROM posts)           AS all_posts,
       (SELECT count(*) FROM published_posts) AS visible_posts;

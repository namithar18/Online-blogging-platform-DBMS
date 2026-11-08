-- =====================================================================
-- transactions.sql — atomic multi-step writes (component 4, step 3).
--
-- Creating a post is several statements: the post row, any new tags, and
-- the post_tags links (component 9 adds the embedding row). Either all of
-- them must happen or none, so they run in ONE transaction (the A in ACID).
--
--   A. Without a transaction: a failure leaves a half-saved post
--   B. With a transaction: post + tags, COMMIT
--   C. With a transaction: one step fails, ROLLBACK undoes everything
--   D. SAVEPOINT: undo only the failed step, keep the rest
--
-- Run order: schema.sql -> seed.sql -> triggers.sql -> views.sql -> this.
-- The file cleans up after itself, so the seed data is unchanged.
--   psql "$DATABASE_URL" -f db/advanced/transactions.sql
--
-- \gset (psql) stores the columns of the last result in psql variables,
-- e.g. RETURNING post_id \gset new_  ->  :new_post_id. The API will do the
-- same with the RETURNING row it gets back from pg.
-- =====================================================================


-- ---------------------------------------------------------------------
-- A. The problem: no transaction.
-- In autocommit mode every statement commits on its own. The post is
-- saved, then the tag insert fails (tag names must be lower case), and
-- nothing undoes the post: the database is left with a post that lost
-- its tags.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP off

\echo ''
\echo '=== A. No transaction: the tag fails but the post stays (bad) ==='
INSERT INTO posts (author_id, community_id, title, content)
VALUES (3, 1, 'Half-saved post', 'Its tags failed but the post was kept.')
RETURNING post_id \gset half_

\echo '--- A1. This tag insert must print ERROR (upper-case tag name)'
INSERT INTO tags (tag_name) VALUES ('BadTag');

\echo '--- A2. The post exists with 0 tags -> inconsistent'
SELECT p.post_id, p.title, count(pt.tag_id) AS tag_count
FROM posts p
LEFT JOIN post_tags pt ON pt.post_id = p.post_id
WHERE p.post_id = :half_post_id
GROUP BY p.post_id, p.title;


-- ---------------------------------------------------------------------
-- B. The fix: BEGIN ... COMMIT.
-- Nothing is visible to other sessions until COMMIT; at COMMIT all of it
-- becomes permanent together (atomicity + durability).
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on

\echo ''
\echo '=== B. Transaction succeeds: post + 2 tags, COMMIT ==='
BEGIN;

-- published_at = now(): C4 needs it for a published post. now() is the
-- transaction start time, the same value created_at gets by default, so
-- published_at >= created_at holds.
INSERT INTO posts (author_id, community_id, title, content, status, published_at)
VALUES (3, 1, 'Isolation Levels in PostgreSQL',
        'Read committed, repeatable read and serializable compared.',
        'published', now())
RETURNING post_id \gset new_

-- Find-or-create tags. 'postgresql' already exists, 'isolation' is new.
-- ON CONFLICT DO NOTHING skips existing names instead of failing on the
-- UNIQUE constraint, so the statement works either way.
INSERT INTO tags (tag_name) VALUES ('postgresql'), ('isolation')
ON CONFLICT (tag_name) DO NOTHING;

-- Link by name, so we do not need to know the tag ids in advance.
INSERT INTO post_tags (post_id, tag_id)
SELECT :new_post_id, tag_id
FROM tags
WHERE tag_name IN ('postgresql', 'isolation');

-- Component 9 adds the embedding here, inside the same transaction:
-- INSERT INTO post_embeddings (post_id, model_name, embedding) VALUES (...);

COMMIT;

\echo '--- B1. The new post with its 2 tags'
SELECT p.post_id, p.title, p.status, string_agg(t.tag_name, ', ' ORDER BY t.tag_name) AS tags
FROM posts p
JOIN post_tags pt ON pt.post_id = p.post_id
JOIN tags t       ON t.tag_id   = pt.tag_id
WHERE p.post_id = :new_post_id
GROUP BY p.post_id, p.title, p.status;


-- ---------------------------------------------------------------------
-- C. A step fails inside the transaction -> ROLLBACK.
-- After an error PostgreSQL marks the transaction as aborted: every
-- further statement is refused until ROLLBACK. (Even COMMIT would only
-- roll back — PostgreSQL never commits half a transaction.)
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP off

\echo ''
\echo '=== C. Transaction fails: one bad step, ROLLBACK undoes the post too ==='
SELECT count(*) AS posts_before FROM posts;

BEGIN;

INSERT INTO posts (author_id, community_id, title, content)
VALUES (3, 1, 'This post must not survive', 'Its tag insert fails.')
RETURNING post_id \gset doomed_

\echo '--- C1. Must print ERROR: upper-case tag name'
INSERT INTO tags (tag_name) VALUES ('BadTag');

\echo '--- C2. Must print ERROR: current transaction is aborted'
INSERT INTO post_tags (post_id, tag_id) VALUES (:doomed_post_id, 1);

-- The API does exactly this in its catch block.
ROLLBACK;

\echo '--- C3. Same count as before, and the post is gone -> 0'
SELECT count(*) AS posts_after FROM posts;
SELECT count(*) AS doomed_post_exists FROM posts WHERE post_id = :doomed_post_id;
-- Its post_id was still used up: sequences are not rolled back, so the
-- next post skips that number. Ids are unique, not gap-free.


-- ---------------------------------------------------------------------
-- D. SAVEPOINT: a marker inside a transaction. ROLLBACK TO SAVEPOINT
-- undoes only the work after the marker and clears the aborted state,
-- so the transaction can continue. Useful when one optional step may fail.
-- The whole transaction is rolled back at the end to keep the seed clean.
-- ---------------------------------------------------------------------
\echo ''
\echo '=== D. SAVEPOINT: undo only the failed tag, keep the post ==='
BEGIN;

INSERT INTO posts (author_id, community_id, title, content)
VALUES (3, 1, 'Savepoint demo', 'The post survives a failed tag.')
RETURNING post_id \gset sp_

SAVEPOINT before_tags;

\echo '--- D1. Must print ERROR: upper-case tag name'
INSERT INTO tags (tag_name) VALUES ('BadTag');

ROLLBACK TO SAVEPOINT before_tags;   -- post kept, error cleared

-- Works now: the transaction is no longer aborted.
INSERT INTO post_tags (post_id, tag_id)
SELECT :sp_post_id, tag_id FROM tags WHERE tag_name = 'sql';

\echo '--- D2. Post still there with 1 tag (inside the transaction)'
SELECT p.post_id, p.title, count(pt.tag_id) AS tag_count
FROM posts p
LEFT JOIN post_tags pt ON pt.post_id = p.post_id
WHERE p.post_id = :sp_post_id
GROUP BY p.post_id, p.title;

ROLLBACK;


-- ---------------------------------------------------------------------
-- Clean-up: remove what A and B committed, so seed data is unchanged and
-- this file can be re-run. post_tags rows go with the posts (CASCADE).
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on

\echo ''
\echo '=== Clean-up: back to the seed data (12 posts, 9 tags) ==='
DELETE FROM posts WHERE post_id IN (:half_post_id, :new_post_id);
DELETE FROM tags  WHERE tag_name = 'isolation';
SELECT (SELECT count(*) FROM posts) AS posts,
       (SELECT count(*) FROM tags)  AS tags;


-- ---------------------------------------------------------------------
-- Isolation (the I in ACID), to try by hand with two psql windows.
-- PostgreSQL's default level is READ COMMITTED.
--   Window 1: BEGIN; UPDATE posts SET title = 'Changed' WHERE post_id = 1;
--   Window 2: SELECT title FROM posts WHERE post_id = 1;  -- old title:
--             uncommitted changes are invisible to other sessions
--   Window 2: UPDATE posts SET title = 'Other' WHERE post_id = 1;
--             -- waits: window 1 holds a row lock
--   Window 1: ROLLBACK;   -- window 2's UPDATE now goes through
-- ---------------------------------------------------------------------

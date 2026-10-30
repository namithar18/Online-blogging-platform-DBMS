-- =====================================================================
-- seed.sql — sample data, then deliberate invalid statements.
-- Run after schema.sql:  psql "$DATABASE_URL" -f db/seed.sql
--
-- Part 1 loads valid data in one transaction: all of it or none of it.
-- Part 2 runs statements that MUST fail; every one should print ERROR.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Empties everything and restarts ids at 1, so the ids used below are
-- predictable and this file can be re-run.
TRUNCATE users, communities, tags, posts, post_tags, community_members,
         comments, reactions, bookmarks, follows, post_embeddings,
         reading_activity
RESTART IDENTITY;

-- C8: placeholders in bcrypt format, not hashes of real passwords.
-- These accounts cannot log in; component 7 creates real hashes.
INSERT INTO users (name, email, password_hash, bio, role, created_at) VALUES
    ('Ravi Kumar',    'ravi@example.com',    '$2b$10$seedplaceholderhash000001', 'Platform admin.',          'ADMIN', '2026-01-05 09:00+05:30'),  -- 1
    ('Meena Iyer',    'meena@example.com',   '$2b$10$seedplaceholderhash000002', 'Community moderator.',     'ADMIN', '2026-01-06 09:00+05:30'),  -- 2
    ('Asha Rao',      'asha@example.com',    '$2b$10$seedplaceholderhash000003', 'Writes about databases.',  'USER',  '2026-01-10 10:00+05:30'),  -- 3
    ('Karthik Nair',  'karthik@example.com', '$2b$10$seedplaceholderhash000004', 'Backend developer.',       'USER',  '2026-01-12 11:00+05:30'),  -- 4
    ('Divya Shetty',  'divya@example.com',   '$2b$10$seedplaceholderhash000005', 'Frontend and ML curious.', 'USER',  '2026-01-15 12:00+05:30'),  -- 5
    ('Arjun Menon',   'arjun@example.com',   '$2b$10$seedplaceholderhash000006', NULL,                       'USER',  '2026-01-18 13:00+05:30'),  -- 6
    ('Sneha Pai',     'sneha@example.com',   '$2b$10$seedplaceholderhash000007', 'Mostly here to read.',     'USER',  '2026-01-20 14:00+05:30'),  -- 7 (reader, no posts)
    ('Rahul Bhat',    'rahul@example.com',   '$2b$10$seedplaceholderhash000008', NULL,                       'USER',  '2026-02-01 15:00+05:30');  -- 8 (reader, no posts)

-- Only admins create communities (C5; the trigger arrives in component 4).
INSERT INTO communities (name, description, created_by, created_at) VALUES
    ('Databases',        'Relational design, SQL and internals.', 1, '2026-01-07 10:00+05:30'),  -- 1
    ('Web Development',  'Frontend, backend and frameworks.',     1, '2026-01-07 10:30+05:30'),  -- 2
    ('Machine Learning', 'Models, embeddings and search.',        2, '2026-01-08 10:00+05:30'),  -- 3
    ('Career Advice',    'Interviews and growing as an engineer.',2, '2026-01-08 10:30+05:30'),  -- 4
    ('Open Source',      'Contributing to public projects.',      2, '2026-02-10 10:00+05:30');  -- 5 (deliberately has no posts)

INSERT INTO tags (tag_name) VALUES
    ('postgresql'),    -- 1
    ('indexing'),      -- 2
    ('sql'),           -- 3
    ('transactions'),  -- 4
    ('nextjs'),        -- 5
    ('react'),         -- 6
    ('embeddings'),    -- 7
    ('career'),        -- 8
    ('rust');          -- 9 (deliberately unused)

-- Covers every status. C4: anything published has published_at.
INSERT INTO posts (author_id, community_id, title, content, status, created_at, updated_at, published_at) VALUES
    (3, 1, 'How B-Tree Indexes Speed Up Lookups',
        'A B-tree keeps keys sorted so PostgreSQL can find a row without scanning the whole table. This post explains how pages and tree depth affect lookup cost.',
        'published', '2026-02-01 10:00+05:30', '2026-02-02 10:00+05:30', '2026-02-02 10:00+05:30'),  -- 1
    (3, 1, 'Understanding ACID Transactions in PostgreSQL',
        'Atomicity, consistency, isolation and durability explained with a bank transfer example, including what happens on ROLLBACK.',
        'published', '2026-02-10 10:00+05:30', '2026-02-10 12:00+05:30', '2026-02-10 12:00+05:30'),  -- 2
    (4, 1, 'Normalization: From 1NF to BCNF',
        'Walking through functional dependencies and the anomalies each normal form removes, using a small course registration table.',
        'published', '2026-02-15 09:00+05:30', '2026-02-15 09:30+05:30', '2026-02-15 09:30+05:30'),  -- 3
    (4, 2, 'Route Handlers in the Next.js App Router',
        'How to build an API layer with Route Handlers, validate input and keep database access on the server.',
        'published', '2026-03-01 09:00+05:30', '2026-03-01 10:00+05:30', '2026-03-01 10:00+05:30'),  -- 4
    (5, 2, 'React Server Components Explained',
        'What runs on the server, what runs in the browser, and why fetching data in a server component simplifies many pages.',
        'published', '2026-03-05 11:00+05:30', '2026-03-05 11:30+05:30', '2026-03-05 11:30+05:30'),  -- 5
    (5, 3, 'What Are Text Embeddings?',
        'Embeddings turn text into vectors so that sentences with similar meanings end up close together, even when they share no words.',
        'published', '2026-03-12 16:00+05:30', '2026-03-12 17:00+05:30', '2026-03-12 17:00+05:30'),  -- 6
    (6, 3, 'Semantic Search with pgvector',
        'Storing vectors next to relational data and ranking results by cosine distance, with notes on approximate indexes.',
        'published', '2026-03-20 18:00+05:30', '2026-03-21 09:00+05:30', '2026-03-21 09:00+05:30'),  -- 7
    (6, 4, 'Preparing for Your First Technical Interview',
        'A practical plan for revising fundamentals, practising out loud and handling questions you cannot answer.',
        'published', '2026-04-02 08:00+05:30', '2026-04-02 08:30+05:30', '2026-04-02 08:30+05:30'),  -- 8
    (3, 2, 'Scaling a Blog with Connection Pooling',
        'Why opening a new database connection per request hurts, and how a shared pool fixes it.',
        'published', '2026-04-10 10:00+05:30', '2026-04-10 11:00+05:30', '2026-04-10 11:00+05:30'),  -- 9
    (3, 3, 'Notes on Vector Indexes',
        'Unfinished notes comparing HNSW and IVFFlat.',
        'draft',       '2026-04-15 10:00+05:30', '2026-04-16 10:00+05:30', NULL),                     -- 10
    (4, 4, 'Why I Stopped Using ORMs',
        'An opinion piece the author later took down for rewriting.',
        'unpublished', '2026-04-18 10:00+05:30', '2026-04-20 10:00+05:30', '2026-04-18 12:00+05:30'), -- 11
    (5, 1, 'Buy Cheap Followers Now',
        'Spam removed by an admin. It must never appear in listings (C7).',
        'removed',     '2026-04-22 10:00+05:30', '2026-04-22 15:00+05:30', '2026-04-22 11:00+05:30'); -- 12

INSERT INTO post_tags (post_id, tag_id) VALUES
    (1, 1), (1, 2), (1, 3),
    (2, 1), (2, 3), (2, 4),
    (3, 3),
    (4, 5),
    (5, 5), (5, 6),
    (6, 7),
    (7, 1), (7, 2), (7, 7),
    (8, 8),
    (9, 1), (9, 5),
    (10, 2), (10, 7),
    (11, 5);
    -- Post 12 is untagged: TAGGED_WITH is partial on the post side.

INSERT INTO community_members (user_id, community_id, joined_at) VALUES
    (3, 1, '2026-01-11 10:00+05:30'), (3, 2, '2026-01-11 10:05+05:30'), (3, 3, '2026-03-01 10:00+05:30'),
    (4, 1, '2026-01-13 10:00+05:30'), (4, 2, '2026-01-13 10:05+05:30'),
    (5, 2, '2026-01-16 10:00+05:30'), (5, 3, '2026-01-16 10:05+05:30'),
    (6, 3, '2026-01-19 10:00+05:30'), (6, 4, '2026-01-19 10:05+05:30'),
    (7, 1, '2026-01-21 10:00+05:30'), (7, 3, '2026-01-21 10:05+05:30'), (7, 4, '2026-02-05 10:00+05:30'),
    (8, 1, '2026-02-02 10:00+05:30');
    -- Users 7 and 8 are members with no posts. User 5 wrote post 12 in
    -- community 1 without joining it (A8: authors need not be members).

-- Inserted in order so that every parent already exists.
INSERT INTO comments (post_id, author_id, parent_comment_id, content, status, created_at, updated_at) VALUES
    (1, 4, NULL, 'Great explanation of tree depth.',                 'visible', '2026-02-03 09:00+05:30', '2026-02-03 09:00+05:30'),  -- 1
    (1, 5, 1,    'Agreed. Does this change for composite indexes?',  'visible', '2026-02-03 10:00+05:30', '2026-02-03 10:00+05:30'),  -- 2 (reply to 1)
    (1, 3, 2,    'Yes, column order matters. I will write about it.','visible', '2026-02-03 11:00+05:30', '2026-02-03 11:00+05:30'),  -- 3 (reply to 2)
    (1, 7, NULL, 'This finally made indexes click for me.',          'visible', '2026-02-04 09:00+05:30', '2026-02-04 09:00+05:30'),  -- 4
    (2, 6, NULL, 'Could you cover isolation levels next?',           'visible', '2026-02-11 09:00+05:30', '2026-02-11 09:00+05:30'),  -- 5
    (2, 3, 5,    'Yes, that is the next post.',                      'visible', '2026-02-11 10:00+05:30', '2026-02-11 10:00+05:30'),  -- 6 (reply to 5)
    (5, 3, NULL, 'Clearest summary I have read.',                    'visible', '2026-03-06 09:00+05:30', '2026-03-06 09:00+05:30'),  -- 7
    (7, 7, NULL, 'Rude remark hidden by a moderator.',               'removed', '2026-03-22 09:00+05:30', '2026-03-22 12:00+05:30'),  -- 8 (soft deleted)
    (7, 5, 8,    'Please keep this friendly.',                       'visible', '2026-03-22 10:00+05:30', '2026-03-22 10:00+05:30'),  -- 9 (reply survives)
    (3, 8, NULL, 'The anomaly examples helped a lot.',               'visible', '2026-02-16 09:00+05:30', '2026-02-16 09:00+05:30');  -- 10

INSERT INTO reactions (user_id, post_id, reaction_type, reacted_at) VALUES
    (4, 1, 'like',       '2026-02-03 09:05+05:30'),
    (5, 1, 'insightful', '2026-02-03 10:05+05:30'),
    (6, 1, 'like',       '2026-02-05 09:00+05:30'),
    (7, 1, 'love',       '2026-02-04 09:05+05:30'),
    (8, 1, 'like',       '2026-02-06 09:00+05:30'),
    (4, 2, 'insightful', '2026-02-12 09:00+05:30'),
    (6, 2, 'like',       '2026-02-11 09:05+05:30'),
    (7, 2, 'like',       '2026-02-13 09:00+05:30'),
    (3, 3, 'like',       '2026-02-16 10:00+05:30'),
    (8, 3, 'insightful', '2026-02-16 09:05+05:30'),
    (3, 5, 'love',       '2026-03-06 09:05+05:30'),
    (4, 5, 'like',       '2026-03-07 09:00+05:30'),
    (3, 6, 'insightful', '2026-03-13 09:00+05:30'),
    (7, 6, 'love',       '2026-03-14 09:00+05:30'),
    (3, 7, 'insightful', '2026-03-22 09:00+05:30'),
    (5, 7, 'like',       '2026-03-22 10:05+05:30'),
    (7, 7, 'love',       '2026-03-23 09:00+05:30'),
    (8, 7, 'like',       '2026-03-24 09:00+05:30'),
    (7, 8, 'like',       '2026-04-03 09:00+05:30');

INSERT INTO bookmarks (user_id, post_id, bookmarked_at) VALUES
    (7, 1, '2026-02-04 09:10+05:30'),
    (7, 6, '2026-03-14 09:05+05:30'),
    (7, 7, '2026-03-23 09:05+05:30'),
    (4, 2, '2026-02-12 09:05+05:30'),
    (5, 7, '2026-03-22 10:10+05:30'),
    (8, 3, '2026-02-16 09:10+05:30');

INSERT INTO follows (follower_id, followee_id, followed_at) VALUES
    (7, 3, '2026-02-04 09:15+05:30'),
    (7, 6, '2026-03-23 09:10+05:30'),
    (8, 3, '2026-02-06 09:05+05:30'),
    (8, 4, '2026-02-16 09:15+05:30'),
    (4, 3, '2026-02-03 09:10+05:30'),
    (3, 4, '2026-02-16 10:05+05:30'),  -- 3 and 4 follow each other: M:N, not symmetric by default
    (5, 6, '2026-03-22 10:15+05:30');

-- Repeated views of one post by one user are allowed (post 1 by user 7).
INSERT INTO reading_activity (user_id, post_id, occurred_at) VALUES
    (7, 1, '2026-02-04 08:55+05:30'),
    (7, 1, '2026-02-10 20:00+05:30'),
    (7, 1, '2026-03-01 21:00+05:30'),
    (7, 6, '2026-03-14 08:50+05:30'),
    (7, 7, '2026-03-23 08:45+05:30'),
    (8, 1, '2026-02-06 08:50+05:30'),
    (8, 3, '2026-02-16 08:50+05:30'),
    (4, 1, '2026-02-03 08:50+05:30'),
    (4, 2, '2026-02-12 08:50+05:30'),
    (5, 7, '2026-03-22 09:50+05:30'),
    (3, 5, '2026-03-06 08:50+05:30');

-- post_embeddings stays empty until component 9: real vectors must come
-- from the embedding model, and made-up ones would make search meaningless.

COMMIT;

\echo ''
\echo '=== Row counts after loading valid data ==='
SELECT 'users' AS table_name, count(*) FROM users
UNION ALL SELECT 'communities', count(*) FROM communities
UNION ALL SELECT 'tags', count(*) FROM tags
UNION ALL SELECT 'posts', count(*) FROM posts
UNION ALL SELECT 'post_tags', count(*) FROM post_tags
UNION ALL SELECT 'community_members', count(*) FROM community_members
UNION ALL SELECT 'comments', count(*) FROM comments
UNION ALL SELECT 'reactions', count(*) FROM reactions
UNION ALL SELECT 'bookmarks', count(*) FROM bookmarks
UNION ALL SELECT 'follows', count(*) FROM follows
UNION ALL SELECT 'post_embeddings', count(*) FROM post_embeddings
UNION ALL SELECT 'reading_activity', count(*) FROM reading_activity;


-- =====================================================================
-- Part 2 — deliberate invalid statements. Every one MUST print ERROR.
-- Keep going after each failure instead of stopping the script.
-- =====================================================================
\set ON_ERROR_STOP off

\echo ''
\echo '=== Invalid statements: each one below must print ERROR ==='

\echo '--- 1. UNIQUE: duplicate email'
INSERT INTO users (name, email, password_hash) VALUES ('Copy', 'asha@example.com', 'h');

\echo '--- 2. CHECK: email not lower case'
INSERT INTO users (name, email, password_hash) VALUES ('Copy', 'NEW@example.com', 'h');

\echo '--- 3. C3: invalid role'
INSERT INTO users (name, email, password_hash, role) VALUES ('Copy', 'boss@example.com', 'h', 'BOSS');

\echo '--- 4. NOT NULL: missing password_hash'
INSERT INTO users (name, email) VALUES ('Copy', 'nopass@example.com');

\echo '--- 5. UNIQUE: duplicate community name'
INSERT INTO communities (name, created_by) VALUES ('Databases', 1);

\echo '--- 6. FK: post in a community that does not exist'
INSERT INTO posts (author_id, community_id, title, content) VALUES (3, 999, 'T', 'C');

\echo '--- 7. C3: invalid post status'
INSERT INTO posts (author_id, community_id, title, content, status) VALUES (3, 1, 'T', 'C', 'hidden');

\echo '--- 8. C4: published without published_at'
INSERT INTO posts (author_id, community_id, title, content, status) VALUES (3, 1, 'T', 'C', 'published');

\echo '--- 9. C9: updated_at earlier than created_at'
UPDATE posts SET updated_at = created_at - interval '1 day' WHERE post_id = 1;

\echo '--- 10. PK: same tag twice on one post'
INSERT INTO post_tags (post_id, tag_id) VALUES (1, 1);

\echo '--- 11. PK: joining the same community twice'
INSERT INTO community_members (user_id, community_id) VALUES (3, 1);

\echo '--- 12. C2: reply on post 2 to a comment that belongs to post 1'
INSERT INTO comments (post_id, author_id, parent_comment_id, content) VALUES (2, 4, 1, 'Wrong post');

\echo '--- 13. C3: invalid comment status'
INSERT INTO comments (post_id, author_id, content, status) VALUES (1, 4, 'Text', 'deleted');

\echo '--- 14. NO ACTION: hard-deleting a comment that has replies'
DELETE FROM comments WHERE comment_id = 1;

\echo '--- 15. A4: second reaction by one user on one post'
INSERT INTO reactions (user_id, post_id, reaction_type) VALUES (4, 1, 'love');

\echo '--- 16. C3: invalid reaction type'
INSERT INTO reactions (user_id, post_id, reaction_type) VALUES (3, 8, 'angry');

\echo '--- 17. PK: bookmarking a post twice'
INSERT INTO bookmarks (user_id, post_id) VALUES (7, 1);

\echo '--- 18. C1: following yourself'
INSERT INTO follows (follower_id, followee_id) VALUES (3, 3);

\echo '--- 19. PK: following the same user twice'
INSERT INTO follows (follower_id, followee_id) VALUES (7, 3);

\echo '--- 20. C6: embedding with the wrong dimension'
INSERT INTO post_embeddings (post_id, model_name, embedding) VALUES (1, 'test-model', '[1,2,3]');

\echo '--- 21. C3: invalid activity type'
INSERT INTO reading_activity (user_id, post_id, activity_type) VALUES (7, 1, 'download');

\echo '--- 22. RESTRICT: deleting a user who has posts'
DELETE FROM users WHERE user_id = 3;

\echo '--- 23. RESTRICT: deleting a community that has posts'
DELETE FROM communities WHERE community_id = 1;

\echo ''
\echo '=== End of invalid statements: row counts should not have changed ==='
SELECT (SELECT count(*) FROM users) AS users,
       (SELECT count(*) FROM posts) AS posts,
       (SELECT count(*) FROM comments) AS comments,
       (SELECT count(*) FROM reactions) AS reactions;


-- =====================================================================
-- Part 3 — valid deletes that show CASCADE, undone with ROLLBACK.
-- These must NOT print ERROR.
-- =====================================================================
\echo ''
\echo '=== CASCADE demo: delete post 1 inside a transaction, then undo it ==='
BEGIN;
DELETE FROM posts WHERE post_id = 1;
-- Post 1 had 4 threaded comments, 5 reactions and 3 tags: all gone, and
-- the composite comment FK did not block it (NO ACTION checks at the end).
SELECT (SELECT count(*) FROM comments  WHERE post_id = 1) AS comments_left,
       (SELECT count(*) FROM reactions WHERE post_id = 1) AS reactions_left,
       (SELECT count(*) FROM post_tags WHERE post_id = 1) AS tags_left;
ROLLBACK;

\echo '=== After ROLLBACK post 1 is back ==='
SELECT post_id, title FROM posts WHERE post_id = 1;

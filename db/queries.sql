-- =====================================================================
-- queries.sql — demonstration queries over the seed data.
-- Run after seed.sql:  psql "$DATABASE_URL" -f db/queries.sql
--
-- Listings filter on status = 'published' to respect C7. Component 4
-- moves that filter into a view. Full-text and vector queries come in
-- components 5 and 9.
-- =====================================================================


-- ---------------------------------------------------------------------
-- JOINs
-- ---------------------------------------------------------------------

\echo '=== Q1. INNER JOIN: published posts with author and community, newest first ==='
-- INNER JOIN is safe here: author_id and community_id are NOT NULL FKs,
-- so every post has a match and no row can be lost.
SELECT p.post_id, p.title, u.name AS author, c.name AS community, p.published_at::date AS published
FROM posts p
JOIN users u       ON u.user_id = p.author_id
JOIN communities c ON c.community_id = p.community_id
WHERE p.status = 'published'
ORDER BY p.published_at DESC;

\echo '=== Q2. M:N JOIN with GROUP BY: published posts with their tags ==='
-- LEFT JOIN keeps a post that has no tags. string_agg folds the many
-- rows of the M:N join back into one row per post.
SELECT p.post_id, p.title,
       COALESCE(string_agg(t.tag_name, ', ' ORDER BY t.tag_name), '(none)') AS tags
FROM posts p
LEFT JOIN post_tags pt ON pt.post_id = p.post_id
LEFT JOIN tags t       ON t.tag_id = pt.tag_id
WHERE p.status = 'published'
GROUP BY p.post_id, p.title
ORDER BY p.post_id;

\echo '=== Q3. LEFT JOIN + IS NULL: tags used by no post ==='
-- Anti-join: rows with no match come back with NULLs on the right side.
SELECT t.tag_name
FROM tags t
LEFT JOIN post_tags pt ON pt.tag_id = t.tag_id
WHERE pt.post_id IS NULL;

\echo '=== Q4. M:N JOIN: published posts bookmarked by a user (user 7) ==='
SELECT p.title, u.name AS author, b.bookmarked_at::date AS saved_on
FROM bookmarks b
JOIN posts p ON p.post_id = b.post_id
JOIN users u ON u.user_id = p.author_id
WHERE b.user_id = 7 AND p.status = 'published'
ORDER BY b.bookmarked_at DESC;

\echo '=== Q5. Members of a community (Databases) ==='
SELECT u.name, cm.joined_at::date AS joined
FROM community_members cm
JOIN users u       ON u.user_id = cm.user_id
JOIN communities c ON c.community_id = cm.community_id
WHERE c.name = 'Databases'
ORDER BY cm.joined_at;

\echo '=== Q6. Self-join: replies with the comment they answer (post 1) ==='
-- Same table twice under two aliases. Inner join leaves out top-level
-- comments, which have no parent.
SELECT reply.comment_id, ru.name AS replier, reply.content AS reply,
       parent.comment_id AS parent_id, parent.content AS parent
FROM comments reply
JOIN comments parent ON parent.comment_id = reply.parent_comment_id
JOIN users ru        ON ru.user_id = reply.author_id
WHERE reply.post_id = 1
ORDER BY reply.created_at;

\echo '=== Q7. Recursive CTE: a whole comment thread in reading order (post 7) ==='
-- A self-join only reaches one level; WITH RECURSIVE follows any depth.
-- path sorts each reply directly under its parent. Removed comments stay
-- in the thread but their text is hidden (soft delete).
WITH RECURSIVE thread AS (
    SELECT comment_id, author_id, status, content, 0 AS depth, ARRAY[comment_id] AS path
    FROM comments
    WHERE post_id = 7 AND parent_comment_id IS NULL
    UNION ALL
    SELECT c.comment_id, c.author_id, c.status, c.content, t.depth + 1, t.path || c.comment_id
    FROM comments c
    JOIN thread t ON c.parent_comment_id = t.comment_id
)
SELECT repeat('    ', t.depth) || u.name AS commenter,
       CASE WHEN t.status = 'removed' THEN '[removed by moderator]' ELSE t.content END AS content
FROM thread t
JOIN users u ON u.user_id = t.author_id
ORDER BY t.path;


-- ---------------------------------------------------------------------
-- GROUP BY, aggregates, ORDER BY
-- ---------------------------------------------------------------------

\echo '=== Q8. Most-reacted-to published posts, with a per-type breakdown ==='
-- Counts are computed, not stored (no like_count column, ER doc A10).
-- COUNT(r.post_id) ignores the NULLs from LEFT JOIN, so a post with no
-- reactions gets 0. COUNT(*) would wrongly give it 1.
SELECT p.title,
       COUNT(r.post_id)                                        AS total,
       COUNT(r.post_id) FILTER (WHERE r.reaction_type = 'like')       AS likes,
       COUNT(r.post_id) FILTER (WHERE r.reaction_type = 'love')       AS loves,
       COUNT(r.post_id) FILTER (WHERE r.reaction_type = 'insightful') AS insightful
FROM posts p
LEFT JOIN reactions r ON r.post_id = p.post_id
WHERE p.status = 'published'
GROUP BY p.post_id, p.title
ORDER BY total DESC, p.title
LIMIT 5;

\echo '=== Q9. Authors ranked by number of published posts ==='
SELECT u.name, COUNT(*) AS published_posts
FROM users u
JOIN posts p ON p.author_id = u.user_id
WHERE p.status = 'published'
GROUP BY u.user_id, u.name
ORDER BY published_posts DESC, u.name;

\echo '=== Q10. Every community with its published post count, including empty ones ==='
-- The status filter is in ON, not WHERE. In WHERE it would throw away the
-- NULL rows from LEFT JOIN and "Open Source" would vanish from the result.
SELECT c.name, COUNT(p.post_id) AS published_posts
FROM communities c
LEFT JOIN posts p ON p.community_id = c.community_id AND p.status = 'published'
GROUP BY c.community_id, c.name
ORDER BY published_posts DESC, c.name;


-- ---------------------------------------------------------------------
-- HAVING
-- ---------------------------------------------------------------------

\echo '=== Q11. HAVING: published posts with at least 3 reactions ==='
-- WHERE filters rows before grouping; HAVING filters groups after it.
-- An aggregate such as COUNT cannot appear in WHERE.
SELECT p.title, COUNT(*) AS reactions
FROM posts p
JOIN reactions r ON r.post_id = p.post_id
WHERE p.status = 'published'
GROUP BY p.post_id, p.title
HAVING COUNT(*) >= 3
ORDER BY reactions DESC, p.title;

\echo '=== Q12. HAVING: authors with at least 3 published posts ==='
SELECT u.name, COUNT(*) AS published_posts
FROM users u
JOIN posts p ON p.author_id = u.user_id
WHERE p.status = 'published'
GROUP BY u.user_id, u.name
HAVING COUNT(*) >= 3
ORDER BY published_posts DESC, u.name;


-- ---------------------------------------------------------------------
-- Subqueries
-- ---------------------------------------------------------------------

\echo '=== Q13. IN subquery: feed of published posts by authors user 7 follows ==='
SELECT p.title, u.name AS author, p.published_at::date AS published
FROM posts p
JOIN users u ON u.user_id = p.author_id
WHERE p.status = 'published'
  AND p.author_id IN (SELECT followee_id FROM follows WHERE follower_id = 7)
ORDER BY p.published_at DESC;

\echo '=== Q14. Correlated NOT EXISTS: users who have never written a post ==='
-- The inner query runs once per outer user, using u.user_id. NOT EXISTS
-- is safer than NOT IN, which returns nothing if the list contains a NULL.
SELECT u.name, u.role
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.author_id = u.user_id)
ORDER BY u.name;

\echo '=== Q15. Derived table: posts with more reactions than the average reacted-to post ==='
-- The inner subquery in FROM computes per-post counts; the scalar subquery
-- compares each one to the average. Posts with no reactions have no row in
-- reactions, so they are not part of that average.
SELECT p.title, rc.reactions
FROM (SELECT post_id, COUNT(*) AS reactions FROM reactions GROUP BY post_id) rc
JOIN posts p ON p.post_id = rc.post_id
WHERE p.status = 'published'
  AND rc.reactions > (SELECT AVG(n) FROM (SELECT COUNT(*) AS n FROM reactions GROUP BY post_id) counts)
ORDER BY rc.reactions DESC, p.title;


-- ---------------------------------------------------------------------
-- Filtering and history
-- ---------------------------------------------------------------------

\echo '=== Q16. Filter by tag and date: posts tagged postgresql published in February 2026 ==='
-- Half-open range [Feb 1, Mar 1) includes all of February 28 whatever the time.
SELECT p.title, p.published_at::date AS published
FROM posts p
JOIN post_tags pt ON pt.post_id = p.post_id
JOIN tags t       ON t.tag_id = pt.tag_id
WHERE p.status = 'published'
  AND t.tag_name = 'postgresql'
  AND p.published_at >= '2026-02-01 00:00+05:30'
  AND p.published_at <  '2026-03-01 00:00+05:30'
ORDER BY p.published_at;

\echo '=== Q17. A user''s reading history: views per post (user 7) ==='
-- Only reading_activity can answer "how many times": it stores one row per
-- view, which is why it is an entity rather than an M:N relationship.
SELECT p.title, COUNT(*) AS views, MAX(ra.occurred_at)::date AS last_viewed
FROM reading_activity ra
JOIN posts p ON p.post_id = ra.post_id
WHERE ra.user_id = 7
GROUP BY p.post_id, p.title
ORDER BY last_viewed DESC;

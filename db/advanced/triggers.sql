-- =====================================================================
-- triggers.sql — rules that need procedural code (component 4, step 1).
--
--   A. communities_creator_must_be_admin   enforces C5
--   B. posts_set_updated_at,
--      comments_set_updated_at             keep updated_at current
--
-- C9 (updated_at >= created_at) is NOT here: it compares two columns of
-- the same row, so a CHECK in schema.sql is enough. A trigger is needed
-- only when a rule must read OTHER rows or OTHER tables, as C5 does.
--
-- Run order: schema.sql -> seed.sql -> this file.
-- DROP TABLE also drops the table's triggers, so re-run this file every
-- time schema.sql is re-run.
--   psql "$DATABASE_URL" -f db/advanced/triggers.sql
-- =====================================================================

\set ON_ERROR_STOP on


-- ---------------------------------------------------------------------
-- A. C5: only an ADMIN may create a community.
--
-- Why a trigger: the rule depends on users.role, a column in ANOTHER
-- table. A CHECK cannot contain a subquery, and the foreign key on
-- created_by only proves the user exists, not what role they have.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_community_creator_is_admin()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    creator_role varchar(5);
BEGIN
    -- FOR SHARE locks the creator's users row until this transaction
    -- ends, so a concurrent transaction cannot demote them to USER
    -- between this check and our COMMIT.
    SELECT role INTO creator_role
    FROM users
    WHERE user_id = NEW.created_by
    FOR SHARE;

    -- No such user: let the foreign key report it. BEFORE triggers run
    -- before the FK check, and "user does not exist" is the real error.
    IF creator_role IS NULL THEN
        RETURN NEW;
    END IF;

    IF creator_role <> 'ADMIN' THEN
        -- 23514 check_violation: the same error code a CHECK constraint
        -- raises, so the API can treat both the same way.
        RAISE EXCEPTION 'C5 violated: user % has role %, only an ADMIN can create a community',
                        NEW.created_by, creator_role
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;   -- BEFORE trigger: returning NEW lets the write go ahead
END;
$$;

-- BEFORE: reject the row before it is written.
-- UPDATE OF created_by: also stops a community being handed to a USER
-- later; updates to name or description do not fire it.
-- FOR EACH ROW: the check is per community, using NEW.created_by.
-- Limitation (viva): demoting an admin afterwards does not touch their
-- existing communities; C5 is checked only when a community row is written.
CREATE OR REPLACE TRIGGER communities_creator_must_be_admin
    BEFORE INSERT OR UPDATE OF created_by ON communities
    FOR EACH ROW
    EXECUTE FUNCTION check_community_creator_is_admin();


-- ---------------------------------------------------------------------
-- B. updated_at maintenance for posts and comments.
--
-- One function, attached to two tables: a trigger function does not name
-- a table; NEW is whichever row is being written.
--
-- It fills in now() only when the UPDATE did not set updated_at itself.
-- If it always overwrote the value, an explicitly wrong updated_at
-- (earlier than created_at) would be silently replaced instead of being
-- rejected by the C9 CHECK, so seed.sql test 9 would stop failing.
-- Trade-off: a client may still set its own valid timestamp.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
        -- now() = start time of the transaction, so every row changed in
        -- one transaction gets the same timestamp.
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

-- BEFORE UPDATE: changing NEW only has an effect before the row is
-- written. Inserts already get updated_at from DEFAULT now().
CREATE OR REPLACE TRIGGER posts_set_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE TRIGGER comments_set_updated_at
    BEFORE UPDATE ON comments
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();


\echo ''
\echo '=== Triggers installed ==='
SELECT event_object_table AS table_name, trigger_name,
       action_timing AS timing, string_agg(event_manipulation, ', ') AS events
FROM information_schema.triggers
WHERE trigger_schema = 'public'
GROUP BY event_object_table, trigger_name, action_timing
ORDER BY table_name, trigger_name;


-- =====================================================================
-- Tests, part 1 — valid statements. Must NOT print ERROR.
-- Run inside a transaction and rolled back, so seed data is unchanged.
-- =====================================================================
\echo ''
\echo '=== Valid: admin creates a community, edits bump updated_at (rolled back) ==='
BEGIN;

\echo '--- 1. C5: user 1 (ADMIN) creates a community -> 1 row'
INSERT INTO communities (name, description, created_by)
VALUES ('Trigger Test', 'Created by an admin.', 1)
RETURNING community_id, name, created_by;

\echo '--- 2. updated_at: edit post 1 without setting updated_at -> it becomes now()'
SELECT post_id, updated_at AS before_update FROM posts WHERE post_id = 1;
UPDATE posts SET title = title || ' (edited)' WHERE post_id = 1
RETURNING post_id, updated_at AS after_update, updated_at = now() AS set_by_trigger;

\echo '--- 3. Same trigger on comments'
UPDATE comments SET content = content || ' (edited)' WHERE comment_id = 1
RETURNING comment_id, updated_at = now() AS set_by_trigger;

ROLLBACK;
-- Note: the rolled-back INSERT still used up a community_id. Sequences are
-- never rolled back, so the next community will skip that number.


-- =====================================================================
-- Tests, part 2 — invalid statements. Every one MUST print ERROR.
-- =====================================================================
\set ON_ERROR_STOP off

\echo ''
\echo '=== Invalid: each one below must print ERROR ==='

\echo '--- 4. C5: user 3 (USER) creates a community'
INSERT INTO communities (name, created_by) VALUES ('Not Allowed', 3);

\echo '--- 5. C5 on UPDATE: hand community 1 over to user 3 (USER)'
UPDATE communities SET created_by = 3 WHERE community_id = 1;

\echo '--- 6. FK, not C5: creator does not exist'
INSERT INTO communities (name, created_by) VALUES ('Ghost', 999);

\echo '--- 7. C9 still wins: explicit updated_at before created_at'
UPDATE posts SET updated_at = created_at - interval '1 day' WHERE post_id = 1;

\echo ''
\echo '=== After the invalid statements nothing changed ==='
SELECT (SELECT count(*) FROM communities)                        AS communities,
       (SELECT created_by FROM communities WHERE community_id = 1) AS community_1_creator,
       (SELECT title FROM posts WHERE post_id = 1)               AS post_1_title;


-- =============================================================
-- db/alter_drop_demo.sql
-- Demonstration of CREATE, ALTER, and DROP operations for the DBMS Level 3 assignment.
--
-- This script is **re-runnable**: it can be executed multiple times against the
-- `scratch` database without error and without leaving any permanent changes.
-- It uses three parts:
--   A) A temporary demo table with a series of ALTER statements.
--   B) Safe ALTER on a real table inside a transaction that is rolled back.
--   C) An expected failure when trying to DROP a referenced table (FK dependency).
-- ------------------------------------------------------------

\set ON_ERROR_STOP on

-- =============================================================
-- Part A: Demo table `demo_post_notes`
-- =============================================================
-- Drop both names: if an earlier run stopped after the RENAME below,
-- the table is left behind as demo_post_notes_tmp.
DROP TABLE IF EXISTS demo_post_notes;
DROP TABLE IF EXISTS demo_post_notes_tmp;
CREATE TABLE demo_post_notes (
    note_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id      BIGINT NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    note_text    TEXT NOT NULL,
    is_important BOOLEAN NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- note_text may be at most 500 characters
    CONSTRAINT demo_note_chk CHECK (char_length(note_text) <= 500)
);

-- Add a column
ALTER TABLE demo_post_notes ADD COLUMN reviewer VARCHAR(100);
SELECT 'Added column reviewer' AS notice;

-- Modify column type (increase length of note_text)
ALTER TABLE demo_post_notes ALTER COLUMN note_text TYPE VARCHAR(500);
SELECT 'Changed note_text to VARCHAR(500)' AS notice;

-- Drop NOT NULL constraint on is_important (make it optional)
ALTER TABLE demo_post_notes ALTER COLUMN is_important DROP NOT NULL;
SELECT 'Dropped NOT NULL from is_important' AS notice;

-- Set a default value on reviewer
ALTER TABLE demo_post_notes ALTER COLUMN reviewer SET DEFAULT 'unknown';
SELECT 'Set default on reviewer' AS notice;

-- Drop the default
ALTER TABLE demo_post_notes ALTER COLUMN reviewer DROP DEFAULT;
SELECT 'Dropped default on reviewer' AS notice;

-- ALTER checks the rows that already exist. Insert one row with no
-- reviewer, so SET NOT NULL must fail (23502 not_null_violation).
-- Post 1 comes from seed.sql.
INSERT INTO demo_post_notes (post_id, note_text, is_important)
VALUES (1, 'Check the examples in this post', true);

-- The DO block catches the expected error so the script can continue
-- (ON_ERROR_STOP would otherwise end it here).
DO $$
BEGIN
    ALTER TABLE demo_post_notes ALTER COLUMN reviewer SET NOT NULL;
    RAISE EXCEPTION 'SET NOT NULL should have failed';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- Fix the existing data first, then the same ALTER succeeds.
UPDATE demo_post_notes SET reviewer = 'asha' WHERE reviewer IS NULL;
ALTER TABLE demo_post_notes ALTER COLUMN reviewer SET NOT NULL;
SELECT 'Set NOT NULL on reviewer (after filling in the NULLs)' AS notice;

-- Drop NOT NULL on reviewer
ALTER TABLE demo_post_notes ALTER COLUMN reviewer DROP NOT NULL;
SELECT 'Dropped NOT NULL on reviewer' AS notice;

-- Add a UNIQUE constraint on (post_id, reviewer)
ALTER TABLE demo_post_notes ADD CONSTRAINT demo_unique_post_reviewer UNIQUE (post_id, reviewer);
SELECT 'Added UNIQUE constraint on (post_id, reviewer)' AS notice;

-- Drop the UNIQUE constraint (showing DROP CONSTRAINT)
ALTER TABLE demo_post_notes DROP CONSTRAINT demo_unique_post_reviewer;
SELECT 'Dropped UNIQUE constraint demo_unique_post_reviewer' AS notice;

-- Add an additional CHECK constraint then drop it
ALTER TABLE demo_post_notes ADD CONSTRAINT demo_chk_review_len CHECK (char_length(reviewer) <= 20);
SELECT 'Added CHECK constraint demo_chk_review_len' AS notice;

ALTER TABLE demo_post_notes DROP CONSTRAINT demo_chk_review_len;
SELECT 'Dropped CHECK constraint demo_chk_review_len' AS notice;

-- Rename column is_important -> flagged
ALTER TABLE demo_post_notes RENAME COLUMN is_important TO flagged;
SELECT 'Renamed column is_important to flagged' AS notice;

-- Rename the table itself
ALTER TABLE demo_post_notes RENAME TO demo_post_notes_tmp;
SELECT 'Renamed table to demo_post_notes_tmp' AS notice;

-- Create an index on the foreign key column
CREATE INDEX idx_demo_tmp_post_id ON demo_post_notes_tmp(post_id);
SELECT 'Created index idx_demo_tmp_post_id' AS notice;

-- Drop the index
DROP INDEX IF EXISTS idx_demo_tmp_post_id;
SELECT 'Dropped index idx_demo_tmp_post_id' AS notice;

-- Clean up: drop the temporary table
DROP TABLE IF EXISTS demo_post_notes_tmp;
SELECT 'Dropped demo_post_notes_tmp' AS notice;

-- =============================================================
-- Part B: Safe ALTER on a real table (users) inside a transaction.
-- =============================================================
-- In PostgreSQL, DDL is transactional: ROLLBACK undoes an ALTER TABLE
-- just like it undoes an INSERT. (In MySQL/Oracle, DDL commits implicitly.)
-- ALTER TABLE takes an ACCESS EXCLUSIVE lock on users until ROLLBACK,
-- so keep the transaction short.
BEGIN;
ALTER TABLE users ADD COLUMN tmp_demo VARCHAR(20);
SELECT 'Added temporary column tmp_demo to users' AS notice;
-- Inside the transaction the column exists (expect 1).
SELECT count(*) AS tmp_demo_columns_before_rollback FROM information_schema.columns
WHERE table_name = 'users' AND column_name = 'tmp_demo';
ROLLBACK;
-- After ROLLBACK the column is gone without any DROP (expect 0).
SELECT count(*) AS tmp_demo_columns_after_rollback FROM information_schema.columns
WHERE table_name = 'users' AND column_name = 'tmp_demo';

-- =============================================================
-- Part C: Demonstrate FK-dependency error when dropping a referenced table.
-- =============================================================
-- Other tables (post_tags, comments, reactions, ...) and the views have
-- foreign keys / dependencies on posts, so a plain DROP (RESTRICT is the
-- default) is refused with 2BP01 dependent_objects_still_exist.
-- DROP ... CASCADE would remove those FKs and views too, which is why we
-- never use it on real tables.
-- The BEGIN ... ROLLBACK is a safety net: even if the DROP somehow
-- succeeded, nothing would be lost.
BEGIN;
DO $$
BEGIN
    DROP TABLE posts;
    RAISE EXCEPTION 'DROP TABLE posts should have failed';
EXCEPTION WHEN dependent_objects_still_exist THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
ROLLBACK;

-- End of demo script

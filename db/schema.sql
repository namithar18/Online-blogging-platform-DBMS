-- =====================================================================
-- schema.sql — Intelligent Community Blogging & Content Discovery Platform
-- PostgreSQL 16 + pgvector
--
-- Source of truth: docs/ER_explanation_and_viva.md §6.1 (mapping) and
-- §6.2 (constraints C1–C9). Tables are created in dependency order:
-- a table is created only after every table its foreign keys point to.
--
-- Enforced here (declaratively): C1, C2, C3, C4, C6, C9.
-- Enforced elsewhere: C5 (trigger, advanced/triggers.sql),
-- C7 (view, advanced/views.sql), C8 (hashing in the API).
--
-- Re-runnable: psql "$DATABASE_URL" -f db/schema.sql
-- =====================================================================

-- pgvector provides the vector(d) type used by post_embeddings.
CREATE EXTENSION IF NOT EXISTS vector;

-- Drop in REVERSE dependency order: a table cannot be dropped while
-- another table still has a foreign key pointing at it.
DROP TABLE IF EXISTS reading_activity;
DROP TABLE IF EXISTS post_embeddings;
DROP TABLE IF EXISTS follows;
DROP TABLE IF EXISTS bookmarks;
DROP TABLE IF EXISTS reactions;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS community_members;
DROP TABLE IF EXISTS post_tags;
DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS communities;
DROP TABLE IF EXISTS users;


-- ---------------------------------------------------------------------
-- 1. users — strong entity USER.
-- "user" is a reserved word in PostgreSQL, hence "users".
-- ---------------------------------------------------------------------
CREATE TABLE users (
    -- Surrogate key: stays stable even if the email changes.
    -- GENERATED ALWAYS (SQL standard) rejects manually supplied ids.
    user_id       bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          varchar(100) NOT NULL
                  CHECK (length(trim(name)) > 0),
    -- Candidate key. Stored in lower case so 'A@x.com' and 'a@x.com'
    -- cannot become two accounts (alternative: citext type).
    email         varchar(255) NOT NULL UNIQUE
                  CHECK (email = lower(email)),
    -- C8: only a bcrypt/argon2 hash is stored (60–~97 chars); the
    -- hashing itself is done in the API, never in SQL.
    password_hash varchar(255) NOT NULL,
    bio           text,                                   -- optional
    -- C3: role domain. Role is an attribute, not an ADMIN subclass,
    -- because admins have no extra attributes (ER doc §6 point 5).
    role          varchar(5)   NOT NULL DEFAULT 'USER'
                  CHECK (role IN ('USER', 'ADMIN')),
    created_at    timestamptz  NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 2. communities — strong entity COMMUNITY; 1:N CREATES folded in
-- as created_by (FK on the N side).
-- ---------------------------------------------------------------------
CREATE TABLE communities (
    community_id  bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          varchar(100) NOT NULL UNIQUE           -- candidate key
                  CHECK (length(trim(name)) > 0),
    description   text,
    -- NOT NULL: total participation of COMMUNITY in CREATES.
    -- RESTRICT: deleting the admin who created a community must fail
    -- rather than silently delete or orphan the community.
    -- (C5 "creator must be ADMIN" needs a trigger — component 4.)
    created_by    bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE RESTRICT,
    created_at    timestamptz  NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 3. tags — strong entity TAG. No dependencies.
-- ---------------------------------------------------------------------
CREATE TABLE tags (
    tag_id        bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Lower case only, so 'PostgreSQL' and 'postgresql' are one tag.
    tag_name      varchar(50)  NOT NULL UNIQUE
                  CHECK (length(trim(tag_name)) > 0
                         AND tag_name = lower(tag_name))
);


-- ---------------------------------------------------------------------
-- 4. posts — strong entity POST; 1:N AUTHORS and BELONGS_TO folded in.
-- ---------------------------------------------------------------------
CREATE TABLE posts (
    post_id       bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- NOT NULL: total participation (every post has exactly one author
    -- and one community). RESTRICT: avoid accidental loss of content —
    -- a user or community that still has posts cannot be deleted.
    author_id     bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE RESTRICT,
    community_id  bigint       NOT NULL
                  REFERENCES communities (community_id) ON DELETE RESTRICT,
    title         varchar(200) NOT NULL
                  CHECK (length(trim(title)) > 0),
    content       text         NOT NULL
                  CHECK (length(trim(content)) > 0),
    -- C3: 'removed' = admin moderation (soft delete, FR-12).
    status        varchar(11)  NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'published', 'unpublished', 'removed')),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),
    published_at  timestamptz,                -- NULL until first published
    -- Derived attribute (dashed ellipse in the ER). A generated column is
    -- recomputed by PostgreSQL on every write, so it can never become
    -- inconsistent with title/content. GIN index comes in component 5.
    search_vector tsvector
                  GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || content)) STORED,

    -- C4: published => published_at IS NOT NULL.
    -- "A implies B" is written as "NOT A OR B".
    CONSTRAINT posts_published_has_date
        CHECK (status <> 'published' OR published_at IS NOT NULL),
    -- C9: a row cannot be updated before it was created. Both columns are
    -- in the same row, so a CHECK is enough (no trigger needed).
    CONSTRAINT posts_updated_after_created
        CHECK (updated_at >= created_at),
    CONSTRAINT posts_published_after_created
        CHECK (published_at IS NULL OR published_at >= created_at)
);

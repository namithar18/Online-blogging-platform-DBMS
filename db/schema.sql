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


-- ---------------------------------------------------------------------
-- 5. post_tags — M:N TAGGED_WITH between posts and tags.
-- ---------------------------------------------------------------------
CREATE TABLE post_tags (
    -- CASCADE: a tag link means nothing once its post or tag is gone.
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    tag_id        bigint       NOT NULL
                  REFERENCES tags (tag_id) ON DELETE CASCADE,
    -- Composite PK: the same tag cannot be put on a post twice.
    PRIMARY KEY (post_id, tag_id)
);


-- ---------------------------------------------------------------------
-- 6. community_members — M:N MEMBER_OF with attribute joined_at.
-- joined_at depends on the whole (user, community) pair (2NF).
-- ---------------------------------------------------------------------
CREATE TABLE community_members (
    user_id       bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    community_id  bigint       NOT NULL
                  REFERENCES communities (community_id) ON DELETE CASCADE,
    joined_at     timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, community_id)
);


-- ---------------------------------------------------------------------
-- 7. comments — strong entity COMMENT; 1:N WRITES and HAS_COMMENT,
-- recursive 1:N REPLIES_TO (parent_comment_id).
-- ---------------------------------------------------------------------
CREATE TABLE comments (
    comment_id    bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- CASCADE: comments have no meaning without their post.
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    -- RESTRICT: same "do not lose content" rule as posts.author_id.
    author_id     bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE RESTRICT,
    parent_comment_id bigint,                 -- NULL = top-level comment
    content       text         NOT NULL
                  CHECK (length(trim(content)) > 0),
    -- C3: soft delete. Moderation sets 'removed' so replies keep their
    -- parent and the thread stays intact (ER doc D9).
    status        varchar(7)   NOT NULL DEFAULT 'visible'
                  CHECK (status IN ('visible', 'removed')),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),

    -- Required by the composite FK below: a foreign key may only point
    -- at a PRIMARY KEY or UNIQUE set of columns.
    CONSTRAINT comments_id_post_unique
        UNIQUE (comment_id, post_id),
    -- C2: a reply must be on the same post as its parent, because both
    -- rows share this one post_id column.
    -- Default MATCH SIMPLE skips the check when parent_comment_id is NULL,
    -- which is what lets top-level comments in. MATCH FULL would reject them.
    -- Default NO ACTION is checked at the END of the statement: deleting a
    -- post can still cascade to all its comments, but directly deleting a
    -- comment that has replies fails (use soft delete instead). CASCADE here
    -- would destroy other users' replies; RESTRICT is checked immediately.
    CONSTRAINT comments_reply_same_post
        FOREIGN KEY (parent_comment_id, post_id)
        REFERENCES comments (comment_id, post_id),
    CONSTRAINT comments_not_own_parent
        CHECK (parent_comment_id <> comment_id),
    -- C9
    CONSTRAINT comments_updated_after_created
        CHECK (updated_at >= created_at)
);


-- ---------------------------------------------------------------------
-- 8. reactions — M:N REACTS_TO with attributes.
-- ---------------------------------------------------------------------
CREATE TABLE reactions (
    user_id       bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    -- C3: reaction domain.
    reaction_type varchar(10)  NOT NULL DEFAULT 'like'
                  CHECK (reaction_type IN ('like', 'love', 'insightful')),
    reacted_at    timestamptz  NOT NULL DEFAULT now(),
    -- A4: one reaction per user per post; changing it is an UPDATE.
    PRIMARY KEY (user_id, post_id)
);


-- ---------------------------------------------------------------------
-- 9. bookmarks — M:N BOOKMARKS with attribute bookmarked_at.
-- ---------------------------------------------------------------------
CREATE TABLE bookmarks (
    user_id       bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    bookmarked_at timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);


-- ---------------------------------------------------------------------
-- 10. follows — recursive M:N FOLLOWS. Two FKs to the same table,
-- named by role (follower / followee).
-- ---------------------------------------------------------------------
CREATE TABLE follows (
    follower_id   bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    followee_id   bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    followed_at   timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    -- C1: nobody can follow themselves.
    CONSTRAINT follows_not_self
        CHECK (follower_id <> followee_id)
);


-- ---------------------------------------------------------------------
-- 11. post_embeddings — weak entity POST_EMBEDDING.
-- PK = owner's key + partial key (model_name).
-- ---------------------------------------------------------------------
CREATE TABLE post_embeddings (
    -- CASCADE: existence dependency — no post, no embedding.
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    model_name    varchar(100) NOT NULL,
    -- C6: vector(384) rejects any other length. 384 is the output size of
    -- the chosen model, all-MiniLM-L6-v2 (free, runs locally).
    embedding     vector(384)  NOT NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    -- C6: at most one embedding per (post, model).
    PRIMARY KEY (post_id, model_name)
);


-- ---------------------------------------------------------------------
-- 12. reading_activity — entity, not M:N: repeated views of one post by
-- one user are separate facts, so each needs its own key (ER doc §6 pt 2).
-- ---------------------------------------------------------------------
CREATE TABLE reading_activity (
    activity_id   bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- CASCADE on user: privacy — a deleted user's history goes with them.
    user_id       bigint       NOT NULL
                  REFERENCES users (user_id) ON DELETE CASCADE,
    post_id       bigint       NOT NULL
                  REFERENCES posts (post_id) ON DELETE CASCADE,
    -- C3: activity domain. Only views are recorded for now.
    activity_type varchar(10)  NOT NULL DEFAULT 'view'
                  CHECK (activity_type IN ('view')),
    occurred_at   timestamptz  NOT NULL DEFAULT now()
);

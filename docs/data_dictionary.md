# Data Dictionary

This document records the exact schema of the **Intelligent Community Blogging and Content Discovery Platform** as defined in `db/schema.sql`. It lists every table, column, data type, nullability, defaults, keys, constraints, as well as the real triggers and indexes defined in the `db/advanced` folder. No assumptions are made; all information is taken directly from the repository.

---

## Table: `users`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `user_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `name` | `varchar(100)` | No | – | `CHECK (length(trim(name)) > 0)` |
| `email` | `varchar(255)` | No | – | `UNIQUE`, `CHECK (email = lower(email))` |
| `password_hash` | `varchar(255)` | No | – | – |
| `bio` | `text` | Yes | – | – |
| `role` | `varchar(5)` | No | `'USER'` | `CHECK (role IN ('USER','ADMIN'))` |
| `created_at` | `timestamptz` | No | `now()` | – |

*Triggers*: none
*Indexes*: primary key (`users_pkey`) created automatically

---

## Table: `communities`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `community_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `name` | `varchar(100)` | No | – | `UNIQUE`, `CHECK (length(trim(name)) > 0)` |
| `description` | `text` | Yes | – | – |
| `created_by` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE RESTRICT` |
| `created_at` | `timestamptz` | No | `now()` | – |

*Triggers*:
- `communities_creator_must_be_admin` (BEFORE INSERT OR UPDATE OF created_by) → function `check_community_creator_is_admin()`

*Indexes*:
- `communities_created_by_idx` on `created_by`

---

## Table: `tags`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `tag_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `tag_name` | `varchar(50)` | No | – | `UNIQUE`, `CHECK (length(trim(tag_name)) > 0 AND tag_name = lower(tag_name))` |

*Triggers*: none
*Indexes*: primary key (`tags_pkey`) automatically created

---

## Table: `posts`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `post_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `author_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE RESTRICT` |
| `community_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES communities.community_id ON DELETE RESTRICT` |
| `title` | `varchar(200)` | No | – | `CHECK (length(trim(title)) > 0)` |
| `content` | `text` | No | – | `CHECK (length(trim(content)) > 0)` |
| `status` | `varchar(11)` | No | `'draft'` | `CHECK (status IN ('draft','published','unpublished','removed'))` |
| `created_at` | `timestamptz` | No | `now()` | – |
| `updated_at` | `timestamptz` | No | `now()` | – |
| `published_at` | `timestamptz` | Yes | – | – |
| `search_vector` | `tsvector` | Yes | – | **Generated**: `to_tsvector('english', title || ' ' || content)` |
| **Constraints** |
| `posts_published_has_date` | `CHECK (status <> 'published' OR published_at IS NOT NULL)` |
| `posts_updated_after_created` | `CHECK (updated_at >= created_at)` |
| `posts_published_after_created` | `CHECK (published_at IS NULL OR published_at >= created_at)` |

*Triggers*:
- `posts_set_updated_at` (BEFORE UPDATE) → function `set_updated_at()`

*Indexes*:
- `posts_author_id_idx` on `author_id`
- `posts_community_id_idx` on `community_id`
- `posts_published_at_idx` on `published_at DESC` **WHERE** `status = 'published'`
- `posts_search_vector_idx` (GIN) on `search_vector`

---

## Table: `post_tags`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `tag_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES tags.tag_id ON DELETE CASCADE` |
| **Primary Key** | `(post_id, tag_id)` |

*Triggers*: none
*Indexes*:
- `post_tags_tag_id_idx` on `tag_id`

---

## Table: `community_members`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `user_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `community_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES communities.community_id ON DELETE CASCADE` |
| `joined_at` | `timestamptz` | No | `now()` | – |
| **Primary Key** | `(user_id, community_id)` |

*Triggers*: none
*Indexes*:
- `community_members_community_id_idx` on `community_id`

---

## Table: `comments`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `comment_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `author_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE RESTRICT` |
| `parent_comment_id` | `bigint` | Yes | – | – |
| `content` | `text` | No | – | `CHECK (length(trim(content)) > 0)` |
| `status` | `varchar(7)` | No | `'visible'` | `CHECK (status IN ('visible','removed'))` |
| `created_at` | `timestamptz` | No | `now()` | – |
| `updated_at` | `timestamptz` | No | `now()` | – |
| **Unique** | `(comment_id, post_id)` |
| **Foreign Key (composite)** | `FOREIGN KEY (parent_comment_id, post_id) REFERENCES comments(comment_id, post_id)` |
| **Check** | `CHECK (parent_comment_id <> comment_id)` |

*Triggers*:
- `comments_set_updated_at` (BEFORE UPDATE) → function `set_updated_at()`

*Indexes*:
- `comments_post_id_idx` on `post_id`
- `comments_author_id_idx` on `author_id`
- `comments_parent_comment_id_idx` on `parent_comment_id`

---

## Table: `reactions`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `user_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `reaction_type` | `varchar(10)` | No | `'like'` | `CHECK (reaction_type IN ('like','love','insightful'))` |
| `reacted_at` | `timestamptz` | No | `now()` | – |
| **Primary Key** | `(user_id, post_id)` |

*Triggers*: none
*Indexes*:
- `reactions_post_id_idx` on `post_id`

---

## Table: `bookmarks`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `user_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `bookmarked_at` | `timestamptz` | No | `now()` | – |
| **Primary Key** | `(user_id, post_id)` |

*Triggers*: none
*Indexes*:
- `bookmarks_post_id_idx` on `post_id`

---

## Table: `follows`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `follower_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `followee_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `followed_at` | `timestamptz` | No | `now()` | – |
| **Primary Key** | `(follower_id, followee_id)` |
| **Check** | `CHECK (follower_id <> followee_id)` |

*Triggers*: none
*Indexes*:
- `follows_followee_id_idx` on `followee_id`

---

## Table: `post_embeddings`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `model_name` | `varchar(100)` | No | – | – |
| `embedding` | `vector(384)` | No | – | – |
| `created_at` | `timestamptz` | No | `now()` | – |
| **Primary Key** | `(post_id, model_name)` |

*Triggers*: none
*Indexes*: none (PK already indexed)
*Column*: post_embeddings.embedding is vector(384), NOT NULL.
*Key*: (post_id, model_name), so one post can have one embedding per model.
*Index type*: HNSW, with m = 16 and ef_construction = 64.
*Distance metric*: cosine distance, from the operator class vector_cosine_ops (queries use the <=> operator).
*Delete rule*: FK to posts is ON DELETE CASCADE.
---

## Table: `reading_activity`
| Column | Type | Nullable | Default | Key / Constraints |
|---|---|---|---|---|
| `activity_id` | `bigint` | No | `GENERATED ALWAYS AS IDENTITY` | Primary Key |
| `user_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES users.user_id ON DELETE CASCADE` |
| `post_id` | `bigint` | No | – | `FOREIGN KEY REFERENCES posts.post_id ON DELETE CASCADE` |
| `activity_type` | `varchar(10)` | No | `'view'` | `CHECK (activity_type IN ('view'))` |
| `occurred_at` | `timestamptz` | No | `now()` | – |

*Triggers*: none
*Indexes*:
- `reading_activity_user_time_idx` on `(user_id, occurred_at DESC)`
- `reading_activity_post_id_idx` on `post_id`

---

# Views (defined in `db/advanced/views.sql`)

## `published_posts`
*Purpose*: expose only posts that are `status = 'published'` and not `removed`.
```sql
SELECT * FROM posts WHERE status = 'published' AND status <> 'removed' WITH CHECK OPTION;
```

## `popular_posts`
*Purpose*: similar to `published_posts` but ordered by a popularity metric (not shown here).

---

# Triggers (defined in `db/advanced/triggers.sql`)

| Trigger | Table | Timing / Event | Function | What it enforces |
|---|---|---|---|---|
| `comments_set_updated_at` | `comments` | BEFORE UPDATE, per row | `set_updated_at()` | Sets `updated_at = now()` automatically, unless the UPDATE already changed `updated_at` itself. `now()` is the transaction start time, so all rows changed in one transaction get the same timestamp. |
| `posts_set_updated_at` | `posts` | BEFORE UPDATE, per row | `set_updated_at()` | Same as above, for `posts`. |
| `communities_creator_must_be_admin` | `communities` | BEFORE INSERT OR UPDATE OF `created_by`, per row | `check_community_creator_is_admin()` | C5: only an ADMIN user can be the creator of a community. Raises `check_violation` (23514) otherwise. Uses `FOR SHARE` on the creator's `users` row so a concurrent transaction cannot demote them before COMMIT. If the user does not exist, it lets the foreign key report the error. |

---

# Indexes (defined in `db/advanced/indexes.sql` and `db/advanced/fulltext.sql`)

| Index | Table | Columns | Type | Predicate | Purpose |
|---|---|---|---|---|---|
| `bookmarks_post_id_idx` | `bookmarks` | `post_id` | B-tree | - | The PK is `(user_id, post_id)`, so it can't serve lookups by post (bookmark count per post). |
| `comments_author_id_idx` | `comments` | `author_id` | B-tree | - | Comments by a user, and FK checks on `author_id`. |
| `comments_id_post_unique` | `comments` | `comment_id, post_id` | UNIQUE B-tree | - | Required as the target of the composite FK `comments_reply_same_post`, which forces a reply to belong to the same post as its parent. |
| `comments_parent_comment_id_idx` | `comments` | `parent_comment_id` | B-tree | - | Fetching the replies of a comment (thread loading). |
| `comments_post_id_idx` | `comments` | `post_id` | B-tree | - | Fetching all comments of a post, and comment counts per post. |
| `communities_created_by_idx` | `communities` | `created_by` | B-tree | - | Communities by creator, and FK checks on `created_by`. |
| `community_members_community_id_idx` | `community_members` | `community_id` | B-tree | - | The PK is `(user_id, community_id)`, so this serves member lists and counts per community. |
| `follows_followee_id_idx` | `follows` | `followee_id` | B-tree | - | The PK is `(follower_id, followee_id)`, so this serves "who follows this author" and follower counts. |
| `post_tags_tag_id_idx` | `post_tags` | `tag_id` | B-tree | - | The PK is `(post_id, tag_id)`, so this serves "all posts with this tag". |
| `posts_author_id_idx` | `posts` | `author_id` | B-tree | - | Posts by author, and FK checks on `author_id`. |
| `posts_community_id_idx` | `posts` | `community_id` | B-tree | - | Posts in a community, and FK checks on `community_id`. |
| `posts_published_at_idx` | `posts` | `published_at DESC` | B-tree (partial) | `status = 'published'` | Newest-published feed: index scan with no sort, and the index stays small because drafts and removed posts are excluded. |
| `posts_search_vector_idx` | `posts` | `search_vector` | GIN | - | Full-text search: makes `search_vector @@ to_tsquery(...)` an index lookup instead of a scan of every post, and supports ranking with `ts_rank`. |
| `post_embeddings_embedding_hnsw_idx` | `post_embeddings` | `embedding` (`vector_cosine_ops`) | HNSW (`m = 16`, `ef_construction = 64`) | - | Approximate nearest-neighbour search for semantic similarity using cosine distance (`<=>`), without comparing against every stored vector. |
| `reactions_post_id_idx` | `reactions` | `post_id` | B-tree | - | The PK is `(user_id, post_id)`, so this serves reaction counts per post. |
| `reading_activity_post_id_idx` | `reading_activity` | `post_id` | B-tree | - | View counts per post. |
| `reading_activity_user_time_idx` | `reading_activity` | `user_id, occurred_at DESC` | B-tree | - | A user's most recent reading history. |

Indexes created automatically by PRIMARY KEY and UNIQUE constraints (`*_pkey`, `communities_name_key`, `tags_tag_name_key`, `users_email_key`) are not listed above.

*All information above is derived directly from the repository's SQL files; no column, constraint, trigger, or index has been invented.*
# Relational Schema Documentation

---

## Table definitions (standard notation)

**bookmarks**(_user_id_ -> users.user_id, _post_id_ -> posts.post_id, bookmarked_at)  
**comments**(**comment_id**, _post_id_ -> posts.post_id, _author_id_ -> users.user_id, _parent_comment_id_ -> comments.comment_id, content, status, created_at, updated_at)  
**communities**(**community_id**, name, description, _created_by_ -> users.user_id, created_at)  
**community_members**(_user_id_ -> users.user_id, _community_id_ -> communities.community_id, joined_at)  
**follows**(_follower_id_ -> users.user_id, _followee_id_ -> users.user_id, followed_at)  
**post_embeddings**(_post_id_ -> posts.post_id, **model_name**, embedding, created_at)  
**post_tags**(_post_id_ -> posts.post_id, _tag_id_ -> tags.tag_id)  
**posts**(**post_id**, _author_id_ -> users.user_id, _community_id_ -> communities.community_id, title, content, status, created_at, updated_at, published_at, search_vector)  
**reactions**(_user_id_ -> users.user_id, _post_id_ -> posts.post_id, reaction_type, reacted_at)  
**reading_activity**(**activity_id**, _user_id_ -> users.user_id, _post_id_ -> posts.post_id, activity_type, occurred_at)  
**tags**(**tag_id**, tag_name)  
**users**(**user_id**, name, email, password_hash, bio, role, created_at)

---

## Relationships table

| Entity A (PK) | Relationship | Entity B (FK) | Cardinality | Implemented by |
|---|---|---|---|---|
| `users` | creates | `communities.created_by` | 1 : N | FK `communities.created_by → users.user_id` |
| `users` | authors | `posts.author_id` | 1 : N | FK `posts.author_id → users.user_id` |
| `communities` | owns | `posts.community_id` | 1 : N | FK `posts.community_id → communities.community_id` |
| `posts` | tagged‑with | `post_tags` | 1 : N (via M:N) | Junction table `post_tags` |
| `tags` | tags‑post | `post_tags` | 1 : N (via M:N) | Junction table `post_tags` |
| `users` | member‑of | `community_members` | M : N | Junction table `community_members` |
| `communities` | has‑member | `community_members` | M : N | Junction table `community_members` |
| `posts` | has‑comment | `comments.post_id` | 1 : N | FK `comments.post_id → posts.post_id` |
| `users` | writes‑comment | `comments.author_id` | 1 : N | FK `comments.author_id → users.user_id` |
| `comments` | replies‑to | `comments.parent_comment_id` (self‑ref) | 1 : N (recursive) | Composite FK `(parent_comment_id, post_id) → comments(comment_id, post_id)` |
| `users` | reacts‑to | `reactions` | M : N (via PK) | PK `(user_id, post_id)` with FKs to both |
| `users` | bookmarks | `bookmarks` | M : N (via PK) | PK `(user_id, post_id)` with FKs to both |
| `users` | follows | `follows` (as follower) | M : N (self‑ref) | PK `(follower_id, followee_id)` with FKs to `users` |
| `users` | followed‑by | `follows` (as followee) | M : N (self‑ref) | Same as above |
| `posts` | has‑embedding | `post_embeddings` | 1 : N | FK `post_embeddings.post_id → posts.post_id` |
| `users` | activity‑log | `reading_activity.user_id` | 1 : N | FK `reading_activity.user_id → users.user_id` |
| `posts` | activity‑log | `reading_activity.post_id` | 1 : N | FK `reading_activity.post_id → posts.post_id` |

---

## ER‑to‑relational mapping notes
* **M:N relationships** (`posts↔tags`, `users↔communities`) are materialized as junction tables (`post_tags`, `community_members`) with composite primary keys.
* **Self‑referencing relationships** (`follows`, `comments.parent_comment_id`) use two foreign‑key columns that both point back to the same primary table.
* **Generated column** `posts.search_vector` is a stored `tsvector` derived from `title || ' ' || content`.
* **Vector column** `post_embeddings.embedding` is of type `vector(384)` (fixed dimension for the embedding model).
* **Triggers** (in `db/advanced/triggers.sql`) enforce business rules that cannot be expressed with plain CHECK constraints:
  * `communities_creator_must_be_admin` ensures only admin users can create a community (C5).
  * `set_updated_at` guarantees `updated_at` is never before `created_at` on posts (C9).

---

## Mermaid diagram (accurate to schema)
```mermaid
erDiagram
    USERS ||--o{ COMMUNITIES : creates
    USERS ||--o{ POSTS : authors
    COMMUNITIES ||--o{ POSTS : owns
    POSTS ||--o{ POST_TAGS : tagged
    TAGS ||--o{ POST_TAGS : tags
    USERS ||--o{ COMMUNITY_MEMBERS : member_of
    COMMUNITIES ||--o{ COMMUNITY_MEMBERS : has_member
    POSTS ||--o{ COMMENTS : has_comment
    USERS ||--o{ COMMENTS : writes_comment
    COMMENTS ||--o{ COMMENTS : replies_to
    USERS ||--o{ REACTIONS : reacts_to
    USERS ||--o{ BOOKMARKS : bookmarks
    USERS ||--o{ FOLLOWS : follows
    USERS ||--o{ POST_EMBEDDINGS : has_embedding
    USERS ||--o{ READING_ACTIVITY : activity_log
    POSTS ||--o{ READING_ACTIVITY : activity_log
```
---

*No other files were modified.*
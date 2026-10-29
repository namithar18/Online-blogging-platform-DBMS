# Intelligent Community Blogging and Content Discovery Platform

## 1. Project Title

**Intelligent Community Blogging and Content Discovery Platform**

## 2. Synopsis (List of Features)

A community-based blogging web application that lets users publish
articles, organize them into communities, interact with authors and
posts, and discover relevant content through keyword-based and semantic
search. PostgreSQL will manage structured relational data, while
PostgreSQL with the `pgvector` extension will store text embeddings and
support similarity search.

### Key Features

-   User registration, authentication, and role-based access for Users
    and Admins.
-   Create, edit, publish, unpublish, and manage blog posts.
-   Organize posts into communities/categories and apply multiple tags.
-   Comment on posts and reply to comments.
-   Like/react to and bookmark posts.
-   Follow authors and browse their published content.
-   Search, filter, sort, and browse by title, tag, community, author,
    or date.
-   PostgreSQL full-text search for keyword-based content retrieval.
-   Semantic search and similar-post recommendations using text
    embeddings and vector similarity.
-   Admin tools for managing users, communities, posts, and
    inappropriate content.
-   Reading/activity history to support content discovery.
-   PostgreSQL for relational data and `pgvector` for vector storage and
    semantic retrieval.
-   Advanced database features such as transactions, views,
    triggers/functions, indexing, and full-text/vector search.

## 3. Problem Statement

Blogging platforms can contain large amounts of content across many
topics and authors. Users may find it difficult to organize posts and
discover articles that match their interests. Keyword search can also
miss useful articles when they express similar ideas using different
words.

This project proposes a community-based blogging platform that supports
structured content organization, user interaction, keyword search, and
semantic content discovery. A relational database manages structured
information, while vector similarity search helps find posts with
similar meanings.

## 4. Motivation

The project combines familiar blogging features with meaningful database
functionality. It provides a practical setting to apply ER modelling,
relational schema design, normalization, constraints, joins,
aggregation, indexing, transactions, and advanced search. Semantic
search gives a clear reason to use vector storage.

## 5. Objectives

1.  Build a functional web application using Next.js.
2.  Implement authentication and User/Admin authorization.
3.  Allow users to publish, organize, discover, and interact with blog
    content.
4.  Design a normalized relational database with primary keys, foreign
    keys, constraints, and indexes.
5.  Implement SQL operations using joins, aggregation, subqueries,
    sorting, and filtering.
6.  Implement PostgreSQL full-text search.
7.  Use text embeddings and vector similarity search to retrieve
    semantically related posts.
8.  Demonstrate at least four advanced database concepts.
9.  Protect credentials and maintain data integrity.
10. Document the architecture, ER diagram, relational schema, queries,
    and test results.

## 6. Scope

### In Scope

-   User and admin accounts.
-   Blog creation, editing, publishing, and viewing.
-   Communities/categories and tags.
-   Comments and replies.
-   Reactions, bookmarks, and following authors.
-   Search, filtering, and sorting.
-   Full-text search and semantic recommendations.
-   Basic content moderation.
-   Reading/activity history.
-   PostgreSQL and pgvector integration.
-   Database design, advanced SQL concepts, testing, and documentation.

### Out of Scope for the Initial Version

Real-time chat, collaborative editing, automatic AI blog writing,
complex notifications, monetization, and large-scale personalized
recommendation systems. These may be considered later.

## 7. User Roles

### User

-   Register, log in, and manage their profile.
-   Create and manage their own posts.
-   Browse communities, tags, and posts.
-   Comment, reply, react, bookmark, and follow authors.
-   Search by keywords or semantic similarity.
-   View bookmarks and their activity history.
-   Report inappropriate content, if reporting is implemented.

### Admin

-   Manage user accounts and communities.
-   Moderate posts and reported content.
-   Remove content that violates platform rules.
-   Review basic platform activity and content statistics.

Authorization must be enforced in the backend/API, not only by hiding
interface elements.

## 8. Functional Requirements

  -----------------------------------------------------------------------
  ID                                  Requirement
  ----------------------------------- -----------------------------------
  FR-01                               Users can register, log in, and log
                                      out.

  FR-02                               The system supports User and Admin
                                      roles.

  FR-03                               Authenticated users can create and
                                      manage their own posts.

  FR-04                               Posts can be organized into
                                      communities and assigned multiple
                                      tags.

  FR-05                               Users can comment on posts and
                                      reply to comments.

  FR-06                               Users can react to and bookmark
                                      posts.

  FR-07                               Users can follow authors and browse
                                      their content.

  FR-08                               Users can search, filter, sort, and
                                      browse posts.

  FR-09                               The system supports full-text
                                      search.

  FR-10                               The system supports embeddings and
                                      semantic similarity search.

  FR-11                               The system recommends similar
                                      posts.

  FR-12                               Admins can manage users,
                                      communities, and inappropriate
                                      content.

  FR-13                               The system records relevant
                                      reading/activity events when
                                      enabled.

  FR-14                               The system validates inputs and
                                      enforces database integrity.
  -----------------------------------------------------------------------

## 9. Proposed Technology Stack

  -----------------------------------------------------------------------
  Layer                   Technology              Purpose
  ----------------------- ----------------------- -----------------------
  Frontend                Next.js                 Pages, forms, post
                                                  views, search, and
                                                  dashboards

  Backend/API             Next.js Route Handlers  Business logic,
                          / API routes            validation,
                                                  authorization, and
                                                  database access

  Relational database     PostgreSQL              Users, posts,
                                                  communities, tags,
                                                  comments, reactions,
                                                  bookmarks, follows, and
                                                  activity

  Vector search           PostgreSQL with         Embeddings and
                          `pgvector`              similarity search

  Embedding model         Suitable text-embedding Converts post/query
                          model                   text into vectors

  Version control         Git and GitHub          Collaboration and
                                                  source history

  Configuration           Environment variables   Protect database URLs,
                                                  secrets, and API keys
  -----------------------------------------------------------------------

**Database decision:** `pgvector` is a PostgreSQL extension, not a
separate database server. It supports vector similarity search within
PostgreSQL. The course requirements list PostgreSQL with pgvector as an
acceptable SQL + vector option; confirm with the instructor if they
expect a separately deployed vector database.

## 10. High-Level Architecture

``` text
User / Admin
     |
     v
Next.js Frontend
     |
     v
Next.js Route Handlers / API Layer
     |
     +--------------------------+
     |                          |
     v                          v
PostgreSQL relational data    pgvector
     |                          |
     |                    Vector similarity
     +-------------+------------+
                   |
                   v
       Search results / recommendations
                   |
                   v
             Next.js Frontend
```

The frontend calls the API layer. The API validates inputs, checks
authentication/authorization, and accesses the database. Semantic search
creates an embedding for a query or post and uses pgvector to retrieve
similar content. Secrets must be stored in environment variables.

## 11. Proposed ER Diagram Entities

The following is the proposed initial relational model. Final attributes
and relationships should be confirmed during implementation.

### USER

-   `user_id` (PK)
-   `name`
-   `email` (unique)
-   `password_hash`
-   `bio` (optional)
-   `role` (e.g., USER or ADMIN)
-   `created_at`

### COMMUNITY

-   `community_id` (PK)
-   `name` (unique)
-   `description`
-   `created_by` (FK → USER)
-   `created_at`

### POST

-   `post_id` (PK)
-   `user_id` (FK → USER)
-   `community_id` (FK → COMMUNITY)
-   `title`
-   `content`
-   `status` (e.g., draft, published, unpublished)
-   `created_at`
-   `updated_at`
-   `published_at` (optional)

Initial assumption: each post belongs to one community. If multiple
communities per post are required, use a `POST_COMMUNITY` junction table
instead.

### TAG

-   `tag_id` (PK)
-   `tag_name` (unique)

### POST_TAG

Junction table for the many-to-many relationship between posts and
tags: - `post_id` (PK component, FK → POST) - `tag_id` (PK component, FK
→ TAG)

Use `(post_id, tag_id)` as the composite primary key.

### COMMENT

-   `comment_id` (PK)
-   `user_id` (FK → USER)
-   `post_id` (FK → POST)
-   `parent_comment_id` (nullable self-referencing FK → COMMENT)
-   `content`
-   `created_at`
-   `updated_at` (optional)

A null parent ID means a top-level comment; otherwise, it identifies the
comment being replied to.

### REACTION

-   `reaction_id` (PK)
-   `user_id` (FK → USER)
-   `post_id` (FK → POST)
-   `reaction_type` (e.g., like)
-   `created_at`

If each user can have only one reaction per post, enforce
`UNIQUE(user_id, post_id)`.

### BOOKMARK

-   `user_id` (PK component, FK → USER)
-   `post_id` (PK component, FK → POST)
-   `created_at`

Use `(user_id, post_id)` as the composite primary key to prevent
duplicate bookmarks.

### FOLLOW

-   `follower_id` (PK component, FK → USER)
-   `following_id` (PK component, FK → USER)
-   `created_at`

Prevent users from following themselves.

### COMMUNITY_MEMBER

-   `user_id` (PK component, FK → USER)
-   `community_id` (PK component, FK → COMMUNITY)
-   `joined_at`

Use `(user_id, community_id)` as the composite primary key.

### POST_EMBEDDING (optional, for pgvector)

-   `embedding_id` (PK, if a separate identifier is useful)
-   `post_id` (FK → POST; unique if only one current embedding per post)
-   `embedding` (vector column with dimensions matching the chosen
    model)
-   `model_name`
-   `created_at`

Regenerate the embedding when the post content changes.

### READING_ACTIVITY (optional)

-   `activity_id` (PK)
-   `user_id` (FK → USER; nullable if anonymous activity is supported)
-   `post_id` (FK → POST)
-   `activity_type` (e.g., view)
-   `occurred_at`

Bookmarks remain separate because they are persistent saved items, not
simply reading events.

## 12. Main Relationships and Cardinalities

-   One user writes many posts; each post has one author.
-   One community contains many posts; each post belongs to one
    community in the initial design.
-   Users and communities have a many-to-many membership relationship
    through `COMMUNITY_MEMBER`.
-   Posts and tags have a many-to-many relationship through `POST_TAG`.
-   One user writes many comments; each comment has one author.
-   One post receives many comments; each comment belongs to one post.
-   Comments can have replies through `parent_comment_id`.
-   Users can react to many posts; posts can receive reactions from many
    users.
-   Users can bookmark many posts; posts can be bookmarked by many
    users.
-   Users can follow many other users and can have many followers.
-   Posts can have associated embeddings for semantic retrieval.
-   Reading activity links users and posts over time.

## 13. Database Integrity and Normalization

-   Use primary keys and foreign keys to identify records and preserve
    relationships.
-   Add unique constraints for email, tag names, community names, and
    relationship pairs where appropriate.
-   Use `NOT NULL` for required attributes and `CHECK` constraints for
    roles, statuses, and reaction types.
-   Choose deletion rules carefully to avoid accidental loss of valuable
    content.
-   Index foreign keys and frequently filtered or sorted columns where
    useful.
-   Validate input in the API and enforce integrity in the database.
-   Use transactions for operations that must succeed or fail together.
-   Avoid storing derived counts unless there is a clear performance
    reason and a consistency strategy.

## 14. Advanced Database Concepts

The project requirements call for at least four advanced database
concepts. Proposed concepts:

1.  **Transactions:** Create a post and associate its tags atomically;
    roll back if a required step fails.
2.  **Views:** Create a view joining published posts with
    author/community information, or a popular-posts view.
3.  **Triggers/functions:** Maintain an audit record or a derived
    counter where useful; document and test consistency.
4.  **Indexing:** Index frequently queried columns and compare query
    plans where practical.
5.  **Full-text search:** Search post titles and content using
    PostgreSQL full-text search and suitable indexes.
6.  **Vector similarity search:** Store embeddings with pgvector and
    retrieve semantically similar posts.

Implement and demonstrate at least four. Full-text and vector search are
especially relevant to this project's purpose.

## 15. Semantic Search Workflow

1.  A post is created or updated.
2.  The application prepares the title and content for embedding.
3.  An embedding model converts the text into a vector.
4.  The vector is stored with the post reference.
5.  A user enters a natural-language query or opens a post.
6.  The query or source post is embedded.
7.  pgvector retrieves the most similar posts using the selected
    similarity metric.
8.  The application returns published and accessible results, excluding
    the source post from similar-post recommendations when appropriate.

Recommendations must respect visibility and moderation rules. The
initial version provides content-similarity recommendations; it does not
claim to implement a sophisticated personalized ranking system.

## 16. SQL Queries and Operations to Demonstrate

-   `CREATE`, `ALTER`, and appropriate `DROP` statements.
-   `INSERT`, `UPDATE`, `DELETE`, and `SELECT`.
-   Joins between posts, users, communities, and tags.
-   Posts with their tags.
-   Most-reacted-to posts using aggregation and `GROUP BY`.
-   Authors with the most published posts.
-   Posts bookmarked by a user.
-   Members of a community.
-   Comments and replies.
-   Filtering posts by community, tag, author, or date.
-   Subqueries and `HAVING` for aggregate conditions.
-   Full-text search and pgvector similarity queries.
-   Transactions for multi-step operations.

Include sample data and representative expected results in the report.

## 17. Non-Functional Requirements

-   **Security:** Store password hashes, protect secrets with
    environment variables, validate inputs, and enforce API
    authorization.
-   **Integrity:** Use constraints and transactions to prevent
    inconsistent data.
-   **Usability:** Provide clear navigation, readable post pages, and
    simple forms.
-   **Performance:** Use pagination and suitable indexes for lists and
    search.
-   **Maintainability:** Keep UI, API, and database-access logic
    organized.
-   **Reliability:** Handle errors without exposing sensitive
    information.
-   **Privacy:** Restrict access to personal details and activity
    history.
-   **Testability:** Test authentication, permissions, database
    constraints, search, and core workflows.

## 18. Proposed Interface Pages

-   Home/feed page.
-   Registration and login.
-   User profile and author page.
-   Create/edit blog page.
-   Blog details page with comments and replies.
-   Community listing and details.
-   Tag-based browsing.
-   Search page with keyword and semantic search.
-   Bookmarks page.
-   Followed-authors page.
-   Reading/activity history (if implemented).
-   Admin dashboard for user, community, and content moderation.

## 19. Testing Plan

-   Valid and invalid registration/login.
-   User versus Admin authorization.
-   Creating, editing, publishing, and managing posts.
-   Invalid foreign keys and duplicate relationship records.
-   Adding/removing tags, reactions, bookmarks, and follows.
-   Comment replies and invalid parent-comment references.
-   Search, filtering, sorting, and pagination.
-   Full-text search relevance.
-   Embedding generation and semantic search results.
-   Transaction rollback on a failed multi-step operation.
-   Trigger/function behavior, if implemented.
-   Unauthorized access to another user's restricted data.
-   Empty inputs, oversized content, and other validation cases.

## 20. Team Work Distribution

For a two-member team, both members should contribute to database design
and application development.

### Member 1 --- Core Relational Features

-   Jointly finalize the ER diagram and relational schema.
-   Implement PostgreSQL tables, constraints, indexes, and sample data.
-   Implement post, community, tag, and comment workflows.
-   Develop and test SQL queries and advanced database features.

### Member 2 --- Interaction and Search Features

-   Jointly review the ER diagram and relational schema.
-   Coordinate authentication and role-based authorization.
-   Implement reactions, bookmarks, follows, and search interfaces.
-   Integrate embeddings and pgvector similarity search.
-   Test retrieval and help prepare documentation.

### Shared Responsibilities

Next.js architecture and API integration, security, validation, database
design review, testing, GitHub collaboration, README, screenshots, and
final demonstration.

## 21. Expected Deliverables

-   GitHub repository containing the source code.
-   Functional Next.js web application.
-   PostgreSQL schema and SQL scripts.
-   ER diagram and relational schema.
-   Data dictionary describing attributes, types, keys, and constraints.
-   Explanation of SQL and vector database choices.
-   Demonstration of at least four advanced database concepts.
-   Sample SQL and vector-search queries.
-   Test cases and results.
-   Application screenshots.
-   README with setup and execution instructions.
-   Final project documentation and demonstration.

## 22. Future Enhancements

Possible future improvements include richer recommendation ranking,
community-specific moderation tools, notifications, post version
history, reading-time estimates, content-quality signals, and analytics
dashboards. These are not required for the initial version.

## 23. Final Summary

The **Intelligent Community Blogging and Content Discovery Platform** is
a Next.js web application that combines blogging and community
interaction with relational database management and semantic content
discovery. PostgreSQL manages structured entities and relationships,
while pgvector enables vector similarity search over blog content. The
project provides opportunities to demonstrate ER modelling, relational
schema design, integrity constraints, complex SQL queries, transactions,
views, triggers/functions, indexing, full-text search, and vector
retrieval.

The initial scope focuses on helping users publish, organize, interact
with, and discover relevant blog content. Additional social and
analytics features should be added only after the core application and
database requirements work reliably.

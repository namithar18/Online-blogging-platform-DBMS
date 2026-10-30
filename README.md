# Intelligent Community Blogging and Content Discovery Platform

> **Draft.** This README describes the project as it stands today and will grow as we build it.
> So far only the database layer exists (schema, seed data and queries). The web app is not started.

DBMS Experiential Learning – Level 3 mini-project, PES University. Two-member team.

## What we are building

A community blogging website. Users publish articles in communities, tag them, comment, react, bookmark and follow authors.

Readers often struggle to find relevant posts, and keyword search misses articles that express the same idea in different words. So the platform offers two kinds of search:

- **Keyword search:** PostgreSQL full-text search.
- **Search by meaning:** text embeddings and vector similarity search with `pgvector`.

## Why these databases

| Type of data | Stored in | Why it fits |
|---|---|---|
| Users, posts, communities, follows and other linked records | PostgreSQL tables | Strongly relational: needs keys, joins, constraints and transactions |
| Meaning of post text | `pgvector` column in the same PostgreSQL database | Comparing meaning needs vectors. Keeping them beside the posts lets search results be filtered by a post's status with a normal join |

This is Option 2 (SQL + Vector Database) in §3 of the assignment, which lists PostgreSQL with pgvector as an accepted vector database.

## Tech stack

| Layer | Choice | Status |
|---|---|---|
| Database | PostgreSQL 16 + `pgvector`, run in Docker | In use |
| Data access | Raw SQL with the `pg` library and parameterised queries (no ORM) | Planned |
| Frontend and API | Next.js (App Router) with Route Handlers | Planned |
| Passwords | bcrypt or argon2 hashes, never plain text | Planned |
| Embeddings | `all-MiniLM-L6-v2` (free, runs locally), 384 dimensions, cosine distance | Column created; generation planned |

Planned request flow: browser → Next.js pages → Route Handlers (validation and authorisation) → PostgreSQL + pgvector. The frontend never talks to the database directly.

## Data model

There are 12 tables, built from 7 entities and 5 many-to-many relationships.

| Group | Tables |
|---|---|
| People and places | `users`, `communities`, `community_members` |
| Content | `posts`, `tags`, `post_tags`, `comments` |
| Interaction | `reactions`, `bookmarks`, `follows`, `reading_activity` |
| Search | `post_embeddings` (`posts.search_vector` handles full-text search) |

- [ER diagram (Chen notation)](docs/ER_diagram_final.png)
- [Logical model](docs/ER_logical_model.png)
- [ER explanation, mapping and viva questions](docs/ER_explanation_and_viva.md)

### Integrity rules

| Rule | Meaning | Enforced by | Status |
|---|---|---|---|
| C1 | Users cannot follow themselves | `CHECK` | Done |
| C2 | A reply is on the same post as its parent | Composite foreign key | Done |
| C3 | Valid values for role, statuses, reaction and activity types | `CHECK` | Done |
| C4 | A published post has a `published_at` | `CHECK` | Done |
| C5 | Only admins create communities | Trigger | Not yet (component 4) |
| C6 | Fixed vector size; one embedding per post and model | `vector(384)` and primary key | Done |
| C7 | Only published, non-removed posts appear in search and recommendations | View | Filter in `queries.sql` for now; view in component 4 |
| C8 | Passwords stored only as hashes | API | Not yet (component 7) |
| C9 | `updated_at` is not before `created_at` | `CHECK` | Done |

## Run the database

You need [Docker](https://www.docker.com/products/docker-desktop/). Run these commands from the project folder.

**1. Start PostgreSQL** (first time only). The password is for local development only.

```bash
docker run -d --name blogdb -e POSTGRES_PASSWORD=devpass -e POSTGRES_DB=blog \
  -p 5432:5432 pgvector/pgvector:pg16
```

After a restart, use `docker start blogdb`.

**2. Create the tables and load the data.** Re-running `schema.sql` deletes all existing data.

```bash
docker exec -i blogdb psql -U postgres -d blog < db/schema.sql
docker exec -i blogdb psql -U postgres -d blog < db/seed.sql 2>&1 | less
docker exec -i blogdb psql -U postgres -d blog < db/queries.sql 2>&1 | less
```

Press `q` to leave `less`.

**3. Check the results.**

- `seed.sql` loads the sample data, then prints exactly **23 `ERROR` lines**. These are expected: each is a deliberately invalid statement being rejected by a constraint.
- `queries.sql` runs 17 demonstration queries with no errors.

**4. Explore the data.**

```bash
docker exec -it blogdb psql -U postgres -d blog
```

At the `blog=#` prompt, `\dt` lists the tables, `\d posts` describes a table and `\q` quits.

Seed accounts use placeholder password hashes, so they will not be able to log in.

## Project layout

```text
db/
  schema.sql     all 12 tables and their constraints
  seed.sql       sample data, then invalid statements that must fail
  queries.sql    JOIN, GROUP BY, HAVING, ORDER BY and subquery demonstrations
docs/            assignment, ER diagrams, ER explanation, feature spec
CLAUDE.md        how we work, database rules and build plan
```

Planned additions are `db/advanced/`, `db/alter_drop_demo.sql`, `src/` (Next.js app) and `tests/`.

## Progress

- [x] 1. Schema
- [x] 2. Seed data and invalid inserts
- [x] 3. Demonstration queries
- [ ] 4. Advanced features: indexes with `EXPLAIN`, views, triggers, a transaction with rollback
- [ ] 5. Full-text search: GIN index and queries (the `search_vector` column already exists)
- [ ] 6. Next.js skeleton: database pool, environment variables, health-check route
- [ ] 7. Authentication and roles (User and Admin)
- [ ] 8. Features: posts, communities, tags, comments, reactions, bookmarks, follows
- [ ] 9. Semantic search: embeddings, pgvector storage, similar posts
- [ ] 10. Admin tools, testing, final README, screenshots

## Still to do for the assignment

- Show `ALTER` and `DROP` in `db/alter_drop_demo.sql` (§5).
- Write the data dictionary and format the relational schema document (§14).
- Document the vector data model and retrieval strategy (§4, §8).
- Record test results and take application screenshots (§14).
- Fill in each member's contribution below (§16).

## Team

| Member | Area | Name |
|---|---|---|
| Member 1 | Core relational features: schema, seed, queries, advanced database features, posts, communities, tags, comments | *TODO* |
| Member 2 | Interaction and search: authentication and roles, reactions, bookmarks, follows, full-text and semantic search | *TODO* |

Both members share architecture, security, testing, documentation and the demo.

## Documents

- [Assignment requirements](docs/DBMS%20Level%203%20Project%20Requirements%20draft.pdf)
- [Feature specification (FR-01 to FR-14)](docs/intelligent_community_blogging_platform.md)
- [ER explanation and viva preparation](docs/ER_explanation_and_viva.md)

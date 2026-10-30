# CLAUDE.md — Intelligent Community Blogging & Content Discovery Platform

DBMS Level 3 mini-project (PES University), built by a two-person team.
Next.js + PostgreSQL + pgvector. The database work is what gets graded most,
so database correctness and our understanding of it come first.

## How to work with us (most important)

We are students learning DBMS. Understanding matters more than speed.

- **Explain before writing.** For every task, first say what you will build,
  why, and which DBMS concept it demonstrates. Wait for our approval before
  writing code.
- **One component at a time.** Only work on the component we name (see the
  Build plan below). Do not edit files belonging to other components unless
  we ask.
- **Small steps.** Prefer several small, reviewable changes over one large one.
- **Teach the "why".** When you choose a constraint, index, ON DELETE rule or
  query shape, add a short SQL comment explaining the reason. Point out
  alternatives and trade-offs when they matter for the viva.
- **We run things ourselves.** Give us the exact commands to run and what
  output to expect, then let us run them. Tell us how to try to break it
  (e.g. insert an invalid row) so we can see the constraint work.
- **Never commit or push.** We commit ourselves so that Git shows each
  member's individual contribution. Suggest a commit message when a step is done.
- **End each component with 5 viva questions** about what we just built.
- If something in the request conflicts with the docs or the assignment,
  stop and ask instead of guessing.

## Sources of truth (read before designing anything)

1. `docs/DBMS_Level_3_Project_Requirements.pdf` — the assignment. Wins every conflict.
2. `docs/ER_explanation_and_viva.md` — final ER model, relational mapping
   (section 6.1), constraints C1–C9, assumptions A1–A10.
3. `docs/ER_diagram_final.png` — final Chen ER diagram.
4. `docs/intelligent_community_blogging_platform.md` — feature spec (FR-01…FR-14).

The schema must match the ER docs. Do not add, remove or rename tables or
columns without asking; if a change is needed, we update the ER docs too.

## Tech decisions (fixed)

- **Database:** PostgreSQL 16 with the `pgvector` extension, run via Docker
  (`pgvector/pgvector` image).
- **Data access:** raw SQL with the `pg` library and parameterised queries
  (`$1, $2 …`). **No ORM** (no Prisma/Drizzle/TypeORM) — the SQL must be visible.
- **App:** Next.js (App Router) with Route Handlers as the API layer.
  The frontend never talks to the database directly.
- **Passwords:** hashed with bcrypt (or argon2). Never stored or logged in plain text.
- **Embedding model:** TODO — decide before the schema is written; it fixes
  the `vector(d)` dimension. Similarity metric: cosine distance (`<=>`).

## Database rules

- Table names are plural snake_case: `users`, `communities`, `posts`, `tags`,
  `post_tags`, `community_members`, `comments`, `reactions`, `bookmarks`,
  `follows`, `post_embeddings`, `reading_activity` (12 tables, see ER doc §6.1).
  `user` is a reserved word — always `users`.
- Every rule that can be enforced in the database must be (assignment §12):
  NOT NULL, UNIQUE, CHECK, foreign keys, composite FK for C2, triggers where
  needed. API validation is in addition to this, never instead of it.
- Choose ON DELETE behaviour deliberately and comment why
  (e.g. CASCADE for `post_embeddings`, soft delete via `status` for comments).
- Counts (likes, comments) are computed with queries, not stored.
- Only published, non-removed posts appear in search and recommendations (C7).
- Multi-step writes (e.g. create post + tags + embedding) use a transaction.

## Security

- All credentials and keys come from environment variables (`.env.local`).
  Never hard-code them; never commit `.env*` files (keep `.env.example`
  with placeholder values instead).
- Always use parameterised queries — never build SQL with string concatenation.
- Enforce USER/ADMIN authorisation in the API route, not only in the UI.
- Error responses must not leak SQL, stack traces or secrets.

## Project layout

```
db/
  schema.sql        CREATE TABLE … in dependency order
  seed.sql          sample data
  queries.sql       demonstration queries (joins, GROUP BY, HAVING, subqueries)
  advanced/         indexes.sql, views.sql, triggers.sql, transactions.sql, fulltext.sql
  alter_drop_demo.sql
src/app/            Next.js pages and api/ route handlers
src/lib/db.ts       single pg Pool, reads DATABASE_URL
docs/               assignment, ER diagram, ER explanation, spec
tests/              test cases and results
```

## Build plan and status

Tick a box only when the component works and we have both understood it.

- [ ] 1. Schema — `db/schema.sql` (all 12 tables and constraints C1–C9)
- [ ] 2. Seed data — `db/seed.sql`, plus deliberate invalid inserts that must fail
- [ ] 3. Queries — `db/queries.sql` (JOIN, GROUP BY, HAVING, ORDER BY, subqueries)
- [ ] 4. Advanced features — indexes + EXPLAIN, views, triggers, transaction with rollback
- [ ] 5. Full-text search — `search_vector` generated column + GIN index
- [ ] 6. Next.js skeleton — DB pool, `.env`, one health-check route
- [ ] 7. Auth and roles — register/login, hashing, USER vs ADMIN
- [ ] 8. Features — posts, communities, tags, comments, reactions, bookmarks, follows
- [ ] 9. Semantic search — embeddings, pgvector storage, similar posts
- [ ] 10. Admin, testing, README, screenshots

Steps 1–5 are pure SQL run in `psql`; do not start the web app before step 6.

## Common commands

```bash
docker compose up -d                                   # start PostgreSQL + pgvector
psql "$DATABASE_URL" -f db/schema.sql                  # (re)create tables
psql "$DATABASE_URL" -f db/seed.sql                    # load sample data
psql "$DATABASE_URL"                                   # interactive shell
npm run dev                                            # Next.js on localhost:3000
```

## Team

- Member 1 — core relational features: schema, seed, queries, advanced DB
  features, posts/communities/tags/comments.
- Member 2 — interaction and search: auth and roles, reactions, bookmarks,
  follows, full-text and semantic search.
- Shared: architecture, security, testing, documentation, demo.

# Vector search: data model and retrieval strategy

Covers assignment sections 4 and 8. Vectors live in PostgreSQL with the `pgvector` extension, in the same database as the posts (Option 2: SQL + vector database).

## 1. Why a vector store, and why pgvector

Keyword search (full-text search) only finds posts that share words with the query. A reader who types "how do databases find rows quickly" should still find the post about B-tree indexes, although it shares no key word. That needs a comparison of meaning, which is done on vectors.

pgvector keeps the vectors beside the posts, so a similarity search can be filtered by post status with a normal join (rule C7) and a post and its embedding are written in one transaction. A separate vector database would need a second system and its own copy of each post's status.

## 2. What is converted into embeddings

One embedding per post, built from the text `title + ". " + content` (`postText()` in `src/lib/embeddings.ts`). Search phrases typed by users are embedded at query time with the same function, so a phrase and a post are compared in the same space. Comments, tags and authors are not embedded.

## 3. Embedding model

| Property | Value |
|---|---|
| Model | `all-MiniLM-L6-v2` (sentence-transformers) |
| Runtime | `@huggingface/transformers`, ONNX build `Xenova/all-MiniLM-L6-v2`, runs locally in the Next.js server process |
| Output size | 384 numbers per text |
| Pooling | mean pooling, then normalisation to unit length |
| Cost | free, no API key; about 90 MB downloaded on first use and cached |

The model is loaded once per server process and reused (like the `pg` Pool). The seed vectors in `db/seed_embeddings.sql` were produced by `scripts/embed-seed/generate.mjs` with the same model and the same text format. If the two differed, app vectors and seed vectors would not be comparable.

## 4. How vectors are stored

Table `post_embeddings` (a weak entity owned by `posts`):

| Column | Type | Meaning |
|---|---|---|
| `post_id` | bigint, FK to `posts` `ON DELETE CASCADE` | the post this vector describes |
| `model_name` | varchar(100) | the model that produced it, here `all-MiniLM-L6-v2` |
| `embedding` | `vector(384)`, NOT NULL | the vector |
| `created_at` | timestamptz | when it was generated |

- **Primary key `(post_id, model_name)` (C6):** at most one embedding per post and model. Because the model name is part of the key, a second model could be added later without a schema change. Vectors from different models are never compared, which is why queries filter on `model_name`.
- **`vector(384)` (C6):** PostgreSQL rejects any vector of another length.
- **`ON DELETE CASCADE`:** existence dependency, so no post means no embedding.
- **Metadata:** `post_id` links each vector to the post's title, status, author and community. All filtering and ranking metadata therefore lives in the ordinary tables and is reached by a join.
- **Writes:** `saveEmbedding()` is an upsert on the primary key and runs on the caller's transaction client, so a post and its embedding commit or roll back together. If the model is unavailable, `embed()` throws HTTP 503 and the post write fails as a whole instead of saving a post without a vector.

## 5. Similarity metric

Cosine distance, operator `<=>`:

    cosine distance = 1 - cosine similarity
    0 = same direction, 1 = unrelated, 2 = opposite

Cosine compares direction and ignores length. The vectors are already normalised to length 1, so this is also equivalent to ranking by inner product, but `<=>` states the intent. The API reports `similarity = 1 - distance`, rounded to four decimals.

pgvector also offers `<->` (Euclidean) and `<#>` (negative inner product). The operator class of an index must match the operator in `ORDER BY`, otherwise the planner ignores the index.

## 6. Index: HNSW

```sql
CREATE INDEX post_embeddings_embedding_hnsw_idx
    ON post_embeddings USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
```

HNSW (Hierarchical Navigable Small World) is a layered graph in which every vector is linked to its near neighbours. A search starts at the top layer and walks towards the query, visiting only a small part of the table instead of computing the distance to every row.

- `vector_cosine_ops` builds the graph for `<=>`.
- `m = 16` is the number of links per node, and `ef_construction = 64` is the number of candidates considered while building. These are pgvector's defaults, written out so they can be discussed: higher values give better recall but a slower build and a bigger index.
- **It is approximate.** HNSW can miss a true nearest neighbour (recall below 100%) in exchange for speed. A B-tree or GIN index never changes the answer, only the speed; an HNSW index can change the answer.
- **Filters and C7.** An HNSW scan returns about `ef_search` (default 40) candidates and the filter runs afterwards, so a very selective filter could leave too few rows. `db/advanced/vector_search.sql` (test 7) shows the planner avoiding this when only a small share of posts is published: it fetches the published posts first and sorts them by exact distance. For less selective filters, pgvector 0.8 and later offers `SET hnsw.iterative_scan = relaxed_order`, which keeps walking the graph until enough rows pass.
- With only 12 seeded posts, the planner still prefers an exact sequential scan and sort. The index pays off as the platform grows, and the application queries already have the shape it needs (`ORDER BY embedding <=> constant LIMIT n`).

## 7. Retrieval strategy

**Search by meaning (`GET /api/search/semantic?q=...&limit=`):**

1. Validate `q` (1 to 500 characters) and clamp `limit` (default 10, maximum 20).
2. Embed the phrase with the same model (HTTP 503 if the model is unavailable).
3. Pass the vector as one bound parameter and run:

```sql
SELECT p.post_id, p.title, left(p.content, 200) AS excerpt, ...,
       round((1 - (e.embedding <=> $1::vector))::numeric, 4) AS similarity
FROM post_embeddings e
JOIN published_posts p ON p.post_id = e.post_id
JOIN users u ON u.user_id = p.author_id
JOIN communities c ON c.community_id = p.community_id
WHERE e.model_name = $2
ORDER BY e.embedding <=> $1::vector
LIMIT $3;
```

- `ORDER BY embedding <=> constant` is the shape the HNSW index serves.
- The join to `published_posts` applies C7: drafts, unpublished and removed posts are never returned.
- There is always a "closest" post, so results are ranked by similarity and not cut off at a threshold.

**Similar posts (`GET /api/posts/:id/similar?limit=`):** the same query with the source vector taken from a scalar subquery (`SELECT embedding FROM post_embeddings WHERE post_id = X AND model_name = ...`). PostgreSQL evaluates it once (an InitPlan), so every row is compared with one fixed vector. The post itself is excluded with `e.post_id <> X`, and `limit` defaults to 5 (maximum 20). The stored vector is used, so no model call is needed.

- The *source* post must be visible to the caller (a draft only to its author and admins), otherwise the API answers 404. The *results* are always published posts (C7).
- If the source post has no embedding yet, the API returns an empty list with status 200.

## 8. Full-text search versus semantic search

| | Full-text search | Semantic search |
|---|---|---|
| Matches | words (stemmed) | meaning |
| Index | GIN on `posts.search_vector` | HNSW on `post_embeddings.embedding` |
| Result set | exactly the posts containing the terms | always the n closest posts |
| Ranking | `ts_rank` | cosine distance |
| Exact? | yes | approximate with HNSW |

The platform offers both because they fail in different ways: keywords miss paraphrases, and meaning can rank loosely related posts.

## 9. How to reproduce

Load the files in this order: `db/schema.sql`, `db/seed.sql`, `db/advanced/triggers.sql`, `db/advanced/views.sql`, `db/advanced/indexes.sql`, `db/advanced/fulltext.sql`, `db/seed_embeddings.sql`, then `db/advanced/vector_search.sql`.

macOS / Linux (bash or zsh):

```bash
docker exec -i blogdb_nextjs psql -U postgres -d blog < db/advanced/vector_search.sql
```

Windows (PowerShell):

```powershell
Get-Content -Raw -Encoding UTF8 db\advanced\vector_search.sql | docker exec -i blogdb_nextjs psql -U postgres -d blog
```

The script shows: the 12 embeddings of 384 dimensions, the most similar posts for posts 1 and 6, draft post 10 appearing when `posts` is queried and disappearing through `published_posts` (C7), and `EXPLAIN ANALYZE` on 10,000 random vectors before and after the HNSW index (rolled back).

## 10. Limits and future work

- Only posts are embedded, and only with one model. Long posts are truncated: `@huggingface/transformers` cuts the input at 512 tokens (`model_max_length` in the model's tokenizer config). The model was trained on texts of up to 256 tokens, so a very long post is represented mostly by its beginning.
- HNSW is approximate, and the build parameters were left at their defaults.
- A hybrid ranking that combines `ts_rank` and similarity is a possible enhancement.
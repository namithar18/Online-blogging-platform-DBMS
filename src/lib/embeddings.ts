import "server-only";
import { type FeatureExtractionPipeline, pipeline } from "@huggingface/transformers";
import type { PoolClient } from "pg";
import { HttpError } from "@/lib/http";

// Stored in post_embeddings.model_name (part of the primary key). Must
// match scripts/embed-seed/generate.mjs, or app vectors and seed vectors
// would not be comparable.
export const EMBEDDING_MODEL = "all-MiniLM-L6-v2";
const HF_MODEL = "Xenova/all-MiniLM-L6-v2"; // ONNX build of the same model
const DIMENSIONS = 384;                     // vector(384) in schema.sql (C6)

declare global {
  var __embedder: Promise<FeatureExtractionPipeline> | undefined;
}

/**
 * Load the model once per server process and reuse it, like the pg Pool.
 * The first call downloads it (~90 MB, cached on disk afterwards) and
 * takes a few seconds; later calls take ~20-50 ms per text.
 */
function getEmbedder(): Promise<FeatureExtractionPipeline> {
  if (!globalThis.__embedder) {
    const loading = pipeline("feature-extraction", HF_MODEL, { dtype: "fp32" });
    // If loading fails, forget the failed attempt so the next request retries.
    loading.catch(() => {
      globalThis.__embedder = undefined;
    });
    globalThis.__embedder = loading;
  }
  return globalThis.__embedder;
}

/** The text that represents a post: same format as generate.mjs. */
export function postText(title: string, content: string): string {
  return `${title}. ${content}`;
}

/**
 * Embed a text and return it in pgvector's text format '[0.1,0.2,...]',
 * ready to pass as a $n::vector parameter.
 * Throws HttpError 503 if the model is unavailable, so a post write fails
 * as a whole instead of saving a post without its embedding.
 */
export async function embed(text: string): Promise<string> {
  let vector: number[];
  try {
    const extractor = await getEmbedder();
    // mean pooling + normalize: one unit-length vector per text, so cosine
    // distance (<=>) compares direction only.
    const output = await extractor(text, { pooling: "mean", normalize: true });
    vector = Array.from(output.data as Float32Array);
  } catch (err) {
    console.error("Embedding model error:", err);
    throw new HttpError(503, "Semantic search is temporarily unavailable, please try again");
  }
  if (vector.length !== DIMENSIONS) {
    throw new Error(`Expected ${DIMENSIONS} dimensions, got ${vector.length}`);
  }
  return `[${vector.join(",")}]`;
}

/**
 * Insert or replace a post's embedding. Runs on the caller's transaction
 * client, so it commits or rolls back together with the post itself.
 * Upsert on the primary key (post_id, model_name): an edited post gets its
 * vector replaced instead of failing on the duplicate key.
 */
export async function saveEmbedding(client: PoolClient, postId: string, vector: string): Promise<void> {
  await client.query(
    `INSERT INTO post_embeddings (post_id, model_name, embedding)
     VALUES ($1, $2, $3::vector)
     ON CONFLICT (post_id, model_name)
     DO UPDATE SET embedding  = EXCLUDED.embedding,
                   created_at = now()`,
    [postId, EMBEDDING_MODEL, vector],
  );
}
